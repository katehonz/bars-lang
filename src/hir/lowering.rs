use crate::ast::{Expr, Pattern, Program as AstProgram, Symbol};
use crate::hir::*;
use anyhow::{bail, Result};

pub struct LoweringCtx {
    temp_counter: usize,
    label_counter: usize,
    blocks: Vec<Block>,
    current_block: String,
    current_instrs: Vec<Instr>,
    current_block_active: bool,
    loop_stack: Vec<(String, Vec<String>)>,
    struct_registry: std::collections::HashMap<String, Vec<String>>,
    /// Lambda functions extracted during lowering
    lambda_funcs: Vec<Func>,
    lambda_counter: usize,
}

impl LoweringCtx {
    pub fn new() -> Self {
        Self {
            temp_counter: 0,
            label_counter: 0,
            blocks: Vec::new(),
            current_block: String::new(),
            current_instrs: Vec::new(),
            current_block_active: false,
            loop_stack: Vec::new(),
            struct_registry: std::collections::HashMap::new(),
            lambda_funcs: Vec::new(),
            lambda_counter: 0,
        }
    }

    fn fresh_temp(&mut self) -> String {
        let t = format!("t{}", self.temp_counter);
        self.temp_counter += 1;
        t
    }

    fn fresh_label(&mut self, prefix: &str) -> String {
        let l = format!("{}_{}", prefix, self.label_counter);
        self.label_counter += 1;
        l
    }

    fn emit(&mut self, instr: Instr) {
        self.current_instrs.push(instr);
    }

    fn seal_block(&mut self, terminator: Terminator) {
        let block = Block {
            label: std::mem::take(&mut self.current_block),
            instrs: std::mem::take(&mut self.current_instrs),
            terminator,
        };
        self.blocks.push(block);
        self.current_block_active = false;
    }

    fn start_block(&mut self, label: String) {
        self.current_block = label;
        self.current_instrs = Vec::new();
        self.current_block_active = true;
    }

    pub fn lower_program(&mut self, program: &AstProgram) -> Result<Program> {
        let mut funcs = Vec::new();
        let mut main_exprs = Vec::new();

        // First pass: collect struct definitions
        for expr in &program.exprs {
            if let Expr::DefStruct { name, fields, .. } = expr {
                let field_names: Vec<String> = fields.iter().map(|f| f.0.clone()).collect();
                self.struct_registry.insert(name.0.clone(), field_names);
            }
        }

        for expr in &program.exprs {
            match expr {
                Expr::Defn { name, params, body, .. } => {
                    let func = self.lower_func(&name.0, params, body)?;
                    funcs.push(func);
                }
                Expr::Lambda { params, body, .. } => {
                    let name = format!("_lambda_{}", self.label_counter);
                    self.label_counter += 1;
                    let func = self.lower_func(&name, params, body)?;
                    funcs.push(func);
                }
                Expr::DefStruct { .. } => {
                    // Skip - compile-time only
                }
                other => {
                    main_exprs.push(other.clone());
                }
            }
        }

        // Add lambda functions extracted during lowering
        funcs.append(&mut self.lambda_funcs);

        // Implicit main if needed
        let has_main = funcs.iter().any(|f| f.name == "main");
        if !main_exprs.is_empty() || !has_main {
            funcs.push(self.lower_implicit_main(&main_exprs)?);
        }

        let struct_registry = std::mem::take(&mut self.struct_registry);
        Ok(Program { funcs, struct_registry })
    }

    fn lower_func(&mut self, name: &str, params: &[(Symbol, Option<crate::ast::Type>)], body: &Expr) -> Result<Func> {
        let entry_label = self.fresh_label("entry");
        self.start_block(entry_label.clone());

        let result = self.lower_expr(body)?;
        if self.current_block_active {
            self.emit(Instr::Assign { dest: "_ret".to_string(), value: result });
            self.seal_block(Terminator::Return(Operand::Var("_ret".to_string())));
        }

        let blocks = std::mem::take(&mut self.blocks);
        Ok(Func {
            name: name.to_string(),
            params: params.iter().map(|(s, _)| s.0.clone()).collect(),
            blocks,
            entry_block: entry_label,
        })
    }

