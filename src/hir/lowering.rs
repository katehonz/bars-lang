use crate::ast::{Expr, Pattern, Program as AstProgram, Symbol};
use crate::hir::*;
use anyhow::{bail, Result};

pub struct LoweringCtx {
    temp_counter: usize,
    label_counter: usize,
    blocks: Vec<Block>,
    current_block: String,
    current_instrs: Vec<Instr>,
}

impl LoweringCtx {
    pub fn new() -> Self {
        Self {
            temp_counter: 0,
            label_counter: 0,
            blocks: Vec::new(),
            current_block: String::new(),
            current_instrs: Vec::new(),
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
    }

    fn start_block(&mut self, label: String) {
        self.current_block = label;
        self.current_instrs = Vec::new();
    }

    pub fn lower_program(&mut self, program: &AstProgram) -> Result<Program> {
        let mut funcs = Vec::new();
        let mut main_exprs = Vec::new();

        for expr in &program.exprs {
            match expr {
                Expr::Defn { name, params, body, .. } => {
                    let func = self.lower_func(&name.0, params, body)?;
                    funcs.push(func);
                }
                other => {
                    main_exprs.push(other.clone());
                }
            }
        }

        // Implicit main if needed
        if !main_exprs.is_empty() || !funcs.iter().any(|f| f.name == "main") {
            funcs.push(self.lower_implicit_main(&main_exprs)?);
        }

        Ok(Program { funcs })
    }

    fn lower_func(&mut self, name: &str, params: &[(Symbol, Option<crate::ast::Type>)], body: &Expr) -> Result<Func> {
        let entry_label = self.fresh_label("entry");
        self.start_block(entry_label.clone());

        let result = self.lower_expr(body)?;
        self.emit(Instr::Assign { dest: "_ret".to_string(), value: result });
        self.seal_block(Terminator::Return(Operand::Var("_ret".to_string())));

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
        }
        self.seal_block(Terminator::Return(last));

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
        match expr {
            Expr::Number(n) => Ok(Operand::Const(*n)),
            Expr::Bool(b) => Ok(Operand::Const(if *b { 1 } else { 0 })),
            Expr::Symbol(sym) => Ok(Operand::Var(sym.0.clone())),

            Expr::String(s) => {
                let dest = self.fresh_temp();
                self.emit(Instr::StringLit { dest: dest.clone(), content: s.clone() });
                Ok(Operand::Var(dest))
            }

            Expr::Let { bindings, body, .. } => {
                for (name, val_expr) in bindings {
                    let val = self.lower_expr(val_expr)?;
                    self.emit(Instr::Assign { dest: name.0.clone(), value: val });
                }
                self.lower_expr(body)
            }

            Expr::If { cond, then_branch, else_branch, .. } => {
                let cond_val = self.lower_expr(cond)?;
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
                self.emit(Instr::Store { addr: Operand::Var(result_slot.clone()), value: then_val });
                self.seal_block(Terminator::Jump(merge_label.clone()));

                // Else block
                self.start_block(else_label);
                let else_val = self.lower_expr(else_branch)?;
                self.emit(Instr::Store { addr: Operand::Var(result_slot.clone()), value: else_val });
                self.seal_block(Terminator::Jump(merge_label.clone()));

                // Merge block (becomes current)
                self.start_block(merge_label);
                self.emit(Instr::Load { dest: result.clone(), addr: Operand::Var(result_slot) });
                Ok(Operand::Var(result))
            }

            Expr::Do { exprs, .. } => {
                let mut last = Operand::Const(0);
                for e in exprs {
                    last = self.lower_expr(e)?;
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
                    lowered_args.push(self.lower_expr(arg)?);
                }
                let dest = self.fresh_temp();
                self.emit(Instr::Call { dest: dest.clone(), func: func_name, args: lowered_args });
                Ok(Operand::Var(dest))
            }

            Expr::Loop { bindings, body, .. } => {
                let loop_label = self.fresh_label("loop");
                let exit_label = self.fresh_label("loop_exit");

                // Initialize loop variables
                for (name, init) in bindings {
                    let init_val = self.lower_expr(init)?;
                    self.emit(Instr::Assign { dest: name.0.clone(), value: init_val });
                }

                // Jump to loop header
                self.seal_block(Terminator::Jump(loop_label.clone()));

                // Loop header block
                self.start_block(loop_label.clone());
                let body_val = self.lower_expr(body)?;
                // After body, jump back to loop header
                self.seal_block(Terminator::Jump(loop_label));

                // Exit block (becomes current)
                self.start_block(exit_label.clone());
                Ok(body_val)
            }

            Expr::Recur { args, .. } => {
                // Recur jumps back to loop header.
                // For now, we store args into loop vars and jump.
                // This is a simplification — real implementation needs loop context.
                for arg in args {
                    let _ = self.lower_expr(arg)?;
                }
                // We don't know the loop label here without context.
                // For now, seal as unreachable and return dummy.
                self.seal_block(Terminator::Unreachable);
                let after = self.fresh_label("after_recur");
                self.start_block(after);
                Ok(Operand::Const(0))
            }

            Expr::FieldAccess { expr, field, .. } => {
                let base = self.lower_expr(expr)?;
                let dest = self.fresh_temp();
                // Need struct registry for offset — for now, assume 0
                // Real implementation would look up field offset.
                self.emit(Instr::FieldLoad { dest: dest.clone(), base, offset: 0 });
                Ok(Operand::Var(dest))
            }

            Expr::Match { expr, arms, .. } => {
                let val = self.lower_expr(expr)?;
                let result_slot = self.fresh_temp();
                let result = self.fresh_temp();
                let merge_label = self.fresh_label("match_merge");

                // Allocate slot for result
                self.emit(Instr::Alloc { dest: result_slot.clone(), size: 8 });

                for (_pattern, body) in arms {
                    let arm_label = self.fresh_label("match_arm");
                    let next_label = self.fresh_label("match_next");

                    // Pattern check: for now, always true
                    let cond = self.fresh_temp();
                    self.emit(Instr::Const { dest: cond.clone(), value: 1 });
                    self.seal_block(Terminator::Branch {
                        cond: Operand::Var(cond),
                        then_block: arm_label.clone(),
                        else_block: next_label.clone(),
                    });

                    // Arm body
                    self.start_block(arm_label);
                    let body_val = self.lower_expr(body)?;
                    self.emit(Instr::Store { addr: Operand::Var(result_slot.clone()), value: body_val });
                    self.seal_block(Terminator::Jump(merge_label.clone()));

                    // Next arm becomes current
                    self.start_block(next_label);
                }

                // Merge block
                self.seal_block(Terminator::Unreachable);
                self.start_block(merge_label.clone());
                self.emit(Instr::Load { dest: result.clone(), addr: Operand::Var(result_slot) });
                Ok(Operand::Var(result))
            }

            Expr::Borrow(inner, _, _) => {
                // Borrow is currently a no-op at HIR level
                self.lower_expr(inner)
            }

            Expr::Def { name, value, .. } => {
                let val = self.lower_expr(value)?;
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

            other => bail!("Unsupported expression in HIR lowering: {:?}", other),
        }
    }
}

pub fn lower(program: &AstProgram) -> Result<Program> {
    let mut ctx = LoweringCtx::new();
    ctx.lower_program(program)
}
