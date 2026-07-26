;; Bars Reader — Lexer + Parser producing tagged S-expression AST
;; Това е първата стъпка към self-hosting.
;;
;; Tag format (numeric, for integer comparison):
;;   [0 val] = number, [1 val] = symbol, [2 val] = string
;;   [3 val] = keyword, [4] = nil, [5 val] = bool
;; Special form tags: 10=defn 11=let 12=if 13=do 14=loop 15=recur
;;                     16=fn 17=match 18=defstruct 19=deftype
;;                     20=extern 21=defmacro 22=quote
;; Reader macro tags: 23=synquote 24=unquote 25=splice 26=meta 27=deref
;;
;; Push mutates vectors in-place. NEVER chain push: (push ...) returns void!

;; ===========================================================================
;; Token ADT
;; ===========================================================================

(deftype Token
  [TNumber v]
  [TFloat v]
  [TString v]
  [TSymbol v]
  [TKeyword v]
  [TBool v]
  [TNilType]
  [TLParen]
  [TRParen]
  [TLBrack]
  [TRBrack]
  [TQuote]
  [TSyntaxQuote]
  [TUnquote]
  [TSplicing]
  [TMeta]
  [TDeref]
  [TEof])

;; ===========================================================================
;; Character helpers
;; ===========================================================================

(defn whitespace? [c]
  (if (= c 32) true
    (if (= c 10) true
      (= c 9))))

(defn digit? [c]
  (if (>= c 48) (<= c 57) false))

(defn alpha? [c]
  (if (<= c 90)
    (>= c 65)
    (if (<= c 122)
      (>= c 97)
      false)))

(defn sym-char? [c]
  (if (>= c 33)
    (if (= c 40) false
      (if (= c 41) false
        (if (= c 91) false
          (if (= c 93) false
            (if (= c 34) false
              (if (= c 39) false
                (if (= c 96) false
                  (if (= c 94) false
                    (if (= c 64) false
                      (if (= c 126) false
                        (if (= c 59) false
                          (if (= c 58) false
                            true))))))))))))
    false))

(defn parse-int [s]
  (let [len (count s)]
    (loop [i 0 acc 0 neg 1]
      (if (>= i len)
        (* acc neg)
        (let [c (str-get s i)]
          (if (= c 45)
            (recur (+ i 1) acc -1)
            (if (digit? c)
              (recur (+ i 1) (+ (* acc 10) (- c 48)) neg)
              (* acc neg))))))))

;; Digit char → one-char string for int-str (0..9)
(defn digit-str [d]
  (str-slice "0123456789" d (+ d 1)))

;; Integer → decimal string (for line:col diagnostics)
(defn int-str [n]
  (if (< n 0)
    (str-concat "-" (int-str (- 0 n)))
    (if (< n 10)
      (digit-str n)
      (str-concat (int-str (/ n 10)) (digit-str (% n 10))))))

;; Byte offset → [line col] (1-based), scanning source text.
(defn offset-to-span [text offset]
  (let [n (count text)
        lim (if (< offset 0) 0 (if (> offset n) n offset))]
    (loop [i 0 line 1 col 1]
      (if (>= i lim)
        (let [v (vector)]
          (do (push v line) (push v col) v))
        (if (= (str-get text i) 10)
          (recur (+ i 1) (+ line 1) 1)
          (recur (+ i 1) line (+ col 1)))))))

;; 1-based line number → line text (without trailing newline).
(defn line-content [text line-num]
  (let [n (count text)]
    (loop [i 0 cur 1 start 0]
      (if (>= i n)
        (if (= cur line-num) (str-slice text start n) "")
        (if (= (str-get text i) 10)
          (if (= cur line-num)
            (str-slice text start i)
            (recur (+ i 1) (+ cur 1) (+ i 1)))
          (recur (+ i 1) cur start))))))

(defn n-spaces [n]
  (loop [i 0 acc ""]
    (if (>= i n) acc
      (recur (+ i 1) (str-concat acc " ")))))

