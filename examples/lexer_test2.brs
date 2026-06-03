(deftype Token [TSymbol String] [TLParen] [TRParen])

(defn tokenize [text]
  (let [tokens (vector)]
    (push tokens (TLParen))
    tokens))

(defn main []
  (println (tokenize "(abc)"))
  0)
