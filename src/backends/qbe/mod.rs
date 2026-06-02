use crate::ast::{Expr, Pattern, Program, Symbol, Type as AstType};
use anyhow::{bail, Result};
use qbe::{Cmp, Function, Instr, Linkage, Module, Type, Value};
use std::collections::HashMap;

/// QBE backend compiler
pub fn sanitize_name(name: &str) -> String {
    name.replace('?', "_Q")
        .replace('!', "_B")
        .replace('-', "_")
        .replace('+', "_plus")
        .replace('*', "_star")
        .replace('/', "_slash")
        .replace('%', "_percent")
        .replace('=', "_eq")
        .replace('<', "_lt")
        .replace('>', "_gt")
        .replace('&', "_amp")
        .replace('|', "_pipe")
}

pub struct QbeBackend {
    module: Module,
    temp_counter: usize,
    label_counter: usize,
    string_counter: usize,
    loop_context: Option<(String, Vec<(String, String)>)>,
    current_block_terminated: bool,
    struct_registry: HashMap<String, Vec<String>>,
}

impl QbeBackend {
    pub fn new() -> Self {
        Self {
            module: Module::new(),
            temp_counter: 0,
            label_counter: 0,
            string_counter: 0,
            loop_context: None,
            current_block_terminated: false,
            struct_registry: HashMap::new(),
        }
    }

    pub fn compile(mut self, program: &Program) -> Result<String> {
        // Separate top-level expressions into functions and others
        let mut has_main = false;
        let mut main_body: Vec<Expr> = Vec::new();

        for expr in &program.exprs {
            match expr {
                Expr::Defn { name, params, body, ret_type, .. } => {
                    self.compile_defn(name, params, body, ret_type.as_ref())?;
                    if name.0 == "main" {
                        has_main = true;
                    }
                }
                Expr::DefStruct { name, fields, .. } => {
                    let field_names: Vec<String> = fields.iter().map(|f| f.0.clone()).collect();
                    self.struct_registry.insert(name.0.clone(), field_names);
                    // Generate QBE type definition: type :Point = { l, l }
                    let qbe_type = format!("type :{} = {{ {} }}", sanitize_name(&name.0), 
                        fields.iter().map(|_| "l".to_string()).collect::<Vec<_>>().join(", "));
                    // We can't easily add raw type defs via qbe-rs, so we'll append them manually
                }
                other => {
                    {
                        main_body.push(other.clone());
                    }
                }
            }
        }

        // If there are top-level expressions and no explicit main, create one
        if !main_body.is_empty() && !has_main {
            self.compile_implicit_main(&main_body)?;
        } else if !has_main {
            // Create empty main that returns 0
            self.compile_implicit_main(&[])?;
        }

        Ok(self.module.to_string())
    }

    fn compile_defn(
        &mut self,
        name: &Symbol,
        params: &[(Symbol, Option<AstType>)],
        body: &Expr,
        ret_type: Option<&AstType>,
    ) -> Result<()> {
        let qbe_ret = ret_type.and_then(|t| Self::ast_type_to_qbe(t));

        let sanitized_name = sanitize_name(&name.0);
        let mut func = Function::new(
            Linkage::public(),
            &sanitized_name,
            params
                .iter()
                .map(|(sym, ty)| {
                    let qbe_ty = ty.as_ref().and_then(|t| Self::ast_type_to_qbe(t)).unwrap_or(Type::Long);
                    let sanitized_param = sanitize_name(&sym.0);
                    (qbe_ty, Value::Temporary(sanitized_param))
                })
                .collect(),
            qbe_ret.or(Some(Type::Long)),
        );

        func.add_block("start");
        self.current_block_terminated = false;

        let mut scope = HashMap::new();
        for (sym, _) in params {
            scope.insert(sym.0.clone(), sanitize_name(&sym.0));
        }

        let result = self.compile_expr(body, &mut func, &mut scope)?;
        func.add_instr(Instr::Ret(Some(result)));

        self.module.add_function(func);
        Ok(())
    }

