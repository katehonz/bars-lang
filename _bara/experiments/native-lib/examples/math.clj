(ns math)

(defn square [x]
  (* x x))

(defn cube [x]
  (* x x x))

(defn add [a b]
  (+ a b))

(defn greet [name]
  (str "Hello, " name "!"))

(defn factorial [n]
  (if (= n 0)
    1
    (* n (factorial (- n 1)))))
