use crate::backends::qbe::sanitize_name;
use crate::hir;
use anyhow::{bail, Result};
use qbe::{Cmp, Function, Instr, Linkage, Module, Type, Value};
use std::collections::HashMap;

pub struct QbeHIRBackend {
    module: Module,
    temp_counter: usize,
    string_counter: usize,
    struct_registry: HashMap<String, Vec<String>>,
}

impl QbeHIRBackend {
    pub fn new() -> Self {
        Self {
            module: Module::new(),
            temp_counter: 0,
            string_counter: 0,
            struct_registry: HashMap::new(),
        }
    }

    pub fn compile(mut self, program: &hir::Program) -> Result<String> {
        for func in &program.funcs {
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

        for (i, block) in func.blocks.iter().enumerate() {
            if i == 0 {
                qbe_func.add_block(&block_labels[&block.label]);
            } else {
                qbe_func.add_block(&block_labels[&block.label]);
            }

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
                            func.assign_instr(
                                Value::Temporary(self.fresh_temp()),
                                Type::Long,
                                Instr::Call("bars_print_newline".to_string(), vec![], None),
                            );
                        } else {
                            // Print integer for now
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
                        func.assign_instr(
                            Value::Temporary(dest.clone()),
                            Type::Long,
                            Instr::Copy(Value::Const(0)),
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
            hir::Terminator::Unreachable => {}
        }
        Ok(())
    }

    fn operand_to_value(&self, op: &hir::Operand) -> Value {
        match op {
            hir::Operand::Var(v) => Value::Temporary(v.clone()),
            hir::Operand::Const(c) => Value::Const(*c as u64),
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
