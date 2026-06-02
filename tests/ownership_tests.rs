use bars::ownership::{check_program, OwnershipError};
use bars::reader;

#[test]
fn test_use_after_move() {
    let prog = reader::read(r#"
        (def x 10)
        (def y x)
        (println x)
    "#).unwrap();
    let err = check_program(&prog).unwrap_err();
    assert!(matches!(err, OwnershipError::UseAfterMove(_)), "Expected UseAfterMove, got: {:?}", err);
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
    assert!(matches!(err, OwnershipError::AlreadyMutBorrowed(_) | OwnershipError::AlreadyBorrowed(_)),
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
          (let [x 5]
            (if true
              (def y x)
              0)
            (println x)))
    "#).unwrap();
    let err = check_program(&prog).unwrap_err();
    assert!(matches!(err, OwnershipError::UseAfterMove(_)), "Expected UseAfterMove after if merge, got: {:?}", err);
}
