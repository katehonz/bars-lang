# Installation

## Prerequisites

| Dependency | Minimum Version | Purpose |
|-----------|-----------------|---------|
| Rust | 1.70 | Building the compiler |
| QBE | 4.0.0 | AOT backend (SSA → assembler) |
| `libgc-dev` | any | Boehm GC for runtime |
| `cc` / `gcc` | any | Linking native binaries |

### Installing QBE

```bash
# From source
git clone git://c9x.me/qbe.git
cd qbe
make
sudo cp qbe /usr/local/bin/

# Or install to ~/.local/bin
make
mkdir -p ~/.local/bin
cp qbe ~/.local/bin/
export PATH="$HOME/.local/bin:$PATH"
```

### Installing libgc-dev

**Debian / Ubuntu:**
```bash
sudo apt-get install libgc-dev
```

**Fedora:**
```bash
sudo dnf install gc-devel
```

**Arch:**
```bash
sudo pacman -S gc
```

### Installing Rust

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
```

## Building Bars

```bash
git clone https://codeberg.org/bars-lang/bars-lang.git
cd bars-lang
cargo build --release
```

The binary will be at `target/release/bars`.

You can add it to your PATH:

```bash
export PATH="$PWD/target/release:$PATH"
```

## Verifying the Build

```bash
bars run examples/hello.brs
# Expected: Hello, World!

bars run examples/math.brs
# Expected: 7\n120

bars repl
bars> (+ 1 2)
3
```

## Development Build

For faster compile times during development:

```bash
cargo build
```

Run tests:

```bash
cargo test
```
