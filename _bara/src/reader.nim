# Bara Lang Reader (EDN subset)
import strutils
import types

type
  ReaderError* = object of CatchableError

proc skipWhitespaceAndComments(s: string, i: var int) =
  while i < s.len:
    let c = s[i]
    if c in Whitespace or c == ',':
      inc i
    elif c == ';':
      while i < s.len and s[i] != '\n':
        inc i
    else:
      break

proc isSymChar(c: char): bool =
  c in Letters or c in Digits or c in {'+', '-', '*', '/', '_', '?', '!', '=', '<', '>', '.', '\'', '#', '%', '&', ':'}

proc readStringTok(s: string, i: var int): string =
  inc i  # skip opening quote
  var resultStr = ""
  while i < s.len and s[i] != '"':
    if s[i] == '\\' and i + 1 < s.len:
      inc i
      case s[i]
      of 'n': resultStr.add('\n')
      of 't': resultStr.add('\t')
      of 'r': resultStr.add('\r')
      of '\\': resultStr.add('\\')
      of '"': resultStr.add('"')
      else: resultStr.add(s[i])
    else:
      resultStr.add(s[i])
    inc i
  if i >= s.len:
    raise newException(ReaderError, "Unterminated string")
  inc i  # skip closing quote
  return resultStr

proc consumeNumericSuffix(s: string, i: var int) =
  # Consume N (BigInt) or M (BigDecimal) suffix after a number
  if i < s.len and (s[i] == 'N' or s[i] == 'M'):
    inc i

proc consumeRatioDenominator(s: string, i: var int) =
  # Consume /denominator for ratio literals like 1/5, -1/5
  if i < s.len and s[i] == '/' and i + 1 < s.len and s[i+1] in Digits:
    inc i  # skip /
    while i < s.len and s[i] in Digits:
      inc i

proc readNumberOrSym(s: string, i: var int): string =
  var start = i
  # handle negative sign or standalone operators
  if s[i] == '-' or s[i] == '+':
    # Check for negative hex: -0xFF
    if i + 3 < s.len and s[i+1] == '0' and (s[i+2] == 'x' or s[i+2] == 'X'):
      inc i  # skip sign
      inc i  # skip 0
      inc i  # skip x
      while i < s.len and s[i] in {'0'..'9', 'a'..'f', 'A'..'F'}:
        inc i
      return s[start..<i]
    # Check for negative float without leading zero: -.5
    if i + 2 < s.len and s[i+1] == '.' and s[i+2] in Digits:
      inc i  # skip sign
      inc i  # skip dot
      while i < s.len and s[i] in Digits:
        inc i
      # Handle scientific notation: -.5e-3
      if i < s.len and (s[i] == 'e' or s[i] == 'E'):
        inc i
        if i < s.len and (s[i] == '-' or s[i] == '+'):
          inc i
        if i < s.len and s[i] in Digits:
          while i < s.len and s[i] in Digits:
            inc i
      consumeNumericSuffix(s, i)
      consumeRatioDenominator(s, i)
      return s[start..<i]
    elif i + 1 < s.len and s[i+1] in Digits:
      inc i
      while i < s.len and s[i] in Digits:
        inc i
      if i < s.len and s[i] == '.':
        inc i
        while i < s.len and s[i] in Digits:
          inc i
      # Handle scientific notation: 1e5, -1.5e-3
      if i < s.len and (s[i] == 'e' or s[i] == 'E'):
        inc i
        if i < s.len and (s[i] == '-' or s[i] == '+'):
          inc i
        if i < s.len and s[i] in Digits:
          while i < s.len and s[i] in Digits:
            inc i
      consumeNumericSuffix(s, i)
      consumeRatioDenominator(s, i)
      return s[start..<i]
    else:
      # it's a symbol like - or +
      inc i
      while i < s.len and isSymChar(s[i]):
        inc i
      return s[start..<i]
  elif s[i] in Digits or (s[i] == '.' and i + 1 < s.len and s[i+1] in Digits):
    # Handle hex literals: 0x1a, 0xFF, etc.
    if s[i] == '0' and i + 1 < s.len and (s[i+1] == 'x' or s[i+1] == 'X'):
      inc i
      inc i
      while i < s.len and s[i] in {'0'..'9', 'a'..'f', 'A'..'F'}:
        inc i
      return s[start..<i]
    # Handle radix literals: 2r101, 16rFF, etc.
    if s[i] in Digits:
      var j = i + 1
      while j < s.len and s[j] in Digits:
        inc j
      if j < s.len and s[j] == 'r' and j + 1 < s.len and s[j+1] in {'0'..'9', 'a'..'z', 'A'..'Z'}:
        i = j + 1
        while i < s.len and s[i] in {'0'..'9', 'a'..'z', 'A'..'Z'}:
          inc i
        return s[start..<i]
    if s[i] == '.':
      inc i  # skip leading dot
    while i < s.len and s[i] in Digits:
      inc i
    if i < s.len and s[i] == '.':
      inc i
      while i < s.len and s[i] in Digits:
        inc i
    if i < s.len and (s[i] == 'e' or s[i] == 'E'):
      inc i
      if i < s.len and (s[i] == '-' or s[i] == '+'):
        inc i
      if i < s.len and s[i] in Digits:
        while i < s.len and s[i] in Digits:
          inc i
    # Clojure BigInt (N) and BigDecimal (M) suffixes
    if i < s.len and (s[i] == 'N' or s[i] == 'M'):
      inc i
    consumeRatioDenominator(s, i)
    return s[start..<i]
  else:
    while i < s.len and isSymChar(s[i]):
      inc i
    return s[start..<i]

