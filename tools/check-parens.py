#!/usr/bin/env python3
"""Check parenthesis balance in Bars (.brs) files."""
import sys

def check_parens(filepath):
    with open(filepath) as f:
        lines = f.readlines()

    balance = 0
    errors = []
    warnings = []
    depth_history = []

    for i, line in enumerate(lines, 1):
        line_opens = line.count('(')
        line_closes = line.count(')')
        line_net = line_opens - line_closes
        balance += line_net
        depth_history.append(balance)

        if balance < 0:
            errors.append(
                f"Line {i}: balance went negative ({balance}) — "
                f"too many ')' here?"
            )
            # Don't accumulate negative balance for further checking
            balance = max(0, balance)

        # Flag lines with unusual close counts
        if line_closes >= 8 and line_net <= -5:
            warnings.append(
                f"Line {i}: {line_closes} closes, {line_opens} opens "
                f"(net {line_net}) — verify close count"
            )

    if errors:
        print(f"\n{'='*60}")
        print(f"ERRORS ({len(errors)}):")
        print(f"{'='*60}")
        for e in errors:
            print(f"  {e}")
        print()

    if warnings:
        print(f"{'='*60}")
        print(f"WARNINGS ({len(warnings)}):")
        print(f"{'='*60}")
        for w in warnings:
            print(f"  {w}")
        print()

    if balance != 0:
        errors.append(
            f"Final balance: {balance} — {'missing' if balance > 0 else 'extra'} "
            f"{'close' if balance > 0 else 'open'} paren(s)"
        )

    if not errors and not warnings:
        print(f"OK — parens balanced (final balance: {balance})")
        return 0

    # Show depth per top-level function
    print(f"{'='*60}")
    print("DEPTH PER FUNCTION")
    print(f"{'='*60}")
    in_defn = False
    defn_line = 0
    defn_name = ""
    for i, line in enumerate(lines, 1):
        if '(defn ' in line:
            in_defn = True
            defn_line = i
            # Extract name
            start = line.index('defn ') + 5
            end = line.index('[', start) if '[' in line[start:] else len(line)
            defn_name = line[start:end].strip()
        if in_defn and depth_history[i-1] == 0:
            print(f"  Lines {defn_line:3d}-{i:3d}: {defn_name}")
            in_defn = False

    if in_defn:
        print(f"  Lines {defn_line:3d}-{len(lines):3d}: {defn_name} (UNCLOSED)")

    print(f"\nFinal balance: {balance}")
    return 1 if balance != 0 else 0


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: check-parens.py <file.brs>")
        sys.exit(1)
    sys.exit(check_parens(sys.argv[1]))
