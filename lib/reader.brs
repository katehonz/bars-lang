;; Bars Lexer — превръща низ във вектор от tokens
;; Това е първата стъпка към self-hosting.

(deftype Token
  [TNumber i64]
  [TFloat f64]
  [TString String]
  [TSymbol String]
  [TKeyword String]
  [TLParen]
  [TRParen]
  [TLBrack]
  [TRBrack]
  [TQuote]
  [TSyntaxQuote]
  [TUnquote]
  [TSplicing]
  [TEof])

;; ---------------------------------------------------------------------------
;; Helpers
;; ---------------------------------------------------------------------------

(defn whitespace? [c]
  (if (= c 32) true
    (if (= c 9) true
      (if (= c 10) true
        (= c 13)))))  ; space tab newline carriage-return

(defn digit? [c]
  (if (>= c 48) (<= c 57) false))

(defn alpha? [c]
  (if (>= c 65) (if (<= c 90) true false)
    (if (>= c 97) (<= c 122) false)))

(defn sym-char? [c]
  (if (alpha? c) true
    (if (digit? c) true
      (if (= c 43) true
        (if (= c 45) true
          (if (= c 42) true
            (if (= c 47) true
              (if (= c 37) true
                (if (= c 61) true
                  (if (= c 60) true
                    (if (= c 62) true
                      (if (= c 33) true
                        (if (= c 63) true
                          (= c 95)))))))))))))) ; _

(defn parse-int [s]
  (let [len (count s)]
    (loop [i 0
           acc 0
           neg 1]
      (if (>= i len)
        (* acc neg)
        (let [c (str-get s i)]
          (if (= c 45)  ; -
            (recur (+ i 1) acc -1)
            (if (digit? c)
              (recur (+ i 1) (+ (* acc 10) (- c 48)) neg)
              (* acc neg))))))))

;; ---------------------------------------------------------------------------
;; Lexer state: [text pos len]
;; ---------------------------------------------------------------------------

(defn peek [state]
  (let [text (get state 0)
        pos  (get state 1)
        len  (get state 2)]
    (if (>= pos len)
      -1
      (str-get text pos))))

(defn advance [state]
  (let [text (get state 0)
        pos  (get state 1)
        len  (get state 2)]
    [text (+ pos 1) len]))

(defn skip-whitespace [state]
  (loop [s state]
    (let [c (peek s)]
      (if (not (= c -1))
        (if (whitespace? c)
          (recur (advance s))
          s)
        s))))

(defn skip-comment [state]
  (loop [s state]
    (let [c (peek s)]
      (if (not (= c -1))
        (if (not (= c 10))
          (recur (advance s))
          s)
        s))))

;; ---------------------------------------------------------------------------
;; Token parsers
;; ---------------------------------------------------------------------------

(defn read-string [state tokens]
  (let [text (get state 0)
        pos  (get state 1)
        len  (get state 2)]
    (loop [i (+ pos 1)
           acc ""]
      (if (>= i len)
        (do (push tokens (TString "")) i)  ; unterminated string
        (let [c (str-get text i)]
          (if (= c 34)  ; "
            (do (push tokens (TString acc)) (+ i 1))
            (if (= c 92)  ; backslash
              (if (>= (+ i 1) len)
                (do (push tokens (TString "")) i)
                (let [next (str-get text (+ i 1))]
                  (recur (+ i 2)
                         (str-concat acc
                                     (cond
                                       (= next 110) "\n"   ; \n
                                       (= next 116) "\t"   ; \t
                                       (= next 114) "\r"   ; \r
                                       (= next 92)  "\\"   ; \\
                                       (= next 34)  "\""   ; \"
                                       :else        (str-slice text (+ i 1) (+ i 2)))))))
              (recur (+ i 1) (str-concat acc (str-slice text i (+ i 1)))))))))))

(defn read-number [state tokens]
  (let [text (get state 0)
        pos  (get state 1)
        len  (get state 2)]
    (loop [i pos
           acc ""]
      (if (>= i len)
        (do (push tokens (TNumber (parse-int acc))) i)
        (let [c (str-get text i)]
          (if (if (digit? c) true (= c 45))  ; digit or -
            (recur (+ i 1) (str-concat acc (str-slice text i (+ i 1))))
            (do (push tokens (TNumber (parse-int acc))) i)))))))

(defn read-symbol [state tokens]
  (let [text (get state 0)
        pos  (get state 1)
        len  (get state 2)]
    (loop [i pos
           acc ""]
      (if (>= i len)
        (do (push tokens (TSymbol acc)) i)
        (let [c (str-get text i)]
          (if (sym-char? c)
            (recur (+ i 1) (str-concat acc (str-slice text i (+ i 1))))
            (do (push tokens (TSymbol acc)) i)))))))

(defn read-keyword [state tokens]
  (let [text (get state 0)
        pos  (get state 1)
        len  (get state 2)]
    (loop [i (+ pos 1)
           acc ""]
      (if (>= i len)
        (do (push tokens (TKeyword acc)) i)
        (let [c (str-get text i)]
          (if (sym-char? c)
            (recur (+ i 1) (str-concat acc (str-slice text i (+ i 1))))
            (do (push tokens (TKeyword acc)) i)))))))

;; ---------------------------------------------------------------------------
;; Main tokenize
;; ---------------------------------------------------------------------------

(defn tokenize [text]
  (let [len (count text)]
    (loop [state [text 0 len]
           tokens (vector)]
      (let [state (skip-whitespace state)
            c (peek state)
            pos (get state 1)]
        (cond
          (= c -1)   (do (push tokens (TEof)) tokens)
          (= c 59)   (recur (skip-comment (advance state)) tokens)  ; ;
          (= c 40)   (recur (advance state) (do (push tokens (TLParen)) tokens))
          (= c 41)   (recur (advance state) (do (push tokens (TRParen)) tokens))
          (= c 91)   (recur (advance state) (do (push tokens (TLBrack)) tokens))
          (= c 93)   (recur (advance state) (do (push tokens (TRBrack)) tokens))
          (= c 34)   (recur [(get state 0) (read-string state tokens) (get state 2)] tokens)
          (= c 39)   (recur (advance state) (do (push tokens (TQuote)) tokens))
          (= c 96)   (recur (advance state) (do (push tokens (TSyntaxQuote)) tokens))
          (= c 126)  (let [next (peek (advance state))]
                       (if (= next 64)
                         (recur (advance (advance state)) (do (push tokens (TSplicing)) tokens))
                         (recur (advance state) (do (push tokens (TUnquote)) tokens))))
          (= c 58)   (recur [(get state 0) (read-keyword state tokens) (get state 2)] tokens)
          (if (digit? c) true (= c 45))  (recur [(get state 0) (read-number state tokens) (get state 2)] tokens)
          (sym-char? c) (recur [(get state 0) (read-symbol state tokens) (get state 2)] tokens)
          :else      (recur (advance state) tokens))))))

(defn main []
  (let [source "(defn inc [x] (+ x 1))"]
    (println (tokenize source))
    0))
