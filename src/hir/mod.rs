pub mod lowering;

/// High-level Intermediate Representation (HIR)
///
/// HIR is a flattened, lower-level representation of Bars AST where:
/// - All control flow is explicit (branches, jumps, labels)
/// - All memory operations are explicit (alloc, store, load, field-access)
/// - There are no nested expressions — everything is sequential instructions
///
/// This makes backend code generation trivial: each HIR instruction maps
/// directly to one or a few target instructions.

/// A HIR program is a list of function definitions
#[derive(Debug, Clone, PartialEq)]
pub struct Program {
    pub funcs: Vec<Func>,
}

/// A function: name, parameters, and a list of basic blocks
#[derive(Debug, Clone, PartialEq)]
pub struct Func {
    pub name: String,
    pub params: Vec<String>,
    pub blocks: Vec<Block>,
    pub entry_block: String,
}

/// A basic block: label + sequential instructions + terminator
#[derive(Debug, Clone, PartialEq)]
pub struct Block {
    pub label: String,
    pub instrs: Vec<Instr>,
    pub terminator: Terminator,
}

/// HIR instructions — each produces a result into a destination variable
#[derive(Debug, Clone, PartialEq)]
pub enum Instr {
    /// dest = value (copy)
    Assign { dest: String, value: Operand },
    /// dest = const_i64
    Const { dest: String, value: i64 },
    /// dest = alloca(size)
    Alloc { dest: String, size: usize },
    /// store value to address
    Store { addr: Operand, value: Operand },
    /// dest = load from address
    Load { dest: String, addr: Operand },
    /// dest = *(base + offset)  (struct field load)
    FieldLoad { dest: String, base: Operand, offset: usize },
    /// *(base + offset) = value  (struct field store)
    FieldStore { base: Operand, offset: usize, value: Operand },
    /// dest = lhs op rhs
    BinOp { dest: String, op: BinOp, lhs: Operand, rhs: Operand },
    /// dest = op operand
    UnOp { dest: String, op: UnOp, operand: Operand },
    /// dest = call func(args)
    Call { dest: String, func: String, args: Vec<Operand> },
    /// dest = global_string(label) — for string literals
    StringLit { dest: String, content: String },
}

/// Binary operators
#[derive(Debug, Clone, PartialEq, Eq, Copy)]
pub enum BinOp {
    Add, Sub, Mul, Div, Rem,
    Eq, Ne, Lt, Le, Gt, Ge,
}

/// Unary operators
#[derive(Debug, Clone, PartialEq, Eq, Copy)]
pub enum UnOp {
    Not,
}

/// An operand — either a variable or a constant
#[derive(Debug, Clone, PartialEq)]
pub enum Operand {
    Var(String),
    Const(i64),
}

/// Block terminator — ends a basic block
#[derive(Debug, Clone, PartialEq)]
pub enum Terminator {
    /// Jump unconditionally to block
    Jump(String),
    /// Branch: if cond then block1 else block2
    Branch { cond: Operand, then_block: String, else_block: String },
    /// Return value
    Return(Operand),
    /// Unreachable (placeholder)
    Unreachable,
}

impl Operand {
    pub fn as_var(&self) -> Option<&str> {
        match self {
            Operand::Var(v) => Some(v),
            _ => None,
        }
    }
}