proc readAtom(s: string, i: var int): CljVal =
  let tok = readNumberOrSym(s, i)
  if tok.len == 0:
    raise newException(ReaderError, "Empty token at position " & $i)
  
  # nil, true, false
  if tok == "nil": return cljNil()
  if tok == "true": return cljBool(true)
  if tok == "false": return cljBool(false)
  
  # keyword
  if tok[0] == ':':
    return cljKeyword(tok[1..^1])

  # Special float tokens (used by test suite after ## stripping)
  if tok == "inf": return cljFloat(Inf)
  if tok == "-inf": return cljFloat(-Inf)
  if tok == "nan": return cljFloat(NaN)
  
  # Strip Clojure BigInt/Decimal suffixes for parsing
  var numTok = tok
  if numTok.len > 1 and (numTok[^1] == 'N' or numTok[^1] == 'M'):
    numTok = numTok[0..^2]

  # Handle hex literals: 0xFF, -0x1a, etc.
  var isNeg = false
  var hexTok = numTok
  if hexTok.len >= 1 and hexTok[0] == '-':
    isNeg = true
    hexTok = hexTok[1..^1]
  if hexTok.len >= 3 and hexTok[0] == '0' and (hexTok[1] == 'x' or hexTok[1] == 'X'):
    try:
      var hexVal = 0'u64
      for j in 2..<hexTok.len:
        let c = hexTok[j]
        hexVal = hexVal * 16 + (
          if c in '0'..'9': cast[uint64](ord(c) - ord('0'))
          elif c in 'a'..'f': cast[uint64](ord(c) - ord('a') + 10)
          else: cast[uint64](ord(c) - ord('A') + 10)
        )
      if isNeg:
        if hexVal == 0x8000000000000000'u64:
          return cljInt(low(int64))
        return cljInt(-cast[int64](hexVal))
      return cljInt(cast[int64](hexVal))
    except CatchableError:
      return cljSymbol(tok)

  # Handle radix literals: 2r101, 16rFF, -8r77, etc.
  if tok.len >= 4:
    var radixTok = tok
    var radixNeg = false
    if radixTok[0] == '-' or radixTok[0] == '+':
      radixNeg = (radixTok[0] == '-')
      radixTok = radixTok[1..^1]
    # Find 'r' separator
    let rPos = radixTok.find('r')
    if rPos > 0 and rPos < radixTok.len - 1:
      try:
        let radix = parseInt(radixTok[0..<rPos])
        if radix >= 2 and radix <= 36:
          var val = 0'u64
          for j in rPos+1..<radixTok.len:
            let c = radixTok[j]
            let digit = 
              if c in '0'..'9': ord(c) - ord('0')
              elif c in 'a'..'z': ord(c) - ord('a') + 10
              elif c in 'A'..'Z': ord(c) - ord('A') + 10
              else: -1
            if digit < 0 or digit >= radix:
              raise newException(ReaderError, "invalid digit")
            val = val * cast[uint64](radix) + cast[uint64](digit)
          if radixNeg:
            return cljInt(-cast[int64](val))
          return cljInt(cast[int64](val))
      except CatchableError:
        return cljSymbol(tok)

  # Check for ratio literal like 1/5, -1/5, 3/4
  let slashPos = numTok.find('/')
  if slashPos > 0 and slashPos < numTok.len - 1:
    let numerStr = numTok[0..<slashPos]
    let denomStr = numTok[slashPos+1..^1]
    try:
      let numer = parseInt(numerStr)
      let denom = parseInt(denomStr)
      if denom != 0:
        return cljList(@[cljSymbol("/"), cljInt(numer.int64), cljInt(denom.int64)])
    except CatchableError:
      discard
    return cljSymbol(tok)

  # number
  var isFloat = false
  var isNumber = true
  var startIdx = 0
  if numTok[0] == '-' or numTok[0] == '+':
    if numTok.len == 1:
      isNumber = false
    else:
      startIdx = 1
  var sawExp = false
  for j in startIdx..<numTok.len:
    if numTok[j] == '.':
      if isFloat:
        isNumber = false
        break
      isFloat = true
    elif numTok[j] == 'e' or numTok[j] == 'E':
      if sawExp:
        isNumber = false
        break
      sawExp = true
      isFloat = true
      if j + 1 < numTok.len and (numTok[j+1] == '-' or numTok[j+1] == '+'):
        discard  # skip exponent sign
    elif numTok[j] notin Digits:
      if sawExp and (numTok[j] == '-' or numTok[j] == '+'):
        if j > 0 and (numTok[j-1] == 'e' or numTok[j-1] == 'E'):
          continue
      isNumber = false
      break
  
  if isNumber and tok.len > startIdx:
    var hasDigit = false
    for j in startIdx..<tok.len:
      if tok[j] in Digits:
        hasDigit = true
        break
    if hasDigit:
      if isFloat:
        try:
          return cljFloat(parseFloat(numTok))
        except CatchableError:
          return cljSymbol(tok)
      else:
        try:
          return cljInt(parseInt(numTok).int64)
        except CatchableError:
          return cljSymbol(tok)
  
  # symbol
  return cljSymbol(tok)

