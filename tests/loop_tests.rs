use std::io::Write;
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
fn test_loop_sum() {
    let source = r#"
(defn main []
  (let [result (loop [i 0 acc 0]
                 (if (= i 10)
                   acc
                   (recur (+ i 1) (+ acc i))))]
    (println result)
    0))
"#;
    let tmp = std::env::temp_dir().join("bars_test_loop_sum.brs");
    std::fs::write(&tmp, source).unwrap();
    let out = run_bars(tmp.to_str().unwrap());
    assert_eq!(out.trim(), "45");
}

#[test]
fn test_loop_factorial() {
    let source = r#"
(defn main []
  (let [result (loop [n 5 acc 1]
                 (if (= n 0)
                   acc
                   (recur (- n 1) (* acc n))))]
    (println result)
    0))
"#;
    let tmp = std::env::temp_dir().join("bars_test_loop_fact.brs");
    std::fs::write(&tmp, source).unwrap();
    let out = run_bars(tmp.to_str().unwrap());
    assert_eq!(out.trim(), "120");
}

#[test]
fn test_loop_repl() {
    let mut child = Command::new("cargo")
        .args(["run", "--quiet", "--", "repl"])
        .current_dir(env!("CARGO_MANIFEST_DIR"))
        .stdin(std::process::Stdio::piped())
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped())
        .spawn()
        .expect("Failed to start REPL");

    {
        let stdin = child.stdin.as_mut().unwrap();
        stdin.write_all(b"(loop [i 0 acc 0] (if (= i 5) acc (recur (+ i 1) (+ acc i))))\n").unwrap();
    }

    let output = child.wait_with_output().unwrap();
    let stdout = String::from_utf8_lossy(&output.stdout);
    assert!(stdout.contains("10"), "Expected '10' in REPL output, got: {}", stdout);
}