    fn compile_implicit_main(&mut self, body: &[Expr]) -> Result<()> {
        let mut func = Function::new(
            Linkage::public(),
            "main",
            vec![],
            Some(Type::Word),
        );
        func.add_block("start");
        self.current_block_terminated = false;
        let mut scope = HashMap::new();

        for expr in body {
            let _ = self.compile_expr(expr, &mut func, &mut scope)?;
        }

        // Return 0 for implicit main (truncate if needed)
        func.add_instr(Instr::Ret(Some(Value::Const(0))));
        self.module.add_function(func);
        Ok(())
    }

    fn compile_expr(
        &mut self,
        expr: &Expr,
        func: &mut Function,
        scope: &mut HashMap<String, String>,
    ) -> Result<Value> {
        match expr {
            Expr::Number(n) => Ok(Value::Const(*n as u64)),
            Expr::Bool(b) => Ok(Value::Const(if *b { 1 } else { 0 })),
            Expr::Float(_f) => {
                // QBE doesn't have direct float constants in Value::Const, we need to handle this differently
                // For now, bail
                bail!("Float literals not yet supported in QBE backend")
            }
            Expr::String(s) => {
                let label = format!("str_{}", self.string_counter);
                self.string_counter += 1;
                let data = qbe::DataDef::new(
                    Linkage::private(),
                    label.clone(),
                    None,
                    vec![
                        (Type::Byte, qbe::DataItem::Str(s.replace("\n", "\\n").clone())),
                        (Type::Byte, qbe::DataItem::Const(0)),
                    ],
                );
                self.module.add_data(data);
                // Call bars_string_new to create a Bars string object
                let result = self.fresh_temp();
                func.assign_instr(
                    Value::Temporary(result.clone()),
                    Type::Long,
                    Instr::Call(
                        "bars_string_new".to_string(),
                        vec![(Type::Long, Value::Global(label))],
                        None,
                    ),
                );
                Ok(Value::Temporary(result))
            }
            Expr::Symbol(sym) => {
                if sym.0 == "nil" {
                    Ok(Value::Const(0))
                } else if let Some(temp) = scope.get(&sym.0) {
                    Ok(Value::Temporary(temp.clone()))
                } else {
                    // Global function reference or variable
                    Ok(Value::Global(sanitize_name(&sym.0)))
                }
            }
            Expr::Keyword(_) => bail!("Keywords cannot be compiled to QBE IR directly"),
            Expr::List(_, _) => bail!("Bare lists not supported in codegen"),
            Expr::Vector(_, _) => bail!("Vectors not yet supported in QBE backend"),
            Expr::Map(_, _) => bail!("Maps not yet supported in QBE backend"),
            Expr::Quote(_, _) => bail!("Quote not yet supported in QBE backend"),
            Expr::SyntaxQuote(_, _) => bail!("Syntax-quote not yet supported in QBE backend"),
            Expr::Unquote(_, _) => bail!("Unquote not yet supported in QBE backend"),
            Expr::Splicing(_, _) => bail!("Splicing not yet supported in QBE backend"),
            Expr::DefMacro { .. } => bail!("defmacro not supported in QBE backend (should be expanded)"),
            Expr::Borrow(_, _, _) => bail!("Borrow not yet supported in QBE backend"),

            Expr::Let { bindings, body, .. } => {
                // Create new temporaries for bindings
                for (name, val_expr) in bindings {
                    let val = self.compile_expr(val_expr, func, scope)?;
                    let temp = self.fresh_temp();
                    func.assign_instr(
                        Value::Temporary(temp.clone()),
                        Type::Long,
                        Instr::Copy(val),
                    );
                    scope.insert(name.0.clone(), temp);
                }
                self.compile_expr(body, func, scope)
            }

            Expr::If { cond, then_branch, else_branch, .. } => {
                let cond_val = self.compile_expr(cond, func, scope)?;
                let then_label = self.fresh_label("then");
                let else_label = self.fresh_label("else");
                let end_label = self.fresh_label("endif");

                // Allocate stack slot for the result
                let slot = self.fresh_temp();
                func.assign_instr(
                    Value::Temporary(slot.clone()),
                    Type::Long,
                    Instr::Alloc8(8),
                );

                func.add_instr(Instr::Jnz(cond_val, then_label.clone(), else_label.clone()));

                // Then block
                func.add_block(&then_label);
                self.current_block_terminated = false;
                let then_val = self.compile_expr(then_branch, func, scope)?;
                if !self.current_block_terminated {
                    func.add_instr(Instr::Store(Type::Long, Value::Temporary(slot.clone()), then_val));
                    func.add_instr(Instr::Jmp(end_label.clone()));
                    self.current_block_terminated = true;
                }

                // Else block
                func.add_block(&else_label);
                self.current_block_terminated = false;
                let else_val = self.compile_expr(else_branch, func, scope)?;
                if !self.current_block_terminated {
                    func.add_instr(Instr::Store(Type::Long, Value::Temporary(slot.clone()), else_val));
                    func.add_instr(Instr::Jmp(end_label.clone()));
                    self.current_block_terminated = true;
                }

                // End block
                func.add_block(&end_label);
                self.current_block_terminated = false;
                let result = self.fresh_temp();
                func.assign_instr(
                    Value::Temporary(result.clone()),
                    Type::Long,
                    Instr::Load(Type::Long, Value::Temporary(slot)),
                );
                Ok(Value::Temporary(result))
            }

            Expr::Match { expr, arms, .. } => {
                let val = self.compile_expr(expr, func, scope)?;
                let end_label = self.fresh_label("matchend");
                let slot = self.fresh_temp();
                func.assign_instr(
                    Value::Temporary(slot.clone()),
                    Type::Long,
                    Instr::Alloc8(8),
                );

                for (pattern, body) in arms {
                    let match_label = self.fresh_label("matcharm");
                    let next_label = self.fresh_label("matchnext");

                    // Compile pattern match check
                    let matches = self.compile_pattern_check(&val, pattern, func, scope)?;
                    func.add_instr(Instr::Jnz(matches, match_label.clone(), next_label.clone()));

                    // Pattern matches — compile body with bindings
                    func.add_block(&match_label);
                    self.current_block_terminated = false;
                    let mut arm_scope = scope.clone();
                    self.compile_pattern_bindings(&val, pattern, func, &mut arm_scope)?;
                    let body_val = self.compile_expr(body, func, &mut arm_scope)?;
                    if !self.current_block_terminated {
                        func.add_instr(Instr::Store(Type::Long, Value::Temporary(slot.clone()), body_val));
                        func.add_instr(Instr::Jmp(end_label.clone()));
                        self.current_block_terminated = true;
                    }

                    // Next arm
                    func.add_block(&next_label);
                    self.current_block_terminated = false;
                }

                // End block — load result
                func.add_block(&end_label);
                self.current_block_terminated = false;
                let result = self.fresh_temp();
                func.assign_instr(
                    Value::Temporary(result.clone()),
                    Type::Long,
                    Instr::Load(Type::Long, Value::Temporary(slot)),
                );
                Ok(Value::Temporary(result))
            }

            Expr::Do { exprs, .. } => {
                let mut last = Value::Const(0);
                for e in exprs {
                    last = self.compile_expr(e, func, scope)?;
                }
                Ok(last)
            }

            Expr::Loop { bindings, body, .. } => {
                let loop_label = self.fresh_label("loop");
                let end_label = self.fresh_label("loopend");

                // Allocate stack slots for loop variables
                let mut slots = Vec::new();
                for (name, _) in bindings {
                    let slot = self.fresh_temp();
                    func.assign_instr(Value::Temporary(slot.clone()), Type::Long, Instr::Alloc8(8));
                    slots.push((name.0.clone(), slot));
                }

                // Initialize slots
                for ((_name, slot), (_, init_expr)) in slots.iter().zip(bindings.iter()) {
                    let init_val = self.compile_expr(init_expr, func, scope)?;
                    func.add_instr(Instr::Store(Type::Long, Value::Temporary(slot.clone()), init_val));
                }

                // Jump to loop header
                func.add_instr(Instr::Jmp(loop_label.clone()));

                // Loop header: load vars from slots into scope
                func.add_block(&loop_label);
                self.current_block_terminated = false;
                let old_scope = scope.clone();
                for (name, slot) in &slots {
                    let temp = self.fresh_temp();
                    func.assign_instr(
                        Value::Temporary(temp.clone()),
                        Type::Long,
                        Instr::Load(Type::Long, Value::Temporary(slot.clone())),
                    );
                    scope.insert(name.clone(), temp);
                }

                // Set loop context
                let prev_loop = self.loop_context.take();
                self.loop_context = Some((loop_label.clone(), slots));

                // Compile body
                let body_val = self.compile_expr(body, func, scope)?;

                // Restore loop context
                self.loop_context = prev_loop;

                // After body, jump to end (if body was recur, this is unreachable)
                if !self.current_block_terminated {
                    func.add_instr(Instr::Jmp(end_label.clone()));
                    self.current_block_terminated = true;
                }

                // End block
                func.add_block(&end_label);
                self.current_block_terminated = false;

                // Restore scope (loop vars are local)
                *scope = old_scope;

                Ok(body_val)
            }

            Expr::Recur { args, .. } => {
                let (loop_label, slots) = self.loop_context
                    .as_ref()
                    .ok_or_else(|| anyhow::anyhow!("recur used outside of loop"))?
                    .clone();

                if args.len() != slots.len() {
                    bail!("recur arity mismatch: expected {}, got {}", slots.len(), args.len());
                }

                // Compute new values and store into slots
                for (arg, (_, slot)) in args.iter().zip(slots.iter()) {
                    let val = self.compile_expr(arg, func, scope)?;
                    func.add_instr(Instr::Store(Type::Long, Value::Temporary(slot.clone()), val));
                }

                // Jump back to loop header
                func.add_instr(Instr::Jmp(loop_label));
                self.current_block_terminated = true;

                Ok(Value::Const(0))
            }

            Expr::FnCall { func: func_expr, args, .. } => {
                let func_name_raw = match func_expr.as_ref() {
                    Expr::Symbol(sym) => sym.0.clone(),
                    _ => bail!("Only direct function calls supported in QBE backend"),
                };

                let mut compiled_args = Vec::new();
                for arg in args {
                    let val = self.compile_expr(arg, func, scope)?;
                    compiled_args.push((Type::Long, val));
                }

                // Check if this is a struct constructor
                if let Some(fields) = self.struct_registry.get(&func_name_raw) {
                    if args.len() != fields.len() {
                        bail!("Struct constructor {} expects {} arguments, got {}", func_name_raw, fields.len(), args.len());
                    }
                    let size = fields.len() * 8;
                    let ptr = self.fresh_temp();
                    func.assign_instr(
                        Value::Temporary(ptr.clone()),
                        Type::Long,
                        Instr::Alloc8(size as u64),
                    );
                    for (i, arg) in compiled_args.iter().enumerate() {
                        let offset = (i * 8) as u64;
                        let addr = self.fresh_temp();
                        func.assign_instr(
                            Value::Temporary(addr.clone()),
                            Type::Long,
                            Instr::Add(Value::Temporary(ptr.clone()), Value::Const(offset)),
                        );
                        func.add_instr(Instr::Store(Type::Long, Value::Temporary(addr), arg.1.clone()));
                    }
                    return Ok(Value::Temporary(ptr));
                }

                // Handle built-in arithmetic operators (before name sanitization)
                match func_name_raw.as_str() {
                    "+" | "-" | "*" | "/" | "%" if compiled_args.len() == 2 => {
                        let instr = match func_name_raw.as_str() {
                            "+" => Instr::Add(compiled_args[0].1.clone(), compiled_args[1].1.clone()),
                            "-" => Instr::Sub(compiled_args[0].1.clone(), compiled_args[1].1.clone()),
                            "*" => Instr::Mul(compiled_args[0].1.clone(), compiled_args[1].1.clone()),
                            "/" => Instr::Div(compiled_args[0].1.clone(), compiled_args[1].1.clone()),
                            "%" => Instr::Rem(compiled_args[0].1.clone(), compiled_args[1].1.clone()),
                            _ => unreachable!(),
                        };
                        let result = self.fresh_temp();
                        func.assign_instr(Value::Temporary(result.clone()), Type::Long, instr);
                        Ok(Value::Temporary(result))
                    }
                    "not" if compiled_args.len() == 1 => {
                        let result = self.fresh_temp();
                        func.assign_instr(
                            Value::Temporary(result.clone()),
                            Type::Long,
                            Instr::Cmp(Type::Long, Cmp::Eq, compiled_args[0].1.clone(), Value::Const(0)),
                        );
                        Ok(Value::Temporary(result))
                    }
                    "<" | ">" | "=" | "<=" | ">=" | "!=" if compiled_args.len() == 2 => {
                        let cmp = match func_name_raw.as_str() {
                            "<" => Cmp::Slt,
                            ">" => Cmp::Sgt,
                            "=" => Cmp::Eq,
                            "<=" => Cmp::Sle,
                            ">=" => Cmp::Sge,
                            "!=" => Cmp::Ne,
                            _ => unreachable!(),
                        };
                        let result = self.fresh_temp();
                        func.assign_instr(
                            Value::Temporary(result.clone()),
                            Type::Long,
                            Instr::Cmp(Type::Long, cmp, compiled_args[0].1.clone(), compiled_args[1].1.clone()),
                        );
                        Ok(Value::Temporary(result))
                    }
                    "println" => {
                        if compiled_args.is_empty() {
                            func.assign_instr(
                                Value::Temporary(self.fresh_temp()),
                                Type::Long,
                                Instr::Call("bars_print_newline".to_string(), vec![], None),
                            );
                        } else if matches!(args.get(0), Some(Expr::String(_))) {
                            // Print a Bars string
                            func.assign_instr(
                                Value::Temporary(self.fresh_temp()),
                                Type::Long,
                                Instr::Call(
                                    "bars_print_string".to_string(),
                                    vec![compiled_args[0].clone()],
                                    None,
                                ),
                            );
                            func.assign_instr(
                                Value::Temporary(self.fresh_temp()),
                                Type::Long,
                                Instr::Call("bars_print_newline".to_string(), vec![], None),
                            );
                        } else {
                            // Print integer
                            let fmt = self.add_string_literal("%ld\n");
                            func.assign_instr(
                                Value::Temporary(self.fresh_temp()),
                                Type::Word,
                                Instr::Call(
                                    "printf".to_string(),
                                    vec![(Type::Long, fmt), compiled_args[0].clone()],
                                    None,
                                ),
                            );
                        }
                        Ok(Value::Const(0))
                    }
                    "vector" => {
                        // Create new vector and push all arguments
                        let vec_temp = self.fresh_temp();
                        func.assign_instr(
                            Value::Temporary(vec_temp.clone()),
                            Type::Long,
                            Instr::Call("bars_vector_new_i64".to_string(), vec![], None),
                        );
                        for arg in &compiled_args {
                            func.assign_instr(
                                Value::Temporary(self.fresh_temp()),
                                Type::Long,
                                Instr::Call(
                                    "bars_vector_push_i64".to_string(),
                                    vec![(Type::Long, Value::Temporary(vec_temp.clone())), arg.clone()],
                                    None,
                                ),
                            );
                        }
                        Ok(Value::Temporary(vec_temp))
                    }
                    "push" if compiled_args.len() == 2 => {
                        func.assign_instr(
                            Value::Temporary(self.fresh_temp()),
                            Type::Long,
                            Instr::Call(
                                "bars_vector_push_i64".to_string(),
                                compiled_args.clone(),
                                None,
                            ),
                        );
                        Ok(Value::Const(0))
                    }
                    "get" if compiled_args.len() == 2 => {
                        let result = self.fresh_temp();
                        func.assign_instr(
                            Value::Temporary(result.clone()),
                            Type::Long,
                            Instr::Call(
                                "bars_vector_get_i64".to_string(),
                                compiled_args.clone(),
                                None,
                            ),
                        );
                        Ok(Value::Temporary(result))
                    }
                    "count" if compiled_args.len() == 1 => {
                        let result = self.fresh_temp();
                        func.assign_instr(
                            Value::Temporary(result.clone()),
                            Type::Long,
                            Instr::Call(
                                "bars_vector_count_i64".to_string(),
                                compiled_args.clone(),
                                None,
                            ),
                        );
                        Ok(Value::Temporary(result))
                    }
                    "map" => {
                        let result = self.fresh_temp();
                        func.assign_instr(
                            Value::Temporary(result.clone()),
                            Type::Long,
                            Instr::Call("bars_map_new_i64".to_string(), vec![], None),
                        );
                        Ok(Value::Temporary(result))
                    }
                    "map-set" if compiled_args.len() == 3 => {
                        func.assign_instr(
                            Value::Temporary(self.fresh_temp()),
                            Type::Long,
                            Instr::Call(
                                "bars_map_set_i64".to_string(),
                                compiled_args.clone(),
                                None,
                            ),
                        );
                        Ok(Value::Const(0))
                    }
                    "map-get" if compiled_args.len() == 2 => {
                        let result = self.fresh_temp();
                        func.assign_instr(
                            Value::Temporary(result.clone()),
                            Type::Long,
                            Instr::Call(
                                "bars_map_get_i64".to_string(),
                                compiled_args.clone(),
                                None,
                            ),
                        );
                        Ok(Value::Temporary(result))
                    }
                    "map-count" if compiled_args.len() == 1 => {
                        let result = self.fresh_temp();
                        func.assign_instr(
                            Value::Temporary(result.clone()),
                            Type::Long,
                            Instr::Call(
                                "bars_map_count_i64".to_string(),
                                compiled_args.clone(),
                                None,
                            ),
                        );
                        Ok(Value::Temporary(result))
                    }
                    _ => {
                        // Generic function call
                        let result = self.fresh_temp();
                        func.assign_instr(
                            Value::Temporary(result.clone()),
                            Type::Long,
                            Instr::Call(sanitize_name(&func_name_raw), compiled_args, None),
                        );
                        Ok(Value::Temporary(result))
                    }
                }
            }

            Expr::FieldAccess { expr, field, .. } => {
                let ptr = self.compile_expr(expr, func, scope)?;
                // Look up struct type from the expression
                // For now, we can't easily know the struct type from just the AST
                // We'll need to track types. For simplicity, we'll look for a struct
                // whose field names include this field.
                let mut found_offset = None;
                for (struct_name, fields) in &self.struct_registry {
                    for (i, f) in fields.iter().enumerate() {
                        if f == &field.0 {
                            found_offset = Some((struct_name.clone(), i));
                            break;
                        }
                    }
                    if found_offset.is_some() {
                        break;
                    }
                }
                let (_, offset_idx) = found_offset
                    .ok_or_else(|| anyhow::anyhow!("Unknown field '{}' in field access", field.0))?;
                let offset = (offset_idx * 8) as u64;
                let addr = self.fresh_temp();
                func.assign_instr(
                    Value::Temporary(addr.clone()),
                    Type::Long,
                    Instr::Add(
                        match &ptr {
                            Value::Temporary(t) => Value::Temporary(t.clone()),
                            Value::Global(g) => Value::Global(g.clone()),
                            Value::Const(c) => Value::Const(*c),
                        },
                        Value::Const(offset),
                    ),
                );
                let result = self.fresh_temp();
                func.assign_instr(
                    Value::Temporary(result.clone()),
                    Type::Long,
                    Instr::Load(Type::Long, Value::Temporary(addr)),
                );
                Ok(Value::Temporary(result))
            }

            Expr::Def { name, value, .. } => {
                let val = self.compile_expr(value, func, scope)?;
                let temp = self.fresh_temp();
                func.assign_instr(
                    Value::Temporary(temp.clone()),
                    Type::Long,
                    Instr::Copy(val),
                );
                scope.insert(name.0.clone(), temp);
                Ok(Value::Temporary(name.0.clone()))
            }

            Expr::Defn { .. } => {
                // Nested defn not supported in expression context
                bail!("Nested defn not supported in QBE backend")
            }
            Expr::DefStruct { .. } => {
                bail!("defstruct not supported in QBE expression context")
            }
        }
    }

