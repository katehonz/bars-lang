use crate::hir;
use anyhow::{bail, Result};
use cranelift_codegen::ir::{types, AbiParam, Block, InstBuilder, MemFlags, StackSlotData, StackSlotKind, TrapCode, Value as ClifValue};
use cranelift_codegen::settings::Configurable;
use cranelift_codegen::settings;
use cranelift_frontend::{FunctionBuilder, FunctionBuilderContext, Variable};
use cranelift_jit::JITModule;
use cranelift_module::{DataDescription, Linkage, Module};
use std::collections::{HashMap, HashSet};
use std::path::Path;

// Real C runtime function declarations
unsafe extern "C" {
    fn bars_print_i64(n: i64);
    fn bars_print_newline();
    fn bars_string_new(cstr: *const u8) -> *mut u8;
    fn bars_string_from_i64(n: i64) -> *mut u8;
    fn bars_print_string(s: *const u8);
    fn bars_vector_new_i64() -> *mut u8;
    fn bars_vector_push_i64(vec: *mut u8, val: i64);
    fn bars_vector_get_i64(vec: *mut u8, idx: i64) -> i64;
    fn bars_vector_count_i64(vec: *mut u8) -> i64;
    fn bars_map_new_i64() -> *mut u8;
    fn bars_map_set_i64(map: *mut u8, key: i64, val: i64);
    fn bars_map_get_i64(map: *mut u8, key: i64) -> i64;
    fn bars_map_count_i64(map: *mut u8) -> i64;
    fn bars_set_new_i64() -> *mut u8;
    fn bars_set_add_i64(set: *mut u8, val: i64);
    fn bars_set_contains_i64(set: *mut u8, val: i64) -> i64;
    fn bars_set_count_i64(set: *mut u8) -> i64;
    fn bars_print_vector_i64(vec: *const u8);
    fn bars_print_map_i64(map: *const u8);
    fn bars_print_set_i64(set: *const u8);
    fn bars_print_any_i64(val: i64);
    fn bars_string_length(s: *const u8) -> i64;
    fn bars_string_concat(a: *const u8, b: *const u8) -> *mut u8;
    fn bars_alloc(size: usize) -> *mut u8;
    fn bars_string_trim(s: *const u8) -> *mut u8;
    fn bars_string_substring(s: *const u8, start: i64, len: i64) -> *mut u8;
    fn bars_string_split(s: *const u8, delim: *const u8) -> *mut u8;
    fn bars_string_join(vec: *const u8, delim: *const u8) -> *mut u8;
    fn bars_sqrt_i64(n: i64) -> i64;
    fn bars_pow_i64(base: i64, exp: i64) -> i64;
    fn bars_abs_i64(n: i64) -> i64;
    fn bars_slurp(path: *const u8) -> *mut u8;
    fn bars_spit(path: *const u8, content: *const u8) -> i64;
    fn bars_string_get(s: *const u8, idx: i64) -> i64;
    fn bars_string_starts_with(s: *const u8, prefix: *const u8) -> i64;
    fn bars_string_ends_with(s: *const u8, suffix: *const u8) -> i64;
    fn bars_string_index_of(s: *const u8, needle: *const u8) -> i64;
    fn bars_string_slice(s: *const u8, start: i64, end: i64) -> *mut u8;
    fn bars_args_count() -> i64;
    fn bars_args_get(idx: i64) -> *mut u8;
    fn bars_exit(status: i64);
    fn bars_code_char(code: i64) -> *mut u8;
    fn bars_char_code(s: *const u8) -> i64;
    fn bars_system(s: *const u8) -> i64;
}

pub struct CraneliftBackend {
    module: JITModule,
    _builder_context: FunctionBuilderContext,
    functions: HashMap<String, cranelift_module::FuncId>,
}

