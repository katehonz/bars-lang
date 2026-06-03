use anyhow::{bail, Context, Result};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::process::Command;

/// Манифест на Bars проект (Bars.toml)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BarsManifest {
    pub package: PackageInfo,
    #[serde(default)]
    pub dependencies: HashMap<String, Dependency>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PackageInfo {
    pub name: String,
    pub version: String,
    pub edition: Option<String>,
    #[serde(default)]
    pub authors: Vec<String>,
    #[serde(default)]
    pub description: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(untagged)]
pub enum Dependency {
    Simple(String),
    Detailed(DependencyDetail),
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DependencyDetail {
    pub version: Option<String>,
    pub git: Option<String>,
    pub path: Option<String>,
}

impl Dependency {
    pub fn version(&self) -> Option<&str> {
        match self {
            Dependency::Simple(v) => Some(v.as_str()),
            Dependency::Detailed(d) => d.version.as_deref(),
        }
    }

    pub fn git(&self) -> Option<&str> {
        match self {
            Dependency::Simple(_) => None,
            Dependency::Detailed(d) => d.git.as_deref(),
        }
    }

    pub fn path(&self) -> Option<&str> {
        match self {
            Dependency::Simple(_) => None,
            Dependency::Detailed(d) => d.path.as_deref(),
        }
    }
}

/// Lock файл за разрешени dependencies
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BarsLock {
    pub package: Vec<LockedPackage>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LockedPackage {
    pub name: String,
    pub version: String,
    pub source: Option<String>,
}

impl BarsManifest {
    pub fn load(dir: &Path) -> Result<Option<Self>> {
        let path = dir.join("Bars.toml");
        if !path.exists() {
            return Ok(None);
        }
        let content = std::fs::read_to_string(&path)
            .with_context(|| format!("cannot read {}", path.display()))?;
        let manifest: BarsManifest = toml::from_str(&content)
            .with_context(|| format!("invalid Bars.toml at {}", path.display()))?;
        Ok(Some(manifest))
    }

    pub fn save(&self, dir: &Path) -> Result<()> {
        let path = dir.join("Bars.toml");
        let content = toml::to_string_pretty(self)?;
        std::fs::write(&path, content)
            .with_context(|| format!("cannot write {}", path.display()))?;
        Ok(())
    }
}

impl BarsLock {
    pub fn load(dir: &Path) -> Result<Option<Self>> {
        let path = dir.join("Bars.lock");
        if !path.exists() {
            return Ok(None);
        }
        let content = std::fs::read_to_string(&path)
            .with_context(|| format!("cannot read {}", path.display()))?;
        let lock: BarsLock = toml::from_str(&content)
            .with_context(|| format!("invalid Bars.lock at {}", path.display()))?;
        Ok(Some(lock))
    }

    pub fn save(&self, dir: &Path) -> Result<()> {
        let path = dir.join("Bars.lock");
        let content = toml::to_string_pretty(self)?;
        std::fs::write(&path, content)
            .with_context(|| format!("cannot write {}", path.display()))?;
        Ok(())
    }
}

/// Създава нов Bars проект
pub fn new_project(name: &str, path: Option<&Path>) -> Result<()> {
    let dir = if let Some(p) = path {
        p.join(name)
    } else {
        PathBuf::from(name)
    };

    if dir.exists() {
        bail!("директория '{}' вече съществува", dir.display());
    }

    std::fs::create_dir_all(&dir)?;
    std::fs::create_dir_all(dir.join("src"))?;

    let manifest = BarsManifest {
        package: PackageInfo {
            name: name.to_string(),
            version: "0.1.0".to_string(),
            edition: Some("2024".to_string()),
            authors: vec![],
            description: None,
        },
        dependencies: HashMap::new(),
    };
    manifest.save(&dir)?;

    let main_brs = r#";; Bars проект
(defn main []
  (println "Hello, Bars!"))
"#;
    std::fs::write(dir.join("src").join("main.brs"), main_brs)?;

    println!("✅ Създаден проект '{}' в {}", name, dir.display());
    Ok(())
}

/// Добавя dependency към текущия проект
pub fn add_dependency(name: &str, dep: Dependency) -> Result<()> {
    let cwd = std::env::current_dir()?;
    let mut manifest = BarsManifest::load(&cwd)?
        .ok_or_else(|| anyhow::anyhow!("няма Bars.toml в текущата директория"))?;

    manifest.dependencies.insert(name.to_string(), dep);
    manifest.save(&cwd)?;
    println!("✅ Добавена зависимост '{}' към {}", name, cwd.join("Bars.toml").display());
    Ok(())
}

/// Разрешава dependencies и връща пътища към тях
pub fn resolve_dependencies(manifest: &BarsManifest, project_dir: &Path) -> Result<Vec<PathBuf>> {
    let deps_dir = project_dir.join("target").join("bars-deps");
    std::fs::create_dir_all(&deps_dir)?;

    let mut resolved = Vec::new();

    for (name, dep) in &manifest.dependencies {
        if let Some(git_url) = dep.git() {
            let dest = deps_dir.join(name);
            if !dest.exists() {
                println!("  📦 Клониране {} от {}", name, git_url);
                let status = Command::new("git")
                    .args(["clone", "--depth", "1", git_url, dest.to_str().unwrap()])
                    .status()?;
                if !status.success() {
                    bail!("git clone failed for {}", name);
                }
            }
            resolved.push(dest.join("src").join("lib.brs"));
        } else if let Some(path_str) = dep.path() {
            let p = project_dir.join(path_str);
            resolved.push(p.join("src").join("lib.brs"));
        } else {
            // Засега не поддържаме central registry
            println!("  ⚠️  Пропускане на {} (няма git/path)", name);
        }
    }

    Ok(resolved)
}

/// Build-ва Bars проект
pub fn build_project(project_dir: &Path, release: bool, backend: &str, bars_bin: &Path) -> Result<PathBuf> {
    let manifest = BarsManifest::load(project_dir)?
        .ok_or_else(|| anyhow::anyhow!("няма Bars.toml в {}", project_dir.display()))?;

    let main_file = project_dir.join("src").join("main.brs");
    if !main_file.exists() {
        bail!("main.brs не съществува в {}", main_file.display());
    }

    // Разреши dependencies
    let dep_paths = resolve_dependencies(&manifest, project_dir)?;

    // Symlink dependency lib файлове в src/ за да работи (load ...)
    let src_dir = project_dir.join("src");
    for dep_path in &dep_paths {
        if dep_path.exists() {
            let link_name = src_dir.join(dep_path.file_name().unwrap_or(dep_path.as_os_str()));
            if !link_name.exists() {
                #[cfg(unix)]
                std::os::unix::fs::symlink(dep_path, &link_name).ok();
                #[cfg(windows)]
                std::os::windows::fs::symlink_file(dep_path, &link_name).ok();
            }
        }
    }

    let out_name = manifest.package.name.clone();
    let out_path = project_dir.join("target").join("release").join(&out_name);
    std::fs::create_dir_all(out_path.parent().unwrap())?;

    let mut cmd = Command::new(bars_bin);
    cmd.arg("build");
    cmd.arg(&main_file);
    cmd.arg("-o").arg(&out_path);
    cmd.arg("--backend").arg(backend);
    if release {
        cmd.arg("--release");
    }

    println!("  🔨 Компилиране {} v{}", manifest.package.name, manifest.package.version);
    let status = cmd.status()
        .with_context(|| "неуспешно изпълнение на bars build. Увери се, че bars е инсталиран.")?;

    if !status.success() {
        bail!("компилацията неуспешна");
    }

    // Запази lock файл
    let lock = BarsLock {
        package: manifest.dependencies.iter().map(|(name, dep)| LockedPackage {
            name: name.clone(),
            version: dep.version().unwrap_or("*").to_string(),
            source: dep.git().map(|s| s.to_string()),
        }).collect(),
    };
    lock.save(project_dir)?;

    println!("✅ Бинарен файл: {}", out_path.display());
    Ok(out_path)
}

/// Run-ва Bars проект
pub fn run_project(project_dir: &Path, release: bool, backend: &str, bars_bin: &Path) -> Result<()> {
    let out = build_project(project_dir, release, backend, bars_bin)?;
    let status = Command::new(&out)
        .status()
        .with_context(|| format!("неуспешно изпълнение на {}", out.display()))?;
    std::process::exit(status.code().unwrap_or(1));
}

/// Намира Bars.toml като търси нагоре от текущата директория
pub fn find_manifest() -> Result<Option<(PathBuf, BarsManifest)>> {
    let mut current = std::env::current_dir()?;
    loop {
        if let Some(manifest) = BarsManifest::load(&current)? {
            return Ok(Some((current, manifest)));
        }
        if !current.pop() {
            break;
        }
    }
    Ok(None)
}
