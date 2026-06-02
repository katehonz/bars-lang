use crate::ast::{Expr, Program, Symbol, Type as AstType};
use anyhow::{bail, Result};
use cranelift_codegen::ir::{types, AbiParam, BlockArg, InstBuilder, Value as ClifValue};
use cranelift_codegen::settings::Configurable;
use cranelift_codegen::{settings, Context};
use cranelift_frontend::{FunctionBuilder, FunctionBuilderContext, Variable};
use cranelift_jit::JITModule;
use cranelift_module::{Linkage, Module};
use std::collections::HashMap;

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
}

pub struct CraneliftBackend {
    module: JITModule,
    builder_context: FunctionBuilderContext,
    functions: HashMap<String, cranelift_module::FuncId>,
    anon_counter: usize,
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

        let module = JITModule::new(jit_builder);

        Ok(Self {
            module,
            builder_context: FunctionBuilderContext::new(),
            functions: HashMap::new(),
            anon_counter: 0,
        })
    }

    pub fn compile_program(&mut self, program: &Program) -> Result<i64> {
        // First pass: declare all functions
        for expr in &program.exprs {
            if let Expr::Defn { name, params, .. } = expr {
                self.declare_function(&name.0, params.len())?;
            }
        }

        // Second pass: define all functions
        for expr in &program.exprs {
            if let Expr::Defn { name, params, body, .. } = expr {
                self.define_function(&name.0, params, body)?;
            }
        }

        self.module.finalize_definitions().unwrap();

        // Find and call main
        if let Some(&main_id) = self.functions.get("main") {
            let main_ptr = self.module.get_finalized_function(main_id);
            let main_fn: unsafe extern "C" fn() -> i64 = unsafe { std::mem::transmute(main_ptr) };
            let result = unsafe { main_fn() };
            Ok(result)
        } else {
            // Execute top-level expressions
            let mut last_result = 0i64;
            for expr in &program.exprs {
                if !matches!(expr, Expr::Defn { .. }) {
                    last_result = self.compile_and_run_expr(expr)?;
                }
            }
            Ok(last_result)
        }
    }

    fn declare_function(&mut self, name: &str, n_params: usize) -> Result<()> {
        let mut sig = self.module.make_signature();
        for _ in 0..n_params {
            sig.params.push(AbiParam::new(types::I64));
        }
        sig.returns.push(AbiParam::new(types::I64));

        let id = self.module.declare_function(name, Linkage::Export, &sig)?;
        self.functions.insert(name.to_string(), id);
        Ok(())
    }

    fn define_function(
        &mut self,
        name: &str,
        params: &[(Symbol, Option<AstType>)],
        body: &Expr,
    ) -> Result<()> {
        let func_id = *self.functions.get(name).unwrap();

        let mut ctx = self.module.make_context();
        ctx.func.signature = self.module.make_signature();
        for _ in params {
            ctx.func.signature.params.push(AbiParam::new(types::I64));
        }
        ctx.func.signature.returns.push(AbiParam::new(types::I64));

        let mut builder = FunctionBuilder::new(&mut ctx.func, &mut self.builder_context);
        let entry_block = builder.create_block();
        builder.append_block_params_for_function_params(entry_block);
        builder.switch_to_block(entry_block);
        builder.seal_block(entry_block);

        let mut vars = HashMap::new();

        for (i, (param, _)) in params.iter().enumerate() {
            let var = builder.declare_var(types::I64);
            let val = builder.block_params(entry_block)[i];
            builder.def_var(var, val);
            vars.insert(param.0.clone(), var);
        }

        let result = compile_expr(body, &mut builder, &mut vars, &self.functions, &mut self.module, &mut None, &mut false)?;
        builder.ins().return_(&[result]);
        builder.finalize();

        self.module.define_function(func_id, &mut ctx)?;

        Ok(())
    }

    fn compile_and_run_expr(&mut self, expr: &Expr) -> Result<i64> {
        let mut ctx = self.module.make_context();
        ctx.func.signature.returns.push(AbiParam::new(types::I64));

        let mut builder = FunctionBuilder::new(&mut ctx.func, &mut self.builder_context);
        let block = builder.create_block();
        builder.switch_to_block(block);
        builder.seal_block(block);

        let mut vars = HashMap::new();
        let result = compile_expr(expr, &mut builder, &mut vars, &self.functions, &mut self.module, &mut None, &mut false)?;
        builder.ins().return_(&[result]);
        builder.finalize();

        let anon_name = format!("__anon_{}", self.anon_counter);
        self.anon_counter += 1;
        let id = self.module.declare_function(&anon_name, Linkage::Export, &ctx.func.signature)?;
        self.module.define_function(id, &mut ctx)?;
        self.module.finalize_definitions().unwrap();

        let ptr = self.module.get_finalized_function(id);
        let f: unsafe extern "C" fn() -> i64 = unsafe { std::mem::transmute(ptr) };
        let result = unsafe { f() };

        Ok(result)
    }
}

