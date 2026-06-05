use std::process::Command;

fn workspace_root() -> String {
    format!("{}/..", env!("CARGO_MANIFEST_DIR"))
}

fn bars() -> Command {
    let mut cmd = Command::new(std::env::var("CARGO_BIN_EXE_bars")
        .unwrap_or_else(|_| "./target/debug/bars".to_string()));
    cmd.current_dir(workspace_root());
    cmd
}

#[test]
fn test_require_core_inc() {
    let out = bars()
        .args(["run", "examples/module_demo.brs"])
        .output()
        .unwrap();
    assert!(
        out.status.success(),
        "stderr: {}",
        String::from_utf8_lossy(&out.stderr)
    );
    assert_eq!(String::from_utf8_lossy(&out.stdout).trim(), "43");
}

#[test]
fn test_require_module_with_internal_call() {
    let out = bars()
        .args(["run", "examples/module_demo2.brs"])
        .output()
        .unwrap();
    assert!(
        out.status.success(),
        "stderr: {}",
        String::from_utf8_lossy(&out.stderr)
    );
    assert_eq!(String::from_utf8_lossy(&out.stdout).trim(), "42");
}

#[test]
fn test_require_adt_constructors() {
    let out = bars()
        .args(["run", "examples/module_adt.brs"])
        .output()
        .unwrap();
    assert!(
        out.status.success(),
        "stderr: {}",
        String::from_utf8_lossy(&out.stderr)
    );
    assert_eq!(String::from_utf8_lossy(&out.stdout).trim(), "red");
}

#[test]
fn test_require_struct() {
    let out = bars()
        .args(["run", "examples/module_struct.brs"])
        .output()
        .unwrap();
    assert!(
        out.status.success(),
        "stderr: {}",
        String::from_utf8_lossy(&out.stderr)
    );
    assert_eq!(String::from_utf8_lossy(&out.stdout).trim(), "30");
}

#[test]
fn test_require_no_conflict() {
    let out = bars()
        .args(["run", "examples/module_conflict.brs"])
        .output()
        .unwrap();
    assert!(
        out.status.success(),
        "stderr: {}",
        String::from_utf8_lossy(&out.stderr)
    );
    assert_eq!(String::from_utf8_lossy(&out.stdout).trim(), "3");
}

#[test]
fn test_nested_require() {
    let out = bars()
        .args(["run", "examples/module_nested.brs"])
        .output()
        .unwrap();
    assert!(
        out.status.success(),
        "stderr: {}",
        String::from_utf8_lossy(&out.stderr)
    );
    assert_eq!(String::from_utf8_lossy(&out.stdout).trim(), "42");
}
