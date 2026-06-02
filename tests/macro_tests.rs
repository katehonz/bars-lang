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
