# Препоръки към cljnim компилатора

> Събрани по време на разработката на BRing — Ring-подобна уеб библиотека за Bara Lang.
>
> **Последно обновяване:** 12 май 2026

---

## 1. Поддръжка на docstrings в `defn` ✅ Имплементирано

**Проблем (преди):**
```clojure
(defn greet "Says hello" [name]
  (str "Hello " name))
```
Гърмеше с:
```
Error: unhandled exception: defn params must be a vector [EmitterError]
```

**Решение:** В `emitSpecialForm` за `defn` сега се проверява дали `items[2]` е стринг (docstring) и ако да — се пропуска и се взема `items[3]` като параметри.

**Пример (сега работи):**
```clojure
(defn greet "Says hello" [name]
  (str "Hello " name))
```

---

## 2. Поддръжка на multi-arity `defn` ✅ Имплементирано

**Проблем (преди):**
```clojure
(defn greet
  ([name] (greet name "Hello"))
  ([name greeting] (str greeting " " name)))
```
Гърмеше с:
```
Error: unhandled exception: defn params must be a vector [EmitterError]
```

**Решение:** Multi-arity синтаксисът сега се разпознава. Генерира се dispatch по `args.len` в Nim.

**Пример (сега работи):**
```clojure
(defn greet
  ([name] (greet name "Hello"))
  ([name greeting] (str greeting " " name)))

(greet "Alice")           ;; => "Hello Alice"
(greet "Alice" "Hi")      ;; => "Hi Alice"
```

---

## 3. `(:key map)` синтаксис (keyword като функция) ✅ Имплементирано

**Проблем (преди):**
```clojure
(:request-method req)   ; Clojure стандарт
```
Генерираше `cljApply(...)` вместо `cljGet(...)` и гърмеше с:
```
apply requires a function
```

**Решение:** В `emitSpecialForm`, когато `items[0].kind == ckKeyword`, сега се генерира `cljGet(args[0], keyword)` вместо `cljApply`.

**Пример (сега работи):**
```clojure
(def req {:request-method :get :uri "/hello"})
(:request-method req)     ;; => :get
(:uri req)                ;; => "/hello"
```

---

## 4. `&` rest параметри в `defn` ✅ Имплементирано

**Проблем (преди):**
```clojure
(defn greet [name & [greeting]]
  ...)
```
Гърмеше с:
```
Error: unhandled exception: defn params must be symbols [EmitterError]
```

**Решение:** `&` сега се разпознава като специален символ в параметрите. Генерира се Nim код, който приема `seq[CljVal]` и разпределя аргументите.

**Пример (сега работи):**
```clojure
(defn sum-all [x & rest]
  (+ x (reduce + rest)))

(sum-all 1 2 3 4)         ;; => 10
```

---

## 5. Nim interop — mangle на имената ✅ Имплементирано

**Проблем (преди):**
```clojure
(nim/bring_http/run-server handler port)
```
Генерираше:
```nim
run-server(handler, port)
```
А `-` не е валиден символ в Nim идентификатори.

**Решение:** В `emitSpecialForm` за `nim/` interop се прилага `sanitizeNimIdent()`, която заменя `-` с `_` и премахва други невалидни символи за Nim.

**Пример (сега работи):**
```clojure
(nim/bring_http/run_server handler port)   ;; run_server в Nim
(nim/strutils/to_upper "hello")            ;; to_upper в Nim
```

---

## 6. `getLibPath()` — търсене на `lib/` директория ✅ Имплементирано

**Проблем (преди):** `getLibPath()` винаги връщаше `appDir/lib`, което правеше невъзможно проекти от други директории да използват свои `lib/` пътища.

**Решение:**
- Добавен `--lib-path <dir>` глобален CLI флаг.
- `getLibPath()` сега проверява в следния ред:
  1. CLI `--lib-path` override
  2. `CLJNIM_LIB_PATH` environment variable
  3. Текуща директория `lib/`
  4. Приложение `lib/`

**Пример:**
```bash
# Със собствена lib директория
./cljnim --lib-path ./my_project/lib run app.clj

# С environment variable
export CLJNIM_LIB_PATH=./my_project/lib
./cljnim run app.clj
```

---

## 7. Поддръжка на `:paths` в `deps.edn` ✅ Имплементирано

**Проблем (преди):** `deps.nim` парсираше само `:deps` от `deps.edn`, но не и `:paths`.

**Решение:** Добавен е парсинг на `:paths` от `deps.edn` и се включват в `searchPaths` при компилация.

**Пример (сега работи):**
```clojure
;; deps.edn
{:paths ["src" "lib"]
 :deps {org.clojure/core.async {:mvn/version "1.6.681"}}}
```

---

## 8. `loop` с `if/else` — проблеми с `discard` ✅ Имплементирано

