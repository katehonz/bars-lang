#!/usr/bin/env python3
"""Check and fix paren balance in Bars .brs files."""
import sys

def check_balance(filepath):
    with open(filepath) as f:
        lines = f.readlines()
    
    balance = 0
    errors = []
    
    for i, line in enumerate(lines, 1):
        # Count opens and closes (ignore comments and strings for simplicity)
        opens = line.count('(') - line.count(')')
        balance += opens
        
        if balance < 0:
            errors.append(f"Line {i}: balance went negative ({balance}) — too many ')'")
            balance = 0  # reset after error
    
    return balance, errors

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: python3 balance.py file.brs")
        sys.exit(1)
    
    balance, errors = check_balance(sys.argv[1])
    if errors:
        for e in errors:
            print(e)
    print(f"Final balance: {balance}")