impl CraneliftBackend {
    pub fn new() -> Result<Self> {
        let mut flag_builder = settings::builder();
        flag_builder.set("use_colocated_libcalls", "false").unwrap();
        flag_builder.set("is_pic", "false").unwrap();
        let isa_builder = cranelift_native::builder().unwrap_or_else(|msg| {
            panic!("host machine is not supported: {}", msg);
        });
        let isa = isa_builder.finish(settings::Flags::new(flag_builder)).unwrap();

        let mut jit_builder = cranelift_jit::JITBuilder::with_isa(isa, cranelift_module::default_libcall_names());

        // Register runtime functions
        jit_builder.symbol("bars_print_i64", bars_print_i64 as *const u8);
        jit_builder.symbol("bars_print_newline", bars_print_newline as *const u8);
        jit_builder.symbol("bars_string_new", bars_string_new as *const u8);
        jit_builder.symbol("bars_string_from_i64", bars_string_from_i64 as *const u8);
        jit_builder.symbol("bars_print_string", bars_print_string as *const u8);
        jit_builder.symbol("bars_vector_new_i64", bars_vector_new_i64 as *const u8);
        jit_builder.symbol("bars_vector_push_i64", bars_vector_push_i64 as *const u8);
        jit_builder.symbol("bars_vector_get_i64", bars_vector_get_i64 as *const u8);
        jit_builder.symbol("bars_vector_count_i64", bars_vector_count_i64 as *const u8);
        jit_builder.symbol("bars_map_new_i64", bars_map_new_i64 as *const u8);
        jit_builder.symbol("bars_map_set_i64", bars_map_set_i64 as *const u8);
        jit_builder.symbol("bars_map_get_i64", bars_map_get_i64 as *const u8);
        jit_builder.symbol("bars_map_count_i64", bars_map_count_i64 as *const u8);
        jit_builder.symbol("bars_set_new_i64", bars_set_new_i64 as *const u8);
        jit_builder.symbol("bars_set_add_i64", bars_set_add_i64 as *const u8);
        jit_builder.symbol("bars_set_contains_i64", bars_set_contains_i64 as *const u8);
        jit_builder.symbol("bars_set_count_i64", bars_set_count_i64 as *const u8);
        jit_builder.symbol("bars_print_vector_i64", bars_print_vector_i64 as *const u8);
        jit_builder.symbol("bars_print_map_i64", bars_print_map_i64 as *const u8);
        jit_builder.symbol("bars_print_set_i64", bars_print_set_i64 as *const u8);
        jit_builder.symbol("bars_print_any_i64", bars_print_any_i64 as *const u8);
        jit_builder.symbol("bars_string_length", bars_string_length as *const u8);
        jit_builder.symbol("bars_string_concat", bars_string_concat as *const u8);
        jit_builder.symbol("bars_alloc", bars_alloc as *const u8);
        jit_builder.symbol("bars_string_trim", bars_string_trim as *const u8);
        jit_builder.symbol("bars_string_substring", bars_string_substring as *const u8);
        jit_builder.symbol("bars_string_split", bars_string_split as *const u8);
        jit_builder.symbol("bars_string_join", bars_string_join as *const u8);
        jit_builder.symbol("bars_sqrt_i64", bars_sqrt_i64 as *const u8);
        jit_builder.symbol("bars_pow_i64", bars_pow_i64 as *const u8);
        jit_builder.symbol("bars_abs_i64", bars_abs_i64 as *const u8);
        jit_builder.symbol("bars_slurp", bars_slurp as *const u8);
        jit_builder.symbol("bars_spit", bars_spit as *const u8);
        jit_builder.symbol("bars_string_get", bars_string_get as *const u8);
        jit_builder.symbol("bars_string_starts_with", bars_string_starts_with as *const u8);
        jit_builder.symbol("bars_string_ends_with", bars_string_ends_with as *const u8);
        jit_builder.symbol("bars_string_index_of", bars_string_index_of as *const u8);
        jit_builder.symbol("bars_string_slice", bars_string_slice as *const u8);
        jit_builder.symbol("bars_args_count", bars_args_count as *const u8);
        jit_builder.symbol("bars_args_get", bars_args_get as *const u8);
        jit_builder.symbol("bars_exit", bars_exit as *const u8);
        jit_builder.symbol("bars_code_char", bars_code_char as *const u8);
        jit_builder.symbol("bars_char_code", bars_char_code as *const u8);
        jit_builder.symbol("bars_system", bars_system as *const u8);

        let module = JITModule::new(jit_builder);

        Ok(Self {
            module,
            _builder_context: FunctionBuilderContext::new(),
            functions: HashMap::new(),
        })
    }

    pub fn compile_hir(&mut self, program: &hir::Program) -> Result<i64> {
        self.compile_hir_entry(program, "main")
    }

    pub fn compile_hir_entry(&mut self, program: &hir::Program, entry_name: &str) -> Result<i64> {
        // Declare all functions first
        for func in &program.funcs {
            if func.is_extern {
                let c_name = func.c_name.as_deref().unwrap_or(&func.name);
                declare_extern_function(&mut self.module, &func.name, c_name, func.params.len(), &mut self.functions)?;
            } else {
                declare_function_generic(&mut self.module, &func.name, func.params.len(), &mut self.functions)?;
            }
        }

        // Define all functions
        for func in &program.funcs {
            if func.is_extern {
                continue;
            }
            define_function_generic(
                &mut self.module,
                func,
                &program.struct_registry,
                &self.functions,
                &HashMap::new(),
            )?;
        }

        self.module.finalize_definitions().unwrap();

        // Find and call entry
        if let Some(&entry_id) = self.functions.get(entry_name) {
            let entry_ptr = self.module.get_finalized_function(entry_id);
            let entry_fn: unsafe extern "C" fn() -> i64 = unsafe { std::mem::transmute(entry_ptr) };
            let result = unsafe { entry_fn() };
            Ok(result)
        } else {
            Ok(0)
        }
    }
}

