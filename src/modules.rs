use crate::ast::{Expr, Pattern, Program};
use anyhow::{bail, Result};
use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};

/// Find a module file by path string, searching standard locations.
/// Tries exact path first, then appends .brs if missing.
fn find_module_file(base: &Path, path_str: &str) -> Option<PathBuf> {
    let candidates: Vec<String> = if path_str.ends_with(".brs") {
        vec![path_str.to_string()]
    } else {
        vec![path_str.to_string(), format!("{}.brs", path_str)]
    };

    for candidate_str in &candidates {
        // 1. Search relative to base (and its parents) — same as load
        let mut current = Some(base);
        while let Some(dir) = current {
            let candidate = dir.join(candidate_str);
            if candidate.exists() {
                return Some(candidate);
            }
            current = dir.parent();
        }

        // 2. Search in lib/ relative to manifest dir
        let manifest_dir = std::env!("CARGO_MANIFEST_DIR");
        let lib_candidate = PathBuf::from(manifest_dir).join(candidate_str);
        if lib_candidate.exists() {
            return Some(lib_candidate);
        }

        // 3. Search in bars-pkg dependencies: target/bars-deps/*/src/
        let deps_dir = PathBuf::from(manifest_dir).join("target/bars-deps");
        if let Ok(entries) = std::fs::read_dir(&deps_dir) {
            for entry in entries.flatten() {
                let dep_src = entry.path().join("src").join(candidate_str);
                if dep_src.exists() {
                    return Some(dep_src);
                }
            }
        }
    }

    None
}

/// Check if a name is internal (runtime built-in or already module-mangled).
fn is_internal_name(name: &str) -> bool {
    name.starts_with("_bars_") || name.starts_with("_m_")
}

/// Collect all top-level public names defined in a program.
fn collect_public_names(program: &Program) -> HashSet<String> {
    let mut names = HashSet::new();
    for expr in &program.exprs {
        match expr {
            Expr::Def { name, .. } => {
                if !is_internal_name(&name.0) { names.insert(name.0.clone()); }
            }
            Expr::Defn { name, .. } => {
                if !is_internal_name(&name.0) { names.insert(name.0.clone()); }
            }
            Expr::DefStruct { name, .. } => {
                if !is_internal_name(&name.0) { names.insert(name.0.clone()); }
            }
            Expr::DefType { name, variants, .. } => {
                if !is_internal_name(&name.0) { names.insert(name.0.clone()); }
                for v in variants {
                    if !is_internal_name(&v.name.0) { names.insert(v.name.0.clone()); }
                }
            }
            Expr::Extern { bars_name, .. } => {
                if !is_internal_name(&bars_name.0) { names.insert(bars_name.0.clone()); }
            }
            Expr::DefMacro { name, .. } => {
                if !is_internal_name(&name.0) { names.insert(name.0.clone()); }
            }
            _ => {}
        }
    }
    names
}

