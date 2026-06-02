use bars::types::{InferCtx, Type};
use bars::reader;

#[test]
fn test_number_is_i64() {
    let prog = reader::read(r#"
        (defn main [] 42)
    "#).unwrap();
    let mut ctx = InferCtx::new();
    let (_, types) = ctx.infer_program(&prog).unwrap();
    assert_eq!(types[0].1, Type::I64, "Number literal should be i64");
}

#[test]
fn test_arithmetic_returns_i64() {
    let prog = reader::read(r#"
        (defn add [a b] (+ a b))
    "#).unwrap();
    let mut ctx = InferCtx::new();
    let (_, types) = ctx.infer_program(&prog).unwrap();
    assert_eq!(types[0].1, Type::I64, "Arithmetic should return i64");
}

#[test]
fn test_bool_comparison() {
    let prog = reader::read(r#"
        (defn eq [a b] (= a b))
    "#).unwrap();
    let mut ctx = InferCtx::new();
    let (_, types) = ctx.infer_program(&prog).unwrap();
    assert_eq!(types[0].1, Type::Bool, "Comparison should return bool");
}

#[test]
fn test_if_branches_must_match() {
    let prog = reader::read(r#"
        (defn pick [x]
          (if x 1 2))
    "#).unwrap();
    let mut ctx = InferCtx::new();
    let result = ctx.infer_program(&prog);
    assert!(result.is_ok(), "Matching if branches should type-check: {:?}", result.err());
}

#[test]
fn test_if_branches_mismatch_error() {
    let prog = reader::read(r#"
        (defn bad [x]
          (if x 1 true))
    "#).unwrap();
    let mut ctx = InferCtx::new();
    let result = ctx.infer_program(&prog);
    assert!(result.is_err(), "Mismatched if branches should error");
}

#[test]
fn test_undefined_var_error() {
    let prog = reader::read(r#"
        (defn main []
          foo)
    "#).unwrap();
    let mut ctx = InferCtx::new();
    let result = ctx.infer_program(&prog);
    assert!(result.is_err(), "Undefined variable should error");
}

#[test]
fn test_let_inference() {
    let prog = reader::read(r#"
        (defn main []
          (let [x 42]
            x))
    "#).unwrap();
    let mut ctx = InferCtx::new();
    let (_, types) = ctx.infer_program(&prog).unwrap();
    assert_eq!(types[0].1, Type::I64, "Let should infer i64");
}

#[test]
fn test_function_call_arity() {
    let prog = reader::read(r#"
        (defn add [a b] (+ a b))
        (defn main []
          (add 1 2))
    "#).unwrap();
    let mut ctx = InferCtx::new();
    let result = ctx.infer_program(&prog);
    assert!(result.is_ok(), "Function call with correct arity should type-check: {:?}", result.err());
}

#[test]
fn test_string_literal() {
    let prog = reader::read(r#"
        (defn main []
          "hello")
    "#).unwrap();
    let mut ctx = InferCtx::new();
    let (_, types) = ctx.infer_program(&prog).unwrap();
    assert_eq!(types[0].1, Type::String, "String literal should be string");
}

#[test]
fn test_struct_constructor() {
    let prog = reader::read(r#"
        (defstruct Point [x y])
        (defn main []
          (Point 10 20))
    "#).unwrap();
    let mut ctx = InferCtx::new();
    let result = ctx.infer_program(&prog);
    assert!(result.is_ok(), "Struct constructor should type-check: {:?}", result.err());
}

#[test]
fn test_loop_with_recur() {
    let prog = reader::read(r#"
        (defn main []
          (loop [i 0]
            (if (= i 10)
              i
              (recur (+ i 1)))))
    "#).unwrap();
    let mut ctx = InferCtx::new();
    let (_, types) = ctx.infer_program(&prog).unwrap();
    assert_eq!(types[0].1, Type::I64, "Loop with recur should infer i64");
}

#[test]
fn test_lambda_type_is_function() {
    let prog = reader::read(r#"
        (fn [x] (+ x 1))
    "#).unwrap();
    let mut ctx = InferCtx::new();
    let result = ctx.infer_program(&prog);
    assert!(result.is_ok(), "Lambda should type-check: {:?}", result.err());
}

#[test]
fn test_lambda_with_annotations() {
    let prog = reader::read(r#"
        (fn [^buf x] x)
    "#).unwrap();
    let mut ctx = InferCtx::new();
    let result = ctx.infer_program(&prog);
    assert!(result.is_ok(), "Lambda with borrow annotation should type-check");
}

#[test]
fn test_lambda_inside_defn() {
    let prog = reader::read(r#"
        (defn make-adder []
          (fn [x] (+ x 1)))
    "#).unwrap();
    let mut ctx = InferCtx::new();
    let result = ctx.infer_program(&prog);
    assert!(result.is_ok(), "Lambda inside defn should type-check: {:?}", result.err());
}
