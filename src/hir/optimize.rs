use crate::hir::*;
use std::collections::HashSet;

/// Fold constant expressions in HIR.
///
/// Replaces `BinOp` and `UnOp` instructions with `Const` when all operands
/// are compile-time constants.
pub fn constant_fold(program: &mut Program) {
    for func in &mut program.funcs {
        for block in &mut func.blocks {
            for instr in &mut block.instrs {
                match instr {
                    Instr::BinOp { dest, op, lhs, rhs } => {
                        if let (Operand::Const(a), Operand::Const(b)) = (lhs, rhs) {
                            if let Some(val) = eval_binop(*op, *a, *b) {
                                *instr = Instr::Const { dest: dest.clone(), value: val };
                            }
                        }
                    }
                    Instr::UnOp { dest, op, operand } => {
                        if let Operand::Const(a) = operand {
                            if let Some(val) = eval_unop(*op, *a) {
                                *instr = Instr::Const { dest: dest.clone(), value: val };
                            }
                        }
                    }
                    _ => {}
                }
            }
        }
    }
}

fn eval_binop(op: BinOp, a: i64, b: i64) -> Option<i64> {
    match op {
        BinOp::Add => Some(a + b),
        BinOp::Sub => Some(a - b),
        BinOp::Mul => Some(a * b),
        BinOp::Div => if b != 0 { Some(a / b) } else { None },
        BinOp::Rem => if b != 0 { Some(a % b) } else { None },
        BinOp::Eq => Some(if a == b { 1 } else { 0 }),
        BinOp::Ne => Some(if a != b { 1 } else { 0 }),
        BinOp::Lt => Some(if a < b { 1 } else { 0 }),
        BinOp::Le => Some(if a <= b { 1 } else { 0 }),
        BinOp::Gt => Some(if a > b { 1 } else { 0 }),
        BinOp::Ge => Some(if a >= b { 1 } else { 0 }),
    }
}

fn eval_unop(op: UnOp, a: i64) -> Option<i64> {
    match op {
        UnOp::Not => Some(if a == 0 { 1 } else { 0 }),
    }
}

/// Remove unreachable blocks from HIR functions.
///
/// A block is unreachable if it is not the entry block and no reachable
/// block jumps to it. We compute reachability via BFS from the entry block.
pub fn remove_dead_blocks(program: &mut Program) {
    for func in &mut program.funcs {
        let mut reachable: HashSet<String> = HashSet::new();
        let mut queue = vec![func.entry_block.clone()];
        reachable.insert(func.entry_block.clone());

        while let Some(label) = queue.pop() {
            if let Some(block) = func.blocks.iter().find(|b| b.label == label) {
                match &block.terminator {
                    Terminator::Jump(target) => {
                        if reachable.insert(target.clone()) {
                            queue.push(target.clone());
                        }
                    }
                    Terminator::Branch { then_block, else_block, .. } => {
                        if reachable.insert(then_block.clone()) {
                            queue.push(then_block.clone());
                        }
                        if reachable.insert(else_block.clone()) {
                            queue.push(else_block.clone());
                        }
                    }
                    Terminator::Return(_) | Terminator::Unreachable => {}
                }
            }
        }

        func.blocks.retain(|b| reachable.contains(&b.label));
    }
}
