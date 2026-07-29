# Installation

## Prerequisites

| Dependency | Purpose |
|------------|---------|
| Rust 1.70+ | Host bootstrap compiler (`bootstrap/`) only |
| `libgc-dev` | Boehm GC for the C runtime |
| `clang` / `cc` | Link self-hosted LLVM / C output |
| `make` | Build targets |
| OpenSSL (`libssl-dev`) | Optional: HTTPS client (`make tls-runtime`) |
| Node 18+ | Optional: VS Code extension (`editors/vscode`) |

QBE is no longer required for day-to-day work. Production codegen is **LLVM IR → clang** via `bars-self` (or Cranelift on the host for bootstrap).

### Installing libgc-dev

**Debian / Ubuntu:**
```bash
sudo apt-get install libgc-dev clang libssl-dev
```

**Fedora:**
```bash
sudo dnf install gc-devel clang openssl-devel
```

**Arch:**
```bash
sudo pacman -S gc clang openssl
```

### Installing Rust

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
```

## Building Bars (recommended)

```bash
git clone https://codeberg.org/bars-lang/bars-lang.git
cd bars-lang

make host          # cargo build --release → target/release/bars
make runtime       # runtime/bars_runtime.o
make bars-self     # host → ./bars-self (Gen1 self-hosted compiler)

make self-test     # example suite (LLVM + C backend + HTTPS smoke)
make identity      # Gen2.ll == Gen3.ll fixed point
```

| Binary | Role |
|--------|------|
| `target/release/bars` | Host (Rust): REPL, `check`, **`lsp`**, cold Gen1 bootstrap |
| `./bars-self` | Day-to-day compiler written in Bars |

Language development is **Bars-first** under `compiler/*.brs`.  
The Rust tree is frozen for bring-up — see `bootstrap/FROZEN.md`.

### Host only (no self-host)

```bash
cargo build --release
./target/release/bars run examples/hello.brs
```

### PATH helpers

```bash
export PATH="$PWD/target/release:$PATH"   # bars
# bars-self is used as ./bars-self from the repo root
```

## Verifying the Build

```bash
./bars-self examples/math.brs /tmp/math && /tmp/math
# Expected: 7\n120

./target/release/bars repl
bars> (+ 1 2)
3

./target/release/bars check --types examples/math.brs
```

## Editor: VS Code + LSP

```bash
make host
cd editors/vscode && npm install
code --install-extension .
# or: ln -sfn "$(pwd)" ~/.vscode/extensions/bars-lang-0.2.0
```

Settings if `bars` is not on `PATH`:

```json
{
  "bars.lsp.path": "/path/to/bars/target/release/bars",
  "bars.lsp.enabled": true
}
```

Details: [`editors/vscode/README.md`](../editors/vscode/README.md).

## TLS runtime (HTTPS)

```bash
make tls-runtime   # runtime/bars_tls.o
# Linking is automatic when code references bars_tls_*
```

## Development

```bash
cargo build          # debug host
cargo test           # host unit tests
make self-test       # self-host suite
```
