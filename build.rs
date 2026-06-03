use std::process::Command;

fn main() {
    println!("cargo:rerun-if-changed=runtime/bars_runtime.c");
    println!("cargo:rerun-if-changed=runtime/bars_runtime.h");

    // Compile C runtime to object file
    let output = Command::new("cc")
        .args(["-c", "-o", "runtime/bars_runtime.o", "runtime/bars_runtime.c"])
        .args(["-I/usr/include"])
        .output()
        .expect("Failed to compile runtime");

    if !output.status.success() {
        panic!(
            "Failed to compile C runtime: {}",
            String::from_utf8_lossy(&output.stderr)
        );
    }

    // Create static library
    let output = Command::new("ar")
        .args(["rcs", "runtime/libbars_runtime.a", "runtime/bars_runtime.o"])
        .output()
        .expect("Failed to create static library");

    if !output.status.success() {
        panic!(
            "Failed to create static library: {}",
            String::from_utf8_lossy(&output.stderr)
        );
    }

    println!("cargo:rustc-link-search=native=runtime");
    println!("cargo:rustc-link-lib=static=bars_runtime");
    println!("cargo:rustc-link-lib=gc");
}
