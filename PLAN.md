# Bars Architecture Refactor Plan

## Goal
Make Bars ownership-sound and introduce a proper HIR lowering phase,
following the advice: borrow checker first, desugaring second, C ABI third.

## Phase 1: Harden Ownership Checker (Week 1)

### 1.1 Borrow Lifetime Tracking
Current: borrow lives until end of scope.
Target: borrow expires after last use (NLL - Non-Lexical Lifetimes).

```clojure
(let [v [1 2 3]]
  (println (first v))   ; borrow of v
  (println (count v))   ; borrow of v again — should be OK
  (def w v))            ; move v — should be OK because borrow expired
```

### 1.2 Struct Field Tracking
Current: moving `p` does not prevent `(.x p)`.
Target: after move, field access is illegal.

```clojure
(def p (Point 10 20))
(def q p)             ; move p
(println (.x p))      ; ERROR: p was moved
```

### 1.3 Drop Checking
Current: no check that resources are properly dropped.
Target: warn/error if owned resource goes out of scope without explicit drop.

```clojure
(defn leaky []
  (def buf (buffer/new 1024))
  (buffer/read buf 0))
  ; ERROR: buf not dropped before return
```

### 1.4 Better Error Messages
Add source location (Span) to OwnershipError.

## Phase 2: HIR / Lowering Phase (Weeks 2-3)

### 2.1 Design HIR Types
```rust
pub enum HirExpr {
    Const(i64),
    Load(String),           // variable
    Store(String, Box<HirExpr>),
    Alloc(usize),           // bytes
    FieldLoad(String, usize), // struct field by offset
    FieldStore(String, usize, Box<HirExpr>),
    Call(String, Vec<HirExpr>),
    Branch(Box<HirExpr>, String, String), // cond, then_label, else_label
    Jump(String),
    Label(String),
    Return(Box<HirExpr>),
}
```

### 2.2 Lowering Pass
`src/hir/lowering.rs`: AST → HIR
- `Expr::Let` → `Alloc` + `Store`
- `Expr::If` → `Branch` with labels
- `Expr::Match` → chain of `Branch`
- `Expr::Loop` → `Label` + `Jump`
- `Expr::Recur` → `Jump`
- `Expr::FieldAccess` → `FieldLoad`

### 2.3 Migrate QBE Backend
QBE backend compiles HIR instead of AST.
Target: ~300 lines (from ~800).

### 2.4 Migrate Cranelift Backend
Same for Cranelift JIT.

## Phase 3: LLVM Backend (Week 1)

### 3.1 Inkwell Integration
`src/backends/llvm/mod.rs`: HIR → LLVM IR via `inkwell`.

### 3.2 Optimization Passes
Enable LLVM O2/O3 for `bars build --release`.

## Acceptance Criteria
- All existing tests pass after each phase.
- New ownership tests for struct fields, borrow lifetimes, drop checking.
- HIR backend produces identical output to current QBE backend.
- LLVM backend compiles `examples/hello.brs` to working binary.
