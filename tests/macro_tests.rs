use bars::r#macro::expand_program;
use bars::reader;

#[test]
fn test_when_macro() {
    let prog = reader::read("(when true 1 2)").unwrap();
    let expanded = expand_program(&prog).unwrap();
    assert!(matches!(expanded.exprs[0], bars::ast::Expr::If { .. }));
}

#[test]
fn test_unless_macro() {
    let prog = reader::read("(unless false 1 2)").unwrap();
    let expanded = expand_program(&prog).unwrap();
    assert!(matches!(expanded.exprs[0], bars::ast::Expr::If { .. }));
}

#[test]
fn test_thread_first() {
    let prog = reader::read("(-> 5 (add 3) (mul 2))").unwrap();
    let expanded = expand_program(&prog).unwrap();
    // Should expand to (mul (add 5 3) 2)
    if let bars::ast::Expr::FnCall { func, args, .. } = &expanded.exprs[0] {
        assert!(matches!(func.as_ref(), bars::ast::Expr::Symbol(sym) if sym.0 == "mul"));
        assert_eq!(args.len(), 2);
    } else {
        panic!("Expected FnCall");
    }
}

#[test]
fn test_thread_last() {
    let prog = reader::read("(->> 5 (add 3) (mul 2))").unwrap();
    let expanded = expand_program(&prog).unwrap();
    // Should expand to (mul 2 (add 3 5))
    if let bars::ast::Expr::FnCall { func, args, .. } = &expanded.exprs[0] {
        assert!(matches!(func.as_ref(), bars::ast::Expr::Symbol(sym) if sym.0 == "mul"));
        assert_eq!(args.len(), 2);
    } else {
        panic!("Expected FnCall");
    }
}

#[test]
fn test_when_in_function() {
    let prog = reader::read(r#"
        (defn main []
          (when true
            (println 1)
            (println 2)))
    "#).unwrap();
    let expanded = expand_program(&prog).unwrap();
    // Should compile and run successfully
    let ir = bars::compile_to_qbe(&expanded).unwrap();
    assert!(ir.contains("jnz"));
}

#[test]
fn test_defmacro_with_syntax_quote() {
    let prog = reader::read(r#"
        (defmacro my-or [a b]
          `(if ~a ~a ~b))
        (defn main []
          (my-or false 42))
    "#).unwrap();
    let expanded = expand_program(&prog).unwrap();
    // Should expand my-or to (if false false 42)
    assert_eq!(expanded.exprs.len(), 1); // only defn remains
    if let bars::ast::Expr::Defn { body, .. } = &expanded.exprs[0] {
        if let bars::ast::Expr::If { cond, then_branch, else_branch, .. } = body.as_ref() {
            assert!(matches!(cond.as_ref(), bars::ast::Expr::Bool(false)));
            assert!(matches!(then_branch.as_ref(), bars::ast::Expr::Bool(false)));
            assert!(matches!(else_branch.as_ref(), bars::ast::Expr::Number(42)));
        } else {
            panic!("Expected If in body, got: {:?}", body);
        }
    } else {
        panic!("Expected Defn");
    }
}

#[test]
fn test_defmacro_with_splicing() {
    let prog = reader::read(r#"
        (defmacro my-do [exprs]
          `(do ~@exprs))
        (defn main []
          (my-do (list (quote (println 1)) (quote (println 2)))))
    "#).unwrap();
    let expanded = expand_program(&prog).unwrap();
    // Should expand my-do to (do (println 1) (println 2))
    assert_eq!(expanded.exprs.len(), 1);
    if let bars::ast::Expr::Defn { body, .. } = &expanded.exprs[0] {
        if let bars::ast::Expr::Do { exprs, .. } = body.as_ref() {
            assert_eq!(exprs.len(), 2);
            assert!(matches!(exprs[0], bars::ast::Expr::FnCall { .. }));
            assert!(matches!(exprs[1], bars::ast::Expr::FnCall { .. }));
        } else {
            panic!("Expected Do in body, got: {:?}", body);
        }
    } else {
        panic!("Expected Defn");
    }
}

#[test]
fn test_match_expression() {
    let prog = reader::read(r#"
        (defn f [x]
          (match x
            0 100
            1 101
            _ 999))
    "#).unwrap();
    let expanded = expand_program(&prog).unwrap();
    assert_eq!(expanded.exprs.len(), 1);
    if let bars::ast::Expr::Defn { body, .. } = &expanded.exprs[0] {
        assert!(matches!(body.as_ref(), bars::ast::Expr::Match { .. }));
    } else {
        panic!("Expected Defn");
    }
}
