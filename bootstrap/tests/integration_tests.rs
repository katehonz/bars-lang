use std::process::Command;

fn workspace_root() -> String {
    format!("{}/..", env!("CARGO_MANIFEST_DIR"))
}

fn bars() -> Command {
    let mut cmd = Command::new("cargo");
    cmd.args(["run", "--quiet", "--"]);
    cmd.current_dir(workspace_root());
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
        .args(["build", "examples/hello.brs", "-o", "/tmp/bars_test_hello"])
        .output()
        .expect("Failed to build");
    assert!(output.status.success(), "Build failed: {}", String::from_utf8_lossy(&output.stderr));
    let stdout = String::from_utf8_lossy(&output.stdout);
    assert!(stdout.contains("Binary written to"));
    // Verify binary exists and runs
    let run = std::process::Command::new("/tmp/bars_test_hello")
        .output()
        .expect("Failed to run built binary");
    let run_stdout = String::from_utf8_lossy(&run.stdout);
    assert!(run_stdout.contains("42"), "Expected '42' in binary output, got: {}", run_stdout);
    let _ = std::fs::remove_file("/tmp/bars_test_hello");
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

#[test]
fn test_run_struct() {
    let output = bars()
        .args(["run", "examples/struct_demo.brs"])
        .output()
        .expect("Failed to run bars");
    let stdout = String::from_utf8_lossy(&output.stdout);
    assert!(stdout.contains("10"), "Expected '10' in output, got: {}", stdout);
    assert!(stdout.contains("20"), "Expected '20' in output, got: {}", stdout);
}

#[test]
fn test_run_struct_match() {
    let output = bars()
        .args(["run", "examples/struct_match.brs"])
        .output()
        .expect("Failed to run bars");
    let stdout = String::from_utf8_lossy(&output.stdout);
    assert!(stdout.contains("0"), "Expected '0' in output, got: {}", stdout);
    assert!(stdout.contains("7"), "Expected '7' in output, got: {}", stdout);
}

#[test]
fn test_run_nested_collections() {
    let output = bars()
        .args(["run", "examples/nested_demo.brs"])
        .output()
        .expect("Failed to run bars");
    let stdout = String::from_utf8_lossy(&output.stdout);
    assert!(stdout.contains("3"), "Expected '3' in output, got: {}", stdout);
    assert!(stdout.contains("2"), "Expected '2' in output, got: {}", stdout);
    assert!(stdout.contains("10"), "Expected '10' in output, got: {}", stdout);
}

#[test]
fn test_run_set() {
    let output = bars()
        .args(["run", "examples/set_demo.brs"])
        .output()
        .expect("Failed to run bars");
    let stdout = String::from_utf8_lossy(&output.stdout);
    assert!(stdout.contains("3"), "Expected '3' in output, got: {}", stdout);
    assert!(stdout.contains("1"), "Expected '1' in output, got: {}", stdout);
    assert!(stdout.contains("0"), "Expected '0' in output, got: {}", stdout);
}

#[test]
fn test_run_adt_option() {
    let output = bars()
        .args(["run", "examples/adt_demo.brs"])
        .output()
        .expect("Failed to run bars");
    let stdout = String::from_utf8_lossy(&output.stdout);
    assert!(stdout.contains("42"), "Expected '42' in output, got: {}", stdout);
    assert!(stdout.contains("0"), "Expected '0' in output, got: {}", stdout);
}

#[test]
fn test_run_adt_result() {
    let output = bars()
        .args(["run", "examples/adt_demo2.brs"])
        .output()
        .expect("Failed to run bars");
    let stdout = String::from_utf8_lossy(&output.stdout);
    assert!(stdout.contains("42"), "Expected '42' in output, got: {}", stdout);
    assert!(stdout.contains("-5"), "Expected '-5' in output, got: {}", stdout);
}

#[test]
fn test_run_adt_shape() {
    let output = bars()
        .args(["run", "examples/adt_demo3.brs"])
        .output()
        .expect("Failed to run bars");
    let stdout = String::from_utf8_lossy(&output.stdout);
    assert!(stdout.contains("25"), "Expected '25' in output, got: {}", stdout);
    assert!(stdout.contains("12"), "Expected '12' in output, got: {}", stdout);
}

#[test]
fn test_adt_exhaustiveness_error() {
    let output = bars()
        .args(["run", "examples/adt_nonexhaustive.brs"])
        .output()
        .expect("Failed to run bars");
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(stderr.contains("not exhaustive") || stderr.contains("missing variant"),
        "Expected exhaustiveness error, got: {}", stderr);
}

#[test]
fn test_ffi_putchar() {
    let output = bars()
        .args(["run", "examples/ffi_demo.brs"])
        .output()
        .expect("Failed to run bars");
    let stdout = String::from_utf8_lossy(&output.stdout);
    assert!(stdout.contains("A"), "Expected 'A' in output, got: {}", stdout);
}

#[test]
fn test_hof_map() {
    let output = bars()
        .args(["run", "examples/hof_demo.brs"])
        .output()
        .expect("Failed to run bars");
    let stdout = String::from_utf8_lossy(&output.stdout);
    assert!(stdout.contains("5"), "Expected map count=5, got: {}", stdout);
    assert!(stdout.contains("2"), "Expected filter count=2, got: {}", stdout);
    assert!(stdout.contains("15"), "Expected reduce sum=15, got: {}", stdout);
}

#[test]
fn test_hof_lambda() {
    let output = bars()
        .args(["run", "examples/hof_lambda.brs"])
        .output()
        .expect("Failed to run bars");
    let stdout = String::from_utf8_lossy(&output.stdout);
    assert!(stdout.contains("2"), "Expected doubled[0]=2, got: {}", stdout);
    assert!(stdout.contains("4"), "Expected doubled[1]=4, got: {}", stdout);
}
