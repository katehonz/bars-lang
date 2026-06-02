use bars::ownership::{check_program, OwnershipError};
use bars::reader;

#[test]
fn test_use_after_move() {
    let prog = reader::read(r#"
        (def x (vector 1 2))
        (def y x)
        (println x)
    "#).unwrap();
    let err = check_program(&prog).unwrap_err();
    assert!(matches!(err, OwnershipError::UseAfterMove(_, _, _)), "Expected UseAfterMove, got: {:?}", err);
}

#[test]
fn test_borrow_ok() {
    let prog = reader::read(r#"
        (defn use [^buf data]
          data)
        (defn main []
          (let [x 5]
            (use ^x)
            (use ^x)))
    "#).unwrap();
    assert!(check_program(&prog).is_ok());
}

#[test]
fn test_mut_borrow_conflict() {
    let prog = reader::read(r#"
        (defn write [^mut buf data]
          data)
        (defn read [^buf data]
          data)
        (defn main []
          (let [x 5]
            (write x)
            (read x)))
    "#).unwrap();
    let err = check_program(&prog).unwrap_err();
    assert!(matches!(err, OwnershipError::AlreadyMutBorrowed(_, _, _) | OwnershipError::AlreadyBorrowed(_, _, _)),
        "Expected borrow error, got: {:?}", err);
}

#[test]
fn test_let_binding_ok() {
    let prog = reader::read(r#"
        (defn main []
          (let [a 1]
            (let [b a]
              b)))
    "#).unwrap();
    assert!(check_program(&prog).is_ok());
}

#[test]
fn test_if_branch_merge() {
    let prog = reader::read(r#"
        (defn main []
          (let [x (vector 1 2)]
            (if true
              (def y x)
              0)
            (println x)))
    "#).unwrap();
    let err = check_program(&prog).unwrap_err();
    assert!(matches!(err, OwnershipError::UseAfterMove(_, _, _)), "Expected UseAfterMove after if merge, got: {:?}", err);
}

#[test]
fn test_struct_field_after_move() {
    let prog = reader::read(r#"
        (defstruct Point [x y])
        (defn main []
          (def p (Point 10 20))
          (def q p)
          (println (.x p)))
    "#).unwrap();
    let err = check_program(&prog).unwrap_err();
    assert!(matches!(err, OwnershipError::UseAfterMove(_, _, _)), "Expected UseAfterMove for field access after move, got: {:?}", err);
}

#[test]
fn test_move_while_borrowed() {
    let prog = reader::read(r#"
        (defn use [^buf data]
          data)
        (defn main []
          (let [x (vector 1 2)]
            (use ^x)
            (def y x)))
    "#).unwrap();
    let err = check_program(&prog).unwrap_err();
    assert!(matches!(err, OwnershipError::MoveWhileBorrowed(_, _, _)), "Expected MoveWhileBorrowed, got: {:?}", err);
}
