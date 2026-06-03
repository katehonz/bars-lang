use crate::hir;
use anyhow::{bail, Result};
use inkwell::builder::Builder;
use inkwell::context::Context;
use inkwell::module::Module;
use inkwell::types::{IntType, VoidType};
use inkwell::values::{FunctionValue, IntValue, PointerValue};
use inkwell::basic_block::BasicBlock;
use inkwell::targets::{Target, TargetMachine, FileType, RelocMode, CodeModel, InitializationConfig};
use inkwell::{OptimizationLevel, IntPredicate, AddressSpace};
use std::collections::{HashMap, HashSet};
use std::path::Path;

/// LLVM backend — compiles HIR to native object file via LLVM.
pub fn compile_hir_to_object(
    program: &hir::Program,
    output: &Path,
    optimize: bool,
) -> Result<()> {
    Target::initialize_native(&InitializationConfig::default())
        .map_err(|e| anyhow::anyhow!("LLVM target init failed: {}", e))?;

    let context = Context::create();
    let module = context.create_module("bars");
    let builder = context.create_builder();
    let i64_type = context.i64_type();
    let i8_type = context.i8_type();
    let void_type = context.void_type();

    let mut backend = LlvmCompiler {
        context: &context,
        module,
        builder,
        i64_type,
        i8_type,
        void_type,
        values: HashMap::new(),
        allocas: HashMap::new(),
        functions: HashMap::new(),
        string_labels: Vec::new(),
    };

    backend.compile(program)?;

    let opt_level = if optimize {
        OptimizationLevel::Aggressive
    } else {
        OptimizationLevel::Default
    };
    let target_machine = create_target_machine(opt_level)?;
    target_machine
        .write_to_file(&backend.module, FileType::Object, output)
        .map_err(|e| anyhow::anyhow!("LLVM object write failed: {}", e))?;

    Ok(())
}

struct LlvmCompiler<'ctx> {
    context: &'ctx Context,
    module: Module<'ctx>,
    builder: Builder<'ctx>,
    i64_type: IntType<'ctx>,
    i8_type: IntType<'ctx>,
    void_type: VoidType<'ctx>,
    values: HashMap<String, IntValue<'ctx>>,
    /// Variables that need alloca (function params, loop vars, etc.)
    allocas: HashMap<String, PointerValue<'ctx>>,
    functions: HashMap<String, FunctionValue<'ctx>>,
    string_labels: Vec<(String, String)>,
}

impl<'ctx> LlvmCompiler<'ctx> {
    fn compile(&mut self, program: &hir::Program) -> Result<()> {
        let struct_registry = program.struct_registry.clone();

        for func in &program.funcs {
            self.declare_func(&func.name, func.params.len())?;
        }
        self.declare_runtime()?;

        for func in &program.funcs {
            self.define_func(func, &struct_registry)?;
        }
        Ok(())
    }

