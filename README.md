# 🐆 Bars

> **Bars** (барс) — дивата котка от Русия. Бърз, независим, опасен.

Системен език за програмиране със синтаксис на **Clojure**, ownership като **Rust** (по-лек), и компилация до нативен код през **QBE** / **Cranelift** / **LLVM**.

```clojure
;; examples/hello.brs
(defn main []
  (println "Здравей, свят!"))
```

```bash
$ bars build examples/hello.brs
$ bars run examples/hello.brs
Здравей, свят!
```

---

## Архитектура

```
.brs → Reader → AST → Ownership Analysis → QBE IR / Cranelift / LLVM → Нативен код
```

| Бекенд | Режим | Статус |
|--------|-------|--------|
| **QBE** | AOT debug builds | 🚧 В разработка |
| **Cranelift** | JIT / REPL | 📋 Планирано |
| **LLVM** | Release builds | 📋 Планирано |

---

## Уникални Характеристики

### Лек Ownership

За разлика от Rust, Bars използва по-лека ownership система без lifetime annotations:

```clojure
(defn process [^buf data]
  ; ^buf = borrow (като & в Rust)
  (buffer/read data 0))

(defn main []
  (def b (buffer/new 16))
  (process b)           ; borrow — OK
  (process b))          ; borrow отново — OK
```

### Хибридна Памет

| Тип | Управление | Пример |
|-----|-----------|--------|
| Stack | Автоматично | `(let [x 42] ...)` |
| Ownership | Ръчно | `(def f (fs/open "x.txt"))` |
| GC | Автоматично | `(def m {:a [1 2 3]})` |

---

## Бърз старт

### Инсталация

```bash
git clone <repo>
cd bars
cargo build --release
```

### Използване

```bash
# Прочети AST
bars read examples/hello.brs

# Компилирай до QBE IR
bars build examples/hello.brs

# Компилирай и изпълни
bars run examples/math.brs

# REPL
bars repl
```

---

## Примери

### Аритметика и рекурсия

```clojure
;; examples/math.brs
(defn factorial [n]
  (if (<= n 1)
    1
    (* n (factorial (- n 1)))))

(defn main []
  (println (factorial 5)))
```

### Ownership

```clojure
;; examples/ownership.brs
(defn use [^mut buf data]
  (buffer/fill data 0))

(defn main []
  (def b (buffer/new 16))
  (use b)
  (buffer/free b))
```

---

## Технологичен Стек

| Компонент | Технология |
|-----------|-----------|
| Език | Rust |
| QBE API | `qbe-rs` |
| CLI | `clap` |
| Тестове | `cargo test` |

---

## Статус на Разработка

Виж [ROADMAP.md](ROADMAP.md) за пълен план.

| Фаза | Статус |
|------|--------|
| Reader (Lexer + Parser) | ✅ Работи |
| AST → QBE IR | ✅ Базов |
| Функции и рекурсия | ✅ Работи |
| Ownership анализатор | 📋 Планирано |
| Runtime + GC | 📋 Планирано |
| REPL + Cranelift JIT | 📋 Планирано |
| Макроси | 📋 Планирано |
| LLVM backend | 📋 Планирано |

---

## Лиценз

MIT или Apache-2.0