**Проблем (преди):**
```clojure
(loop [pairs (seq headers)]
  (if (empty? pairs)
    nil
    (let [[k v] (first pairs)]
      (if (= k name)
        v
        (recur (rest pairs))))))
```
Гърмеше с:
```
expression 'cljNil()' is of type 'CljVal' and has to be used (or discarded)
```

**Решение:**
- Добавен е `loopResult` променлива, която събира резултата.
- Подобрено е генерирането на `loop` така, че всички клонове на `if` вътре да връщат стойност правилно.
- Добавена е `needsValue` логика — `loop` се wrap-ва в IIFE `(proc(): CljVal = ...)()` когато е в expression context (напр. като аргумент на функция, в `let` RHS, или като последна стойност в програма).

**Пример (сега работи):**
```clojure
(defn find-header [headers name]
  (loop [pairs (seq headers)]
    (if (empty? pairs)
      nil
      (let [[k v] (first pairs)]
        (if (= k name)
          v
          (recur (rest pairs)))))))

(find-header [[:content-type "text/html"] [:accept "*/*"]] :accept)
;; => "*/*"
```

---

## 9. Конфликти на имена между Clojure и Nim ✅ Имплементирано

**Проблем:** Nim е case-insensitive за първата буква и игнорира `_`. Значи:
- `parseQueryString` ≡ `parse_query_string` ≡ `parsequerystring`

Ако cljnim генерира `proc parse_query_string` и съществува `proc parseQueryString` в импортиран модул, Nim ги третира като едно и също име.

**Решение:** Добавен е `clj_` prefix към всички генерирани Nim процедури от Clojure код:
```nim
proc clj_parse_query_string(...)  ; вместо parse_query_string
```
За `nim/` interop се използва `sanitizeNimIdent()` без prefix, така че native Nim имената да не се чупят.

---

## 10. `when isMainModule` в генерирания код ✅ Имплементирано

**Проблем (преди):** `when isMainModule` в края на генерирания Nim файл означаваше, че ако файлът се импортира от друг Nim модул, `main` кодът няма да се изпълни.

**Решение:** `emitProgramLib` сега skip-ва `when isMainModule` guard, което позволява генерирането на "библиотечни" Clojure файлове.

---

## 11. Поддръжка на `try`/`catch`/`finally` ✅ Имплементирано

**Решение:**
- `finally` блок сега правилно discard-ва expression резултатите.
- `catch` handler използва оригиналното име за scope tracking.

**Пример (сега работи):**
```clojure
(try
  (risky-operation)
  (catch Exception e
    (println "Error:" (:message e)))
  (finally
    (cleanup)))
```

---

## 12. First-class функции (defn като стойности) ✅ Имплементирано

**Проблем (преди):** User-defined `defn` функции не можеха да се подават като стойности на други функции (напр. `map`, `filter`, `apply`).

**Решение:**
- Проследяват се арностите на функциите в `definedFnArities` таблица.
- Когато символ на `defn` се използва като стойност, се генерира `cljFn` wrapper:
  - Multi-arity / rest: `cljFn(procName)` (вече е `seq[CljVal]`)
  - Single-arity: `cljFn(proc(args): procName(args[0], ...))`
- Директни извиквания остават непроменени (fast path).

**Пример (сега работи):**
```clojure
(defn square [x] (* x x))

(map square [1 2 3 4])    ;; => [1 4 9 16]
(filter odd? [1 2 3 4])   ;; => [1 3]
(apply + [1 2 3])         ;; => 6
```

---

## Обобщена таблица

| # | Проблем | Статус | Commit |
|---|---------|--------|--------|
| 1 | Docstrings в `defn` | ✅ Готово | e36bf4e |
| 2 | Multi-arity `defn` | ✅ Готово | e36bf4e |
| 3 | `(:key map)` синтаксис | ✅ Готово | e36bf4e |
| 4 | `&` rest параметри | ✅ Готово | e36bf4e |
| 5 | Nim interop mangle | ✅ Готово | e36bf4e, 3aaf3c0 |
| 6 | `getLibPath()` / `--lib-path` | ✅ Готово | e36bf4e, 9a8519d |
| 7 | `:paths` в deps.edn | ✅ Готово | e36bf4e |
| 8 | `loop` + `if/else` discard | ✅ Готово | e36bf4e, a1a65f1 |
| 9 | Конфликти на имена (`clj_` prefix) | ✅ Готово | fb8928e, 3aaf3c0 |
| 10 | `when isMainModule` | ✅ Готово | e36bf4e |
| 11 | `try`/`catch`/`finally` | ✅ Готово | fb8928e |
| 12 | First-class `defn` функции | ✅ Готово | aac39a0 |

---

*Документът е съставен по време на разработката на [BRing](https://github.com/) — нативна Clojure уеб библиотека за cljnim.*
*Последно обновяване: 12 май 2026*