fn compile_expr(
    expr: &Expr,
    builder: &mut FunctionBuilder,
    vars: &mut HashMap<String, Variable>,
    functions: &HashMap<String, cranelift_module::FuncId>,
    module: &mut JITModule,
    loop_context: &mut Option<(cranelift_codegen::ir::Block, Vec<Variable>)>,
    block_filled: &mut bool,
) -> Result<ClifValue> {
    match expr {
        Expr::Number(n) => Ok(builder.ins().iconst(types::I64, *n)),
        Expr::Bool(b) => Ok(builder.ins().iconst(types::I64, if *b { 1 } else { 0 })),

        Expr::Symbol(sym) => {
            if let Some(&var) = vars.get(&sym.0) {
                Ok(builder.use_var(var))
            } else {
                Ok(builder.ins().iconst(types::I64, 0))
            }
        }

        Expr::Let { bindings, body, .. } => {
            for (name, val_expr) in bindings {
                let val = compile_expr(val_expr, builder, vars, functions, module, loop_context, block_filled)?;
                let var = builder.declare_var(types::I64);
                builder.def_var(var, val);
                vars.insert(name.0.clone(), var);
            }
            compile_expr(body, builder, vars, functions, module, loop_context, block_filled)
        }

        Expr::If { cond, then_branch, else_branch, .. } => {
            let cond_val = compile_expr(cond, builder, vars, functions, module, loop_context, block_filled)?;
            let zero = builder.ins().iconst(types::I64, 0);
            let cond_bool = builder.ins().icmp(cranelift_codegen::ir::condcodes::IntCC::NotEqual, cond_val, zero);

            let then_block = builder.create_block();
            let else_block = builder.create_block();
            let merge_block = builder.create_block();
            builder.append_block_param(merge_block, types::I64);

            builder.ins().brif(cond_bool, then_block, &[], else_block, &[]);

            builder.switch_to_block(then_block);
            builder.seal_block(then_block);
            *block_filled = false;
            let then_val = compile_expr(then_branch, builder, vars, functions, module, loop_context, block_filled)?;
            if !*block_filled {
                builder.ins().jump(merge_block, &[BlockArg::Value(then_val)]);
            }

            builder.switch_to_block(else_block);
            builder.seal_block(else_block);
            *block_filled = false;
            let else_val = compile_expr(else_branch, builder, vars, functions, module, loop_context, block_filled)?;
            if !*block_filled {
                builder.ins().jump(merge_block, &[BlockArg::Value(else_val)]);
            }

            builder.switch_to_block(merge_block);
            builder.seal_block(merge_block);
            *block_filled = false;
            Ok(builder.block_params(merge_block)[0])
        }

        Expr::Do { exprs, .. } => {
            let mut last = builder.ins().iconst(types::I64, 0);
            for e in exprs {
                last = compile_expr(e, builder, vars, functions, module, loop_context, block_filled)?;
            }
            Ok(last)
        }

        Expr::Loop { bindings, body, .. } => {
            let loop_block = builder.create_block();
            for _ in bindings {
                builder.append_block_param(loop_block, types::I64);
            }

            let exit_block = builder.create_block();
            builder.append_block_param(exit_block, types::I64);

            // Initial jump to loop block with binding values
            let mut init_vals = Vec::new();
            for (_, init_expr) in bindings {
                let val = compile_expr(init_expr, builder, vars, functions, module, loop_context, block_filled)?;
                init_vals.push(BlockArg::Value(val));
            }
            builder.ins().jump(loop_block, &init_vals);

            // Compile loop body
            builder.switch_to_block(loop_block);

            // Save old variable mappings and set up loop variables
            let mut old_vars = HashMap::new();
            let loop_vars: Vec<Variable> = bindings.iter().enumerate().map(|(i, (name, _))| {
                let param = builder.block_params(loop_block)[i];
                let var = builder.declare_var(types::I64);
                old_vars.insert(name.0.clone(), vars.get(&name.0).copied());
                vars.insert(name.0.clone(), var);
                builder.def_var(var, param);
                var
            }).collect();

            // Set loop context for recur
            let prev_loop = loop_context.take();
            *loop_context = Some((loop_block, loop_vars.clone()));

            let body_val = compile_expr(body, builder, vars, functions, module, loop_context, block_filled)?;

            // Restore loop context
            *loop_context = prev_loop;

            // Jump to exit with body value (if block not already filled by recur)
            if !*block_filled {
                builder.ins().jump(exit_block, &[BlockArg::Value(body_val)]);
            }

            builder.seal_block(loop_block);
            builder.switch_to_block(exit_block);
            builder.seal_block(exit_block);
            *block_filled = false;
            Ok(builder.block_params(exit_block)[0])
        }

        Expr::Recur { args, .. } => {
            let (loop_block, loop_vars) = loop_context
                .as_ref()
                .ok_or_else(|| anyhow::anyhow!("recur used outside of loop"))?
                .clone();

            if args.len() != loop_vars.len() {
                bail!("recur arity mismatch: expected {}, got {}", loop_vars.len(), args.len());
            }

            let mut new_vals = Vec::new();
            for arg in args {
                let val = compile_expr(arg, builder, vars, functions, module, loop_context, block_filled)?;
                new_vals.push(BlockArg::Value(val));
            }
            let dummy = builder.ins().iconst(types::I64, 0);
            builder.ins().jump(loop_block, &new_vals);
            *block_filled = true;
            Ok(dummy)
        }

        Expr::FnCall { func, args, .. } => {
            if let Expr::Symbol(sym) = func.as_ref() {
                match sym.0.as_str() {
                    "+" | "-" | "*" | "/" if args.len() == 2 => {
                        let lhs = compile_expr(&args[0], builder, vars, functions, module, loop_context, block_filled)?;
                        let rhs = compile_expr(&args[1], builder, vars, functions, module, loop_context, block_filled)?;
                        let result = match sym.0.as_str() {
                            "+" => builder.ins().iadd(lhs, rhs),
                            "-" => builder.ins().isub(lhs, rhs),
                            "*" => builder.ins().imul(lhs, rhs),
                            "/" => builder.ins().sdiv(lhs, rhs),
                            _ => unreachable!(),
                        };
                        Ok(result)
                    }
                    "<" | ">" | "=" | "<=" | ">=" | "!=" if args.len() == 2 => {
                        let lhs = compile_expr(&args[0], builder, vars, functions, module, loop_context, block_filled)?;
                        let rhs = compile_expr(&args[1], builder, vars, functions, module, loop_context, block_filled)?;
                        let cc = match sym.0.as_str() {
                            "<" => cranelift_codegen::ir::condcodes::IntCC::SignedLessThan,
                            ">" => cranelift_codegen::ir::condcodes::IntCC::SignedGreaterThan,
                            "=" => cranelift_codegen::ir::condcodes::IntCC::Equal,
                            "<=" => cranelift_codegen::ir::condcodes::IntCC::SignedLessThanOrEqual,
                            ">=" => cranelift_codegen::ir::condcodes::IntCC::SignedGreaterThanOrEqual,
                            "!=" => cranelift_codegen::ir::condcodes::IntCC::NotEqual,
                            _ => unreachable!(),
                        };
                        let cmp = builder.ins().icmp(cc, lhs, rhs);
                        Ok(builder.ins().uextend(types::I64, cmp))
                    }
                    "println" => {
                        if !args.is_empty() {
                            let val = compile_expr(&args[0], builder, vars, functions, module, loop_context, block_filled)?;
                            call_runtime(builder, module, "bars_print_i64", &[val])?;
                        }
                        call_runtime(builder, module, "bars_print_newline", &[])?;
                        Ok(builder.ins().iconst(types::I64, 0))
                    }
                    "not" if args.len() == 1 => {
                        let val = compile_expr(&args[0], builder, vars, functions, module, loop_context, block_filled)?;
                        let zero = builder.ins().iconst(types::I64, 0);
                        let cmp = builder.ins().icmp(cranelift_codegen::ir::condcodes::IntCC::Equal, val, zero);
                        Ok(builder.ins().uextend(types::I64, cmp))
                    }
                    func_name => {
                        if let Some(&func_id) = functions.get(func_name) {
                            let func_ref = module.declare_func_in_func(func_id, builder.func);
                            let arg_vals: Result<Vec<_>> = args
                                .iter()
                                .map(|a| compile_expr(a, builder, vars, functions, module, loop_context, block_filled))
                                .collect();
                            let arg_vals = arg_vals?;
                            let call = builder.ins().call(func_ref, &arg_vals);
                            Ok(builder.inst_results(call)[0])
                        } else {
                            bail!("Unknown function: {}", func_name)
                        }
                    }
                }
            } else {
                bail!("Only direct function calls supported in Cranelift backend")
            }
        }

        Expr::Defn { .. } => bail!("Nested defn not supported in Cranelift backend"),
        Expr::Def { .. } => bail!("def not supported in Cranelift expression context"),
        Expr::String(_) => bail!("String not yet supported in Cranelift JIT"),
        Expr::Float(_) => bail!("Float not yet supported in Cranelift JIT"),
        Expr::Keyword(_) => bail!("Keyword not yet supported in Cranelift JIT"),
        Expr::List(_, _) => bail!("List not supported in Cranelift JIT"),
        Expr::Vector(_, _) => bail!("Vector not supported in Cranelift JIT"),
        Expr::Map(_, _) => bail!("Map not supported in Cranelift JIT"),
        Expr::Quote(_, _) => bail!("Quote not supported in Cranelift JIT"),
        Expr::SyntaxQuote(_, _) => bail!("Syntax-quote not supported in Cranelift JIT"),
        Expr::Unquote(_, _) => bail!("Unquote not supported in Cranelift JIT"),
        Expr::Splicing(_, _) => bail!("Splicing not supported in Cranelift JIT"),
        Expr::DefMacro { .. } => bail!("defmacro not supported in Cranelift JIT (should be expanded)"),
        Expr::Borrow(_, _, _) => bail!("Borrow not supported in Cranelift JIT"),
    }
}

fn call_runtime(
    builder: &mut FunctionBuilder,
    module: &mut JITModule,
    name: &str,
    args: &[ClifValue],
) -> Result<ClifValue> {
    let mut sig = module.make_signature();
    for _ in args {
        sig.params.push(AbiParam::new(types::I64));
    }
    if name != "bars_print_newline" {
        sig.returns.push(AbiParam::new(types::I64));
    }

    let func_id = module.declare_function(name, Linkage::Import, &sig)?;
    let func_ref = module.declare_func_in_func(func_id, builder.func);
    let call = builder.ins().call(func_ref, args);
    if name != "bars_print_newline" {
        Ok(builder.inst_results(call)[0])
    } else {
        Ok(builder.ins().iconst(types::I64, 0))
    }
}
