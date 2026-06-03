(deftype Shape [Circle i64] [Rect i64 i64])

(defn area [s]
  (match s
    (Circle r) (* r r)
    (Rect w h) (* w h)))

(println (area (Circle 5)))
(println (area (Rect 3 4)))
