#include "bars_runtime.h"
#include <gc/gc.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <errno.h>

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
        case BARS_VECTOR: bars_print_vector_i64(v->data.vector); break;
        case BARS_MAP: bars_print_map_i64(v->data.map); break;
        case BARS_KEYWORD: printf(":%s", v->data.string->data); break;
    }
}

void bars_print_vector_i64(const bars_vector_t* vec) {
    printf("[");
    if (vec) {
        for (size_t i = 0; i < vec->len; i++) {
            bars_value_t v = vec->data[i];
            if (v.tag == BARS_I64) {
                /* Use bars_print_any_i64 so nested vectors/strings/ADTs
                   are pretty-printed instead of showing raw addresses. */
                bars_print_any_i64(v.data.i64);
            } else if (v.tag == BARS_STRING) {
                bars_print_string(v.data.string);
            } else {
                bars_print_value(&v);
            }
            if (i + 1 < vec->len) printf(" ");
        }
    }
    printf("]");
}

void bars_print_map_i64(const bars_map_t* map) {
    printf("{");
    if (map) {
        int first = 1;
        for (size_t i = 0; i < map->cap; i++) {
            bars_map_entry_t* entry = map->buckets[i];
            while (entry) {
                if (!first) printf(", ");
                first = 0;
                bars_print_value(&entry->key);
                printf(" ");
                bars_print_value(&entry->val);
                entry = entry->next;
            }
        }
    }
    printf("}");
}

void bars_print_set_i64(const bars_map_t* set) {
    printf("#{");
    if (set) {
        int first = 1;
        for (size_t i = 0; i < set->cap; i++) {
            bars_map_entry_t* entry = set->buckets[i];
            while (entry) {
                if (!first) printf(" ");
                first = 0;
                bars_print_value(&entry->key);
                entry = entry->next;
            }
        }
    }
    printf("}");
}

void bars_print_any_i64(int64_t val) {
    if (val == 0) {
        bars_print_i64(val);
        return;
    }
    /* Small values are definitely not heap pointers.
       Boehm GC on 64-bit systems allocates in high addresses.
       Most reasonable integers fit below 256MB. */
    if (val < 0x10000000L || val < 0) {
        bars_print_i64(val);
        return;
    }
    /* Check if val looks like a valid heap pointer (reasonably aligned) */
    if ((val & 0x7) != 0) {
        bars_print_i64(val);
        return;
    }
    /* Try to read magic number */
    uint32_t* magic_ptr = (uint32_t*)(uintptr_t)val;
    uint32_t magic = *magic_ptr;
    if (magic == BARS_MAGIC_VECTOR) {
        bars_print_vector_i64((const bars_vector_t*)magic_ptr);
    } else if (magic == BARS_MAGIC_MAP) {
        bars_print_map_i64((const bars_map_t*)magic_ptr);
    } else if (magic == BARS_MAGIC_STRING) {
        bars_print_string((const bars_string_t*)magic_ptr);
    } else {
        bars_print_i64(val);
    }
}

/* --- String --- */