/// Recursively rename references to public names inside an expression.
/// `local_scope` tracks locally-bound names that shadow public names.
fn rename_in_expr(
    expr: &mut Expr,
    public_names: &HashSet<String>,
    prefix: &str,
    local_scope: &mut HashSet<String>,
) {
    match expr {
        Expr::Symbol(sym, _) => {
            if public_names.contains(&sym.0) && !local_scope.contains(&sym.0) && !is_internal_name(&sym.0) {
                sym.0 = format!("{}{}", prefix, sym.0);
            }
        }

        Expr::Let { bindings, body, .. } => {
            let mut bound = Vec::new();
            for (name, val_expr) in bindings {
                rename_in_expr(val_expr, public_names, prefix, local_scope);
                bound.push(name.0.clone());
                local_scope.insert(name.0.clone());
            }
            rename_in_expr(body, public_names, prefix, local_scope);
            for b in bound {
                local_scope.remove(&b);
            }
        }

        Expr::If { cond, then_branch, else_branch, .. } => {
            rename_in_expr(cond, public_names, prefix, local_scope);
            rename_in_expr(then_branch, public_names, prefix, local_scope);
            rename_in_expr(else_branch, public_names, prefix, local_scope);
        }

        Expr::Do { exprs, .. } => {
            for e in exprs {
                rename_in_expr(e, public_names, prefix, local_scope);
            }
        }

        Expr::FnCall { func, args, .. } => {
            rename_in_expr(func, public_names, prefix, local_scope);
            for arg in args {
                rename_in_expr(arg, public_names, prefix, local_scope);
            }
        }

        Expr::Loop { bindings, body, .. } => {
            let mut bound = Vec::new();
            for (name, init) in bindings {
                rename_in_expr(init, public_names, prefix, local_scope);
                bound.push(name.0.clone());
                local_scope.insert(name.0.clone());
            }
            rename_in_expr(body, public_names, prefix, local_scope);
            for b in bound {
                local_scope.remove(&b);
            }
        }

        Expr::Recur { args, .. } => {
            for arg in args {
                rename_in_expr(arg, public_names, prefix, local_scope);
            }
        }

        Expr::Lambda { params, body, .. } => {
            let mut bound = Vec::new();
            for (name, _) in params {
                bound.push(name.0.clone());
                local_scope.insert(name.0.clone());
            }
            rename_in_expr(body, public_names, prefix, local_scope);
            for b in bound {
                local_scope.remove(&b);
            }
        }

        Expr::Match { expr, arms, .. } => {
            rename_in_expr(expr, public_names, prefix, local_scope);
            for (pat, arm_expr) in arms {
                rename_in_pattern(pat, public_names, prefix);
                let mut pat_bindings = Vec::new();
                collect_pattern_bindings(pat, &mut pat_bindings);
                for b in &pat_bindings {
                    local_scope.insert(b.clone());
                }
                rename_in_expr(arm_expr, public_names, prefix, local_scope);
                for b in pat_bindings {
                    local_scope.remove(&b);
                }
            }
        }

        Expr::FieldAccess { expr: inner, .. } => {
            rename_in_expr(inner, public_names, prefix, local_scope);
        }

        Expr::Quote(inner, _) | Expr::SyntaxQuote(inner, _) |
        Expr::Unquote(inner, _) | Expr::Splicing(inner, _) |
        Expr::Borrow(inner, _, _) => {
            rename_in_expr(inner, public_names, prefix, local_scope);
        }

        Expr::Vector(elements, _) | Expr::List(elements, _) => {
            for e in elements {
                rename_in_expr(e, public_names, prefix, local_scope);
            }
        }

        Expr::Defn { body, .. } => {
            rename_in_expr(body, public_names, prefix, local_scope);
        }
        Expr::Def { value, .. } => {
            rename_in_expr(value, public_names, prefix, local_scope);
        }
        // DefStruct, DefType, Extern are top-level only and have no expressions to rename
        _ => {}
    }
}

fn collect_pattern_bindings(pat: &Pattern, out: &mut Vec<String>) {
    match pat {
        Pattern::Binding(name) => out.push(name.0.clone()),
        Pattern::Struct { fields, .. } => {
            for f in fields {
                collect_pattern_bindings(f, out);
            }
        }
        Pattern::Vector(elements, _) | Pattern::List(elements, _) => {
            for e in elements {
                collect_pattern_bindings(e, out);
            }
        }
        _ => {}
    }
}

fn rename_in_pattern(
    pat: &mut Pattern,
    public_names: &HashSet<String>,
    prefix: &str,
) {
    match pat {
        Pattern::Struct { name, fields, .. } => {
            if public_names.contains(&name.0) && !is_internal_name(&name.0) {
                name.0 = format!("{}{}", prefix, name.0);
            }
            for f in fields {
                rename_in_pattern(f, public_names, prefix);
            }
        }
        Pattern::Vector(elements, _) | Pattern::List(elements, _) => {
            for e in elements {
                rename_in_pattern(e, public_names, prefix);
            }
        }
        _ => {}
    }
}

fn substitute_qualified_in_pattern(
    pat: &mut Pattern,
    alias_map: &HashMap<String, String>,
) {
    match pat {
        Pattern::Struct { name, fields, .. } => {
            if let Some(pos) = name.0.find('/') {
                let alias = &name.0[..pos];
                let nm = &name.0[pos + 1..];
                if let Some(prefix) = alias_map.get(alias) {
                    name.0 = format!("{}{}", prefix, nm);
                }
            }
            for f in fields {
                substitute_qualified_in_pattern(f, alias_map);
            }
        }
        Pattern::Vector(elements, _) | Pattern::List(elements, _) => {
            for e in elements {
                substitute_qualified_in_pattern(e, alias_map);
            }
        }
        _ => {}
    }
}