proc readForm(s: string, i: var int): CljVal

proc readList(s: string, i: var int): CljVal =
  inc i  # skip '('
  var items: seq[CljVal] = @[]
  while true:
    skipWhitespaceAndComments(s, i)
    if i >= s.len:
      raise newException(ReaderError, "Unterminated list")
    if s[i] == ')':
      inc i
      break
    let form = readForm(s, i)
    if form == nil:
      continue
    if form.kind == ckList and form.items.len == 2 and
       form.items[0].kind == ckSymbol and form.items[0].symName == "splice-unwrap":
      let inner = form.items[1]
      if inner.kind == ckVector:
        for item in inner.items:
          items.add(item)
    else:
      items.add(form)
  return cljList(items)

proc readVector(s: string, i: var int): CljVal =
  inc i  # skip '['
  var items: seq[CljVal] = @[]
  while true:
    skipWhitespaceAndComments(s, i)
    if i >= s.len:
      raise newException(ReaderError, "Unterminated vector")
    if s[i] == ']':
      inc i
      break
    let form = readForm(s, i)
    if form != nil:
      if form.kind == ckList and form.items.len == 2 and
         form.items[0].kind == ckSymbol and form.items[0].symName == "splice-unwrap":
        let inner = form.items[1]
        if inner.kind == ckVector:
          for item in inner.items:
            items.add(item)
      else:
        items.add(form)
  return cljVector(items)