    fn add_string_literal(&mut self, s: &str) -> Value {
        let label = format!("fmt_{}", self.string_counter);
        self.string_counter += 1;
        let data = qbe::DataDef::new(
            Linkage::private(),
            label.clone(),
            None,
            vec![
                (Type::Byte, qbe::DataItem::Str(s.replace("\n", "\\n").to_string())),
                (Type::Byte, qbe::DataItem::Const(0)),
            ],
        );
        self.module.add_data(data);
        Value::Global(label)
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

    fn compile_pattern_check(
        &mut self,
        val: &Value,
        pattern: &Pattern,
        func: &mut Function,
        _scope: &HashMap<String, String>,
    ) -> Result<Value> {
        match pattern {
            Pattern::Wildcard | Pattern::Binding(_) => {
                // Always matches
                Ok(Value::Const(1))
            }
            Pattern::Literal(Expr::Number(n)) => {
                let result = self.fresh_temp();
                func.assign_instr(
                    Value::Temporary(result.clone()),
                    Type::Long,
                    Instr::Cmp(Type::Long, Cmp::Eq, val.clone(), Value::Const(*n as u64)),
                );
                Ok(Value::Temporary(result))
            }
            Pattern::Literal(Expr::Bool(b)) => {
                let result = self.fresh_temp();
                func.assign_instr(
                    Value::Temporary(result.clone()),
                    Type::Long,
                    Instr::Cmp(Type::Long, Cmp::Eq, val.clone(), Value::Const(if *b { 1 } else { 0 })),
                );
                Ok(Value::Temporary(result))
            }
            Pattern::Literal(Expr::Keyword(k)) => {
                // Keywords are interned strings — compare by pointer/identity
                // For now, compare the string content by calling strcmp
                let keyword_label = self.add_string_literal(&k.0);
                let result = self.fresh_temp();
                func.assign_instr(
                    Value::Temporary(result.clone()),
                    Type::Word,
                    Instr::Call(
                        "strcmp".to_string(),
                        vec![(Type::Long, val.clone()), (Type::Long, keyword_label)],
                        None,
                    ),
                );
                // strcmp returns 0 on match
                let is_eq = self.fresh_temp();
                func.assign_instr(
                    Value::Temporary(is_eq.clone()),
                    Type::Long,
                    Instr::Cmp(Type::Long, Cmp::Eq, Value::Temporary(result), Value::Const(0)),
                );
                Ok(Value::Temporary(is_eq))
            }
            Pattern::Literal(Expr::String(s)) => {
                let str_label = self.add_string_literal(s);
                let result = self.fresh_temp();
                func.assign_instr(
                    Value::Temporary(result.clone()),
                    Type::Word,
                    Instr::Call(
                        "strcmp".to_string(),
                        vec![(Type::Long, val.clone()), (Type::Long, str_label)],
                        None,
                    ),
                );
                let is_eq = self.fresh_temp();
                func.assign_instr(
                    Value::Temporary(is_eq.clone()),
                    Type::Long,
                    Instr::Cmp(Type::Long, Cmp::Eq, Value::Temporary(result), Value::Const(0)),
                );
                Ok(Value::Temporary(is_eq))
            }
            Pattern::Vector(_, _) | Pattern::List(_, _) => {
                bail!("Vector/List patterns not yet supported in QBE backend")
            }
            Pattern::Struct { name, fields } => {
                // Get struct field info
                let struct_fields = self.struct_registry.get(&name.0)
                    .ok_or_else(|| anyhow::anyhow!("Unknown struct '{}' in pattern", name.0))?;
                if fields.len() != struct_fields.len() {
                    bail!("Struct pattern {} field count mismatch: expected {}, got {}", name.0, struct_fields.len(), fields.len());
                }
                // AND together all field matches
                let mut overall = Value::Const(1);
                for (i, field_pat) in fields.iter().enumerate() {
                    let offset = (i * 8) as u64;
                    let addr = self.fresh_temp();
                    func.assign_instr(
                        Value::Temporary(addr.clone()),
                        Type::Long,
                        Instr::Add(
                            match val {
                                Value::Temporary(t) => Value::Temporary(t.clone()),
                                Value::Global(g) => Value::Global(g.clone()),
                                Value::Const(c) => Value::Const(*c),
                            },
                            Value::Const(offset),
                        ),
                    );
                    let field_val = self.fresh_temp();
                    func.assign_instr(
                        Value::Temporary(field_val.clone()),
                        Type::Long,
                        Instr::Load(Type::Long, Value::Temporary(addr)),
                    );
                    let field_match = self.compile_pattern_check(&Value::Temporary(field_val), field_pat, func, _scope)?;
                    let new_overall = self.fresh_temp();
                    func.assign_instr(
                        Value::Temporary(new_overall.clone()),
                        Type::Long,
                        Instr::And(overall, field_match),
                    );
                    overall = Value::Temporary(new_overall);
                }
                Ok(overall)
            }
            other => bail!("Unsupported pattern in QBE backend: {:?}", other),
        }
    }

    fn compile_pattern_bindings(
        &mut self,
        val: &Value,
        pattern: &Pattern,
        _func: &mut Function,
        scope: &mut HashMap<String, String>,
    ) -> Result<()> {
        match pattern {
            Pattern::Binding(sym) => {
                scope.insert(sym.0.clone(), match val {
                    Value::Temporary(t) => t.clone(),
                    Value::Global(g) => g.clone(),
                    Value::Const(c) => {
                        // We need a temporary for constants
                        // This is handled by the caller storing the value
                        format!("const_{}", c)
                    }
                });
                Ok(())
            }
            Pattern::Vector(patterns, _) | Pattern::List(patterns, _) => {
                for p in patterns {
                    self.compile_pattern_bindings(val, p, _func, scope)?;
                }
                Ok(())
            }
            Pattern::Struct { name, fields } => {
                let struct_fields = self.struct_registry.get(&name.0)
                    .ok_or_else(|| anyhow::anyhow!("Unknown struct '{}' in pattern bindings", name.0))?;
                for (i, field_pat) in fields.iter().enumerate() {
                    let offset = (i * 8) as u64;
                    let addr = self.fresh_temp();
                    _func.assign_instr(
                        Value::Temporary(addr.clone()),
                        Type::Long,
                        Instr::Add(
                            match val {
                                Value::Temporary(t) => Value::Temporary(t.clone()),
                                Value::Global(g) => Value::Global(g.clone()),
                                Value::Const(c) => Value::Const(*c),
                            },
                            Value::Const(offset),
                        ),
                    );
                    let field_val = self.fresh_temp();
                    _func.assign_instr(
                        Value::Temporary(field_val.clone()),
                        Type::Long,
                        Instr::Load(Type::Long, Value::Temporary(addr)),
                    );
                    self.compile_pattern_bindings(&Value::Temporary(field_val), field_pat, _func, scope)?;
                }
                Ok(())
            }
            _ => Ok(()),
        }
    }

    fn ast_type_to_qbe(ty: &AstType) -> Option<Type> {
        match ty {
            AstType::I64 => Some(Type::Long),
            AstType::F64 => Some(Type::Double),
            AstType::Bool => Some(Type::Word),
            AstType::Void => None,
            _ => Some(Type::Long),
        }
    }
}

impl Default for QbeBackend {
    fn default() -> Self {
        Self::new()
    }
}
