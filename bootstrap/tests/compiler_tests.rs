use bars::reader;

#[test]
fn test_compile_hello() {
    let prog = reader::read("(defn main [] (println 42))").unwrap();
    let ir = bars::compile_to_qbe(&prog).unwrap();
    assert!(ir.contains("export function l $main()"));
    assert!(ir.contains("$printf"));
}

#[test]
fn test_compile_arithmetic() {
    let prog = reader::read("(defn main [] (+ 1 2))").unwrap();
    let ir = bars::compile_to_qbe(&prog).unwrap();
    assert!(ir.contains("add"));
}

#[test]
fn test_compile_if() {
    let prog = reader::read("(defn main [] (if true 1 2))").unwrap();
    let ir = bars::compile_to_qbe(&prog).unwrap();
    assert!(ir.contains("jnz"));
    // In tail position, if no longer needs alloc8/load (TCO optimization)
    assert!(ir.contains("ret"));
}

#[test]
fn test_compile_let() {
    let prog = reader::read("(defn main [] (let [x 5] (+ x 1)))").unwrap();
    let ir = bars::compile_to_qbe(&prog).unwrap();
    assert!(ir.contains("copy"));
}

#[test]
fn test_compile_function_call() {
    let prog = reader::read("(defn add [a b] (+ a b)) (defn main [] (add 3 4))").unwrap();
    let ir = bars::compile_to_qbe(&prog).unwrap();
    assert!(ir.contains("export function l $add"));
    assert!(ir.contains("call $add"));
}

#[test]
fn test_tail_call_recognized() {
    let prog = reader::read(r#"
        (defn sum [n acc]
          (if (= n 0)
            acc
            (sum (- n 1) (+ acc n))))
        (defn main [] (println (sum 10 0)) 0)
    "#).unwrap();
    let ir = bars::compile_to_qbe(&prog).unwrap();
    // QBE backend compiles TailCall as call + ret
    assert!(ir.contains("call $sum"));
    assert!(ir.contains("ret"));
}

/// Regression: lambda extraction must save/restore current_params so a later
/// loop that shadows a function parameter still renames the loop var (QBE).
#[test]
fn test_lambda_then_loop_param_shadow() {
    let prog = reader::read(r#"
        (defn main [n]
          (let [f (fn [x] (+ x 1))]
            (loop [n 0]
              (if (= n 3)
                n
                (recur (+ n 1))))))
    "#).unwrap();
    let hir = bars::lower_and_optimize(&prog).unwrap();
    let main = hir.funcs.iter().find(|f| f.name == "main").expect("main");
    // Loop var shadowing param `n` must be renamed to _lv_n (not clobbered by lambda params).
    let has_lv = main.blocks.iter().any(|b| {
        b.instrs.iter().any(|i| match i {
            bars::hir::Instr::Assign { dest, .. } => dest == "_lv_n" || dest.starts_with("_lv_"),
            _ => false,
        })
    });
    assert!(
        has_lv,
        "expected renamed loop var after lambda extraction; blocks: {:?}",
        main.blocks
    );
}