;; Host-style snippet:
;;   3 |   (+ 1 2
;;     |   ^
(defn print-snippet [text line col]
  (if (if (<= line 0) true (= (count text) 0))
    0
    (let [src (line-content text line)
          gutter (int-str line)
          pad (n-spaces (count gutter))
          c0 (if (< col 1) 0 (- col 1))
          c1 (if (> c0 (count src)) (count src) c0)
          indent (n-spaces c1)]
      (do (println "")
          (println (str-concat "  " (str-concat gutter (str-concat " | " src))))
          (println (str-concat "  " (str-concat pad (str-concat " | " (str-concat indent "^")))))
          0))))

;; Print parse error with line:col, path arrow, and source snippet.
(defn parse-err [text path off msg]
  (let [lc (offset-to-span text off)
        line (get lc 0)
        col (get lc 1)
        where (str-concat (int-str line) (str-concat ":" (int-str col)))]
    (do (println (str-concat "error: parse: " (str-concat msg (str-concat " at " where))))
        (if (> (count path) 0)
          (println (str-concat "  --> " (str-concat path (str-concat ":" where))))
          0)
        (print-snippet text line col)
        0)))

;; ===========================================================================
;; Lexer state helpers
;; ===========================================================================

(defn lex-peek [state]
  (let [text (get state 0) pos (get state 1) len (get state 2)]
    (if (>= pos len) -1 (str-get text pos))))

(defn lex-advance [state]
  (let [text (get state 0) pos (get state 1) len (get state 2)]
    [text (+ pos 1) len]))

(defn lex-skip-whitespace [state]
  (loop [s state]
    (let [c (lex-peek s)]
      (if (not (= c -1))
        (if (whitespace? c) (recur (lex-advance s)) s)
        s))))

(defn lex-skip-comment [state]
  (loop [s state]
    (let [c (lex-peek s)]
      (if (not (= c -1))
        (if (not (= c 10)) (recur (lex-advance s)) s)
        s))))

;; ===========================================================================
;; Token parsers — emit tok+span; return new byte offset
;; ===========================================================================

(defn emit-tok [tokens spans tok off]
  (do (push tokens tok)
      (push spans off)))

(defn digit-or-sign? [c acc]
  (if (digit? c) true
    (if (= c 45) (= (count acc) 0) false)))

(defn lex-read-string-at [state tokens spans off]
  (let [text (get state 0) pos (get state 1) len (get state 2)]
    (loop [i (+ pos 1) acc ""]
      (if (>= i len)
        (do (emit-tok tokens spans (TString acc) off) i)
        (let [c (str-get text i)]
          (if (= c 34)
            (do (emit-tok tokens spans (TString acc) off) (+ i 1))
            (if (= c 92)
              (if (>= (+ i 1) len)
                (do (emit-tok tokens spans (TString acc) off) i)
                (let [next (str-get text (+ i 1))
                      esc (if (= next 110) "\n"
                            (if (= next 116) "\t"
                              (if (= next 114) "\r"
                                (if (= next 92) "\\"
                                  (if (= next 34) "\""
                                    (str-slice text (+ i 1) (+ i 2)))))))]
                  (recur (+ i 2) (str-concat acc esc))))
              (recur (+ i 1) (str-concat acc (str-slice text i (+ i 1)))))))))))

(defn lex-read-number-at [state tokens spans off]
  (let [text (get state 0) pos (get state 1) len (get state 2)]
    (loop [i pos acc ""]
      (if (>= i len)
        (do (emit-tok tokens spans (TNumber (parse-int acc)) off) i)
        (let [c (str-get text i)]
          (if (digit-or-sign? c acc)
            (recur (+ i 1) (str-concat acc (str-slice text i (+ i 1))))
            (do (emit-tok tokens spans (TNumber (parse-int acc)) off) i)))))))

(defn lex-read-symbol-at [state tokens spans off]
  (let [text (get state 0) pos (get state 1) len (get state 2)]
    (loop [i pos acc ""]
      (if (>= i len)
        (do (emit-tok tokens spans (TSymbol acc) off) i)
        (let [c (str-get text i)]
          (if (sym-char? c)
            (recur (+ i 1) (str-concat acc (str-slice text i (+ i 1))))
            (do (emit-tok tokens spans (TSymbol acc) off) i)))))))

(defn lex-read-keyword-at [state tokens spans off]
  (let [text (get state 0) pos (get state 1) len (get state 2)]
    (loop [i (+ pos 1) acc ""]
      (if (>= i len)
        (do (emit-tok tokens spans (TKeyword acc) off) i)
        (let [c (str-get text i)]
          (if (sym-char? c)
            (recur (+ i 1) (str-concat acc (str-slice text i (+ i 1))))
            (do (emit-tok tokens spans (TKeyword acc) off) i)))))))

(defn lex-is-neg-number? [state]
  (let [c (lex-peek state)]
    (if (= c 45)
      (let [next-c (lex-peek (lex-advance state))]
        (digit? next-c))
      false)))

;; ===========================================================================
;; Main tokenize — returns [tokens spans] (spans[i] = start byte offset)
;; ===========================================================================

(defn tokenize [text]
  (let [len (count text)
        tokens (vector)
        spans (vector)]
    (loop [state [text 0 len]]
      (let [state (lex-skip-whitespace state)
            c (lex-peek state)
            off (get state 1)]
        (cond
          (= c -1)
            (do (emit-tok tokens spans (TEof) off)
                (let [out (vector)]
                  (do (push out tokens) (push out spans) out)))
          (= c 59)
            (recur (lex-skip-comment (lex-advance state)))
          (= c 40)
            (do (emit-tok tokens spans (TLParen) off)
                (recur (lex-advance state)))
          (= c 41)
            (do (emit-tok tokens spans (TRParen) off)
                (recur (lex-advance state)))
          (= c 91)
            (do (emit-tok tokens spans (TLBrack) off)
                (recur (lex-advance state)))
          (= c 93)
            (do (emit-tok tokens spans (TRBrack) off)
                (recur (lex-advance state)))
          (= c 34)
            (let [npos (lex-read-string-at state tokens spans off)]
              (recur [text npos len]))
          (= c 39)
            (do (emit-tok tokens spans (TQuote) off)
                (recur (lex-advance state)))
          (= c 96)
            (do (emit-tok tokens spans (TSyntaxQuote) off)
                (recur (lex-advance state)))
          (= c 94)
            (do (emit-tok tokens spans (TMeta) off)
                (recur (lex-advance state)))
          (= c 64)
            (do (emit-tok tokens spans (TDeref) off)
                (recur (lex-advance state)))
          (= c 126)
            (let [next (lex-peek (lex-advance state))]
              (if (= next 64)
                (do (emit-tok tokens spans (TSplicing) off)
                    (recur (lex-advance (lex-advance state))))
                (do (emit-tok tokens spans (TUnquote) off)
                    (recur (lex-advance state)))))
          (= c 58)
            (let [npos (lex-read-keyword-at state tokens spans off)]
              (recur [text npos len]))
          (lex-is-neg-number? state)
            (let [npos (lex-read-number-at state tokens spans off)]
              (recur [text npos len]))
          (digit? c)
            (let [npos (lex-read-number-at state tokens spans off)]
              (recur [text npos len]))
          (sym-char? c)
            (let [npos (lex-read-symbol-at state tokens spans off)]
              (recur [text npos len]))
          :else (recur (lex-advance state)))))))

;; ===========================================================================
;; PARSER
;; ===========================================================================
;;
;; Each parse-* returns [ast_value pos] where ast_value is a tagged value.
;; reader-macro tags: 22=quote 23=synquote 24=unquote 25=splice 26=meta 27=deref

;; Helper: create tagged value [tag value] or [tag value off]
(defn t1 [tag val]
  (let [v (vector)] (do (push v tag) (do (push v val) v))))

(defn t1-off [tag val off]
  (let [v (vector)]
    (do (push v tag) (push v val) (push v off) v)))

;; Helper: create tagged value without value [tag]
(defn t0 [tag]
  (let [v (vector)] (do (push v tag) v)))

(defn t0-off [tag off]
  (let [v (vector)]
    (do (push v tag) (push v 0) (push v off) v)))

;; Special form detection by exact name.
;; NOTE: do NOT use first_char*100+len alone — collisions (mk-if/mk-do vs match).
(defn name-eq? [a b]
  (if (!= (count a) (count b)) false
    (= (str-starts-with? a b) 1)))

(defn special-tag [name]
  (if (name-eq? name "defn") 10
    (if (name-eq? name "let") 11
      (if (name-eq? name "if") 12
        (if (name-eq? name "do") 13
          (if (name-eq? name "loop") 14
            (if (name-eq? name "recur") 15
              (if (name-eq? name "fn") 16
                (if (name-eq? name "match") 17
                  (if (name-eq? name "defstruct") 18
                    (if (name-eq? name "deftype") 19
                      (if (name-eq? name "extern") 20
                        (if (name-eq? name "defmacro") 21
                          (if (name-eq? name "quote") 22
                            1))))))))))))))

(defn special? [tag] (>= tag 10))

;; --- Token / span peeking ---
;; ctx = [tokens spans text path]

(defn ctx-tokens [ctx] (get ctx 0))
(defn ctx-spans [ctx] (get ctx 1))
(defn ctx-text [ctx] (get ctx 2))
(defn ctx-path [ctx] (get ctx 3))

(defn peek-t [ctx pos]
  (let [tokens (ctx-tokens ctx)]
    (if (>= pos (count tokens)) (TEof) (get tokens pos))))

(defn span-at [ctx pos]
  (let [spans (ctx-spans ctx)]
    (if (>= pos (count spans))
      (if (> (count spans) 0) (get spans (- (count spans) 1)) 0)
      (get spans pos))))

(defn perr [ctx pos msg]
  (parse-err (ctx-text ctx) (ctx-path ctx) (span-at ctx pos) msg))

;; --- parse-expr: main dispatch ---
;; Atoms carry optional byte offset as 3rd element: [tag val off].
;; Returns [ast new-pos] or 0 on error. ctx threaded for spans.
(defn parse-expr [ctx pos]
  (let [t (peek-t ctx pos)
        off (span-at ctx pos)]
    (match t
      (TLParen)       (parse-list ctx (+ pos 1) off)
      (TLBrack)       (parse-vector ctx (+ pos 1) off)
      (TQuote)        (parse-macro ctx (+ pos 1) 22)
      (TSyntaxQuote)  (parse-macro ctx (+ pos 1) 23)
      (TUnquote)      (parse-macro ctx (+ pos 1) 24)
      (TSplicing)     (parse-macro ctx (+ pos 1) 25)
      (TMeta)         (parse-macro ctx (+ pos 1) 26)
      (TDeref)        (parse-macro ctx (+ pos 1) 27)
      (TNumber v)     [(t1-off 0 v off) (+ pos 1)]
      (TFloat v)      [(t1-off 0 v off) (+ pos 1)]
      (TString v)     [(t1-off 2 v off) (+ pos 1)]
      (TSymbol v)     [(t1-off 1 v off) (+ pos 1)]
      (TKeyword v)    [(t1-off 3 v off) (+ pos 1)]
      (TBool v)       [(t1-off 5 v off) (+ pos 1)]
      (TNilType)      [(t1-off 4 0 off) (+ pos 1)]
      (TRParen)       [(t1-off 99 0 off) (+ pos 1)]
      (TRBrack)       [(t1-off 99 0 off) (+ pos 1)]
      (TEof)          [(t1-off 99 0 off) (+ pos 1)])))

;; --- parse-list: collect items, detect special forms ---
;; open-off = byte offset of '(' for unclosed diagnostics.
(defn parse-list [ctx pos open-off]
  (let [result (collect-items ctx pos (vector) open-off)]
    (if (= result 0) 0
      (let [items (get result 0)
            pos (get result 1)]
        (if (> (count items) 0)
          (let [head (get items 0)]
            ;; head may be [tag val] or [tag val off]
            (if (>= (count head) 2)
              (let [tag (get head 0)]
                (if (= tag 1)
                  (let [name (get head 1)
                        stag (special-tag name)]
                    (if (special? stag)
                      (let [hoff (if (>= (count head) 3) (get head 2) -1)
                            new-head (if (< hoff 0) (t1 stag name) (t1-off stag name hoff))
                            new-items (vector)]
                        (do (push new-items new-head)
                            (loop [i 1]
                              (if (>= i (count items))
                                [new-items pos]
                                (do (push new-items (get items i))
                                    (recur (+ i 1)))))))
                      [items pos]))
                  [items pos]))
              [items pos]))
          [items pos])))))

;; Returns [items new-pos] or 0 on unclosed '('.
(defn collect-items [ctx pos items open-off]
  (loop [items items pos pos]
    (let [t (peek-t ctx pos)]
      (match t
        (TRParen) [items (+ pos 1)]
        (TEof)
          (do (parse-err (ctx-text ctx) (ctx-path ctx) open-off "unclosed list")
              0)
        _
          (let [res (parse-expr ctx pos)]
            (if (= res 0)
              0
              (let [expr (get res 0)
                    np (get res 1)]
                (do (push items expr)
                    (recur items np)))))))))

;; --- parse-vector ---
;; open-off = byte offset of '['.
(defn parse-vector [ctx pos open-off]
  (loop [items (vector) pos pos]
    (let [t (peek-t ctx pos)]
      (match t
        (TRBrack)
          (let [wrapped (vector)]
            (do (push wrapped (t0 28))
                (loop [i 0]
                  (if (>= i (count items))
                    0
                    (do (push wrapped (get items i))
                        (recur (+ i 1)))))
                [wrapped (+ pos 1)]))
        (TEof)
          (do (parse-err (ctx-text ctx) (ctx-path ctx) open-off "unclosed vector")
              0)
        _
          (let [res (parse-expr ctx pos)]
            (if (= res 0)
              0
              (let [expr (get res 0)
                    np (get res 1)]
                (do (push items expr)
                    (recur items np)))))))))

;; --- parse-macro: ' ` ~ ~@ ^ @ ---
(defn parse-macro [ctx pos tag]
  (let [res (parse-expr ctx pos)]
    (if (= res 0)
      0
      (let [expr (get res 0)
            np (get res 1)]
        [(t1 tag expr) np]))))

;; --- parse-all: all top-level expressions; 0 on parse error ---
(defn parse-all [ctx]
  (loop [exprs (vector) pos 0]
    (let [t (peek-t ctx pos)]
      (match t
        (TEof) exprs
        (TRParen)
          (do (perr ctx pos "unexpected ')'") 0)
        (TRBrack)
          (do (perr ctx pos "unexpected ']'") 0)
        _
          (let [res (parse-expr ctx pos)]
            (if (= res 0)
              0
              (let [expr (get res 0)
                    np (get res 1)
                    tag0 (if (> (count expr) 0) (get expr 0) -1)]
                (if (= tag0 99)
                  (do (perr ctx pos "unexpected token") 0)
                  (do (push exprs expr)
                      (recur exprs np))))))))))

;; --- Public API ---
;; bars-read / bars-read-at → AST vector or 0 on parse error.

(defn make-ctx [tokens spans text path]
  (let [v (vector)]
    (do (push v tokens)
        (push v spans)
        (push v text)
        (push v path)
        v)))

(defn bars-read-at [source path]
  (if (= source 0)
    0
    (let [pack (tokenize source)
          tokens (get pack 0)
          spans (get pack 1)]
      (parse-all (make-ctx tokens spans source path)))))

(defn bars-read [source]
  (bars-read-at source ""))

;; ===========================================================================
;; Demo
;; ===========================================================================

(defn main []
  (do (println "=== Reader ===")
      (println (bars-read "(defn main [] 42)"))
      (println (bars-read "(+ 1 2)"))
      (println (bars-read "[1 2 3]"))
      (println (bars-read ":hello"))
      (println (bars-read "'sym"))
      (println (bars-read "\"hi\""))
      0))