fn declare_function_generic<M: Module>(
    module: &mut M,
    name: &str,
    n_params: usize,
    functions: &mut HashMap<String, cranelift_module::FuncId>,
) -> Result<()> {
    let mut sig = module.make_signature();
    for _ in 0..n_params {
        sig.params.push(AbiParam::new(types::I64));
    }
    sig.returns.push(AbiParam::new(types::I64));

    let id = module.declare_function(name, Linkage::Export, &sig)?;
    functions.insert(name.to_string(), id);
    Ok(())
}

fn declare_extern_function<M: Module>(
    module: &mut M,
    name: &str,
    c_name: &str,
    n_params: usize,
    functions: &mut HashMap<String, cranelift_module::FuncId>,
) -> Result<()> {
    let mut sig = module.make_signature();
    for _ in 0..n_params {
        sig.params.push(AbiParam::new(types::I64));
    }
    sig.returns.push(AbiParam::new(types::I64));

    // Use the C name for the actual symbol
    let id = module.declare_function(c_name, Linkage::Import, &sig)?;
    functions.insert(name.to_string(), id);
    Ok(())
}

fn define_function_generic<M: Module>(
    module: &mut M,
    func: &hir::Func,
    struct_registry: &HashMap<String, Vec<String>>,
    functions: &HashMap<String, cranelift_module::FuncId>,
    string_data_ids: &HashMap<String, cranelift_module::DataId>,
) -> Result<()> {
    let func_id = *functions.get(&func.name).unwrap();

    let mut ctx = module.make_context();
    ctx.func.signature = module.make_signature();
    for _ in &func.params {
        ctx.func.signature.params.push(AbiParam::new(types::I64));
    }
    ctx.func.signature.returns.push(AbiParam::new(types::I64));

    let mut builder_context = FunctionBuilderContext::new();
    let mut builder = FunctionBuilder::new(&mut ctx.func, &mut builder_context);

    // Create Cranelift blocks for all HIR blocks, entry first
    let mut blocks: HashMap<String, Block> = HashMap::new();
    let entry_block = builder.create_block();
    blocks.insert(func.entry_block.clone(), entry_block);
    for block in &func.blocks {
        if block.label != func.entry_block {
            blocks.insert(block.label.clone(), builder.create_block());
        }
    }

    builder.append_block_params_for_function_params(entry_block);
    builder.switch_to_block(entry_block);

    let mut values: HashMap<String, Variable> = HashMap::new();
    for (i, param) in func.params.iter().enumerate() {
        let var = builder.declare_var(types::I64);
        builder.def_var(var, builder.block_params(entry_block)[i]);
        values.insert(param.clone(), var);
    }

    let mut string_temps: HashSet<String> = HashSet::new();

    // Compile each block
    for block in &func.blocks {
        let clif_block = blocks[&block.label];
        builder.switch_to_block(clif_block);

        for instr in &block.instrs {
            compile_instr(
                instr,
                &mut builder,
                &mut values,
                &mut string_temps,
                struct_registry,
                functions,
                module,
                string_data_ids,
            )?;
        }

        compile_terminator(&block.terminator, &mut builder, &values, &blocks, func, &functions, module)?;
    }

    // Seal all blocks after all jumps are emitted
    for block in &func.blocks {
        builder.seal_block(blocks[&block.label]);
    }

    builder.finalize();
    module.define_function(func_id, &mut ctx)?;

    Ok(())
}

fn get_or_declare_var(name: &str, values: &mut HashMap<String, Variable>, builder: &mut FunctionBuilder) -> Variable {
    *values.entry(name.to_string()).or_insert_with(|| builder.declare_var(types::I64))
}

