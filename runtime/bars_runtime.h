#ifndef BARS_RUNTIME_H
#define BARS_RUNTIME_H

#include <stddef.h>
#include <stdint.h>

/* Runtime object magic numbers for dynamic type detection */
#define BARS_MAGIC_STRING  0xB4157E11u  /* BARSTRI */
#define BARS_MAGIC_VECTOR  0xB4157E22u  /* BARVEC  */
#define BARS_MAGIC_MAP     0xB4157E33u  /* BARMAP  */

/* Bars Value Tag */
typedef enum {
    BARS_NIL = 0,
    BARS_I64,
    BARS_F64,
    BARS_BOOL,
    BARS_STRING,
    BARS_VECTOR,
    BARS_MAP,
    BARS_KEYWORD,
} bars_tag_t;

/* Forward declarations */
typedef struct bars_string bars_string_t;
typedef struct bars_vector bars_vector_t;
typedef struct bars_map bars_map_t;

/* Boxed value */
typedef struct {
    bars_tag_t tag;
    union {
        int64_t i64;
        double f64;
        bars_string_t* string;
        bars_vector_t* vector;
        bars_map_t* map;
    } data;
} bars_value_t;

/* String: pointer + length (managed by GC) */
struct bars_string {
    uint32_t magic;
    char* data;
    size_t len;
};

/* Vector: dynamic array (managed by GC) */
struct bars_vector {
    uint32_t magic;
    bars_value_t* data;
    size_t len;
    size_t cap;
};

/* Map entry */
typedef struct bars_map_entry {
    bars_value_t key;
    bars_value_t val;
    struct bars_map_entry* next;
} bars_map_entry_t;

/* Hash map (managed by GC) */
struct bars_map {
    uint32_t magic;
    bars_map_entry_t** buckets;
    size_t size;
    size_t cap;
};

/* GC initialization */
void bars_gc_init(void);

/* Allocation (uses Boehm GC) */
void* bars_alloc(size_t size);

/* Print functions */
void bars_print_i64(int64_t n);
void bars_print_string(const bars_string_t* s);
void bars_print_newline(void);
void bars_print_value(const bars_value_t* v);
void bars_print_vector_i64(const bars_vector_t* vec);
void bars_print_map_i64(const bars_map_t* map);
void bars_print_set_i64(const bars_map_t* set);
void bars_print_any_i64(int64_t val);

/* String operations */
bars_string_t* bars_string_new(const char* cstr);
bars_string_t* bars_string_from_i64(int64_t n);
int64_t bars_string_len(const bars_string_t* s);

/* Vector operations (i64-only for now) */
bars_vector_t* bars_vector_new(void);
void bars_vector_push(bars_vector_t* vec, bars_value_t val);
bars_value_t bars_vector_get(const bars_vector_t* vec, size_t idx);
int64_t bars_vector_len(const bars_vector_t* vec);

/* Simple i64 vector helpers */
bars_vector_t* bars_vector_new_i64(void);
void bars_vector_push_i64(bars_vector_t* vec, int64_t val);
int64_t bars_vector_get_i64(bars_vector_t* vec, int64_t idx);
int64_t bars_vector_count_i64(bars_vector_t* vec);

/* Map operations */
bars_map_t* bars_map_new(void);
void bars_map_set(bars_map_t* map, bars_value_t key, bars_value_t val);
bars_value_t bars_map_get(const bars_map_t* map, bars_value_t key);
int64_t bars_map_len(const bars_map_t* map);

/* Simple i64 map helpers */
bars_map_t* bars_map_new_i64(void);
void bars_map_set_i64(bars_map_t* map, int64_t key, int64_t val);
int64_t bars_map_get_i64(bars_map_t* map, int64_t key);
int64_t bars_map_count_i64(bars_map_t* map);

/* Simple i64 set helpers (backed by map) */
bars_map_t* bars_set_new_i64(void);
void bars_set_add_i64(bars_map_t* set, int64_t val);
int64_t bars_set_contains_i64(bars_map_t* set, int64_t val);
int64_t bars_set_count_i64(bars_map_t* set);

/* Utility */
uint64_t bars_hash_value(bars_value_t val);
int bars_value_eq(bars_value_t a, bars_value_t b);

/* Math (libm wrappers, return i64) */
int64_t bars_sqrt_i64(int64_t n);
int64_t bars_pow_i64(int64_t base, int64_t exp);
int64_t bars_abs_i64(int64_t n);

/* String operations */
int64_t bars_string_length(bars_string_t* s);
bars_string_t* bars_string_concat(bars_string_t* a, bars_string_t* b);
bars_string_t* bars_string_trim(bars_string_t* s);
bars_string_t* bars_string_substring(bars_string_t* s, int64_t start, int64_t len);
bars_vector_t* bars_string_split(bars_string_t* s, bars_string_t* delim);
bars_string_t* bars_string_join(bars_vector_t* vec, bars_string_t* delim);

/* I/O */
bars_string_t* bars_slurp(const char* path);
int64_t bars_spit(const char* path, bars_string_t* content);

#endif
