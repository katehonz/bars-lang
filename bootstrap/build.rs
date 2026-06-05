use std::process::Command;

fn main() {
    let manifest_dir = std::env::var("CARGO_MANIFEST_DIR").unwrap();
    let runtime_dir = format!("{}/../runtime", manifest_dir);

    println!("cargo:rerun-if-changed={}/bars_runtime.c", runtime_dir);
    println!("cargo:rerun-if-changed={}/bars_runtime.h", runtime_dir);

    // Compile C runtime to object file
    let obj_path = format!("{}/bars_runtime.o", runtime_dir);
    let src_path = format!("{}/bars_runtime.c", runtime_dir);
    let output = Command::new("cc")
        .args(["-c", "-o", &obj_path, &src_path])
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
    let lib_path = format!("{}/libbars_runtime.a", runtime_dir);
    let output = Command::new("ar")
        .args(["rcs", &lib_path, &obj_path])
        .output()
        .expect("Failed to create static library");

    if !output.status.success() {
        panic!(
            "Failed to create static library: {}",
            String::from_utf8_lossy(&output.stderr)
        );
    }

    println!("cargo:rustc-link-search=native={}", runtime_dir);
    println!("cargo:rustc-link-lib=static=bars_runtime");
    println!("cargo:rustc-link-lib=gc");
}
