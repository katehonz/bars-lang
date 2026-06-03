(deftype Color [Red] [Green] [Blue])

(defn color-name [c]
  (match c
    [Red] "red"
    [Green] "green"
    [Blue] "blue"))
