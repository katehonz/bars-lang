use bars::types::{InferCtx, Type};
use bars::reader;

#[test]
fn test_number_is_i64() {
    let prog = reader::read(r#"
        (defn main [] 42)
    "#).unwrap();
    let mut ctx = InferCtx::new();
    let (_, types) = ctx.infer_program(&prog).unwrap();
    // main has type Fun([], I64)
    match &types[0].1.ty {
        Type::Fun(params, ret) => {
            assert!(params.is_empty());
            assert_eq!(ret.as_ref(), &Type::I64);
        }
        other => panic!("Expected function type, got {:?}", other),
    }
    assert!(types[0].1.vars.is_empty(), "Concrete type should have no generic vars");
}

#[test]
fn test_arithmetic_returns_i64() {
    let prog = reader::read(r#"
        (defn add [a b] (+ a b))
    "#).unwrap();
    let mut ctx = InferCtx::new();
    let (_, types) = ctx.infer_program(&prog).unwrap();
    // add has type Fun([I64, I64], I64)
    match &types[0].1.ty {
        Type::Fun(params, ret) => {
            assert_eq!(params.len(), 2);
            assert_eq!(ret.as_ref(), &Type::I64);
        }
        other => panic!("Expected function type, got {:?}", other),
    }
    assert!(types[0].1.vars.is_empty(), "Concrete type should have no generic vars");
}

#[test]
fn test_bool_comparison() {
    let prog = reader::read(r#"
        (defn eq [a b] (= a b))
    "#).unwrap();
    let mut ctx = InferCtx::new();
    let (_, types) = ctx.infer_program(&prog).unwrap();
    // eq has type Fun([I64, I64], Bool)
    match &types[0].1.ty {
        Type::Fun(params, ret) => {
            assert_eq!(params.len(), 2);
            assert_eq!(ret.as_ref(), &Type::Bool);
        }
        other => panic!("Expected function type, got {:?}", other),
    }
    assert!(types[0].1.vars.is_empty(), "Concrete type should have no generic vars");
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
    // main has type Fun([], I64)
    match &types[0].1.ty {
        Type::Fun(params, ret) => {
            assert!(params.is_empty());
            assert_eq!(ret.as_ref(), &Type::I64);
        }
        other => panic!("Expected function type, got {:?}", other),
    }
    assert!(types[0].1.vars.is_empty(), "Concrete type should have no generic vars");
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
    // main has type Fun([], I64) — strings are i64 pointers at runtime
    match &types[0].1.ty {
        Type::Fun(params, ret) => {
            assert!(params.is_empty());
            assert_eq!(ret.as_ref(), &Type::I64);
        }
        other => panic!("Expected function type, got {:?}", other),
    }
    assert!(types[0].1.vars.is_empty(), "Concrete type should have no generic vars");
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
    // main has type Fun([], I64)
    match &types[0].1.ty {
        Type::Fun(params, ret) => {
            assert!(params.is_empty());
            assert_eq!(ret.as_ref(), &Type::I64);
        }
        other => panic!("Expected function type, got {:?}", other),
    }
    assert!(types[0].1.vars.is_empty(), "Concrete type should have no generic vars");
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

#[test]
fn test_return_type_annotation_ok() {
    let prog = reader::read(r#"
        (defn add [a b] -> i64 (+ a b))
        (defn main [] (add 1 2))
    "#).unwrap();
    let result = bars::infer_types(&prog);
    assert!(result.is_ok(), "Return type annotation should match: {:?}", result.err());
}

#[test]
fn test_return_type_annotation_mismatch() {
    let prog = reader::read(r#"
        (defn bad [x] -> bool (+ x 1))
    "#).unwrap();
    let result = bars::infer_types(&prog);
    assert!(result.is_err(), "Return type mismatch should error");
}

#[test]
fn test_generic_identity() {
    let prog = reader::read(r#"
        (defn id [x] x)
    "#).unwrap();
    let mut ctx = InferCtx::new();
    let (_, types) = ctx.infer_program(&prog).unwrap();
    println!("id scheme: {:?}", types[0].1);
    // id should be generic: has type variables
    assert!(!types[0].1.vars.is_empty(), "Identity function should be generic, got: {:?}", types[0].1);
    // The type should be a function
    match &types[0].1.ty {
        Type::Fun(params, ret) => {
            assert_eq!(params.len(), 1);
            // Param and return should be the same type variable
            assert_eq!(&params[0], ret.as_ref(), "Param and return type should match");
        }
        other => panic!("Expected function type, got {:?}", other),
    }
}

#[test]
fn test_generic_identity_used_twice() {
    let prog = reader::read(r#"
        (defn id [x] x)
        (defn main []
          (id 42)
          (id "hello"))
    "#).unwrap();
    let mut ctx = InferCtx::new();
    let result = ctx.infer_program(&prog);
    assert!(result.is_ok(), "Generic identity used with i64 and string should type-check: {:?}", result.err());
}

#[test]
fn test_generic_const() {
    let prog = reader::read(r#"
        (defn const [x y] x)
    "#).unwrap();
    let mut ctx = InferCtx::new();
    let (_, types) = ctx.infer_program(&prog).unwrap();
    // const should be generic: has type variables
    assert!(!types[0].1.vars.is_empty(), "Const function should be generic");
    // The type should be a function with 2 params
    match &types[0].1.ty {
        Type::Fun(params, ret) => {
            assert_eq!(params.len(), 2);
            // First param and return should match
            assert_eq!(&params[0], ret.as_ref(), "First param and return type should match");
        }
        other => panic!("Expected function type, got {:?}", other),
    }
}

#[test]
fn test_adt_constructor_types() {
    let prog = reader::read(r#"
        (deftype Option [Some i64] [None])
        (defn main [] (Some 42))
    "#).unwrap();
    let mut ctx = InferCtx::new();
    let (_, types) = ctx.infer_program(&prog).unwrap();
    // main returns Option type (Named("Option"))
    match &types.iter().find(|(n, _)| n == "main").map(|(_, t)| &t.ty) {
        Some(Type::Fun(params, ret)) => {
            assert!(params.is_empty());
            assert_eq!(ret.as_ref(), &Type::Named("Option".to_string()));
        }
        other => panic!("Expected main: () → Option, got {:?}", other),
    }
}

#[test]
fn test_adt_match_inference() {
    let prog = reader::read(r#"
        (deftype Option [Some i64] [None])
        (defn unwrap [opt]
          (match opt
            (Some v) v
            None 0))
    "#).unwrap();
    let mut ctx = InferCtx::new();
    let result = ctx.infer_program(&prog);
    assert!(result.is_ok(), "Type inference should succeed for ADT match: {:?}", result.err());
}

#[test]
fn test_adt_result_type() {
    let prog = reader::read(r#"
        (deftype Result [Ok i64] [Err i64])
        (defn ok-val [] (Ok 1))
        (defn err-val [] (Err 2))
    "#).unwrap();
    let mut ctx = InferCtx::new();
    let result = ctx.infer_program(&prog);
    assert!(result.is_ok(), "Type inference should succeed for Result: {:?}", result.err());
    let (_, types) = result.unwrap();
    let result_type = Type::Named("Result".to_string());
    for (name, scheme) in &types {
        match &scheme.ty {
            Type::Fun(_, ret) => {
                assert_eq!(ret.as_ref(), &result_type, "{} should return Result", name);
            }
            _ => {}
        }
    }
}
