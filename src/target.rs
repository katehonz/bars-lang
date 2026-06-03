use anyhow::{bail, Result};

fn command_exists(cmd: &str) -> bool {
    std::process::Command::new(cmd)
        .arg("--version")
        .output()
        .map(|o| o.status.success())
        .unwrap_or(false)
}

/// Cross-compilation target triple.
///
/// Примери: `x86_64-unknown-linux-gnu`, `aarch64-unknown-linux-gnu`, `wasm32-unknown-unknown`
#[derive(Debug, Clone, PartialEq)]
pub struct TargetTriple {
    pub triple: String,
}

impl TargetTriple {
    pub fn host() -> Self {
        Self {
            triple: std::env::consts::ARCH.to_string() + "-unknown-" + std::env::consts::OS + "-gnu",
        }
    }

    pub fn parse(s: &str) -> Result<Self> {
        let triple = s.to_string();
        // Валидация: поне трябва да има архитектура
        if triple.is_empty() {
            bail!("empty target triple");
        }
        Ok(Self { triple })
    }

    pub fn is_host(&self) -> bool {
        // Опростена проверка — сравняваме архитектура и OS
        let host_arch = std::env::consts::ARCH;
        let host_os = std::env::consts::OS;
        self.triple.starts_with(host_arch) && self.triple.contains(host_os)
    }

    /// QBE target name (за `-t` флаг)
    pub fn qbe_target(&self) -> Result<&'static str> {
        if self.triple.starts_with("x86_64") {
            Ok("amd64_sysv")
        } else if self.triple.starts_with("aarch64") {
            Ok("arm64")
        } else {
            bail!("QBE backend не поддържа target '{}'. Поддържани: x86_64, aarch64", self.triple)
        }
    }

    /// Cranelift target triple string
    pub fn cranelift_triple(&self) -> String {
        self.triple.clone()
    }

    /// LLVM target triple string
    pub fn llvm_triple(&self) -> String {
        self.triple.clone()
    }

    /// Име на cross-compiler prefix (напр. `aarch64-linux-gnu`)
    pub fn cross_prefix(&self) -> Option<String> {
        if self.is_host() {
            return None;
        }
        // Опростена хевристика: премахваме последния компонент (-gnu, -musl, etc.)
        let parts: Vec<&str> = self.triple.rsplitn(2, '-').collect();
        if parts.len() == 2 {
            Some(parts[1].to_string())
        } else {
            None
        }
    }

    /// Проверява дали target е WASM
    pub fn is_wasm(&self) -> bool {
        self.triple.starts_with("wasm32") || self.triple.starts_with("wasm64")
    }
}

/// Намира C runtime обект файл за даден target.
/// При host target връща стандартния `bars_runtime.o`.
/// При cross target търси `bars_runtime_<triple>.o`.
pub fn find_runtime_obj(target: &TargetTriple) -> Result<std::path::PathBuf> {
    let manifest_dir = std::env!("CARGO_MANIFEST_DIR");
    if target.is_host() {
        let path = std::path::PathBuf::from(format!("{}/runtime/bars_runtime.o", manifest_dir));
        if path.exists() {
            return Ok(path);
        }
        bail!("host runtime {} not found", path.display());
    }

    // Опит 1: bars_runtime_<triple>.o
    let path = std::path::PathBuf::from(format!(
        "{}/runtime/bars_runtime_{}.o",
        manifest_dir,
        target.triple.replace("-", "_")
    ));
    if path.exists() {
        return Ok(path);
    }

    // Опит 2: bars_runtime_<arch>.o
    let arch = target.triple.split('-').next().unwrap_or(&target.triple);
    let path = std::path::PathBuf::from(format!(
        "{}/runtime/bars_runtime_{}.o",
        manifest_dir, arch
    ));
    if path.exists() {
        return Ok(path);
    }

    bail!(
        "cross-compiled runtime за '{}' не е намерен.\n\
         Компилирай: cc -c -o runtime/bars_runtime_{}.o runtime/bars_runtime.c\n\
         или инсталирай cross toolchain.",
        target.triple,
        target.triple.replace("-", "_")
    )
}

/// Намира подходящ linker за target.
pub fn find_linker(target: &TargetTriple) -> Result<(String, Vec<String>)> {
    if target.is_host() {
        return Ok(("cc".to_string(), vec![]));
    }

    if target.is_wasm() {
        return Ok(("wasm-ld".to_string(), vec!["--no-entry".to_string()]));
    }

    // Опитваме се да намерим cross gcc по няколко well-known имена
    let candidates = [
        format!("{}-gcc", target.triple),                              // пълен triple
        format!("{}-gcc", target.triple.replace("-unknown", "")),     // без -unknown vendor
    ];
    for cc in &candidates {
        if command_exists(cc) {
            return Ok((cc.clone(), vec![]));
        }
    }
    if let Some(prefix) = target.cross_prefix() {
        let cross_cc = format!("{}-gcc", prefix);
        if command_exists(&cross_cc) {
            return Ok((cross_cc, vec![]));
        }
        let cross_ld = format!("{}-ld", prefix);
        if command_exists(&cross_ld) {
            return Ok((cross_ld, vec![]));
        }
    }

    // Опитваме clang като cross compiler
    if command_exists("clang") {
        return Ok(("clang".to_string(), vec!["-target".to_string(), target.triple.clone()]));
    }

    // Fallback към cc — може да не работи за cross
    Ok(("cc".to_string(), vec![]))
}