fn compile_instr<M: Module>(
    instr: &hir::Instr,
    builder: &mut FunctionBuilder,
    values: &mut HashMap<String, Variable>,
    string_temps: &mut HashSet<String>,
    struct_registry: &HashMap<String, Vec<String>>,
    functions: &HashMap<String, cranelift_module::FuncId>,
    module: &mut M,
    string_data_ids: &HashMap<String, cranelift_module::DataId>,
) -> Result<()> {
    match instr {
        hir::Instr::Assign { dest, value } => {
            let val = operand_to_value(value, values, builder);
            let var = get_or_declare_var(dest, values, builder);
            builder.def_var(var, val);
        }
        hir::Instr::Const { dest, value } => {
            let val = builder.ins().iconst(types::I64, *value);
            let var = get_or_declare_var(dest, values, builder);
            builder.def_var(var, val);
        }
        hir::Instr::Alloc { dest, size } => {
            let slot_data = StackSlotData::new(StackSlotKind::ExplicitSlot, *size as u32, 3);
            let slot = builder.create_sized_stack_slot(slot_data);
            let addr = builder.ins().stack_addr(types::I64, slot, 0);
            let var = get_or_declare_var(dest, values, builder);
            builder.def_var(var, addr);
        }
        hir::Instr::Store { addr, value } => {
            let a = operand_to_value(addr, values, builder);
            let v = operand_to_value(value, values, builder);
            builder.ins().store(MemFlags::new(), v, a, 0);
        }
        hir::Instr::Load { dest, addr } => {
            let a = operand_to_value(addr, values, builder);
            let val = builder.ins().load(types::I64, MemFlags::new(), a, 0);
            let var = get_or_declare_var(dest, values, builder);
            builder.def_var(var, val);
        }
        hir::Instr::FieldLoad { dest, base, offset } => {
            let base_val = operand_to_value(base, values, builder);
            let offset_val = builder.ins().iconst(types::I64, *offset as i64);
            let addr = builder.ins().iadd(base_val, offset_val);
            let val = builder.ins().load(types::I64, MemFlags::new(), addr, 0);
            let var = get_or_declare_var(dest, values, builder);
            builder.def_var(var, val);
        }
        hir::Instr::FieldStore { base, offset, value } => {
            let base_val = operand_to_value(base, values, builder);
            let offset_val = builder.ins().iconst(types::I64, *offset as i64);
            let addr = builder.ins().iadd(base_val, offset_val);
            let v = operand_to_value(value, values, builder);
            builder.ins().store(MemFlags::new(), v, addr, 0);
        }
        hir::Instr::BinOp { dest, op, lhs, rhs } => {
            let lhs_val = operand_to_value(lhs, values, builder);
            let rhs_val = operand_to_value(rhs, values, builder);
            let val = match op {
                hir::BinOp::Add => builder.ins().iadd(lhs_val, rhs_val),
                hir::BinOp::Sub => builder.ins().isub(lhs_val, rhs_val),
                hir::BinOp::Mul => builder.ins().imul(lhs_val, rhs_val),
                hir::BinOp::Div => builder.ins().sdiv(lhs_val, rhs_val),
                hir::BinOp::Rem => builder.ins().srem(lhs_val, rhs_val),
                hir::BinOp::Eq => {
                    let cmp = builder.ins().icmp(cranelift_codegen::ir::condcodes::IntCC::Equal, lhs_val, rhs_val);
                    builder.ins().uextend(types::I64, cmp)
                }
                hir::BinOp::Ne => {
                    let cmp = builder.ins().icmp(cranelift_codegen::ir::condcodes::IntCC::NotEqual, lhs_val, rhs_val);
                    builder.ins().uextend(types::I64, cmp)
                }
                hir::BinOp::Lt => {
                    let cmp = builder.ins().icmp(cranelift_codegen::ir::condcodes::IntCC::SignedLessThan, lhs_val, rhs_val);
                    builder.ins().uextend(types::I64, cmp)
                }
                hir::BinOp::Le => {
                    let cmp = builder.ins().icmp(cranelift_codegen::ir::condcodes::IntCC::SignedLessThanOrEqual, lhs_val, rhs_val);
                    builder.ins().uextend(types::I64, cmp)
                }
                hir::BinOp::Gt => {
                    let cmp = builder.ins().icmp(cranelift_codegen::ir::condcodes::IntCC::SignedGreaterThan, lhs_val, rhs_val);
                    builder.ins().uextend(types::I64, cmp)
                }
                hir::BinOp::Ge => {
                    let cmp = builder.ins().icmp(cranelift_codegen::ir::condcodes::IntCC::SignedGreaterThanOrEqual, lhs_val, rhs_val);
                    builder.ins().uextend(types::I64, cmp)
                }
            };
            let var = get_or_declare_var(dest, values, builder);
            builder.def_var(var, val);
        }
        hir::Instr::UnOp { dest, op, operand } => {
            let val = operand_to_value(operand, values, builder);
            match op {
                hir::UnOp::Not => {
                    let zero = builder.ins().iconst(types::I64, 0);
                    let cmp = builder.ins().icmp(cranelift_codegen::ir::condcodes::IntCC::Equal, val, zero);
                    let result = builder.ins().uextend(types::I64, cmp);
                    let var = get_or_declare_var(dest, values, builder);
                    builder.def_var(var, result);
                }
            }
        }
        hir::Instr::Call { dest, func: func_name, args } => {
            let arg_vals: Vec<ClifValue> = args.iter().map(|a| operand_to_value(a, values, builder)).collect();


            // Check for struct constructor
            if let Some(fields) = struct_registry.get(func_name) {
                let size = fields.len() * 8;
                // Allocate on the GC heap via runtime instead of stack
                let size_val = builder.ins().iconst(types::I64, size as i64);
                let alloc_result = call_runtime(builder, module, "bars_alloc", &[size_val])?;
                let ptr = alloc_result;
                for (i, arg) in arg_vals.iter().enumerate() {
                    let offset = (i * 8) as i64;
                    let offset_val = builder.ins().iconst(types::I64, offset);
                    let addr = builder.ins().iadd(ptr, offset_val);
                    builder.ins().store(MemFlags::new(), *arg, addr, 0);
                }
                let var = get_or_declare_var(dest, values, builder);
                builder.def_var(var, ptr);
                return Ok(());
            }

            let result = match func_name.as_str() {
                "+" if arg_vals.len() == 2 => builder.ins().iadd(arg_vals[0], arg_vals[1]),
                "-" if arg_vals.len() == 2 => builder.ins().isub(arg_vals[0], arg_vals[1]),
                "*" if arg_vals.len() == 2 => builder.ins().imul(arg_vals[0], arg_vals[1]),
                "/" if arg_vals.len() == 2 => builder.ins().sdiv(arg_vals[0], arg_vals[1]),
                "%" if arg_vals.len() == 2 => builder.ins().srem(arg_vals[0], arg_vals[1]),
                "=" if arg_vals.len() == 2 => {
                    let cmp = builder.ins().icmp(cranelift_codegen::ir::condcodes::IntCC::Equal, arg_vals[0], arg_vals[1]);
                    builder.ins().uextend(types::I64, cmp)
                }
                "!=" if arg_vals.len() == 2 => {
                    let cmp = builder.ins().icmp(cranelift_codegen::ir::condcodes::IntCC::NotEqual, arg_vals[0], arg_vals[1]);
                    builder.ins().uextend(types::I64, cmp)
                }
                "<" if arg_vals.len() == 2 => {
                    let cmp = builder.ins().icmp(cranelift_codegen::ir::condcodes::IntCC::SignedLessThan, arg_vals[0], arg_vals[1]);
                    builder.ins().uextend(types::I64, cmp)
                }
                "<=" if arg_vals.len() == 2 => {
                    let cmp = builder.ins().icmp(cranelift_codegen::ir::condcodes::IntCC::SignedLessThanOrEqual, arg_vals[0], arg_vals[1]);
                    builder.ins().uextend(types::I64, cmp)
                }
                ">" if arg_vals.len() == 2 => {
                    let cmp = builder.ins().icmp(cranelift_codegen::ir::condcodes::IntCC::SignedGreaterThan, arg_vals[0], arg_vals[1]);
                    builder.ins().uextend(types::I64, cmp)
                }
                ">=" if arg_vals.len() == 2 => {
                    let cmp = builder.ins().icmp(cranelift_codegen::ir::condcodes::IntCC::SignedGreaterThanOrEqual, arg_vals[0], arg_vals[1]);
                    builder.ins().uextend(types::I64, cmp)
                }
                "not" if arg_vals.len() == 1 => {
                    let zero = builder.ins().iconst(types::I64, 0);
                    let cmp = builder.ins().icmp(cranelift_codegen::ir::condcodes::IntCC::Equal, arg_vals[0], zero);
                    builder.ins().uextend(types::I64, cmp)
                }
                "println" => {
                    if !arg_vals.is_empty() && is_string_arg(&args[0], string_temps) {
                        call_runtime(builder, module, "bars_print_string", &[arg_vals[0]])?;
                        call_runtime(builder, module, "bars_print_newline", &[])?;
                    } else if !arg_vals.is_empty() && matches!(args[0], hir::Operand::Const(_)) {
                        call_runtime(builder, module, "bars_print_i64", &[arg_vals[0]])?;
                        call_runtime(builder, module, "bars_print_newline", &[])?;
                    } else if !arg_vals.is_empty() {
                        call_runtime(builder, module, "bars_print_any_i64", &[arg_vals[0]])?;
                        call_runtime(builder, module, "bars_print_newline", &[])?;
                    } else {
                        call_runtime(builder, module, "bars_print_newline", &[])?;
                    }
                    builder.ins().iconst(types::I64, 0)
                }
                "vector" => {
                    let ptr = call_runtime(builder, module, "bars_vector_new_i64", &[])?;
                    for arg in &arg_vals {
                        call_runtime(builder, module, "bars_vector_push_i64", &[ptr, *arg])?;
                    }
                    ptr
                }
                "push" if arg_vals.len() == 2 => {
                    call_runtime(builder, module, "bars_vector_push_i64", &arg_vals)?;
                    builder.ins().iconst(types::I64, 0)
                }
                "get" if arg_vals.len() == 2 => {
                    call_runtime(builder, module, "bars_vector_get_i64", &arg_vals)?
                }
                "count" if arg_vals.len() == 1 => {
                    call_runtime(builder, module, "bars_vector_count_i64", &arg_vals)?
                }
                "map" => {
                    call_runtime(builder, module, "bars_map_new_i64", &[])?
                }
                "map_set" | "map-set" if arg_vals.len() == 3 => {
                    call_runtime(builder, module, "bars_map_set_i64", &arg_vals)?;
                    builder.ins().iconst(types::I64, 0)
                }
                "map_get" | "map-get" if arg_vals.len() == 2 => {
                    call_runtime(builder, module, "bars_map_get_i64", &arg_vals)?
                }
                "map_count" | "map-count" if arg_vals.len() == 1 => {
                    call_runtime(builder, module, "bars_map_count_i64", &arg_vals)?
                }
                "set" => {
                    call_runtime(builder, module, "bars_set_new_i64", &[])?
                }
                "set_add" | "set-add" if arg_vals.len() == 2 => {
                    call_runtime(builder, module, "bars_set_add_i64", &arg_vals)?;
                    builder.ins().iconst(types::I64, 0)
                }
                "set_contains?" | "set-contains?" if arg_vals.len() == 2 => {
                    call_runtime(builder, module, "bars_set_contains_i64", &arg_vals)?
                }
                "set_count" | "set-count" if arg_vals.len() == 1 => {
                    call_runtime(builder, module, "bars_set_count_i64", &arg_vals)?
                }
                // Math
                "sqrt" if arg_vals.len() == 1 => {
                    call_runtime(builder, module, "bars_sqrt_i64", &arg_vals)?
                }
                "pow" if arg_vals.len() == 2 => {
                    call_runtime(builder, module, "bars_pow_i64", &arg_vals)?
                }
                "abs" if arg_vals.len() == 1 => {
                    call_runtime(builder, module, "bars_abs_i64", &arg_vals)?
                }
                // String ops
                "str-count" | "str_count" if arg_vals.len() == 1 => {
                    call_runtime(builder, module, "bars_string_length", &arg_vals)?
                }
                "str-concat" | "str_concat" if arg_vals.len() == 2 => {
                    call_runtime(builder, module, "bars_string_concat", &arg_vals)?
                }
                "str-concat" | "str_concat" if arg_vals.len() == 1 => {
                    arg_vals[0]
                }
                // I/O
                "slurp" if arg_vals.len() == 1 => {
                    call_runtime(builder, module, "bars_slurp", &arg_vals)?
                }
                "spit" if arg_vals.len() == 2 => {
                    call_runtime(builder, module, "bars_spit", &arg_vals)?
                }
                "str-trim" | "str_trim" if arg_vals.len() == 1 => {
                    call_runtime(builder, module, "bars_string_trim", &arg_vals)?
                }
                "str-substring" | "str_substring" | "substring" if arg_vals.len() == 3 => {
                    call_runtime(builder, module, "bars_string_substring", &arg_vals)?
                }
                "str-split" | "str_split" | "split" if arg_vals.len() == 2 => {
                    call_runtime(builder, module, "bars_string_split", &arg_vals)?
                }
                "str-join" | "str_join" | "join" if arg_vals.len() == 2 => {
                    call_runtime(builder, module, "bars_string_join", &arg_vals)?
                }
                "str-get" | "str_get" if arg_vals.len() == 2 => {
                    call_runtime(builder, module, "bars_string_get", &arg_vals)?
                }
                "str-starts-with?" | "str_starts_with" if arg_vals.len() == 2 => {
                    call_runtime(builder, module, "bars_string_starts_with", &arg_vals)?
                }
                "str-ends-with?" | "str_ends_with" if arg_vals.len() == 2 => {
                    call_runtime(builder, module, "bars_string_ends_with", &arg_vals)?
                }
                "str-index-of" | "str_index_of" if arg_vals.len() == 2 => {
                    call_runtime(builder, module, "bars_string_index_of", &arg_vals)?
                }
                "str-slice" | "str_slice" | "slice" if arg_vals.len() == 3 => {
                    call_runtime(builder, module, "bars_string_slice", &arg_vals)?
                }
                "code-char" | "code_char" if arg_vals.len() == 1 => {
                    call_runtime(builder, module, "bars_code_char", &arg_vals)?
                }
                "char-code" | "char_code" if arg_vals.len() == 1 => {
                    call_runtime(builder, module, "bars_char_code", &arg_vals)?
                }
                "args-count" | "args_count" if arg_vals.is_empty() => {
                    call_runtime(builder, module, "bars_args_count", &arg_vals)?
                }
                "args-get" | "args_get" if arg_vals.len() == 1 => {
                    call_runtime(builder, module, "bars_args_get", &arg_vals)?
                }
                "exit" if arg_vals.len() == 1 => {
                    call_runtime(builder, module, "bars_exit", &arg_vals)?
                }
                _ => {
                    if let Some(&func_id) = functions.get(func_name) {
                        let func_ref = module.declare_func_in_func(func_id, builder.func);
                        let call = builder.ins().call(func_ref, &arg_vals);
                        builder.inst_results(call)[0]
                    } else {
                        eprintln!("DEBUG: Unknown func_name='{}' arg_count={}", func_name, arg_vals.len());
                        bail!("Unknown function in Cranelift backend: {}", func_name)
                    }
                }
            };
            let var = get_or_declare_var(dest, values, builder);
            builder.def_var(var, result);
        }
        hir::Instr::StringLit { dest, content } => {
            let result = if let Some(&data_id) = string_data_ids.get(content) {
                let gv = module.declare_data_in_func(data_id, builder.func);
                let ptr_val = builder.ins().global_value(types::I64, gv);
                call_runtime(builder, module, "bars_string_new", &[ptr_val])?
            } else {
                // Fallback for JIT mode (should not happen in AOT)
                let mut bytes = content.as_bytes().to_vec();
                bytes.push(0);
                let leaked = Box::leak(bytes.into_boxed_slice());
                let ptr = leaked.as_ptr() as i64;
                let ptr_val = builder.ins().iconst(types::I64, ptr);
                call_runtime(builder, module, "bars_string_new", &[ptr_val])?
            };
            let var = get_or_declare_var(dest, values, builder);
            builder.def_var(var, result);
            string_temps.insert(dest.clone());
        }
    }
    Ok(())
}