bars_string_t* bars_string_new(const char* cstr) {
    size_t len = strlen(cstr);
    bars_string_t* s = (bars_string_t*)bars_alloc(sizeof(bars_string_t));
    s->magic = BARS_MAGIC_STRING;
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
    vec->magic = BARS_MAGIC_VECTOR;
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
    map->magic = BARS_MAGIC_MAP;
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

/* --- Math (libm wrappers) --- */

int64_t bars_sqrt_i64(int64_t n) {
    if (n < 0) return 0;
    return (int64_t)sqrt((double)n);
}

int64_t bars_pow_i64(int64_t base, int64_t exp) {
    return (int64_t)pow((double)base, (double)exp);
}

int64_t bars_abs_i64(int64_t n) {
    return n < 0 ? -n : n;
}

/* --- String operations --- */

int64_t bars_string_length(bars_string_t* s) {
    return s ? (int64_t)s->len : 0;
}

bars_string_t* bars_string_concat(bars_string_t* a, bars_string_t* b) {
    if (!a && !b) return bars_string_new("");
    if (!a) return b;
    if (!b) return a;
    size_t new_len = a->len + b->len;
    bars_string_t* result = (bars_string_t*)bars_alloc(sizeof(bars_string_t));
    result->magic = BARS_MAGIC_STRING;
    result->data = (char*)bars_alloc(new_len + 1);
    memcpy(result->data, a->data, a->len);
    memcpy(result->data + a->len, b->data, b->len);
    result->data[new_len] = '\0';
    result->len = new_len;
    return result;
}

/* --- I/O --- */

bars_string_t* bars_slurp(bars_string_t* path) {
    const char* p = (path && path->data) ? path->data : "";
    FILE* f = fopen(p, "rb");
    if (!f) return bars_string_new("");
    fseek(f, 0, SEEK_END);
    long sz = ftell(f);
    fseek(f, 0, SEEK_SET);
    bars_string_t* s = (bars_string_t*)bars_alloc(sizeof(bars_string_t));
    s->magic = BARS_MAGIC_STRING;
    s->len = sz > 0 ? (size_t)sz : 0;
    s->data = (char*)bars_alloc(s->len + 1);
    if (sz > 0) fread(s->data, 1, (size_t)sz, f);
    s->data[s->len] = '\0';
    fclose(f);
    return s;
}

int64_t bars_spit(bars_string_t* path, bars_string_t* content) {
    if (!content || !content->data) return 0;
    const char* p = (path && path->data) ? path->data : "";
    FILE* f = fopen(p, "wb");
    if (!f) return 0;
    size_t written = fwrite(content->data, 1, content->len, f);
    fclose(f);
    return (int64_t)written;
}

bars_string_t* bars_string_trim(bars_string_t* s) {
    if (!s || !s->data || s->len == 0) return bars_string_new("");
    size_t start = 0;
    while (start < s->len && (s->data[start] == ' ' || s->data[start] == '\t' || s->data[start] == '\n' || s->data[start] == '\r'))
        start++;
    size_t end = s->len;
    while (end > start && (s->data[end - 1] == ' ' || s->data[end - 1] == '\t' || s->data[end - 1] == '\n' || s->data[end - 1] == '\r'))
        end--;
    size_t new_len = end - start;
    bars_string_t* result = (bars_string_t*)bars_alloc(sizeof(bars_string_t));
    result->magic = BARS_MAGIC_STRING;
    result->data = (char*)bars_alloc(new_len + 1);
    memcpy(result->data, s->data + start, new_len);
    result->data[new_len] = '\0';
    result->len = new_len;
    return result;
}

bars_string_t* bars_string_substring(bars_string_t* s, int64_t start, int64_t len) {
    if (!s || !s->data || s->len == 0 || len <= 0) return bars_string_new("");
    if (start < 0) start = 0;
    if ((size_t)start >= s->len) return bars_string_new("");
    size_t max_len = s->len - (size_t)start;
    size_t actual_len = (size_t)len > max_len ? max_len : (size_t)len;
    bars_string_t* result = (bars_string_t*)bars_alloc(sizeof(bars_string_t));
    result->magic = BARS_MAGIC_STRING;
    result->data = (char*)bars_alloc(actual_len + 1);
    memcpy(result->data, s->data + start, actual_len);
    result->data[actual_len] = '\0';
    result->len = actual_len;
    return result;
}

bars_vector_t* bars_string_split(bars_string_t* s, bars_string_t* delim) {
    bars_vector_t* vec = bars_vector_new();
    if (!s || !s->data || s->len == 0) return vec;
    if (!delim || !delim->data || delim->len == 0) {
        bars_value_t v = { .tag = BARS_STRING, .data = { .string = bars_string_new(s->data) } };
        bars_vector_push(vec, v);
        return vec;
    }
    char* p = s->data;
    char* end = s->data + s->len;
    while (p < end) {
        char* found = p;
        /* naive search for delimiter */
        int found_delim = 0;
        for (; found <= end - (long)delim->len; found++) {
            if (memcmp(found, delim->data, delim->len) == 0) {
                found_delim = 1;
                break;
            }
        }
        if (!found_delim) found = end;
        size_t part_len = found - p;
        bars_string_t* part = (bars_string_t*)bars_alloc(sizeof(bars_string_t));
        part->magic = BARS_MAGIC_STRING;
        part->data = (char*)bars_alloc(part_len + 1);
        memcpy(part->data, p, part_len);
        part->data[part_len] = '\0';
        part->len = part_len;
        bars_value_t v = { .tag = BARS_STRING, .data = { .string = part } };
        bars_vector_push(vec, v);
        if (!found_delim) break;
        p = found + delim->len;
        if (p > end) break;
    }
    return vec;
}

bars_string_t* bars_string_join(bars_vector_t* vec, bars_string_t* delim) {
    if (!vec || vec->len == 0) return bars_string_new("");
    if (!delim) delim = bars_string_new("");
    size_t total = 0;
    size_t delim_len = delim->len;
    for (size_t i = 0; i < vec->len; i++) {
        if (vec->data[i].tag == BARS_STRING && vec->data[i].data.string) {
            total += vec->data[i].data.string->len;
        }
    }
    if (vec->len > 1) total += delim_len * (vec->len - 1);
    bars_string_t* result = (bars_string_t*)bars_alloc(sizeof(bars_string_t));
    result->magic = BARS_MAGIC_STRING;
    result->data = (char*)bars_alloc(total + 1);
    result->data[0] = '\0';
    result->len = total;
    size_t pos = 0;
    for (size_t i = 0; i < vec->len; i++) {
        if (vec->data[i].tag == BARS_STRING && vec->data[i].data.string) {
            bars_string_t* part = vec->data[i].data.string;
            memcpy(result->data + pos, part->data, part->len);
            pos += part->len;
        }
        if (i + 1 < vec->len && delim_len > 0) {
            memcpy(result->data + pos, delim->data, delim_len);
            pos += delim_len;
        }
    }
    result->data[pos] = '\0';
    return result;
}

/* --- String introspection --- */

int64_t bars_string_get(bars_string_t* s, int64_t idx) {
    if (!s || !s->data || idx < 0 || (size_t)idx >= s->len) return -1;
    return (int64_t)(unsigned char)s->data[idx];
}

int64_t bars_string_starts_with(bars_string_t* s, bars_string_t* prefix) {
    if (!s || !prefix) return 0;
    if (prefix->len > s->len) return 0;
    return memcmp(s->data, prefix->data, prefix->len) == 0 ? 1 : 0;
}

int64_t bars_string_ends_with(bars_string_t* s, bars_string_t* suffix) {
    if (!s || !suffix) return 0;
    if (suffix->len > s->len) return 0;
    return memcmp(s->data + s->len - suffix->len, suffix->data, suffix->len) == 0 ? 1 : 0;
}

int64_t bars_string_index_of(bars_string_t* s, bars_string_t* needle) {
    if (!s || !needle || needle->len == 0) return 0;
    if (needle->len > s->len) return -1;
    for (size_t i = 0; i <= s->len - needle->len; i++) {
        if (memcmp(s->data + i, needle->data, needle->len) == 0) {
            return (int64_t)i;
        }
    }
    return -1;
}

bars_string_t* bars_string_slice(bars_string_t* s, int64_t start, int64_t end) {
    if (!s || !s->data || s->len == 0) return bars_string_new("");
    if (start < 0) start = 0;
    if (end < 0) end = 0;
    if ((size_t)start >= s->len) return bars_string_new("");
    if ((size_t)end > s->len) end = (int64_t)s->len;
    if (end <= start) return bars_string_new("");
    int64_t len = end - start;
    return bars_string_substring(s, start, len);
}

/* --- Char / string conversions --- */

bars_string_t* bars_code_char(int64_t code) {
    char buf[2] = { (char)(code & 0xFF), '\0' };
    return bars_string_new(buf);
}

int64_t bars_char_code(bars_string_t* s) {
    if (!s || s->len == 0) return -1;
    return (int64_t)(unsigned char)s->data[0];
}

/* --- CLI args --- */

static int bars_argc = 0;
static char** bars_argv = NULL;

void bars_set_args(int argc, char** argv) {
    bars_argc = argc;
    bars_argv = argv;
}

int64_t bars_args_count(void) {
    return (int64_t)bars_argc;
}

bars_string_t* bars_args_get(int64_t idx) {
    if (idx < 0 || idx >= bars_argc) return bars_string_new("");
    return bars_string_new(bars_argv[(int)idx]);
}

/* --- Process --- */

void bars_exit(int64_t status) {
    exit((int)status);
}

int64_t bars_system(bars_string_t* cmd) {
    if (!cmd || !cmd->data) return -1;
    return (int64_t)system(cmd->data);
}
