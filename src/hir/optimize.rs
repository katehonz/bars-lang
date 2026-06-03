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
                    Terminator::Return(_) | Terminator::Unreachable | Terminator::TailCall { .. } => {}
                }
            }
        }

        func.blocks.retain(|b| reachable.contains(&b.label));
    }
}

/// Optimize self-recursive tail calls into TailCall terminators.
///
/// Recognizes two patterns:
/// 1. Call { dest, func, args } followed by Return(Var(dest))
/// 2. Call { dest, func, args }, Assign { _ret, Var(dest) }, Return(Var(_ret))
pub fn tail_call_optimize(program: &mut Program) {
    for func in &mut program.funcs {
        let func_name = func.name.clone();
        for block in &mut func.blocks {
            let n = block.instrs.len();
            if n == 0 {
                continue;
            }

            // Pattern 1: Call ... Return(Var(dest))
            if let Some(Instr::Call { dest, func: call_func, args }) = block.instrs.last() {
                if call_func == &func_name {
                    if let Terminator::Return(ret_op) = &block.terminator {
                        if ret_op == &Operand::Var(dest.clone()) {
                            let args = args.clone();
                            block.instrs.pop();
                            block.terminator = Terminator::TailCall { func: func_name.clone(), args };
                            continue;
                        }
                    }
                }
            }

            // Pattern 2: Call ..., Assign { _ret, Var(dest) }, Return(Var(_ret))
            if n >= 2 {
                if let Some(Instr::Call { dest, func: call_func, args }) = block.instrs.get(n - 2) {
                    if call_func == &func_name {
                        if let Some(Instr::Assign { dest: assign_dest, value: Operand::Var(assign_val) }) = block.instrs.last() {
                            if assign_dest == "_ret" && assign_val == dest {
                                if let Terminator::Return(Operand::Var(ret_var)) = &block.terminator {
                                    if ret_var == "_ret" {
                                        let args = args.clone();
                                        block.instrs.pop();
                                        block.instrs.pop();
                                        block.terminator = Terminator::TailCall { func: func_name.clone(), args };
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