fn compile_terminator<M: Module>(
    term: &hir::Terminator,
    builder: &mut FunctionBuilder,
    values: &HashMap<String, Variable>,
    blocks: &HashMap<String, Block>,
    _func: &hir::Func,
    functions: &HashMap<String, cranelift_module::FuncId>,
    module: &mut M,
) -> Result<()> {
    match term {
        hir::Terminator::Jump(label) => {
            let target = blocks[label];
            builder.ins().jump(target, &[]);
        }
        hir::Terminator::Branch { cond, then_block, else_block } => {
            let cond_val = operand_to_value(cond, values, builder);
            let zero = builder.ins().iconst(types::I64, 0);
            let cond_bool = builder.ins().icmp(cranelift_codegen::ir::condcodes::IntCC::NotEqual, cond_val, zero);
            let then_target = blocks[then_block];
            let else_target = blocks[else_block];
            builder.ins().brif(cond_bool, then_target, &[], else_target, &[]);
        }
        hir::Terminator::Return(val) => {
            let ret_val = operand_to_value(val, values, builder);
            builder.ins().return_(&[ret_val]);
        }
        hir::Terminator::Unreachable => {
            builder.ins().trap(TrapCode::unwrap_user(1));
        }
        hir::Terminator::TailCall { func: func_name, args } => {
            // For now, compile tail calls as regular calls + return
            // (Cranelift TCO would require jump to entry block with block params,
            // which is complex to implement correctly.)
            let arg_vals: Vec<ClifValue> = args.iter()
                .map(|a| operand_to_value(a, values, builder))
                .collect();
            if let Some(&func_id) = functions.get(func_name) {
                let func_ref = module.declare_func_in_func(func_id, builder.func);
                let call = builder.ins().call(func_ref, &arg_vals);
                let ret_val = builder.inst_results(call)[0];
                builder.ins().return_(&[ret_val]);
            } else {
                panic!("Unknown function in Cranelift backend: {}", func_name)
            }
        }
    }
    Ok(())
}

