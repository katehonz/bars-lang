import subprocess, tempfile, os, re, sys

def extract_default(content, start):
    """Extract the :default branch value from reader conditional content.
    Returns (value_string, consumed_length)."""
    content = content.strip()
    # Find :default keyword
    default_idx = content.find(':default')
    if default_idx < 0:
        return '', len(content)
    rest = content[default_idx + len(':default'):].strip()
    if not rest:
        return '', len(content)
    # Read one s-expression
    if rest[0] in '([':
        open_c = rest[0]
        close_c = ']' if open_c == '[' else ')'
        depth = 0
        k = 0
        while k < len(rest):
            if rest[k] == open_c:
                depth += 1
            elif rest[k] == close_c:
                depth -= 1
                if depth == 0:
                    return rest[:k+1], k+1
            k += 1
        return rest, len(rest)
    elif rest[0] == '"':
        # String
        k = 1
        while k < len(rest):
            if rest[k] == '\\':
                k += 1
            elif rest[k] == '"':
                return rest[:k+1], k+1
            k += 1
        return rest, len(rest)
    else:
        # Atom: read until whitespace or )
        k = 0
        while k < len(rest) and rest[k] not in ' \t\n\r,)':
            k += 1
        return rest[:k], k

def strip_reader_conditionals(text):
    """Strip #? and #?@ reader conditionals, keeping :default branch content.
    For #?@, if the default is a vector/list, unwrap it (splice semantics)."""
    result = []
    i = 0
    while i < len(text):
        # Check for #?@ or #?
        is_splice = False
        if i + 3 <= len(text) and text[i:i+3] == '#?@':
            j = i + 3
            is_splice = True
        elif i + 2 <= len(text) and text[i:i+2] == '#?':
            j = i + 2
        else:
            result.append(text[i])
            i += 1
            continue

        # Skip whitespace between #? and (
        while j < len(text) and text[j] in ' \t\n\r':
            j += 1
        if j >= len(text) or text[j] != '(':
            result.append(text[i])
            i += 1
            continue

        # Find matching closing paren
        depth = 0
        k = j
        while k < len(text):
            if text[k] == '(':
                depth += 1
            elif text[k] == ')':
                depth -= 1
                if depth == 0:
                    break
            k += 1
        if depth != 0:
            result.append(text[i])
            i += 1
            continue

        # Extract content between parens
        inner = text[j+1:k]
        default_val, _ = extract_default(inner, 0)
        if is_splice and len(default_val) >= 2 and default_val[0] in '([':
            default_val = default_val[1:-1]
        result.append(default_val)
        i = k + 1

    return ''.join(result)

def run_test(cljc_path, timeout=30):
    with open(cljc_path, 'r') as f:
        content = f.read()
    # Reader conditionals are now handled by the reader itself
    # content = strip_reader_conditionals(content)
    content = content.replace('##Inf', 'inf').replace('##-Inf', '-inf').replace('##NaN', 'nan')
    content = re.sub(r'#:([\w-]+)', r'\1', content)    # #:foo → foo
    stubs = '''(do
'''
    content = stubs + content + ')'
    content = re.sub(r'clojure\.test', 'test', content)
    fd, path = tempfile.mkstemp(suffix='.clj')
    try:
        os.write(fd, content.encode())
    finally:
        os.close(fd)
    try:
        result = subprocess.run(['./cljnim', 'run', path], capture_output=True, text=True, timeout=timeout)
        return result.returncode, result.stdout, result.stderr
    finally:
        os.unlink(path)

if len(sys.argv) > 1:
    cljc = sys.argv[1]
    rc, out, err = run_test(cljc)
    print(f'rc={rc}')
    if rc != 0:
        print('stderr:', err[:500])
    if out.strip():
        print('stdout:', out[:500])
else:
    for test in ['zipmap', 'zero_qmark', 'with_out_str']:
        cljc = f'/tmp/clojure-test-suite/test/clojure/core_test/{test}.cljc'
        rc, out, err = run_test(cljc)
        print(f'{test}: rc={rc}')
        if rc != 0:
            print('  stderr:', err[:300])
