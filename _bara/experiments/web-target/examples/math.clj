(ns math)

(defn square [x]
  (* x x))

(defn factorial [n]
  (if (= n 0)
    1
    (* n (factorial (- n 1)))))

(defn greet [name]
  (str "Hello, " name "!"))
