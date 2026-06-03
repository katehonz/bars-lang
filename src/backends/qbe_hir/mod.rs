use crate::backends::sanitize_name;
use crate::hir;
use anyhow::Result;
use qbe::{Cmp, Function, Instr, Linkage, Module, Type, Value};
use std::collections::HashMap;

pub struct QbeHIRBackend {
    module: Module,
    temp_counter: usize,
    string_counter: usize,
    struct_registry: HashMap<String, Vec<String>>,
    string_temps: HashMap<String, ()>,
}

impl QbeHIRBackend {
    pub fn new() -> Self {
        Self {
            module: Module::new(),
            temp_counter: 0,
            string_counter: 0,
            struct_registry: HashMap::new(),
            string_temps: HashMap::new(),
        }
    }

    pub fn compile(mut self, program: &hir::Program) -> Result<String> {
        for func in &program.funcs {
            if func.is_extern {
                continue; // Extern functions are resolved at link time
            }
            self.compile_func(func)?;
        }
        Ok(self.module.to_string())
    }

    pub fn add_struct(&mut self, name: &str, fields: Vec<String>) {
        self.struct_registry.insert(name.to_string(), fields);
    }

    fn compile_func(&mut self, func: &hir::Func) -> Result<()> {
        let sanitized = sanitize_name(&func.name);
        let mut qbe_func = Function::new(
            Linkage::public(),
            &sanitized,
            func.params.iter().map(|p| (Type::Long, Value::Temporary(p.clone()))).collect(),
            Some(Type::Long),
        );

        let mut block_labels: HashMap<String, String> = HashMap::new();
        for block in &func.blocks {
            let qbe_label = sanitize_name(&block.label);
            block_labels.insert(block.label.clone(), qbe_label);
        }

        for (_i, block) in func.blocks.iter().enumerate() {
            qbe_func.add_block(&block_labels[&block.label]);

            for instr in &block.instrs {
                self.compile_instr(instr, &mut qbe_func)?;
            }

            self.compile_terminator(&block.terminator, &mut qbe_func, &block_labels)?;
        }

        self.module.add_function(qbe_func);
        Ok(())
    }

