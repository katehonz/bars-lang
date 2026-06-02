use std::process::Command;

fn run_bars(file: &str) -> String {
    let output = Command::new("cargo")
        .args(["run", "--", "run", file])
        .current_dir(env!("CARGO_MANIFEST_DIR"))
        .output()
        .expect("cargo run failed");
    let stdout = String::from_utf8_lossy(&output.stdout);
    let stderr = String::from_utf8_lossy(&output.stderr);
    if !output.status.success() {
        panic!("bars run failed:\nstdout: {}\nstderr: {}", stdout, stderr);
    }
    stdout.lines().map(|s| s.to_string()).collect::<Vec<_>>().join("\n")
}

#[test]
fn test_core_demo() {
    let out = run_bars("examples/core_demo.brs");
    let lines: Vec<_> = out.lines().collect();
    assert_eq!(lines.len(), 12);
    assert_eq!(lines[1], "4");
    assert_eq!(lines[2], "6");
    assert_eq!(lines[3], "10");
    assert_eq!(lines[4], "7");
    assert_eq!(lines[5], "3");
    assert_eq!(lines[6], "1");
    assert_eq!(lines[7], "1");
    assert_eq!(lines[8], "0");
    assert_eq!(lines[9], "1");
    assert_eq!(lines[10], "1");
    assert_eq!(lines[11], "3");
}

#[test]
fn test_stdlib_demo() {
    let out = run_bars("examples/stdlib_demo.brs");
    let lines: Vec<_> = out.lines().collect();
    assert_eq!(lines.len(), 16);
    assert_eq!(lines[0], "25");
    assert_eq!(lines[1], "27");
    assert_eq!(lines[2], "6");
    assert_eq!(lines[3], "12");
    assert_eq!(lines[4], "120");
    assert_eq!(lines[5], "55");
    assert_eq!(lines[6], "10");
    assert_eq!(lines[7], "24");
    assert_eq!(lines[8], "4");
    assert_eq!(lines[13], "1");
    assert_eq!(lines[14], "2");
}

#[test]
fn test_cond_macro() {
    let out = run_bars("examples/cond_demo.brs");
    let lines: Vec<_> = out.lines().collect();
    assert_eq!(lines[0], "20");
    assert_eq!(lines[1], "200");
}
