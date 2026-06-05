pub mod cranelift;
#[cfg(feature = "llvm-backend")]
pub mod llvm;
pub mod qbe_hir;

/// Sanitize a Bars identifier into a valid QBE/C identifier.
pub fn sanitize_name(name: &str) -> String {
    name.replace('?', "_Q")
        .replace('!', "_B")
        .replace('-', "_")
        .replace('+', "_plus")
        .replace('*', "_star")
        .replace('/', "_slash")
        .replace('%', "_percent")
        .replace('=', "_eq")
        .replace('<', "_lt")
        .replace('>', "_gt")
        .replace('&', "_amp")
        .replace('|', "_pipe")
}
