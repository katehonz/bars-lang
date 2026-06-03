(deftype Token [TSymbol String] [TLParen] [TRParen] [TEof])

(defn sym-char? [c]
  (if (>= c 97) (if (<= c 122) true false) false))

(defn tokenize [text]
  (let [len (count text)]
    (loop [pos 0
           tokens (vector)]
      (if (>= pos len)
        (do (push tokens (TEof)) tokens)
        (let [c (str-get text pos)]
          (if (= c 40)
            (recur (+ pos 1) (do (push tokens (TLParen)) tokens))
            (if (sym-char? c)
              (recur (+ pos 1) (do (push tokens (TSymbol "x")) tokens))
              (recur (+ pos 1) tokens))))))))

(defn main []
  (println (tokenize "(abc)"))
  0)