    fn lower_implicit_main(&mut self, exprs: &[Expr]) -> Result<Func> {
        let entry_label = self.fresh_label("main_entry");
        self.start_block(entry_label.clone());

        let mut last = Operand::Const(0);
        for expr in exprs {
            last = self.lower_expr(expr)?;
            if !self.current_block_active {
                break;
            }
        }
        if self.current_block_active {
            self.seal_block(Terminator::Return(last));
        }

        let blocks = std::mem::take(&mut self.blocks);
        Ok(Func {
            name: "main".to_string(),
            params: vec![],
            blocks,
            entry_block: entry_label,
        })
    }

    /// Lower an expression into an operand.
    /// Side effect: appends instructions to the current block.
    fn lower_expr(&mut self, expr: &Expr) -> Result<Operand> {
        if !self.current_block_active {
            // Block is already sealed (e.g., by recur/return in a sibling branch).
            // Return a dummy operand; this value won't be used.
            return Ok(Operand::Const(0));
        }

        match expr {
            Expr::Number(n) => Ok(Operand::Const(*n)),
            Expr::Bool(b) => Ok(Operand::Const(if *b { 1 } else { 0 })),
            Expr::Symbol(sym) => {
                if sym.0 == "nil" {
                    Ok(Operand::Const(0))
                } else {
                    Ok(Operand::Var(sym.0.clone()))
                }
            }

            Expr::String(s) => {
                let dest = self.fresh_temp();
                self.emit(Instr::StringLit { dest: dest.clone(), content: s.clone() });
                Ok(Operand::Var(dest))
            }

            Expr::Let { bindings, body, .. } => {
                for (name, val_expr) in bindings {
                    let val = self.lower_expr(val_expr)?;
                    if !self.current_block_active {
                        return Ok(Operand::Const(0));
                    }
                    self.emit(Instr::Assign { dest: name.0.clone(), value: val });
                }
                self.lower_expr(body)
            }

            Expr::If { cond, then_branch, else_branch, .. } => {
                let cond_val = self.lower_expr(cond)?;
                if !self.current_block_active {
                    return Ok(Operand::Const(0));
                }
                let result_slot = self.fresh_temp();
                let result = self.fresh_temp();

                let then_label = self.fresh_label("then");
                let else_label = self.fresh_label("else");
                let merge_label = self.fresh_label("merge");

                // Allocate slot for result
                self.emit(Instr::Alloc { dest: result_slot.clone(), size: 8 });

                // Terminate current block with branch
                self.seal_block(Terminator::Branch {
                    cond: cond_val,
                    then_block: then_label.clone(),
                    else_block: else_label.clone(),
                });

                // Then block
                self.start_block(then_label);
                let then_val = self.lower_expr(then_branch)?;
                if self.current_block_active {
                    self.emit(Instr::Store { addr: Operand::Var(result_slot.clone()), value: then_val });
                    self.seal_block(Terminator::Jump(merge_label.clone()));
                }

                // Else block
                self.start_block(else_label);
                let else_val = self.lower_expr(else_branch)?;
                if self.current_block_active {
                    self.emit(Instr::Store { addr: Operand::Var(result_slot.clone()), value: else_val });
                    self.seal_block(Terminator::Jump(merge_label.clone()));
                }

                // Merge block (becomes current)
                self.start_block(merge_label);
                self.emit(Instr::Load { dest: result.clone(), addr: Operand::Var(result_slot) });
                Ok(Operand::Var(result))
            }

            Expr::Do { exprs, .. } => {
                let mut last = Operand::Const(0);
                for e in exprs {
                    last = self.lower_expr(e)?;
                    if !self.current_block_active {
                        break;
                    }
                }
                Ok(last)
            }

            Expr::FnCall { func, args, .. } => {
                let func_name = match func.as_ref() {
                    Expr::Symbol(sym) => sym.0.clone(),
                    _ => bail!("Only direct function calls in HIR lowering"),
                };
                let mut lowered_args = Vec::new();
                for arg in args {
                    let val = self.lower_expr(arg)?;
                    if !self.current_block_active {
                        return Ok(Operand::Const(0));
                    }
                    lowered_args.push(val);
                }
                let dest = self.fresh_temp();
                self.emit(Instr::Call { dest: dest.clone(), func: func_name, args: lowered_args });
                Ok(Operand::Var(dest))
            }

            Expr::Loop { bindings, body, .. } => {
                let loop_label = self.fresh_label("loop");
                let exit_label = self.fresh_label("loop_exit");
                let result_slot = self.fresh_temp();

                let loop_vars: Vec<String> = bindings.iter().map(|(name, _)| name.0.clone()).collect();

                // Initialize loop variables
                for (name, init) in bindings {
                    let init_val = self.lower_expr(init)?;
                    if !self.current_block_active {
                        return Ok(Operand::Const(0));
                    }
                    self.emit(Instr::Assign { dest: name.0.clone(), value: init_val });
                }

                // Allocate result slot
                self.emit(Instr::Alloc { dest: result_slot.clone(), size: 8 });

                // Jump to loop header
                self.seal_block(Terminator::Jump(loop_label.clone()));

                // Loop header block
                self.start_block(loop_label.clone());

                // Push loop context
                self.loop_stack.push((loop_label.clone(), loop_vars));

                // Lower body
                let body_val = self.lower_expr(body)?;

                // Pop loop context
                self.loop_stack.pop();

                // If body didn't seal the block (e.g., no recur at end),
                // store result and jump to exit
                if self.current_block_active {
                    self.emit(Instr::Store { addr: Operand::Var(result_slot.clone()), value: body_val });
                    self.seal_block(Terminator::Jump(exit_label.clone()));
                }

                // Exit block
                self.start_block(exit_label.clone());
                let result = self.fresh_temp();
                self.emit(Instr::Load { dest: result.clone(), addr: Operand::Var(result_slot) });
                Ok(Operand::Var(result))
            }

            Expr::Recur { args, .. } => {
                if let Some((loop_label, loop_vars)) = self.loop_stack.last().cloned() {
                    // Evaluate all args into temporaries FIRST (using old loop var values),
                    // then assign all temps to loop variables. This prevents
                    // left-to-right evaluation from affecting subsequent args.
                    let mut arg_vals = Vec::new();
                    for arg in args {
                        let val = self.lower_expr(arg)?;
                        if !self.current_block_active {
                            return Ok(Operand::Const(0));
                        }
                        arg_vals.push(val);
                    }
                    for (i, val) in arg_vals.iter().enumerate() {
                        if i < loop_vars.len() {
                            self.emit(Instr::Assign { dest: loop_vars[i].clone(), value: val.clone() });
                        }
                    }
                    // Jump back to loop header
                    self.seal_block(Terminator::Jump(loop_label));
                    self.current_block_active = false;
                    Ok(Operand::Const(0))
                } else {
                    bail!("recur outside of loop")
                }
            }

            Expr::FieldAccess { expr, field, .. } => {
                let base = self.lower_expr(expr)?;
                if !self.current_block_active {
                    return Ok(Operand::Const(0));
                }
                let dest = self.fresh_temp();
                // Look up field offset from struct registry
                let offset = self.field_offset(expr, &field.0);
                self.emit(Instr::FieldLoad { dest: dest.clone(), base, offset });
                Ok(Operand::Var(dest))
            }

            Expr::Match { expr, arms, .. } => {
                let val = self.lower_expr(expr)?;
                if !self.current_block_active {
                    return Ok(Operand::Const(0));
                }
                let result_slot = self.fresh_temp();
                let result = self.fresh_temp();
                let merge_label = self.fresh_label("match_merge");

                // Allocate slot for result
                self.emit(Instr::Alloc { dest: result_slot.clone(), size: 8 });

                for (pattern, body) in arms {
                    let arm_label = self.fresh_label("match_arm");
                    let next_label = self.fresh_label("match_next");

                    // Pattern check
                    let cond = self.lower_pattern_check(&val, pattern)?;
                    self.seal_block(Terminator::Branch {
                        cond,
                        then_block: arm_label.clone(),
                        else_block: next_label.clone(),
                    });

                    // Arm body
                    self.start_block(arm_label);

                    // Bind pattern variables
                    self.lower_pattern_bindings(&val, pattern)?;

                    let body_val = self.lower_expr(body)?;
                    if self.current_block_active {
                        self.emit(Instr::Store { addr: Operand::Var(result_slot.clone()), value: body_val });
                        self.seal_block(Terminator::Jump(merge_label.clone()));
                    }

                    // Next arm becomes current
                    self.start_block(next_label);
                }

                // After last arm: if no pattern matched, store 0 (shouldn't happen in well-formed code)
                if self.current_block_active {
                    self.seal_block(Terminator::Unreachable);
                }

                self.start_block(merge_label.clone());
                self.emit(Instr::Load { dest: result.clone(), addr: Operand::Var(result_slot) });
                Ok(Operand::Var(result))
            }

            Expr::Vector(elements, _) => {
                let dest = self.fresh_temp();
                // Create empty vector
                self.emit(Instr::Call { dest: dest.clone(), func: "vector".to_string(), args: vec![] });
                for elem in elements {
                    let val = self.lower_expr(elem)?;
                    if !self.current_block_active {
                        return Ok(Operand::Const(0));
                    }
                    let tmp = self.fresh_temp();
                    self.emit(Instr::Call {
                        dest: tmp,
                        func: "push".to_string(),
                        args: vec![Operand::Var(dest.clone()), val],
                    });
                }
                Ok(Operand::Var(dest))
            }

            Expr::List(elements, _) => {
                // Lists are represented as vectors at runtime for simplicity
                let dest = self.fresh_temp();
                self.emit(Instr::Call { dest: dest.clone(), func: "vector".to_string(), args: vec![] });
                for elem in elements {
                    let val = self.lower_expr(elem)?;
                    if !self.current_block_active {
                        return Ok(Operand::Const(0));
                    }
                    let tmp = self.fresh_temp();
                    self.emit(Instr::Call {
                        dest: tmp,
                        func: "push".to_string(),
                        args: vec![Operand::Var(dest.clone()), val],
                    });
                }
                Ok(Operand::Var(dest))
            }

            Expr::Keyword(kw) => {
                // Keywords are represented as strings at runtime for now
                let dest = self.fresh_temp();
                self.emit(Instr::StringLit { dest: dest.clone(), content: format!(":{}", kw.0) });
                Ok(Operand::Var(dest))
            }

            Expr::Borrow(inner, _, _) => {
                // Borrow is currently a no-op at HIR level
                self.lower_expr(inner)
            }

            Expr::Def { name, value, .. } => {
                let val = self.lower_expr(value)?;
                if !self.current_block_active {
                    return Ok(Operand::Const(0));
                }
                self.emit(Instr::Assign { dest: name.0.clone(), value: val });
                Ok(Operand::Var(name.0.clone()))
            }

            Expr::DefStruct { .. } => {
                // Struct definitions are compile-time only, no HIR code
                Ok(Operand::Const(0))
            }

            Expr::Defn { .. } => {
                bail!("Nested defn not supported in HIR lowering")
            }

            Expr::Lambda { params, body, .. } => {
                // Save current lowering state, extract lambda as a separate function,
                // then restore state.
                let saved_blocks = std::mem::take(&mut self.blocks);
                let saved_instrs = std::mem::take(&mut self.current_instrs);
                let saved_block = std::mem::take(&mut self.current_block);
                let saved_active = self.current_block_active;
                let saved_loop = std::mem::take(&mut self.loop_stack);

                let name = format!("_lambda_{}", self.lambda_counter);
                self.lambda_counter += 1;
                let func = self.lower_func(&name, params, body)?;
                self.lambda_funcs.push(func);

                // Restore state
                self.blocks = saved_blocks;
                self.current_instrs = saved_instrs;
                self.current_block = saved_block;
                self.current_block_active = saved_active;
                self.loop_stack = saved_loop;

                // Lambda expression returns 0
                Ok(Operand::Const(0))
            }

            other => bail!("Unsupported expression in HIR lowering: {:?}", other),
        }
    }