fn operand_to_value(
    op: &hir::Operand,
    values: &HashMap<String, Variable>,
    builder: &mut FunctionBuilder,
) -> ClifValue {
    match op {
        hir::Operand::Var(v) => {
            let var = values.get(v).copied().unwrap_or_else(|| {
                panic!("Undefined variable in Cranelift backend: {}", v)
            });
            builder.use_var(var)
        }
        hir::Operand::Const(c) => builder.ins().iconst(types::I64, *c),
    }
}

fn is_string_arg(arg: &hir::Operand, string_temps: &HashSet<String>) -> bool {
    matches!(arg, hir::Operand::Var(v) if string_temps.contains(v))
}



fn call_runtime<M: Module>(
    builder: &mut FunctionBuilder,
    module: &mut M,
    name: &str,
    args: &[ClifValue],
) -> Result<ClifValue> {
    let mut sig = module.make_signature();
    for _ in args {
        sig.params.push(AbiParam::new(types::I64));
    }
    let is_void = matches!(name,
        "bars_print_newline" |
        "bars_print_string" |
        "bars_print_any_i64" |
        "bars_print_vector_i64" |
        "bars_print_map_i64" |
        "bars_print_set_i64" |
        "bars_vector_push_i64" |
        "bars_map_set_i64"
    );
    if !is_void {
        sig.returns.push(AbiParam::new(types::I64));
    }

    let func_id = module.declare_function(name, Linkage::Import, &sig)?;
    let func_ref = module.declare_func_in_func(func_id, builder.func);
    let call = builder.ins().call(func_ref, args);

    if !is_void {
        Ok(builder.inst_results(call)[0])
    } else {
        Ok(builder.ins().iconst(types::I64, 0))
    }
}

