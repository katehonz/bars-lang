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
;; Token parsers — mutate tokens in-place; return just position
;; ===========================================================================

(defn lex-read-string [state tokens]
  (let [text (get state 0) pos (get state 1) len (get state 2)]
    (loop [i (+ pos 1) acc ""]
      (if (>= i len)
        (do (push tokens (TString "")) i)
        (let [c (str-get text i)]
          (if (= c 34)
            (do (push tokens (TString acc)) (+ i 1))
            (if (= c 92)
              (if (>= (+ i 1) len)
                (do (push tokens (TString acc)) i)
                (let [next (str-get text (+ i 1))
                      esc (if (= next 110) "\n"
                            (if (= next 116) "\t"
                              (if (= next 114) "\r"
                                (if (= next 92) "\\"
                                  (if (= next 34) "\""
                                    (str-slice text (+ i 1) (+ i 2)))))))]
                  (recur (+ i 2) (str-concat acc esc))))
              (recur (+ i 1) (str-concat acc (str-slice text i (+ i 1)))))))))))

(defn digit-or-sign? [c acc]
  (if (digit? c) true
    (if (= c 45) (= (count acc) 0) false)))

(defn lex-read-number [state tokens]
  (let [text (get state 0) pos (get state 1) len (get state 2)]
    (loop [i pos acc ""]
      (if (>= i len)
        (do (push tokens (TNumber (parse-int acc))) i)
        (let [c (str-get text i)]
          (if (digit-or-sign? c acc)
            (recur (+ i 1) (str-concat acc (str-slice text i (+ i 1))))
            (do (push tokens (TNumber (parse-int acc))) i)))))))

(defn lex-read-symbol [state tokens]
  (let [text (get state 0) pos (get state 1) len (get state 2)]
    (loop [i pos acc ""]
      (if (>= i len)
        (do (push tokens (TSymbol acc)) i)
        (let [c (str-get text i)]
          (if (sym-char? c)
            (recur (+ i 1) (str-concat acc (str-slice text i (+ i 1))))
            (do (push tokens (TSymbol acc)) i)))))))

(defn lex-read-keyword [state tokens]
  (let [text (get state 0) pos (get state 1) len (get state 2)]
    (loop [i (+ pos 1) acc ""]
      (if (>= i len)
        (do (push tokens (TKeyword acc)) i)
        (let [c (str-get text i)]
          (if (sym-char? c)
            (recur (+ i 1) (str-concat acc (str-slice text i (+ i 1))))
            (do (push tokens (TKeyword acc)) i)))))))

(defn lex-is-neg-number? [state]
  (let [c (lex-peek state)]
    (if (= c 45)
      (let [next-c (lex-peek (lex-advance state))]
        (digit? next-c))
      false)))

;; ===========================================================================
;; Main tokenize
;; ===========================================================================

(defn tokenize [text]
  (let [len (count text)]
    (loop [state [text 0 len] tokens (vector)]
      (let [state (lex-skip-whitespace state)
            c (lex-peek state)]
        (cond
          (= c -1)               (do (push tokens (TEof)) tokens)
          (= c 59)               (recur (lex-skip-comment (lex-advance state)) tokens)
          (= c 40)               (recur (lex-advance state) (do (push tokens (TLParen)) tokens))
          (= c 41)               (recur (lex-advance state) (do (push tokens (TRParen)) tokens))
          (= c 91)               (recur (lex-advance state) (do (push tokens (TLBrack)) tokens))
          (= c 93)               (recur (lex-advance state) (do (push tokens (TRBrack)) tokens))
          (= c 34)               (recur [(get state 0) (lex-read-string state tokens) (get state 2)] tokens)
          (= c 39)               (recur (lex-advance state) (do (push tokens (TQuote)) tokens))
          (= c 96)               (recur (lex-advance state) (do (push tokens (TSyntaxQuote)) tokens))
          (= c 94)               (recur (lex-advance state) (do (push tokens (TMeta)) tokens))
          (= c 64)               (recur (lex-advance state) (do (push tokens (TDeref)) tokens))
          (= c 126)              (let [next (lex-peek (lex-advance state))]
                                   (if (= next 64)
                                     (recur (lex-advance (lex-advance state))
                                            (do (push tokens (TSplicing)) tokens))
                                     (recur (lex-advance state)
                                            (do (push tokens (TUnquote)) tokens))))
          (= c 58)               (recur [(get state 0) (lex-read-keyword state tokens) (get state 2)] tokens)
          (lex-is-neg-number? state) (recur [(get state 0) (lex-read-number state tokens) (get state 2)] tokens)
          (digit? c)              (recur [(get state 0) (lex-read-number state tokens) (get state 2)] tokens)
          (sym-char? c)           (recur [(get state 0) (lex-read-symbol state tokens) (get state 2)] tokens)
          :else                   (recur (lex-advance state) tokens))))))

;; ===========================================================================
;; PARSER
;; ===========================================================================
;;
;; Each parse-* returns [ast_value pos] where ast_value is a tagged value.
;; reader-macro tags: 22=quote 23=synquote 24=unquote 25=splice 26=meta 27=deref

