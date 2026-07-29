/* Bars runtime — TLS client (Phase 17.11)
 *
 * Separate translation unit on purpose: it is compiled to runtime/bars_tls.o
 * and linked ONLY when the generated program references bars_tls_* symbols
 * (build.brs detects them and appends this object + -lssl -lcrypto).
 * That keeps the base runtime free of any OpenSSL dependency.
 *
 * API mirrors the plain TCP fns so lib/http can switch transports:
 *   bars_tls_connect(host, port, verify) → handle (≥0) or -1
 *   bars_tls_send(handle, data)          → bytes sent or -1
 *   bars_tls_recv(handle, max_len)       → string or 0 (closed/error)
 *   bars_tls_close(handle)               → 0
 *   bars_tls_last_error()                → string with the last OpenSSL error
 *                                          ("" if none)
 *
 * verify=1 → SSL_VERIFY_PEER + hostname check (SSL_set1_host) against the
 *            system default CA paths (production).
 * verify=0 → SSL_VERIFY_NONE (local dev / self-signed test servers).
 */
#include <openssl/ssl.h>
#include <openssl/err.h>

#include <gc/gc.h>
#include <unistd.h>

#include "bars_runtime.h"

/* Plain TCP connect lives in the base runtime (always linked). */
extern int64_t bars_tcp_connect(bars_string_t* host, int64_t port);

#define BARS_MAGIC_TLS 0xB4157E55u  /* BARTLS — handle validation */

typedef struct {
    uint32_t magic;  /* must stay first: validated before any other deref */
    SSL_CTX* ctx;
    SSL*     ssl;
    int      fd;
} bars_tls_conn_t;

/* Validate a handle coming from Bars code: aligned, GC-known, right magic.
   Anything else is an arbitrary integer, not a connection. */
static bars_tls_conn_t* tls_conn_from_handle(int64_t handle) {
    if (handle <= 0 || (handle & 0x7) != 0) return NULL;
    bars_tls_conn_t* c = (bars_tls_conn_t*)(uintptr_t)handle;
    if (GC_base(c) == NULL) return NULL;
    if (c->magic != BARS_MAGIC_TLS) return NULL;
    return c;
}

static int bars_tls_ready = 0;

static void bars_tls_init_once(void) {
    if (bars_tls_ready) return;
    SSL_library_init();
    SSL_load_error_strings();
    OpenSSL_add_ssl_algorithms();
    bars_tls_ready = 1;
}

/* Last OpenSSL error string, for bars_tls_last_error() diagnostics. */
static char tls_last_err[256] = "";

static void tls_note_error(void) {
    unsigned long e = ERR_get_error();
    if (e) ERR_error_string_n(e, tls_last_err, sizeof(tls_last_err));
}

/* Teardown shared by bars_tls_close and the GC finalizer. */
static void tls_conn_teardown(bars_tls_conn_t* c) {
    if (c->magic != BARS_MAGIC_TLS) return;
    if (c->ssl) { SSL_shutdown(c->ssl); SSL_free(c->ssl); c->ssl = NULL; }
    if (c->ctx) { SSL_CTX_free(c->ctx); c->ctx = NULL; }
    if (c->fd >= 0) { close(c->fd); c->fd = -1; }
    c->magic = 0;  /* reuse of a closed handle fails validation */
}

/* If Bars code drops a connection without tls/close, the GC reclaims the
   struct — the finalizer releases the SSL/fd resources with it. */
static void tls_conn_finalize(void* obj, void* data) {
    (void)data;
    tls_conn_teardown((bars_tls_conn_t*)obj);
}

int64_t bars_tls_last_error(void) {
    return (int64_t)(uintptr_t)bars_string_new(tls_last_err);
}

int64_t bars_tls_connect(bars_string_t* host, int64_t port, int64_t verify) {
    if (!host || !host->data) return -1;
    bars_tls_init_once();
    int fd = (int)bars_tcp_connect(host, port);
    if (fd < 0) return -1;
    SSL_CTX* ctx = SSL_CTX_new(TLS_client_method());
    if (!ctx) { close(fd); return -1; }
    /* TLS 1.2 floor — 1.0/1.1 are long deprecated. */
    SSL_CTX_set_min_proto_version(ctx, TLS1_2_VERSION);
    if (verify) {
        SSL_CTX_set_verify(ctx, SSL_VERIFY_PEER, NULL);
        if (SSL_CTX_set_default_verify_paths(ctx) != 1) {
            SSL_CTX_free(ctx);
            close(fd);
            return -1;
        }
    } else {
        SSL_CTX_set_verify(ctx, SSL_VERIFY_NONE, NULL);
    }
    SSL* ssl = SSL_new(ctx);
    if (!ssl) { SSL_CTX_free(ctx); close(fd); return -1; }
    SSL_set_fd(ssl, fd);
    SSL_set_tlsext_host_name(ssl, host->data);  /* SNI */
    if (verify && SSL_set1_host(ssl, host->data) != 1) {
        /* hostname verification: cert must match `host`, not just any CA cert */
        tls_note_error();
        SSL_free(ssl);
        SSL_CTX_free(ctx);
        close(fd);
        return -1;
    }
    if (SSL_connect(ssl) != 1) {
        tls_note_error();
        SSL_free(ssl);
        SSL_CTX_free(ctx);
        close(fd);
        return -1;
    }
    bars_tls_conn_t* c = (bars_tls_conn_t*)bars_alloc(sizeof(bars_tls_conn_t));
    if (!c) { SSL_free(ssl); SSL_CTX_free(ctx); close(fd); return -1; }
    c->magic = BARS_MAGIC_TLS;
    c->ctx = ctx;
    c->ssl = ssl;
    c->fd  = fd;
    GC_register_finalizer(c, tls_conn_finalize, NULL, NULL, NULL);
    return (int64_t)(uintptr_t)c;
}

int64_t bars_tls_send(int64_t handle, bars_string_t* data) {
    bars_tls_conn_t* c = tls_conn_from_handle(handle);
    if (!c || !c->ssl || !data || !data->data) return -1;
    size_t left = data->len;
    const char* p = data->data;
    while (left > 0) {
        int n = SSL_write(c->ssl, p, (int)left);
        if (n <= 0) {
            int e = SSL_get_error(c->ssl, n);
            if (e == SSL_ERROR_WANT_READ || e == SSL_ERROR_WANT_WRITE) continue;
            tls_note_error();
            return -1;
        }
        p += (size_t)n;
        left -= (size_t)n;
    }
    return (int64_t)data->len;
}

bars_string_t* bars_tls_recv(int64_t handle, int64_t max_len) {
    bars_tls_conn_t* c = tls_conn_from_handle(handle);
    if (!c || !c->ssl) return 0;
    size_t cap = 4096;
    if (max_len > 0 && max_len < (1 << 20)) cap = (size_t)max_len;
    char* buf = (char*)malloc(cap);
    if (!buf) return 0;
    int n = SSL_read(c->ssl, buf, (int)cap);
    if (n <= 0) {
        free(buf);
        return 0;  /* orderly close or error — same contract as bars_tcp_recv */
    }
    bars_string_t* s = bars_string_new_len(buf, (size_t)n);
    free(buf);
    return s;
}

int64_t bars_tls_close(int64_t handle) {
    bars_tls_conn_t* c = tls_conn_from_handle(handle);
    if (!c) return 0;
    tls_conn_teardown(c);
    return 0;
}