    fn compile_instr(&mut self, instr: &hir::Instr, func: &mut Function) -> Result<()> {
        match instr {
            hir::Instr::Assign { dest, value } => {
                let val = self.operand_to_value(value);
                func.assign_instr(Value::Temporary(dest.clone()), Type::Long, Instr::Copy(val));
            }
            hir::Instr::Const { dest, value } => {
                func.assign_instr(Value::Temporary(dest.clone()), Type::Long, Instr::Copy(Value::Const(*value as u64)));
            }
            hir::Instr::Alloc { dest, size } => {
                func.assign_instr(Value::Temporary(dest.clone()), Type::Long, Instr::Alloc8(*size as u64));
            }
            hir::Instr::Store { addr, value } => {
                let a = self.operand_to_value(addr);
                let v = self.operand_to_value(value);
                func.add_instr(Instr::Store(Type::Long, a, v));
            }
            hir::Instr::Load { dest, addr } => {
                let a = self.operand_to_value(addr);
                func.assign_instr(Value::Temporary(dest.clone()), Type::Long, Instr::Load(Type::Long, a));
            }
            hir::Instr::FieldLoad { dest, base, offset } => {
                let base_val = self.operand_to_value(base);
                let addr = self.fresh_temp();
                func.assign_instr(Value::Temporary(addr.clone()), Type::Long, Instr::Add(base_val, Value::Const(*offset as u64)));
                func.assign_instr(Value::Temporary(dest.clone()), Type::Long, Instr::Load(Type::Long, Value::Temporary(addr)));
            }
            hir::Instr::FieldStore { base, offset, value } => {
                let base_val = self.operand_to_value(base);
                let addr = self.fresh_temp();
                func.assign_instr(Value::Temporary(addr.clone()), Type::Long, Instr::Add(base_val, Value::Const(*offset as u64)));
                let v = self.operand_to_value(value);
                func.add_instr(Instr::Store(Type::Long, Value::Temporary(addr), v));
            }
            hir::Instr::BinOp { dest, op, lhs, rhs } => {
                let lhs_val = self.operand_to_value(lhs);
                let rhs_val = self.operand_to_value(rhs);
                let qbe_op = match op {
                    hir::BinOp::Add => Instr::Add(lhs_val, rhs_val),
                    hir::BinOp::Sub => Instr::Sub(lhs_val, rhs_val),
                    hir::BinOp::Mul => Instr::Mul(lhs_val, rhs_val),
                    hir::BinOp::Div => Instr::Div(lhs_val, rhs_val),
                    hir::BinOp::Rem => Instr::Rem(lhs_val, rhs_val),
                    hir::BinOp::Eq => Instr::Cmp(Type::Long, Cmp::Eq, lhs_val, rhs_val),
                    hir::BinOp::Ne => Instr::Cmp(Type::Long, Cmp::Ne, lhs_val, rhs_val),
                    hir::BinOp::Lt => Instr::Cmp(Type::Long, Cmp::Slt, lhs_val, rhs_val),
                    hir::BinOp::Le => Instr::Cmp(Type::Long, Cmp::Sle, lhs_val, rhs_val),
                    hir::BinOp::Gt => Instr::Cmp(Type::Long, Cmp::Sgt, lhs_val, rhs_val),
                    hir::BinOp::Ge => Instr::Cmp(Type::Long, Cmp::Sge, lhs_val, rhs_val),
                };
                func.assign_instr(Value::Temporary(dest.clone()), Type::Long, qbe_op);
            }
            hir::Instr::UnOp { dest, op, operand } => {
                let val = self.operand_to_value(operand);
                match op {
                    hir::UnOp::Not => {
                        func.assign_instr(Value::Temporary(dest.clone()), Type::Long, Instr::Cmp(Type::Long, Cmp::Eq, val, Value::Const(0)));
                    }
                }
            }
            hir::Instr::Call { dest, func: func_name, args } => {
                let compiled_args: Vec<_> = args.iter()
                    .map(|a| (Type::Long, self.operand_to_value(a)))
                    .collect();

                // Check if this is a struct constructor
                if let Some(fields) = self.struct_registry.get(func_name) {
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
                    func.assign_instr(
                        Value::Temporary(dest.clone()),
                        Type::Long,
                        Instr::Copy(Value::Temporary(ptr)),
                    );
                    return Ok(());
                }

                // Handle built-in operators and runtime functions
                match func_name.as_str() {
                    "+" | "-" | "*" | "/" | "%" | "=" | "!=" | "<" | "<=" | ">" | ">=" if args.len() == 2 => {
                        let lhs = self.operand_to_value(&args[0]);
                        let rhs = self.operand_to_value(&args[1]);
                        let instr = match func_name.as_str() {
                            "+" => Instr::Add(lhs, rhs),
                            "-" => Instr::Sub(lhs, rhs),
                            "*" => Instr::Mul(lhs, rhs),
                            "/" => Instr::Div(lhs, rhs),
                            "%" => Instr::Rem(lhs, rhs),
                            "=" => Instr::Cmp(Type::Long, Cmp::Eq, lhs, rhs),
                            "!=" => Instr::Cmp(Type::Long, Cmp::Ne, lhs, rhs),
                            "<" => Instr::Cmp(Type::Long, Cmp::Slt, lhs, rhs),
                            "<=" => Instr::Cmp(Type::Long, Cmp::Sle, lhs, rhs),
                            ">" => Instr::Cmp(Type::Long, Cmp::Sgt, lhs, rhs),
                            ">=" => Instr::Cmp(Type::Long, Cmp::Sge, lhs, rhs),
                            _ => unreachable!(),
                        };
                        func.assign_instr(Value::Temporary(dest.clone()), Type::Long, instr);
                    }
                    "not" if args.len() == 1 => {
                        let val = self.operand_to_value(&args[0]);
                        func.assign_instr(
                            Value::Temporary(dest.clone()),
                            Type::Long,
                            Instr::Cmp(Type::Long, Cmp::Eq, val, Value::Const(0)),
                        );
                    }
                    "println" => {
                        if args.is_empty() {
                            func.add_instr(
                                Instr::Call("bars_print_newline".to_string(), vec![], None),
                            );
                        } else if self.is_string_arg(&args[0]) {
                            // Print a Bars string
                            func.add_instr(
                                Instr::Call(
                                    "bars_print_string".to_string(),
                                    vec![compiled_args[0].clone()],
                                    None,
                                ),
                            );
                            func.add_instr(
                                Instr::Call("bars_print_newline".to_string(), vec![], None),
                            );
                        } else if matches!(args[0], hir::Operand::Const(_)) {
                            // Print integer constant
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
                        } else {
                            // Dynamic type detection via magic number
                            func.add_instr(
                                Instr::Call(
                                    "bars_print_any_i64".to_string(),
                                    vec![compiled_args[0].clone()],
                                    None,
                                ),
                            );
                            func.add_instr(
                                Instr::Call("bars_print_newline".to_string(), vec![], None),
                            );
                        }
                        func.assign_instr(
                            Value::Temporary(dest.clone()),
                            Type::Long,
                            Instr::Copy(Value::Const(0)),
                        );
                    }
                    "vector" => {
                        // Create new vector and push all arguments
                        let ptr = self.fresh_temp();
                        func.assign_instr(
                            Value::Temporary(ptr.clone()),
                            Type::Long,
                            Instr::Call("bars_vector_new_i64".to_string(), vec![], None),
                        );
                        for arg in &compiled_args {
                            func.assign_instr(
                                Value::Temporary(self.fresh_temp()),
                                Type::Long,
                                Instr::Call(
                                    "bars_vector_push_i64".to_string(),
                                    vec![(Type::Long, Value::Temporary(ptr.clone())), arg.clone()],
                                    None,
                                ),
                            );
                        }
                        func.assign_instr(
                            Value::Temporary(dest.clone()),
                            Type::Long,
                            Instr::Copy(Value::Temporary(ptr)),
                        );
                    }
                    "push" if compiled_args.len() == 2 => {
                        func.assign_instr(
                            Value::Temporary(dest.clone()),
                            Type::Long,
                            Instr::Call(
                                "bars_vector_push_i64".to_string(),
                                compiled_args.clone(),
                                None,
                            ),
                        );
                    }
                    "get" if compiled_args.len() == 2 => {
                        func.assign_instr(
                            Value::Temporary(dest.clone()),
                            Type::Long,
                            Instr::Call(
                                "bars_vector_get_i64".to_string(),
                                compiled_args.clone(),
                                None,
                            ),
                        );
                    }
                    "count" if compiled_args.len() == 1 => {
                        func.assign_instr(
                            Value::Temporary(dest.clone()),
                            Type::Long,
                            Instr::Call(
                                "bars_vector_count_i64".to_string(),
                                compiled_args.clone(),
                                None,
                            ),
                        );
                    }
                    "map" => {
                        func.assign_instr(
                            Value::Temporary(dest.clone()),
                            Type::Long,
                            Instr::Call("bars_map_new_i64".to_string(), vec![], None),
                        );
                    }
                    "map_set" | "map-set" if compiled_args.len() == 3 => {
                        func.assign_instr(
                            Value::Temporary(dest.clone()),
                            Type::Long,
                            Instr::Call(
                                "bars_map_set_i64".to_string(),
                                compiled_args.clone(),
                                None,
                            ),
                        );
                    }
                    "map_get" | "map-get" if compiled_args.len() == 2 => {
                        func.assign_instr(
                            Value::Temporary(dest.clone()),
                            Type::Long,
                            Instr::Call(
                                "bars_map_get_i64".to_string(),
                                compiled_args.clone(),
                                None,
                            ),
                        );
                    }
                    "map_count" | "map-count" if compiled_args.len() == 1 => {
                        func.assign_instr(
                            Value::Temporary(dest.clone()),
                            Type::Long,
                            Instr::Call(
                                "bars_map_count_i64".to_string(),
                                compiled_args.clone(),
                                None,
                            ),
                        );
                    }
                    "set" => {
                        func.assign_instr(
                            Value::Temporary(dest.clone()),
                            Type::Long,
                            Instr::Call("bars_set_new_i64".to_string(), vec![], None),
                        );
                    }
                    "set_add" | "set-add" if compiled_args.len() == 2 => {
                        func.assign_instr(
                            Value::Temporary(dest.clone()),
                            Type::Long,
                            Instr::Call(
                                "bars_set_add_i64".to_string(),
                                compiled_args.clone(),
                                None,
                            ),
                        );
                    }
                    "set_contains?" | "set-contains?" if compiled_args.len() == 2 => {
                        func.assign_instr(
                            Value::Temporary(dest.clone()),
                            Type::Long,
                            Instr::Call(
                                "bars_set_contains_i64".to_string(),
                                compiled_args.clone(),
                                None,
                            ),
                        );
                    }
                    "set_count" | "set-count" if compiled_args.len() == 1 => {
                        func.assign_instr(
                            Value::Temporary(dest.clone()),
                            Type::Long,
                            Instr::Call(
                                "bars_set_count_i64".to_string(),
                                compiled_args.clone(),
                                None,
                            ),
                        );
                    }
                    // Math
                    "sqrt" if compiled_args.len() == 1 => {
                        func.assign_instr(
                            Value::Temporary(dest.clone()),
                            Type::Long,
                            Instr::Call(
                                "bars_sqrt_i64".to_string(),
                                compiled_args.clone(),
                                None,
                            ),
                        );
                    }
                    "pow" if compiled_args.len() == 2 => {
                        func.assign_instr(
                            Value::Temporary(dest.clone()),
                            Type::Long,
                            Instr::Call(
                                "bars_pow_i64".to_string(),
                                compiled_args.clone(),
                                None,
                            ),
                        );
                    }
                    "abs" if compiled_args.len() == 1 => {
                        func.assign_instr(
                            Value::Temporary(dest.clone()),
                            Type::Long,
                            Instr::Call(
                                "bars_abs_i64".to_string(),
                                compiled_args.clone(),
                                None,
                            ),
                        );
                    }
                    // String ops
                    "str-count" | "str_count" if compiled_args.len() == 1 => {
                        func.assign_instr(
                            Value::Temporary(dest.clone()),
                            Type::Long,
                            Instr::Call(
                                "bars_string_length".to_string(),
                                compiled_args.clone(),
                                None,
                            ),
                        );
                    }
                    "str-concat" | "str_concat" if compiled_args.len() == 2 => {
                        func.assign_instr(
                            Value::Temporary(dest.clone()),
                            Type::Long,
                            Instr::Call(
                                "bars_string_concat".to_string(),
                                compiled_args.clone(),
                                None,
                            ),
                        );
                    }
                    // I/O
                    "slurp" if compiled_args.len() == 1 => {
                        func.assign_instr(
                            Value::Temporary(dest.clone()),
                            Type::Long,
                            Instr::Call(
                                "bars_slurp".to_string(),
                                compiled_args.clone(),
                                None,
                            ),
                        );
                    }
                    "spit" if compiled_args.len() == 2 => {
                        func.assign_instr(
                            Value::Temporary(dest.clone()),
                            Type::Long,
                            Instr::Call(
                                "bars_spit".to_string(),
                                compiled_args.clone(),
                                None,
                            ),
                        );
                    }
                    _ => {
                        func.assign_instr(
                            Value::Temporary(dest.clone()),
                            Type::Long,
                            Instr::Call(sanitize_name(func_name), compiled_args, None),
                        );
                    }
                }
            }
            hir::Instr::StringLit { dest, content } => {
                let label = self.add_string_literal(content);
                func.assign_instr(
                    Value::Temporary(dest.clone()),
                    Type::Long,
                    Instr::Call("bars_string_new".to_string(), vec![(Type::Long, label)], None),
                );
                self.string_temps.insert(dest.clone(), ());
            }
        }
        Ok(())
    }