    fn declare_func(&mut self, name: &str, n_params: usize) -> Result<FunctionValue<'ctx>> {
        let mut param_types = Vec::new();
        for _ in 0..n_params {
            param_types.push(self.i64_type.into());
        }
        let fn_type = self.i64_type.fn_type(&param_types, false);
        let func = self.module.add_function(name, fn_type, None);
        self.functions.insert(name.to_string(), func);
        Ok(func)
    }

    fn declare_runtime(&mut self) -> Result<()> {
        let i8_ptr = self.i8_type.ptr_type(AddressSpace::default());

        // void f(i64)
        let void_i64 = self.void_type.fn_type(&[self.i64_type.into()], false);
        self.module.add_function("bars_print_i64", void_i64, None);

        // void f()
        let void_noarg = self.void_type.fn_type(&[], false);
        self.module.add_function("bars_print_newline", void_noarg, None);

        // void f(i8*)
        let void_str = self.void_type.fn_type(&[i8_ptr.into()], false);
        self.module.add_function("bars_print_string", void_str, None);

        // i8* f(i8*)
        let str_str = i8_ptr.fn_type(&[i8_ptr.into()], false);
        self.module.add_function("bars_string_new", str_str, None);

        // i8* f()
        let ptr_noarg = i8_ptr.fn_type(&[], false);
        self.module.add_function("bars_vector_new_i64", ptr_noarg, None);
        self.module.add_function("bars_map_new_i64", ptr_noarg, None);

        // void f(i8*, i64)
        let void_ptr_i64 = self.void_type.fn_type(&[i8_ptr.into(), self.i64_type.into()], false);
        self.module.add_function("bars_vector_push_i64", void_ptr_i64, None);
        self.module.add_function("bars_map_set_i64", void_ptr_i64, None);

        // i64 f(i8*, i64)
        let i64_ptr_i64 = self.i64_type.fn_type(&[i8_ptr.into(), self.i64_type.into()], false);
        self.module.add_function("bars_vector_get_i64", i64_ptr_i64, None);
        self.module.add_function("bars_map_get_i64", i64_ptr_i64, None);

        // i64 f(i8*)
        let i64_ptr = self.i64_type.fn_type(&[i8_ptr.into()], false);
        self.module.add_function("bars_vector_count_i64", i64_ptr, None);
        self.module.add_function("bars_map_count_i64", i64_ptr, None);

        Ok(())
    }

    fn define_func(
        &mut self,
        func: &hir::Func,
        struct_registry: &HashMap<String, Vec<String>>,
    ) -> Result<()> {
        let llvm_func = *self.functions.get(&func.name).unwrap();
        self.values.clear();
        self.allocas.clear();

        // Pre-scan: collect names that get assigned (mutable variables)
        let mut assigned_vars: HashSet<String> = HashSet::new();
        for block in &func.blocks {
            for instr in &block.instrs {
                if let hir::Instr::Assign { dest, .. } = instr {
                    assigned_vars.insert(dest.clone());
                }
            }
        }
        // Also alloc vars that appear as function params
        for p in &func.params {
            assigned_vars.insert(p.clone());
        }

        // Collect all Alloc instructions to hoist them to entry block
        let mut alloc_instrs: Vec<(String, usize)> = Vec::new();
        for block in &func.blocks {
            for instr in &block.instrs {
                if let hir::Instr::Alloc { dest, size } = instr {
                    alloc_instrs.push((dest.clone(), *size));
                }
            }
        }

        // Create basic blocks
        let mut blocks: HashMap<String, BasicBlock<'ctx>> = HashMap::new();
        let entry_bb = self.context.append_basic_block(llvm_func, &func.entry_block);
        blocks.insert(func.entry_block.clone(), entry_bb);
        for block in &func.blocks {
            if block.label != func.entry_block {
                let bb = self.context.append_basic_block(llvm_func, &block.label);
                blocks.insert(block.label.clone(), bb);
            }
        }

        // Entry block: allocas for mutable vars + hoisted Allocs
        self.builder.position_at_end(entry_bb);
        for var_name in &assigned_vars {
            let alloca = self.builder.build_alloca(self.i64_type, "var").unwrap();
            self.allocas.insert(var_name.clone(), alloca);
        }
        for (dest, size) in &alloc_instrs {
            let array_type = self.i8_type.array_type(*size as u32);
            let alloca = self.builder.build_alloca(array_type, "alloc").unwrap();
            let ptr = self.builder.build_ptr_to_int(alloca, self.i64_type, "ptr").unwrap();
            self.values.insert(dest.clone(), ptr);
        }
        // Store params to their allocas
        for (i, param) in func.params.iter().enumerate() {
            let llvm_param = llvm_func.get_nth_param(i as u32).unwrap().into_int_value();
            let alloca = self.allocas[param];
            let _ = self.builder.build_store(alloca, llvm_param).unwrap();
        }

        // Compile each block
        for block in &func.blocks {
            let bb = blocks[&block.label];
            if block.label != func.entry_block {
                self.builder.position_at_end(bb);
            }
            for instr in &block.instrs {
                if matches!(instr, hir::Instr::Alloc { .. }) {
                    continue;
                }
                if let hir::Instr::Assign { dest, value } = instr {
                    // Store value to variable's alloca
                    let val = self.operand_to_int(value);
                    if let Some(&alloca) = self.allocas.get(dest) {
                        let _ = self.builder.build_store(alloca, val).unwrap();
                    }
                    self.values.insert(dest.clone(), val); // also cache for current block
                } else {
                    self.compile_instr(instr, struct_registry)?;
                }
            }
            self.compile_terminator(&block.terminator, &blocks)?;
        }

        Ok(())
    }

    fn compile_instr(
        &mut self,
        instr: &hir::Instr,
        struct_registry: &HashMap<String, Vec<String>>,
    ) -> Result<()> {
        match instr {
            // Alloc handled in prologue, Assign handled in define_func
            hir::Instr::Alloc { .. } | hir::Instr::Assign { .. } => {},
            hir::Instr::Const { dest, value } => {
                let val = self.i64_type.const_int(*value as u64, true);
                self.values.insert(dest.clone(), val);
            }
            hir::Instr::Store { addr, value } => {
                let addr_val = self.operand_to_int(addr);
                let val = self.operand_to_int(value);
                let ptr = self.builder.build_int_to_ptr(
                    addr_val, self.i64_type.ptr_type(AddressSpace::default()), "store_ptr",
                ).unwrap();
                let _ = self.builder.build_store(ptr, val).unwrap();
            }
            hir::Instr::Load { dest, addr } => {
                let addr_val = self.operand_to_int(addr);
                let ptr = self.builder.build_int_to_ptr(
                    addr_val, self.i64_type.ptr_type(AddressSpace::default()), "load_ptr",
                ).unwrap();
                let loaded = self.builder.build_load(ptr, "load_val").unwrap();
                let val = loaded.into_int_value();
                self.values.insert(dest.clone(), val);
            }
            hir::Instr::FieldLoad { dest, base, offset } => {
                let base_val = self.operand_to_int(base);
                let offset_val = self.i64_type.const_int(*offset as u64, false);
                let addr = self.builder.build_int_add(base_val, offset_val, "field_addr").unwrap();
                let ptr = self.builder.build_int_to_ptr(
                    addr, self.i64_type.ptr_type(AddressSpace::default()), "field_ptr",
                ).unwrap();
                let loaded = self.builder.build_load(ptr, "field_val").unwrap();
                let val = loaded.into_int_value();
                self.values.insert(dest.clone(), val);
            }
            hir::Instr::FieldStore { base, offset, value } => {
                let base_val = self.operand_to_int(base);
                let offset_val = self.i64_type.const_int(*offset as u64, false);
                let addr = self.builder.build_int_add(base_val, offset_val, "field_addr").unwrap();
                let ptr = self.builder.build_int_to_ptr(
                    addr, self.i64_type.ptr_type(AddressSpace::default()), "field_store_ptr",
                ).unwrap();
                let val = self.operand_to_int(value);
                let _ = self.builder.build_store(ptr, val).unwrap();
            }
            hir::Instr::BinOp { dest, op, lhs, rhs } => {
                let lhs_val = self.operand_to_int(lhs);
                let rhs_val = self.operand_to_int(rhs);
                let result = match op {
                    hir::BinOp::Add => self.builder.build_int_add(lhs_val, rhs_val, "add").unwrap(),
                    hir::BinOp::Sub => self.builder.build_int_sub(lhs_val, rhs_val, "sub").unwrap(),
                    hir::BinOp::Mul => self.builder.build_int_mul(lhs_val, rhs_val, "mul").unwrap(),
                    hir::BinOp::Div => self.builder.build_int_signed_div(lhs_val, rhs_val, "div").unwrap(),
                    hir::BinOp::Rem => self.builder.build_int_signed_rem(lhs_val, rhs_val, "rem").unwrap(),
                    hir::BinOp::Eq => {
                        let cmp = self.builder.build_int_compare(IntPredicate::EQ, lhs_val, rhs_val, "eq").unwrap();
                        self.builder.build_int_z_extend(cmp, self.i64_type, "eq_ext").unwrap()
                    }
                    hir::BinOp::Ne => {
                        let cmp = self.builder.build_int_compare(IntPredicate::NE, lhs_val, rhs_val, "ne").unwrap();
                        self.builder.build_int_z_extend(cmp, self.i64_type, "ne_ext").unwrap()
                    }
                    hir::BinOp::Lt => {
                        let cmp = self.builder.build_int_compare(IntPredicate::SLT, lhs_val, rhs_val, "lt").unwrap();
                        self.builder.build_int_z_extend(cmp, self.i64_type, "lt_ext").unwrap()
                    }
                    hir::BinOp::Le => {
                        let cmp = self.builder.build_int_compare(IntPredicate::SLE, lhs_val, rhs_val, "le").unwrap();
                        self.builder.build_int_z_extend(cmp, self.i64_type, "le_ext").unwrap()
                    }
                    hir::BinOp::Gt => {
                        let cmp = self.builder.build_int_compare(IntPredicate::SGT, lhs_val, rhs_val, "gt").unwrap();
                        self.builder.build_int_z_extend(cmp, self.i64_type, "gt_ext").unwrap()
                    }
                    hir::BinOp::Ge => {
                        let cmp = self.builder.build_int_compare(IntPredicate::SGE, lhs_val, rhs_val, "ge").unwrap();
                        self.builder.build_int_z_extend(cmp, self.i64_type, "ge_ext").unwrap()
                    }
                };
                self.values.insert(dest.clone(), result);
            }
            hir::Instr::UnOp { dest, op, operand } => {
                let val = self.operand_to_int(operand);
                match op {
                    hir::UnOp::Not => {
                        let zero = self.i64_type.const_int(0, false);
                        let cmp = self.builder.build_int_compare(IntPredicate::EQ, val, zero, "not_cmp").unwrap();
                        let result = self.builder.build_int_z_extend(cmp, self.i64_type, "not_ext").unwrap();
                        self.values.insert(dest.clone(), result);
                    }
                }
            }
            hir::Instr::Call { dest, func: func_name, args } => {
                let arg_vals: Vec<IntValue<'ctx>> = args.iter()
                    .map(|a| self.operand_to_int(a))
                    .collect();

                // Struct constructor
                if let Some(fields) = struct_registry.get(func_name) {
                    let size = fields.len() * 8;
                    let array_type = self.i8_type.array_type(size as u32);
                    let alloca = self.builder.build_alloca(array_type, "struct_alloca").unwrap();
                    let base_ptr = self.builder.build_ptr_to_int(alloca, self.i64_type, "struct_ptr").unwrap();
                    for (i, field_val) in arg_vals.iter().enumerate() {
                        let offset = self.i64_type.const_int((i as u64) * 8, false);
                        let addr = self.builder.build_int_add(base_ptr, offset, "field_addr").unwrap();
                        let ptr = self.builder.build_int_to_ptr(
                            addr, self.i64_type.ptr_type(AddressSpace::default()), "field_ptr",
                        ).unwrap();
                        let _ = self.builder.build_store(ptr, *field_val).unwrap();
                    }
                    self.values.insert(dest.clone(), base_ptr);
                    return Ok(());
                }

                let result = match func_name.as_str() {
                    "+" if arg_vals.len() == 2 =>
                        self.builder.build_int_add(arg_vals[0], arg_vals[1], "add").unwrap(),
                    "-" if arg_vals.len() == 2 =>
                        self.builder.build_int_sub(arg_vals[0], arg_vals[1], "sub").unwrap(),
                    "*" if arg_vals.len() == 2 =>
                        self.builder.build_int_mul(arg_vals[0], arg_vals[1], "mul").unwrap(),
                    "/" if arg_vals.len() == 2 =>
                        self.builder.build_int_signed_div(arg_vals[0], arg_vals[1], "div").unwrap(),
                    "%" if arg_vals.len() == 2 =>
                        self.builder.build_int_signed_rem(arg_vals[0], arg_vals[1], "rem").unwrap(),
                    "=" if arg_vals.len() == 2 => {
                        let cmp = self.builder.build_int_compare(IntPredicate::EQ, arg_vals[0], arg_vals[1], "eq").unwrap();
                        self.builder.build_int_z_extend(cmp, self.i64_type, "eq_ext").unwrap()
                    }
                    "!=" if arg_vals.len() == 2 => {
                        let cmp = self.builder.build_int_compare(IntPredicate::NE, arg_vals[0], arg_vals[1], "ne").unwrap();
                        self.builder.build_int_z_extend(cmp, self.i64_type, "ne_ext").unwrap()
                    }
                    "<" if arg_vals.len() == 2 => {
                        let cmp = self.builder.build_int_compare(IntPredicate::SLT, arg_vals[0], arg_vals[1], "lt").unwrap();
                        self.builder.build_int_z_extend(cmp, self.i64_type, "lt_ext").unwrap()
                    }
                    "<=" if arg_vals.len() == 2 => {
                        let cmp = self.builder.build_int_compare(IntPredicate::SLE, arg_vals[0], arg_vals[1], "le").unwrap();
                        self.builder.build_int_z_extend(cmp, self.i64_type, "le_ext").unwrap()
                    }
                    ">" if arg_vals.len() == 2 => {
                        let cmp = self.builder.build_int_compare(IntPredicate::SGT, arg_vals[0], arg_vals[1], "gt").unwrap();
                        self.builder.build_int_z_extend(cmp, self.i64_type, "gt_ext").unwrap()
                    }
                    ">=" if arg_vals.len() == 2 => {
                        let cmp = self.builder.build_int_compare(IntPredicate::SGE, arg_vals[0], arg_vals[1], "ge").unwrap();
                        self.builder.build_int_z_extend(cmp, self.i64_type, "ge_ext").unwrap()
                    }
                    "not" if arg_vals.len() == 1 => {
                        let zero = self.i64_type.const_int(0, false);
                        let cmp = self.builder.build_int_compare(IntPredicate::EQ, arg_vals[0], zero, "not").unwrap();
                        self.builder.build_int_z_extend(cmp, self.i64_type, "not_ext").unwrap()
                    }
                    "println" => {
                        if !arg_vals.is_empty() && self.is_string_value(&args[0]) {
                            self.call_runtime_void_str("bars_print_string", arg_vals[0])?;
                            self.call_runtime_void("bars_print_newline", &[])?;
                        } else {
                            if !arg_vals.is_empty() {
                                self.call_runtime_void("bars_print_i64", &[arg_vals[0]])?;
                            }
                            self.call_runtime_void("bars_print_newline", &[])?;
                        }
                        self.i64_type.const_int(0, false)
                    }
                    "vector" => {
                        let ptr = self.call_runtime_ptr("bars_vector_new_i64", &[])?;
                        for arg in &arg_vals {
                            self.call_runtime_void_ptr_i64("bars_vector_push_i64", ptr, *arg)?;
                        }
                        self.ptr_to_i64(ptr)
                    }
                    "push" if arg_vals.len() == 2 => {
                        let ptr = self.i64_to_ptr(arg_vals[0]);
                        self.call_runtime_void_ptr_i64("bars_vector_push_i64", ptr, arg_vals[1])?;
                        self.i64_type.const_int(0, false)
                    }
                    "get" if arg_vals.len() == 2 => {
                        let ptr = self.i64_to_ptr(arg_vals[0]);
                        self.call_runtime_i64_ptr_i64("bars_vector_get_i64", ptr, arg_vals[1])?
                    }
                    "count" if arg_vals.len() == 1 => {
                        let ptr = self.i64_to_ptr(arg_vals[0]);
                        self.call_runtime_i64_ptr("bars_vector_count_i64", ptr)?
                    }
                    "map" => {
                        let ptr = self.call_runtime_ptr("bars_map_new_i64", &[])?;
                        self.ptr_to_i64(ptr)
                    }
                    "map_set" | "map-set" if arg_vals.len() == 3 => {
                        let ptr = self.i64_to_ptr(arg_vals[0]);
                        self.call_runtime_void_ptr_i64("bars_map_set_i64", ptr, arg_vals[2])?;
                        self.i64_type.const_int(0, false)
                    }
                    "map_get" | "map-get" if arg_vals.len() == 2 => {
                        let ptr = self.i64_to_ptr(arg_vals[0]);
                        self.call_runtime_i64_ptr_i64("bars_map_get_i64", ptr, arg_vals[1])?
                    }
                    "map_count" | "map-count" if arg_vals.len() == 1 => {
                        let ptr = self.i64_to_ptr(arg_vals[0]);
                        self.call_runtime_i64_ptr("bars_map_count_i64", ptr)?
                    }
                    "set" => {
                        let ptr = self.call_runtime_ptr("bars_set_new_i64", &[])?;
                        self.ptr_to_i64(ptr)
                    }
                    "set_add" | "set-add" if arg_vals.len() == 2 => {
                        let ptr = self.i64_to_ptr(arg_vals[0]);
                        self.call_runtime_void_ptr_i64("bars_set_add_i64", ptr, arg_vals[1])?;
                        self.i64_type.const_int(0, false)
                    }
                    "set_contains?" | "set-contains?" if arg_vals.len() == 2 => {
                        let ptr = self.i64_to_ptr(arg_vals[0]);
                        self.call_runtime_i64_ptr_i64("bars_set_contains_i64", ptr, arg_vals[1])?
                    }
                    "set_count" | "set-count" if arg_vals.len() == 1 => {
                        let ptr = self.i64_to_ptr(arg_vals[0]);
                        self.call_runtime_i64_ptr("bars_set_count_i64", ptr)?
                    }
                    _ => {
                        if let Some(user_func) = self.functions.get(func_name).copied() {
                            let args_meta: Vec<inkwell::values::BasicMetadataValueEnum<'ctx>> = arg_vals.iter()
                                .map(|&v| v.into())
                                .collect();
                            let call = self.builder.build_call(user_func, &args_meta, "call").unwrap();
                            call.try_as_basic_value().left()
                                .map(|v| v.into_int_value())
                                .unwrap_or_else(|| self.i64_type.const_int(0, false))
                        } else {
                            bail!("Unknown function in LLVM backend: {}", func_name)
                        }
                    }
                };
                self.values.insert(dest.clone(), result);
            }
            hir::Instr::StringLit { dest, content } => {
                let str_val = self.builder.build_global_string_ptr(content, "str_lit").unwrap();
                let cstr = str_val.as_pointer_value();
                let ptr = self.call_runtime_ptr("bars_string_new", &[cstr])?;
                let val = self.ptr_to_i64(ptr);
                self.values.insert(dest.clone(), val);
                self.string_labels.push((dest.clone(), content.clone()));
            }
        }
        Ok(())
    }

    fn compile_terminator(
        &self,
        term: &hir::Terminator,
        blocks: &HashMap<String, BasicBlock<'ctx>>,
    ) -> Result<()> {
        match term {
            hir::Terminator::Jump(label) => {
                let target = blocks[label];
                let _ = self.builder.build_unconditional_branch(target);
            }
            hir::Terminator::Branch { cond, then_block, else_block } => {
                let cond_val = self.operand_to_int(cond);
                let zero = self.i64_type.const_int(0, false);
                let cond_bool = self.builder.build_int_compare(
                    IntPredicate::NE, cond_val, zero, "branch_cond",
                ).unwrap();
                let then_bb = blocks[then_block];
                let else_bb = blocks[else_block];
                let _ = self.builder.build_conditional_branch(cond_bool, then_bb, else_bb);
            }
            hir::Terminator::Return(val) => {
                let ret_val = self.operand_to_int(val);
                let _ = self.builder.build_return(Some(&ret_val));
            }
            hir::Terminator::Unreachable => {
                let _ = self.builder.build_unreachable();
            }
        }
        Ok(())
    }

    // --- Helpers ---

    fn operand_to_int(&self, op: &hir::Operand) -> IntValue<'ctx> {
        match op {
            hir::Operand::Var(v) => {
                // If variable has an alloca, load from it
                if let Some(&alloca) = self.allocas.get(v) {
                    let loaded = self.builder.build_load(alloca, "load").unwrap();
                    loaded.into_int_value()
                } else if let Some(&val) = self.values.get(v) {
                    val
                } else {
                    panic!("Undefined variable in LLVM backend: {}", v)
                }
            }
            hir::Operand::Const(c) => self.i64_type.const_int(*c as u64, true),
        }
    }

    fn i64_to_ptr(&self, val: IntValue<'ctx>) -> PointerValue<'ctx> {
        self.builder.build_int_to_ptr(
            val, self.i8_type.ptr_type(AddressSpace::default()), "i64_to_ptr",
        ).unwrap()
    }

    fn ptr_to_i64(&self, ptr: PointerValue<'ctx>) -> IntValue<'ctx> {
        self.builder.build_ptr_to_int(ptr, self.i64_type, "ptr_to_i64").unwrap()
    }

    fn is_string_value(&self, op: &hir::Operand) -> bool {
        if let hir::Operand::Var(v) = op {
            self.string_labels.iter().any(|(name, _)| name == v)
        } else {
            false
        }
    }

    fn call_runtime_void(&self, name: &str, args: &[IntValue<'ctx>]) -> Result<()> {
        let func = self.module.get_function(name).unwrap();
        let args_meta: Vec<inkwell::values::BasicMetadataValueEnum<'ctx>> = args.iter().map(|&v| v.into()).collect();
        let _ = self.builder.build_call(func, &args_meta, "").unwrap();
        Ok(())
    }

    fn call_runtime_void_str(&self, name: &str, ptr: IntValue<'ctx>) -> Result<()> {
        let func = self.module.get_function(name).unwrap();
        let str_ptr = self.i64_to_ptr(ptr);
        let _ = self.builder.build_call(func, &[str_ptr.into()], "").unwrap();
        Ok(())
    }

    fn call_runtime_void_ptr_i64(&self, name: &str, ptr: PointerValue<'ctx>, val: IntValue<'ctx>) -> Result<()> {
        let func = self.module.get_function(name).unwrap();
        let _ = self.builder.build_call(func, &[ptr.into(), val.into()], "").unwrap();
        Ok(())
    }

    fn call_runtime_ptr(&self, name: &str, args: &[PointerValue<'ctx>]) -> Result<PointerValue<'ctx>> {
        let func = self.module.get_function(name).unwrap();
        let args_meta: Vec<inkwell::values::BasicMetadataValueEnum<'ctx>> = args.iter().map(|&v| v.into()).collect();
        let call = self.builder.build_call(func, &args_meta, name).unwrap();
        Ok(call.try_as_basic_value().left()
            .map(|v| v.into_pointer_value())
            .unwrap_or_else(|| self.i8_type.ptr_type(AddressSpace::default()).const_null()))
    }

    fn call_runtime_i64_ptr(&self, name: &str, ptr: PointerValue<'ctx>) -> Result<IntValue<'ctx>> {
        let func = self.module.get_function(name).unwrap();
        let call = self.builder.build_call(func, &[ptr.into()], name).unwrap();
        Ok(call.try_as_basic_value().left()
            .map(|v| v.into_int_value())
            .unwrap_or_else(|| self.i64_type.const_int(0, false)))
    }

    fn call_runtime_i64_ptr_i64(&self, name: &str, ptr: PointerValue<'ctx>, val: IntValue<'ctx>) -> Result<IntValue<'ctx>> {
        let func = self.module.get_function(name).unwrap();
        let call = self.builder.build_call(func, &[ptr.into(), val.into()], name).unwrap();
        Ok(call.try_as_basic_value().left()
            .map(|v| v.into_int_value())
            .unwrap_or_else(|| self.i64_type.const_int(0, false)))
    }
}

fn create_target_machine(opt_level: OptimizationLevel) -> Result<TargetMachine> {
    let target_triple = TargetMachine::get_default_triple();
    let target = Target::from_triple(&target_triple)
        .map_err(|e| anyhow::anyhow!("LLVM target not found for {}: {:?}", target_triple, e))?;
    let cpu = TargetMachine::get_host_cpu_name();
    let features = TargetMachine::get_host_cpu_features();

    target
        .create_target_machine(
            &target_triple,
            cpu.to_str().unwrap_or("generic"),
            features.to_str().unwrap_or(""),
            opt_level,
            RelocMode::PIC,
            CodeModel::Default,
        )
        .ok_or_else(|| anyhow::anyhow!("Failed to create LLVM target machine"))
}