/// Rename all top-level definitions and their references in a module.
fn rename_module(program: &mut Program, prefix: &str) {
    let public_names = collect_public_names(program);
    if public_names.is_empty() {
        return;
    }

    // Rename top-level definition names (skip already-mangled nested module names)
    for expr in &mut program.exprs {
        match expr {
            Expr::Def { name, .. } => {
                if !is_internal_name(&name.0) {
                    name.0 = format!("{}{}", prefix, name.0);
                }
            }
            Expr::Defn { name, .. } => {
                if !is_internal_name(&name.0) {
                    name.0 = format!("{}{}", prefix, name.0);
                }
            }
            Expr::DefStruct { name, .. } => {
                if !is_internal_name(&name.0) {
                    name.0 = format!("{}{}", prefix, name.0);
                }
            }
            Expr::DefType { name, variants, .. } => {
                if !is_internal_name(&name.0) {
                    name.0 = format!("{}{}", prefix, name.0);
                }
                for v in variants {
                    if !is_internal_name(&v.name.0) {
                        v.name.0 = format!("{}{}", prefix, v.name.0);
                    }
                }
            }
            Expr::Extern { bars_name, .. } => {
                if !is_internal_name(&bars_name.0) {
                    bars_name.0 = format!("{}{}", prefix, bars_name.0);
                }
            }
            Expr::DefMacro { name, .. } => {
                if !is_internal_name(&name.0) {
                    name.0 = format!("{}{}", prefix, name.0);
                }
            }
            _ => {}
        }
    }

    // Rename references inside all expressions (including top-level values and bodies)
    let mut local_scope = HashSet::new();
    for expr in &mut program.exprs {
        rename_in_expr(expr, &public_names, prefix, &mut local_scope);
    }
}

/// Substitute qualified symbols (alias/name) with their mangled counterparts.
fn substitute_qualified(
    expr: &mut Expr,
    alias_map: &HashMap<String, String>,
    local_scope: &mut HashSet<String>,
) {
    match expr {
        Expr::Symbol(sym, _) => {
            if let Some(pos) = sym.0.find('/') {
                let alias = &sym.0[..pos];
                let name = &sym.0[pos + 1..];
                if let Some(prefix) = alias_map.get(alias) {
                    let mangled = format!("{}{}", prefix, name);
                    sym.0 = mangled;
                }
            }
        }

        Expr::Let { bindings, body, .. } => {
            let mut bound = Vec::new();
            for (name, val_expr) in bindings {
                substitute_qualified(val_expr, alias_map, local_scope);
                bound.push(name.0.clone());
                local_scope.insert(name.0.clone());
            }
            substitute_qualified(body, alias_map, local_scope);
            for b in bound {
                local_scope.remove(&b);
            }
        }

        Expr::If { cond, then_branch, else_branch, .. } => {
            substitute_qualified(cond, alias_map, local_scope);
            substitute_qualified(then_branch, alias_map, local_scope);
            substitute_qualified(else_branch, alias_map, local_scope);
        }

        Expr::Do { exprs, .. } => {
            for e in exprs {
                substitute_qualified(e, alias_map, local_scope);
            }
        }

        Expr::FnCall { func, args, .. } => {
            substitute_qualified(func, alias_map, local_scope);
            for arg in args {
                substitute_qualified(arg, alias_map, local_scope);
            }
        }

        Expr::Loop { bindings, body, .. } => {
            let mut bound = Vec::new();
            for (name, init) in bindings {
                substitute_qualified(init, alias_map, local_scope);
                bound.push(name.0.clone());
                local_scope.insert(name.0.clone());
            }
            substitute_qualified(body, alias_map, local_scope);
            for b in bound {
                local_scope.remove(&b);
            }
        }

        Expr::Recur { args, .. } => {
            for arg in args {
                substitute_qualified(arg, alias_map, local_scope);
            }
        }

        Expr::Lambda { params, body, .. } => {
            let mut bound = Vec::new();
            for (name, _) in params {
                bound.push(name.0.clone());
                local_scope.insert(name.0.clone());
            }
            substitute_qualified(body, alias_map, local_scope);
            for b in bound {
                local_scope.remove(&b);
            }
        }

        Expr::Match { expr, arms, .. } => {
            substitute_qualified(expr, alias_map, local_scope);
            for (pat, arm_expr) in arms {
                substitute_qualified_in_pattern(pat, alias_map);
                let mut pat_bindings = Vec::new();
                collect_pattern_bindings(pat, &mut pat_bindings);
                for b in &pat_bindings {
                    local_scope.insert(b.clone());
                }
                substitute_qualified(arm_expr, alias_map, local_scope);
                for b in pat_bindings {
                    local_scope.remove(&b);
                }
            }
        }

        Expr::FieldAccess { expr: inner, .. } => {
            substitute_qualified(inner, alias_map, local_scope);
        }

        Expr::Quote(inner, _) | Expr::SyntaxQuote(inner, _) |
        Expr::Unquote(inner, _) | Expr::Splicing(inner, _) |
        Expr::Borrow(inner, _, _) => {
            substitute_qualified(inner, alias_map, local_scope);
        }

        Expr::Vector(elements, _) | Expr::List(elements, _) => {
            for e in elements {
                substitute_qualified(e, alias_map, local_scope);
            }
        }

        Expr::Defn { body, .. } => {
            substitute_qualified(body, alias_map, local_scope);
        }
        Expr::Def { value, .. } => {
            substitute_qualified(value, alias_map, local_scope);
        }

        _ => {}
    }
}

