use bars::reader;

#[test]
fn test_parse_number() {
    let prog = reader::read("42").unwrap();
    assert_eq!(prog.exprs.len(), 1);
    assert!(matches!(prog.exprs[0], bars::ast::Expr::Number(42, _)));
}

#[test]
fn test_parse_add() {
    let prog = reader::read("(+ 1 2)").unwrap();
    assert_eq!(prog.exprs.len(), 1);
    assert!(matches!(prog.exprs[0], bars::ast::Expr::FnCall { .. }));
}

#[test]
fn test_parse_let() {
    let prog = reader::read("(let [x 5] x)").unwrap();
    assert_eq!(prog.exprs.len(), 1);
    assert!(matches!(prog.exprs[0], bars::ast::Expr::Let { .. }));
}

#[test]
fn test_parse_defn() {
    let prog = reader::read("(defn add [a b] (+ a b))").unwrap();
    assert_eq!(prog.exprs.len(), 1);
    assert!(matches!(prog.exprs[0], bars::ast::Expr::Defn { .. }));
}

#[test]
fn test_parse_if() {
    let prog = reader::read("(if true 1 2)").unwrap();
    assert_eq!(prog.exprs.len(), 1);
    assert!(matches!(prog.exprs[0], bars::ast::Expr::If { .. }));
}

#[test]
fn test_parse_vector() {
    let prog = reader::read("[1 2 3]").unwrap();
    assert_eq!(prog.exprs.len(), 1);
    assert!(matches!(prog.exprs[0], bars::ast::Expr::Vector(_, _)));
}

#[test]
fn test_parse_keyword() {
    let prog = reader::read(":hello").unwrap();
    assert_eq!(prog.exprs.len(), 1);
    assert!(matches!(prog.exprs[0], bars::ast::Expr::Keyword(_, _)));
}

#[test]
fn test_multi_expr_body() {
    let prog = reader::read(r#"
        (defn main []
          (println 1)
          (println 2))
    "#).unwrap();
    assert_eq!(prog.exprs.len(), 1);
    if let bars::ast::Expr::Defn { body, .. } = &prog.exprs[0] {
        assert!(matches!(body.as_ref(), bars::ast::Expr::Do { .. }));
    } else {
        panic!("Expected Defn with Do body");
    }
}

#[test]
fn test_parse_lambda() {
    let prog = reader::read(r#"
        (fn [x] (+ x 1))
    "#).unwrap();
    assert_eq!(prog.exprs.len(), 1);
    assert!(matches!(&prog.exprs[0], bars::ast::Expr::Lambda { .. }),
        "Expected Lambda, got {:?}", prog.exprs[0]);
}

#[test]
fn test_parse_lambda_multi_body() {
    let prog = reader::read(r#"
        (fn [x]
          (println x)
          (+ x 1))
    "#).unwrap();
    assert!(matches!(&prog.exprs[0], bars::ast::Expr::Lambda { .. }));
}

#[test]
fn test_unterminated_string_errors() {
    let err = reader::read(r#""hello"#).unwrap_err();
    let msg = format!("{err}");
    assert!(
        msg.to_lowercase().contains("unterminated"),
        "expected unterminated string error, got: {msg}"
    );
}

#[test]
fn test_parse_match_and_deftype() {
    let prog = reader::read(r#"
        (deftype Option [Some i64] [None])
        (defn main []
          (match (Some 1)
            (Some x) x
            (None) 0))
    "#).unwrap();
    assert_eq!(prog.exprs.len(), 2);
    assert!(matches!(prog.exprs[0], bars::ast::Expr::DefType { .. }));
    assert!(matches!(prog.exprs[1], bars::ast::Expr::Defn { .. }));
}

#[test]
fn test_parse_struct_and_field() {
    let prog = reader::read(r#"
        (defstruct Point [x y])
        (defn main []
          (let [p (Point 1 2)]
            (.x p)))
    "#).unwrap();
    assert_eq!(prog.exprs.len(), 2);
    assert!(matches!(prog.exprs[0], bars::ast::Expr::DefStruct { .. }));
}