    fn field_offset(&self, _expr: &Expr, field_name: &str) -> usize {
        // Search all known structs for a field with this name.
        // Use the first match's index as the offset (simplified heuristic).
        for (_struct_name, fields) in &self.struct_registry {
            for (i, f) in fields.iter().enumerate() {
                if f == field_name {
                    return i * 8;
                }
            }
        }
        0
    }

    fn lower_pattern_check(&mut self, val: &Operand, pattern: &Pattern) -> Result<Operand> {
        match pattern {
            Pattern::Wildcard => Ok(Operand::Const(1)),
            Pattern::Binding(_) => Ok(Operand::Const(1)),
            Pattern::Literal(lit_expr) => {
                match lit_expr {
                    Expr::Number(n) => {
                        let dest = self.fresh_temp();
                        self.emit(Instr::BinOp {
                            dest: dest.clone(),
                            op: BinOp::Eq,
                            lhs: val.clone(),
                            rhs: Operand::Const(*n),
                        });
                        Ok(Operand::Var(dest))
                    }
                    Expr::Bool(b) => {
                        let dest = self.fresh_temp();
                        self.emit(Instr::BinOp {
                            dest: dest.clone(),
                            op: BinOp::Eq,
                            lhs: val.clone(),
                            rhs: Operand::Const(if *b { 1 } else { 0 }),
                        });
                        Ok(Operand::Var(dest))
                    }
                    _ => {
                        // For other literals, always match for now
                        Ok(Operand::Const(1))
                    }
                }
            }
            Pattern::Struct { name, fields, .. } => {
                // Check if val matches struct pattern by comparing fields
                // For simplicity, we AND together all field comparisons
                // For binding patterns, we treat them as always matching
                // For literal patterns, we compare the field value
                if let Some(field_names) = self.struct_registry.get(&name.0).cloned() {
                    let mut result = Operand::Const(1);
                    for (i, field_pat) in fields.iter().enumerate() {
                        if i >= field_names.len() {
                            break;
                        }
                        let offset = i * 8;
                        let field_val = self.fresh_temp();
                        self.emit(Instr::FieldLoad {
                            dest: field_val.clone(),
                            base: val.clone(),
                            offset,
                        });
                        let field_check = self.lower_pattern_check(&Operand::Var(field_val), field_pat)?;
                        let and_dest = self.fresh_temp();
                        self.emit(Instr::BinOp {
                            dest: and_dest.clone(),
                            op: BinOp::Mul,
                            lhs: result,
                            rhs: field_check,
                        });
                        result = Operand::Var(and_dest);
                    }
                    Ok(result)
                } else {
                    Ok(Operand::Const(1))
                }
            }
            _ => Ok(Operand::Const(1)),
        }
    }

    fn lower_pattern_bindings(&mut self, val: &Operand, pattern: &Pattern) -> Result<()> {
        match pattern {
            Pattern::Binding(name) => {
                self.emit(Instr::Assign { dest: name.0.clone(), value: val.clone() });
            }
            Pattern::Struct { name, fields, .. } => {
                if let Some(field_names) = self.struct_registry.get(&name.0).cloned() {
                    for (i, field_pat) in fields.iter().enumerate() {
                        if i >= field_names.len() {
                            break;
                        }
                        let offset = i * 8;
                        let field_val = self.fresh_temp();
                        self.emit(Instr::FieldLoad {
                            dest: field_val.clone(),
                            base: val.clone(),
                            offset,
                        });
                        self.lower_pattern_bindings(&Operand::Var(field_val), field_pat)?;
                    }
                }
            }
            Pattern::Literal(_) | Pattern::Wildcard => {}
            _ => {}
        }
        Ok(())
    }
}

pub fn lower(program: &AstProgram) -> Result<Program> {
    let mut ctx = LoweringCtx::new();
    ctx.lower_program(program)
}