proc readMap(s: string, i: var int): CljVal =
  inc i  # skip '{'
  var pairs: seq[(CljVal, CljVal)] = @[]
  while true:
    skipWhitespaceAndComments(s, i)
    if i >= s.len:
      raise newException(ReaderError, "Unterminated map")
    if s[i] == '}':
      inc i
      break
    let key = readForm(s, i)
    if key == nil:
      # Reader conditional returned nil for key; skip associated value
      skipWhitespaceAndComments(s, i)
      if i < s.len and s[i] != '}':
        discard readForm(s, i)
      continue
    skipWhitespaceAndComments(s, i)
    if i >= s.len or s[i] == '}':
      raise newException(ReaderError, "Map must have even number of forms")
    let val = readForm(s, i)
    if val == nil:
      # Reader conditional returned nil for value; skip this pair
      continue
    pairs.add((key, val))
  return cljMapFromPairs(pairs)

proc readSet(s: string, i: var int): CljVal =
  inc i  # skip '{' after #
  var items: seq[CljVal] = @[]
  while true:
    skipWhitespaceAndComments(s, i)
    if i >= s.len:
      raise newException(ReaderError, "Unterminated set")
    if s[i] == '}':
      inc i
      break
    let form = readForm(s, i)
    if form != nil:
      items.add(form)
  return cljSet(items)

proc readDispatch(s: string, i: var int): CljVal =
  inc i  # skip '#'
  if i >= s.len:
    raise newException(ReaderError, "Unexpected end after #")
  let c = s[i]
  case c
  of '#':
    inc i  # skip second '#'
    let form = readForm(s, i)
    if form != nil and form.kind == ckSymbol:
      case form.symName
      of "Inf": return cljFloat(Inf)
      of "-Inf": return cljFloat(-Inf)
      of "NaN": return cljFloat(NaN)
      else: discard
    return form
  of '{':
    return readSet(s, i)
  of '(':
    let fnBody = readList(s, i)
    return cljList(@[cljSymbol("fn*"), cljVector(@[cljSymbol("%")]), fnBody])
  of '\'':
    inc i
    let sym = readForm(s, i)
    return cljList(@[cljSymbol("var"), sym])
  of '_':
    inc i
    discard readForm(s, i)
    return nil
  of '"':
    # #"regex" — treat as string for now
    inc i
    var regexStr = ""
    while i < s.len and s[i] != '"':
      if s[i] == '\\' and i + 1 < s.len:
        regexStr.add(s[i])
        regexStr.add(s[i+1])
        inc i
      else:
        regexStr.add(s[i])
      inc i
    if i < s.len: inc i  # skip closing "
    return cljString(regexStr)
  of 'u':
    # #uuid"..." — read as string
    if i + 4 < s.len and s[i..i+3] == "uuid":
      i += 4
      while i < s.len and s[i] == ' ': inc i
      if i < s.len and s[i] == '"':
        inc i
        var uuidStr = ""
        while i < s.len and s[i] != '"':
          uuidStr.add(s[i])
          inc i
        if i < s.len: inc i
        return cljString(uuidStr)
    raise newException(ReaderError, "Unknown dispatch: #u")
  of '?':
    # Reader conditional: #?(:clj expr :cljs expr :default expr)
    # Read the next char - if '@' it's splicing version #?@
    var isSplice = false
    inc i
    if i < s.len and s[i] == '@':
      isSplice = true
      inc i
    let form = readForm(s, i)
    if form == nil:
      return nil
    if form.kind != ckList:
      return nil
    var items = form.items
    var cljVal: CljVal = nil
    var defaultVal: CljVal = nil
    var k = 0
    while k < items.len - 1:
      let isKeyword = items[k].kind == ckKeyword
      let isSym = items[k].kind == ckSymbol
      if isKeyword or isSym:
        let name = if isKeyword: items[k].kwName else: items[k].symName
        case name
        of "clj":
          cljVal = items[k + 1]
        of "default":
          defaultVal = items[k + 1]
        else: discard
      k += 2
    var resultVal: CljVal = nil
    if defaultVal != nil:
      resultVal = defaultVal
    elif cljVal != nil:
      resultVal = cljVal
    else:
      return nil
    if isSplice and resultVal != nil and resultVal.kind == ckVector:
      return cljList(@[cljSymbol("splice-unwrap"), resultVal])
    return resultVal
  else:
    # Unknown dispatch macro: skip the next form and return nil
    discard readForm(s, i)
    return nil

