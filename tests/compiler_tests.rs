use bars::backends::qbe::QbeBackend;
use bars::reader;

#[test]
fn test_compile_hello() {
    let prog = reader::read("(defn main [] (println 42))").unwrap();
    let backend = QbeBackend::new();
    let ir = backend.compile(&prog).unwrap();
    assert!(ir.contains("export function l $main()"));
    assert!(ir.contains("$printf"));
}

#[test]
fn test_compile_arithmetic() {
    let prog = reader::read("(defn main [] (+ 1 2))").unwrap();
    let backend = QbeBackend::new();
    let ir = backend.compile(&prog).unwrap();
    assert!(ir.contains("add"));
}

#[test]
fn test_compile_if() {
    let prog = reader::read("(defn main [] (if true 1 2))").unwrap();
    let backend = QbeBackend::new();
    let ir = backend.compile(&prog).unwrap();
    assert!(ir.contains("jnz"));
    assert!(ir.contains("alloc8"));
    assert!(ir.contains("load"));
}

#[test]
fn test_compile_let() {
    let prog = reader::read("(defn main [] (let [x 5] (+ x 1)))").unwrap();
    let backend = QbeBackend::new();
    let ir = backend.compile(&prog).unwrap();
    assert!(ir.contains("copy"));
}

#[test]
fn test_compile_function_call() {
    let prog = reader::read("(defn add [a b] (+ a b)) (defn main [] (add 3 4))").unwrap();
    let backend = QbeBackend::new();
    let ir = backend.compile(&prog).unwrap();
    assert!(ir.contains("export function l $add"));
    assert!(ir.contains("call $add"));
}
