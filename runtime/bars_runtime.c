#include "bars_runtime.h"
#include <gc/gc.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void bars_gc_init(void) {
    /* Boehm GC initializes automatically, but we can force it */
}

void* bars_alloc(size_t size) {
    return GC_malloc(size);
}

/* --- Print --- */

void bars_print_i64(int64_t n) {
    printf("%ld", (long)n);
}

void bars_print_string(const bars_string_t* s) {
    if (s && s->data) {
        fwrite(s->data, 1, s->len, stdout);
    }
}

void bars_print_newline(void) {
    putchar('\n');
}

void bars_print_value(const bars_value_t* v) {
    if (!v) {
        printf("nil");
        return;
    }
    switch (v->tag) {
        case BARS_NIL: printf("nil"); break;
        case BARS_I64: printf("%ld", (long)v->data.i64); break;
        case BARS_F64: printf("%f", v->data.f64); break;
        case BARS_BOOL: printf("%s", v->data.i64 ? "true" : "false"); break;
        case BARS_STRING: bars_print_string(v->data.string); break;
        case BARS_VECTOR: printf("[vector]"); break;
        case BARS_MAP: printf("{map}"); break;
        case BARS_KEYWORD: printf(":%s", v->data.string->data); break;
    }
}

/* --- String --- */

bars_string_t* bars_string_new(const char* cstr) {
    size_t len = strlen(cstr);
    bars_string_t* s = (bars_string_t*)bars_alloc(sizeof(bars_string_t));
    s->data = (char*)bars_alloc(len + 1);
    memcpy(s->data, cstr, len);
    s->data[len] = '\0';
    s->len = len;
    return s;
}

bars_string_t* bars_string_from_i64(int64_t n) {
    char buf[32];
    snprintf(buf, sizeof(buf), "%ld", (long)n);
    return bars_string_new(buf);
}

/* --- Vector --- */

bars_vector_t* bars_vector_new(void) {
    bars_vector_t* vec = (bars_vector_t*)bars_alloc(sizeof(bars_vector_t));
    vec->cap = 8;
    vec->len = 0;
    vec->data = (bars_value_t*)bars_alloc(sizeof(bars_value_t) * vec->cap);
    return vec;
}

void bars_vector_push(bars_vector_t* vec, bars_value_t val) {
    if (vec->len >= vec->cap) {
        vec->cap *= 2;
        vec->data = (bars_value_t*)GC_realloc(vec->data, sizeof(bars_value_t) * vec->cap);
    }
    vec->data[vec->len++] = val;
}

void bars_vector_push_i64(bars_vector_t* vec, int64_t val) {
    bars_value_t v = { .tag = BARS_I64, .data = { .i64 = val } };
    bars_vector_push(vec, v);
}

int64_t bars_vector_get_i64(bars_vector_t* vec, int64_t idx) {
    if (idx < 0 || idx >= (int64_t)vec->len) return 0;
    bars_value_t v = vec->data[idx];
    if (v.tag == BARS_I64) return v.data.i64;
    return 0;
}

int64_t bars_vector_count_i64(bars_vector_t* vec) {
    return vec ? (int64_t)vec->len : 0;
}

/* Simple i64 vector helpers */

bars_vector_t* bars_vector_new_i64(void) {
    return bars_vector_new();
}

/* --- Map --- */

uint64_t bars_hash_value(bars_value_t v) {
    switch (v.tag) {
        case BARS_I64: return (uint64_t)v.data.i64;
        case BARS_BOOL: return v.data.i64 ? 1 : 0;
        case BARS_STRING: {
            uint64_t h = 14695981039346656037ULL;
            for (size_t i = 0; i < v.data.string->len; i++) {
                h ^= (unsigned char)v.data.string->data[i];
                h *= 1099511628211ULL;
            }
            return h;
        }
        default: return 0;
    }
}

int bars_value_eq(bars_value_t a, bars_value_t b) {
    if (a.tag != b.tag) return 0;
    switch (a.tag) {
        case BARS_I64: return a.data.i64 == b.data.i64;
        case BARS_BOOL: return a.data.i64 == b.data.i64;
        case BARS_STRING: {
            if (a.data.string->len != b.data.string->len) return 0;
            return memcmp(a.data.string->data, b.data.string->data, a.data.string->len) == 0;
        }
        default: return 0;
    }
}

bars_map_t* bars_map_new(void) {
    bars_map_t* map = (bars_map_t*)bars_alloc(sizeof(bars_map_t));
    map->size = 0;
    map->cap = 16;
    map->buckets = (bars_map_entry_t**)bars_alloc(sizeof(bars_map_entry_t*) * map->cap);
    memset(map->buckets, 0, sizeof(bars_map_entry_t*) * map->cap);
    return map;
}

void bars_map_set(bars_map_t* map, bars_value_t key, bars_value_t val) {
    uint64_t h = bars_hash_value(key);
    size_t idx = h & (map->cap - 1);
    bars_map_entry_t* entry = map->buckets[idx];
    while (entry) {
        if (bars_value_eq(entry->key, key)) {
            entry->val = val;
            return;
        }
        entry = entry->next;
    }
    bars_map_entry_t* new_entry = (bars_map_entry_t*)bars_alloc(sizeof(bars_map_entry_t));
    new_entry->key = key;
    new_entry->val = val;
    new_entry->next = map->buckets[idx];
    map->buckets[idx] = new_entry;
    map->size++;
}

bars_value_t bars_map_get(const bars_map_t* map, bars_value_t key) {
    uint64_t h = bars_hash_value(key);
    size_t idx = h & (map->cap - 1);
    bars_map_entry_t* entry = map->buckets[idx];
    while (entry) {
        if (bars_value_eq(entry->key, key)) {
            return entry->val;
        }
        entry = entry->next;
    }
    bars_value_t nil = { .tag = BARS_NIL };
    return nil;
}

int64_t bars_map_len(const bars_map_t* map) {
    return map ? (int64_t)map->size : 0;
}

/* --- Simple i64 map helpers --- */

bars_map_t* bars_map_new_i64(void) {
    return bars_map_new();
}

void bars_map_set_i64(bars_map_t* map, int64_t key, int64_t val) {
    bars_value_t k = { .tag = BARS_I64, .data = { .i64 = key } };
    bars_value_t v = { .tag = BARS_I64, .data = { .i64 = val } };
    bars_map_set(map, k, v);
}

int64_t bars_map_get_i64(bars_map_t* map, int64_t key) {
    bars_value_t k = { .tag = BARS_I64, .data = { .i64 = key } };
    bars_value_t v = bars_map_get(map, k);
    if (v.tag == BARS_I64) return v.data.i64;
    return 0;
}

int64_t bars_map_count_i64(bars_map_t* map) {
    return bars_map_len(map);
}

/* --- Simple i64 set helpers (backed by map with dummy values) --- */

bars_map_t* bars_set_new_i64(void) {
    return bars_map_new();
}

void bars_set_add_i64(bars_map_t* set, int64_t val) {
    bars_value_t k = { .tag = BARS_I64, .data = { .i64 = val } };
    bars_value_t v = { .tag = BARS_I64, .data = { .i64 = 1 } };
    bars_map_set(set, k, v);
}

int64_t bars_set_contains_i64(bars_map_t* set, int64_t val) {
    bars_value_t k = { .tag = BARS_I64, .data = { .i64 = val } };
    bars_value_t v = bars_map_get(set, k);
    return (v.tag == BARS_I64) ? 1 : 0;
}

int64_t bars_set_count_i64(bars_map_t* set) {
    return bars_map_len(set);
}