/// Parse a require form: (require "path" :as alias)
/// Returns Some((path, alias)) if this is a require form.
fn parse_require(expr: &Expr) -> Option<(String, String)> {
    if let Expr::FnCall { func, args, .. } = expr {
        if let Expr::Symbol(sym, _) = func.as_ref() {
            if sym.0 != "require" {
                return None;
            }
            if args.len() != 3 {
                return None;
            }
            let path = match &args[0] {
                Expr::String(s, _) => s.clone(),
                _ => return None,
            };
            let keyword = match &args[1] {
                Expr::Keyword(kw, _) => kw.0.clone(),
                _ => return None,
            };
            if keyword != "as" {
                return None;
            }
            let alias = match &args[2] {
                Expr::Symbol(sym, _) => sym.0.clone(),
                _ => return None,
            };
            return Some((path, alias));
        }
    }
    None
}

/// Resolve all (require ...) forms in a program, recursively loading modules.
pub fn resolve_requires(
    program: &mut Program,
    base: &Path,
    visited: &mut HashSet<PathBuf>,
) -> Result<()> {
    let mut requires = Vec::new(); // (index_in_exprs, path, alias)
    let mut aliases = HashMap::new(); // alias → prefix

    // Scan for require forms
    for (i, expr) in program.exprs.iter().enumerate() {
        if let Some((path, alias)) = parse_require(expr) {
            requires.push((i, path, alias));
        }
    }

    if requires.is_empty() {
        return Ok(());
    }

    // Resolve each require
    let mut module_exprs = Vec::new(); // (insert_index, module_program_exprs)
    for (index, path, alias) in requires {
        let module_path = find_module_file(base, &path)
            .ok_or_else(|| anyhow::anyhow!("Cannot find module '{}'", path))?;
        let canonical = std::fs::canonicalize(&module_path)
            .map_err(|e| anyhow::anyhow!("Cannot canonicalize module '{}': {}", path, e))?;

        if !visited.insert(canonical.clone()) {
            bail!("Circular module dependency detected: {}", path);
        }

        let source = std::fs::read_to_string(&module_path)
            .map_err(|e| anyhow::anyhow!("Cannot read module '{}': {}", path, e))?;
        let mut module_program = crate::reader::read(&source)
            .map_err(|e| anyhow::anyhow!("Parse error in module '{}': {}", path, e))?;

        let module_base = module_path.parent().unwrap_or(Path::new("."));

        // Resolve loads within the module first
        let mut module_loaded = std::collections::HashSet::new();
        module_loaded.insert(canonical.clone());
        crate::resolve_loads(&mut module_program, module_base, &mut module_loaded)
            .map_err(|e| anyhow::anyhow!("Load error in module '{}': {}", path, e))?;

        // Recursively resolve the module's own requires
        resolve_requires(&mut module_program, module_base, visited)?;

        let prefix = format!("_m_{}_", alias);

        // Rename the module's definitions with the alias prefix
        rename_module(&mut module_program, &prefix);

        // Record alias mapping for later substitution in the current file
        aliases.insert(alias.clone(), prefix);

        module_exprs.push((index, module_program.exprs));
    }

    // Insert module expressions in reverse order so indices stay valid
    for (index, exprs) in module_exprs.into_iter().rev() {
        // Remove the require form and insert module expressions
        program.exprs.remove(index);
        for (i, expr) in exprs.into_iter().enumerate() {
            program.exprs.insert(index + i, expr);
        }
    }

    // Substitute qualified symbols in the current program
    let mut local_scope = HashSet::new();
    for expr in &mut program.exprs {
        substitute_qualified(expr, &aliases, &mut local_scope);
    }

    Ok(())
}
