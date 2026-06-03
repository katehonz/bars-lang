# Стратегия — Как да победим

> *Не се бием на всички фронтове едновременно. Избираме бойното поле.*

---

## Разделение на библиотеките

Библиотеките се разделят на три категории според target-а:

### 1. Основни (Basic) — всички backend-ове

Библиотеки, които работят на QBE, Cranelift и LLVM:

- **Мрежа** — TCP/UDP sockets, DNS, TLS
- **Криптография** — хешове, симетрично/асиметрично криптиране
- **Структури от данни** — вектори, карти, множества, дървета
- **Формати** — JSON, TOML, CSV, MsgPack
- **Алгоритми** — сортиране, търсене, графи

Това е общият знаменател. Всеки Bars проект може да ги ползва.

### 2. Web — само Cranelift

Web програмирането е **ексклузивно за Cranelift backend**. Защо?

- Cranelift има **вграден WASM target** — компилираме директно до WebAssembly
- JIT компилацията позволява **бърз development цикъл** — както в REPL, така и в dev server
- AOT за production се прави през WASM → оптимизиран WASM

**План за web екосистемата:**

| Компонент | Описание | Аналог |
|-----------|----------|--------|
| **JWT** | JSON Web Tokens — signed/encrypted claims | `jose` (Elixir) |
| **Cloud runtime** | WWW-cloud контейнер runtime — deploy на WASM в edge | Cloudflare Workers |
| **ORM** | PostgreSQL ORM с typesafe queries | Ecto (Elixir) / Avram (Crystal) |
| **HTTP server** | Async HTTP/1.1 + HTTP/2 server | Plug (Elixir) / Kemal (Crystal) |
| **Web framework** | Full-stack MVC — routing, templates, middleware | Lucky (Crystal) / Phoenix (Elixir) |

**Защо Lucky, а не Rails или Django?**

Lucky (Crystal) за кратко изпревари Nim по популярност. Причината: **compile-time safety + ergonomics**. Бърз, type-safe, с малко магия. Това е моделът — не повтаряме грешките на Nim общността, където липсва концентрация ("няма нито малка снежна леопардска концентрация").

### 3. Системни (System) — засега замразени

Системното програмиране (kernels, drivers, embedded) **остава за по-късно**.

- Имаме човек с опит в Bosh, Visteon, BMW, SUSE Linux
- Но ресурсите са ограничени — не разпиляваме енергия преди web екосистемата да е стабилна
- Когато дойде време: QBE backend + bare-metal targets

---

## Структура на репото

```
libraries/
├── basic/          # QBE + Cranelift + LLVM
│   ├── net/
│   ├── crypto/
│   ├── json/
│   └── collections/
├── web/            # Cranelift only (WASM)
│   ├── jwt/
│   ├── cloud/
│   ├── orm/
│   ├── http/
│   └── framework/
└── system/         # QBE + LLVM (бъдеще)
    ├── kernel/
    └── embedded/

apps/               # Примерни апликации
├── web/
├── cli/
└── system/
```

---

## Защо тази стратегия работи

1. **Базова общост** — всеки може да ползва `basic` библиотеките, независимо от backend
2. **Web фокус** — там е пазарът, там са парите, там е лесно да се привлекат early adopters
3. **WASM предимство** — Cranelift ни дава безплатен cloud/edge deployment
4. **Не повтаряме Nim** — те разпиляха общността между 100 hobby проекта. Ние концентрираме в web
5. **Snow leopard подход** — бърз, независим, опасен. Не сме елен в стадо.

---

*Bars — the Snow Leopard. Fast, independent, dangerous.*
