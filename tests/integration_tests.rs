use std::process::Command;

fn bars() -> Command {
    let mut cmd = Command::new("cargo");
    cmd.args(["run", "--quiet", "--"]);
    cmd.current_dir(env!("CARGO_MANIFEST_DIR"));
    cmd
}

#[test]
fn test_run_hello() {
    let output = bars()
        .args(["run", "examples/hello.brs"])
        .output()
        .expect("Failed to run bars");
    let stdout = String::from_utf8_lossy(&output.stdout);
    assert!(stdout.contains("42"), "Expected '42' in output, got: {}", stdout);
}

#[test]
fn test_run_math() {
    let output = bars()
        .args(["run", "examples/math.brs"])
        .output()
        .expect("Failed to run bars");
    let stdout = String::from_utf8_lossy(&output.stdout);
    assert!(stdout.contains("7"), "Expected '7' in output, got: {}", stdout);
    assert!(stdout.contains("120"), "Expected '120' in output, got: {}", stdout);
}

#[test]
fn test_run_string() {
    let output = bars()
        .args(["run", "examples/string.brs"])
        .output()
        .expect("Failed to run bars");
    let stdout = String::from_utf8_lossy(&output.stdout);
    assert!(stdout.contains("Hello, Bars world!"), "Expected string output, got: {}", stdout);
    assert!(stdout.contains("42"), "Expected '42' in output, got: {}", stdout);
}

#[test]
fn test_run_vector() {
    let output = bars()
        .args(["run", "examples/vector.brs"])
        .output()
        .expect("Failed to run bars");
    let stdout = String::from_utf8_lossy(&output.stdout);
    assert!(stdout.contains("4"), "Expected '4' in output, got: {}", stdout);
    assert!(stdout.contains("10"), "Expected '10' in output, got: {}", stdout);
    assert!(stdout.contains("40"), "Expected '40' in output, got: {}", stdout);
}

#[test]
fn test_run_map() {
    let output = bars()
        .args(["run", "examples/map.brs"])
        .output()
        .expect("Failed to run bars");
    let stdout = String::from_utf8_lossy(&output.stdout);
    assert!(stdout.contains("2"), "Expected '2' in output, got: {}", stdout);
    assert!(stdout.contains("100"), "Expected '100' in output, got: {}", stdout);
    assert!(stdout.contains("200"), "Expected '200' in output, got: {}", stdout);
}

#[test]
fn test_build_output() {
    let output = bars()
        .args(["build", "examples/hello.brs"])
        .output()
        .expect("Failed to build");
    let stdout = String::from_utf8_lossy(&output.stdout);
    assert!(stdout.contains("export function l $main()"));
    assert!(stdout.contains("$printf"));
}

#[test]
fn test_run_defmacro() {
    let output = bars()
        .args(["run", "examples/defmacro_demo2.brs"])
        .output()
        .expect("Failed to run bars");
    let stdout = String::from_utf8_lossy(&output.stdout);
    assert!(stdout.contains("42"), "Expected '42' in output, got: {}", stdout);
    assert!(stdout.contains("10"), "Expected '10' in output, got: {}", stdout);
}

#[test]
fn test_run_splicing() {
    let output = bars()
        .args(["run", "examples/splicing_demo.brs"])
        .output()
        .expect("Failed to run bars");
    let stdout = String::from_utf8_lossy(&output.stdout);
    assert!(stdout.contains("1"), "Expected '1' in output, got: {}", stdout);
    assert!(stdout.contains("2"), "Expected '2' in output, got: {}", stdout);
}

#[test]
fn test_run_match() {
    let output = bars()
        .args(["run", "examples/match_demo.brs"])
        .output()
        .expect("Failed to run bars");
    let stdout = String::from_utf8_lossy(&output.stdout);
    assert!(stdout.contains("0"), "Expected '0' in output, got: {}", stdout);
    assert!(stdout.contains("1"), "Expected '1' in output, got: {}", stdout);
    assert!(stdout.contains("999"), "Expected '999' in output, got: {}", stdout);
}
