#!/usr/bin/env python3
"""Validate and emit compiler/types.brs (paren-balanced type inference).

After Phase 17.7–17.9, `compiler/types.brs` is the hand-tuned source of truth
(interleaved solve, accept-any builtins, generalize_prefix, diagnostics, …).
This tool keeps the old workflow working:

  python3 tools/gen_types.py > compiler/types.brs   # identity emit + check
  python3 tools/gen_types.py --check                # validate only (exit 1 on fail)

It refuses to emit unbalanced code and reports net paren drift with a line hint.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TYPES_PATH = ROOT / "compiler" / "types.brs"


def paren_balance(text: str) -> tuple[int, int | None]:
    """Return (net_open_minus_close, first_line_that_goes_negative_or_None)."""
    net = 0
    bad_line = None
    for i, line in enumerate(text.splitlines(), 1):
        # Strip line comments so `;; (foo` does not count.
        code = line.split(";;", 1)[0]
        for ch in code:
            if ch == "(":
                net += 1
            elif ch == ")":
                net -= 1
                if net < 0 and bad_line is None:
                    bad_line = i
    return net, bad_line


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument(
        "--check",
        action="store_true",
        help="validate paren balance only; do not write to stdout",
    )
    ap.add_argument(
        "--path",
        type=Path,
        default=TYPES_PATH,
        help=f"types.brs path (default: {TYPES_PATH})",
    )
    args = ap.parse_args(argv)

    path: Path = args.path
    if not path.is_file():
        print(f"error: missing {path}", file=sys.stderr)
        return 1

    text = path.read_text(encoding="utf-8")
    if not text.endswith("\n"):
        text += "\n"

    net, bad = paren_balance(text)
    if net != 0 or bad is not None:
        print(f"error: paren imbalance in {path} (net={net})", file=sys.stderr)
        if bad is not None:
            print(f"  first negative balance near line {bad}", file=sys.stderr)
        elif net > 0:
            print(f"  {net} unclosed '('", file=sys.stderr)
        else:
            print(f"  {-net} extra ')'", file=sys.stderr)
        return 1

    if args.check:
        print(f"ok: {path} ({len(text.splitlines())} lines, balanced)")
        return 0

    # Identity emit — safe under `> compiler/types.brs` because we read first.
    sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