;; Helper: create tagged value [tag value]
(defn t1 [tag val]
  (let [v (vector)] (do (push v tag) (do (push v val) v))))

;; Helper: create tagged value without value [tag]
(defn t0 [tag]
  (let [v (vector)] (do (push v tag) v)))

;; Special form detection: hash = first_char * 100 + length
(defn special-tag [name]
  (let [ch (str-get name 0)
        ln (count name)
        h (+ (* ch 100) ln)]
    (cond
      (= h 10004) 10     ;; d+4 = defn
      (= h 10002) 13     ;; d+2 = do
      (= h 10803) 11     ;; l+3 = let
      (= h 10804) 14     ;; l+4 = loop
      (= h 10502) 12     ;; i+2 = if
      (= h 11405) 15     ;; r+5 = recur
      (= h 10202) 16     ;; f+2 = fn
      (= h 10905) 17     ;; m+5 = match
      (= h 10009) 18     ;; d+9 = defstruct
      (= h 10007) 19     ;; d+7 = deftype
      (= h 10106) 20     ;; e+6 = extern
      (= h 10008) 21     ;; d+8 = defmacro
      (= h 11305) 22     ;; q+5 = quote
      :else 1)))

(defn special? [tag] (>= tag 10))

;; --- Token peeking ---
(defn peek-t [tokens pos]
  (if (>= pos (count tokens)) (TEof) (get tokens pos)))

;; --- parse-expr: main dispatch ---
(defn parse-expr [tokens pos]
  (let [t (peek-t tokens pos)]
    (match t
      (TLParen)       (parse-list tokens (+ pos 1))
      (TLBrack)       (parse-vector tokens (+ pos 1))
      (TQuote)        (parse-macro tokens (+ pos 1) 22)
      (TSyntaxQuote)  (parse-macro tokens (+ pos 1) 23)
      (TUnquote)      (parse-macro tokens (+ pos 1) 24)
      (TSplicing)     (parse-macro tokens (+ pos 1) 25)
      (TMeta)         (parse-macro tokens (+ pos 1) 26)
      (TDeref)        (parse-macro tokens (+ pos 1) 27)
      (TNumber v)     [(t1 0 v) (+ pos 1)]
      (TFloat v)      [(t1 0 v) (+ pos 1)]
      (TString v)     [(t1 2 v) (+ pos 1)]
      (TSymbol v)     [(t1 1 v) (+ pos 1)]
      (TKeyword v)    [(t1 3 v) (+ pos 1)]
      (TBool v)       [(t1 5 v) (+ pos 1)]
      (TNilType)      [(t0 4) (+ pos 1)]
      (TRParen)       [(t0 99) (+ pos 1)]
      (TRBrack)       [(t0 99) (+ pos 1)]
      (TEof)          [(t0 99) (+ pos 1)])))

;; --- parse-list: collect items, detect special forms ---
(defn parse-list [tokens pos]
  (let [result (collect-items tokens pos (vector))
        items (get result 0)
        pos (get result 1)]
    (if (> (count items) 0)
      (let [head (get items 0)]
        (if (= (count head) 2)
          (let [tag (get head 0)]
            (if (= tag 1)
              (let [name (get head 1)
                    stag (special-tag name)]
                (if (special? stag)
                  (let [new-head (t1 stag name)
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
      [items pos])))

(defn collect-items [tokens pos items]
  (loop [items items pos pos]
    (let [t (peek-t tokens pos)]
      (match t
        (TRParen) [items (+ pos 1)]
        (TEof)    [items pos]
        _ (let [res (parse-expr tokens pos)
                expr (get res 0)
                np (get res 1)]
            (do (push items expr) (recur items np)))))))

;; --- parse-vector ---
(defn parse-vector [tokens pos]
  (loop [items (vector) pos pos]
    (let [t (peek-t tokens pos)]
      (match t
        (TRBrack) [items (+ pos 1)]
        (TEof)    [items pos]
        _ (let [res (parse-expr tokens pos)
                expr (get res 0)
                np (get res 1)]
            (do (push items expr) (recur items np)))))))

;; --- parse-macro: ' ` ~ ~@ ^ @ ---
(defn parse-macro [tokens pos tag]
  (let [res (parse-expr tokens pos)
        expr (get res 0)
        np (get res 1)]
    [(t1 tag expr) np]))

;; --- parse-all: all top-level expressions ---
(defn parse-all [tokens]
  (loop [exprs (vector) pos 0]
    (let [t (peek-t tokens pos)]
      (match t
        (TEof) exprs
        _ (let [res (parse-expr tokens pos)
                expr (get res 0)
                np (get res 1)]
            (do (push exprs expr) (recur exprs np)))))))

;; --- Public: read ---
(defn bars-read [source]
  (let [tokens (tokenize source)]
    (parse-all tokens)))

;; ===========================================================================
;; Demo
;; ===========================================================================

(defn main []
  (println "=== Reader ===")
  (println (bars-read "(defn main [] 42)"))
  (println (bars-read "(+ 1 2)"))
  (println (bars-read "[1 2 3]"))
  (println (bars-read ":hello"))
  (println (bars-read "'sym"))
  (println (bars-read "\"hi\""))
  0)