proc readWithMeta(s: string, i: var int): CljVal =
  inc i  # skip '^'
  let meta = readForm(s, i)
  let form = readForm(s, i)
  return cljList(@[cljSymbol("with-meta"), form, meta])

proc readSyntaxQuote(s: string, i: var int): CljVal =
  inc i  # skip '`'
  let form = readForm(s, i)
  return cljList(@[cljSymbol("syntax-quote"), form])

proc readUnquoteSplicing(s: string, i: var int): CljVal =
  inc i  # skip '~'
  inc i  # skip '@'
  let form = readForm(s, i)
  return cljList(@[cljSymbol("unquote-splicing"), form])

proc readUnquote(s: string, i: var int): CljVal =
  inc i  # skip '~'
  let form = readForm(s, i)
  return cljList(@[cljSymbol("unquote"), form])

proc readDeref(s: string, i: var int): CljVal =
  inc i  # skip '@'
  let form = readForm(s, i)
  return cljList(@[cljSymbol("deref"), form])

proc readCharLiteral(s: string, i: var int): CljVal =
  inc i  # skip '\'
  if i >= s.len:
    raise newException(ReaderError, "Unexpected end after \\")
  let c = s[i]
  if c in Letters:
    # Could be a named char like newline, space, tab, or a single letter
    var name = ""
    while i < s.len and isSymChar(s[i]):
      name.add(s[i])
      inc i
    case name
    of "newline": return cljString("\n")
    of "space": return cljString(" ")
    of "tab": return cljString("\t")
    of "return": return cljString("\r")
    of "formfeed": return cljString("\x0C")
    of "backspace": return cljString("\x08")
    else:
      if name.len == 1:
        return cljString(name)
      raise newException(ReaderError, "Unknown character literal: \\" & name)
  else:
    # Single character literal like \1, \\ etc
    let ch = $c
    inc i
    return cljString(ch)

proc readForm(s: string, i: var int): CljVal =
  skipWhitespaceAndComments(s, i)
  if i >= s.len:
    raise newException(ReaderError, "Unexpected end of input")
  
  let c = s[i]
  case c
  of '(':
    return readList(s, i)
  of '[':
    return readVector(s, i)
  of '{':
    return readMap(s, i)
  of '"':
    return cljString(readStringTok(s, i))
  of '\'':
    inc i  # skip quote
    let form = readForm(s, i)
    return cljList(@[cljSymbol("quote"), form])
  of '#':
    return readDispatch(s, i)
  of '^':
    return readWithMeta(s, i)
  of '`':
    return readSyntaxQuote(s, i)
  of '~':
    if i + 1 < s.len and s[i+1] == '@':
      return readUnquoteSplicing(s, i)
    return readUnquote(s, i)
  of '@':
    return readDeref(s, i)
  of '\\':
    return readCharLiteral(s, i)
  else:
    return readAtom(s, i)

proc readOne*(s: string, i: var int): CljVal =
  skipWhitespaceAndComments(s, i)
  if i >= s.len:
    return nil
  result = readForm(s, i)
  while result == nil:
    skipWhitespaceAndComments(s, i)
    if i >= s.len:
      return nil
    result = readForm(s, i)

proc read*(s: string): CljVal =
  var i = 0
  var res: CljVal = nil
  while res == nil:
    skipWhitespaceAndComments(s, i)
    if i >= s.len:
      raise newException(ReaderError, "No form found")
    res = readForm(s, i)
  skipWhitespaceAndComments(s, i)
  if i < s.len:
    raise newException(ReaderError, "Extra input after form: " & s[i..^1])
  return res

proc readAll*(s: string): seq[CljVal] =
  var i = 0
  var forms: seq[CljVal] = @[]
  while true:
    skipWhitespaceAndComments(s, i)
    if i >= s.len:
      break
    let form = readForm(s, i)
    if form == nil:
      continue
    if form.kind == ckList and form.items.len == 2 and
       form.items[0].kind == ckSymbol and form.items[0].symName == "splice-unwrap":
      let inner = form.items[1]
      if inner.kind == ckVector:
        for item in inner.items:
          forms.add(item)
    else:
      forms.add(form)
  return forms