/// AOT compilation: compile HIR program to a native object file using Cranelift.
pub fn compile_hir_to_object(
    program: &hir::Program,
    output: &Path,
    optimize: bool,
    target: Option<&crate::target::TargetTriple>,
) -> Result<()> {
    let mut flag_builder = settings::builder();
    flag_builder.set("use_colocated_libcalls", "false").unwrap();
    flag_builder.set("is_pic", "false").unwrap();
    if optimize {
        flag_builder.set("opt_level", "speed_and_size").unwrap();
    }

    let isa: std::sync::Arc<dyn cranelift_codegen::isa::TargetIsa> = if let Some(t) = target {
        let triple: target_lexicon::Triple = t.cranelift_triple().parse()
            .map_err(|e| anyhow::anyhow!("invalid target triple for Cranelift: {}", e))?;
        let isa_builder = cranelift_codegen::isa::lookup(triple)
            .map_err(|e| anyhow::anyhow!("Cranelift does not support target: {:?}", e))?;
        isa_builder.finish(settings::Flags::new(flag_builder))
            .map_err(|e| anyhow::anyhow!("Cranelift ISA finish failed: {}", e))?
    } else {
        cranelift_native::builder().unwrap_or_else(|msg| {
            panic!("host machine is not supported: {}", msg);
        }).finish(settings::Flags::new(flag_builder))
            .map_err(|e| anyhow::anyhow!("Cranelift ISA finish failed: {}", e))?
    };

    let builder = ObjectBuilder::new(
        isa,
        "bars_output",
        cranelift_module::default_libcall_names(),
    ).map_err(|e| anyhow::anyhow!("ObjectBuilder error: {}", e))?;

    let mut module = ObjectModule::new(builder);
    let mut functions: HashMap<String, cranelift_module::FuncId> = HashMap::new();

    // Declare all functions first
    for func in &program.funcs {
        if func.is_extern {
            let c_name = func.c_name.as_deref().unwrap_or(&func.name);
            declare_extern_function(&mut module, &func.name, c_name, func.params.len(), &mut functions)?;
        } else {
            declare_function_generic(&mut module, &func.name, func.params.len(), &mut functions)?;
        }
    }

    // Collect and declare string literals as data objects
    let mut string_data_ids: HashMap<String, cranelift_module::DataId> = HashMap::new();
    let mut string_counter = 0;
    for func in &program.funcs {
        for block in &func.blocks {
            for instr in &block.instrs {
                if let hir::Instr::StringLit { content, .. } = instr {
                    if !string_data_ids.contains_key(content) {
                        let name = format!("_bars_str_{}", string_counter);
                        string_counter += 1;
                        let data_id = module.declare_data(&name, Linkage::Local, false, false)
                            .map_err(|e| anyhow::anyhow!("declare_data error: {}", e))?;
                        let mut data_desc = DataDescription::new();
                        let mut bytes = content.as_bytes().to_vec();
                        bytes.push(0);
                        data_desc.define(bytes.into_boxed_slice());
                        module.define_data(data_id, &data_desc)
                            .map_err(|e| anyhow::anyhow!("define_data error: {}", e))?;
                        string_data_ids.insert(content.clone(), data_id);
                    }
                }
            }
        }
    }

    // Define all functions
    for func in &program.funcs {
        if func.is_extern {
            continue;
        }
        define_function_generic(
            &mut module,
            func,
            &program.struct_registry,
            &functions,
            &string_data_ids,
        )?;
    }

    let product = module.finish();
    let bytes = product.emit().map_err(|e| anyhow::anyhow!("emit object: {}", e))?;
    std::fs::write(output, bytes)?;
    Ok(())
}

use cranelift_object::{ObjectBuilder, ObjectModule};