    fn compile_terminator(
        &mut self,
        term: &hir::Terminator,
        func: &mut Function,
        block_labels: &HashMap<String, String>,
    ) -> Result<()> {
        match term {
            hir::Terminator::Jump(label) => {
                func.add_instr(Instr::Jmp(block_labels[label].clone()));
            }
            hir::Terminator::Branch { cond, then_block, else_block } => {
                let cond_val = self.operand_to_value(cond);
                func.add_instr(Instr::Jnz(cond_val, block_labels[then_block].clone(), block_labels[else_block].clone()));
            }
            hir::Terminator::Return(val) => {
                let ret_val = self.operand_to_value(val);
                func.add_instr(Instr::Ret(Some(ret_val)));
            }
            hir::Terminator::Unreachable => {
                func.add_instr(Instr::Ret(Some(Value::Const(0))));
            }
            hir::Terminator::TailCall { func: func_name, args } => {
                let compiled_args: Vec<_> = args.iter()
                    .map(|a| (Type::Long, self.operand_to_value(a)))
                    .collect();
                let dest = self.fresh_temp();
                func.assign_instr(
                    Value::Temporary(dest.clone()),
                    Type::Long,
                    Instr::Call(sanitize_name(func_name), compiled_args, None),
                );
                func.add_instr(Instr::Ret(Some(Value::Temporary(dest))));
            }
        }
        Ok(())
    }

    fn operand_to_value(&self, op: &hir::Operand) -> Value {
        match op {
            hir::Operand::Var(v) => Value::Temporary(v.clone()),
            hir::Operand::Const(c) => Value::Const(*c as u64),
        }
    }

    fn is_string_arg(&self, arg: &hir::Operand) -> bool {
        match arg {
            hir::Operand::Var(v) => self.string_temps.contains_key(v),
            _ => false,
        }
    }

    fn fresh_temp(&mut self) -> String {
        let t = format!("_t{}", self.temp_counter);
        self.temp_counter += 1;
        t
    }

    fn add_string_literal(&mut self, s: &str) -> Value {
        let label = format!("str_{}", self.string_counter);
        self.string_counter += 1;
        let data = qbe::DataDef::new(
            Linkage::private(),
            label.clone(),
            None,
            vec![
                (Type::Byte, qbe::DataItem::Str(s.replace('\n', "\\n"))),
                (Type::Byte, qbe::DataItem::Const(0)),
            ],
        );
        self.module.add_data(data);
        Value::Global(label)
    }
}

impl Default for QbeHIRBackend {
    fn default() -> Self {
        Self::new()
    }
}
