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
 *
 * verify=1 → SSL_VERIFY_PEER with the system default CA paths (production).
 * verify=0 → SSL_VERIFY_NONE (local dev / self-signed test servers).
 */
#include <openssl/ssl.h>
#include <openssl/err.h>

#include <unistd.h>

#include "bars_runtime.h"

/* Plain TCP connect lives in the base runtime (always linked). */
extern int64_t bars_tcp_connect(bars_string_t* host, int64_t port);

typedef struct {
    SSL_CTX* ctx;
    SSL*     ssl;
    int      fd;
} bars_tls_conn_t;

static int bars_tls_ready = 0;

static void bars_tls_init_once(void) {
    if (bars_tls_ready) return;
    SSL_library_init();
    SSL_load_error_strings();
    OpenSSL_add_ssl_algorithms();
    bars_tls_ready = 1;
}

int64_t bars_tls_connect(bars_string_t* host, int64_t port, int64_t verify) {
    if (!host || !host->data) return -1;
    bars_tls_init_once();
    int fd = (int)bars_tcp_connect(host, port);
    if (fd < 0) return -1;
    SSL_CTX* ctx = SSL_CTX_new(TLS_client_method());
    if (!ctx) { close(fd); return -1; }
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
    if (SSL_connect(ssl) != 1) {
        SSL_free(ssl);
        SSL_CTX_free(ctx);
        close(fd);
        return -1;
    }
    bars_tls_conn_t* c = (bars_tls_conn_t*)bars_alloc(sizeof(bars_tls_conn_t));
    if (!c) { SSL_free(ssl); SSL_CTX_free(ctx); close(fd); return -1; }
    c->ctx = ctx;
    c->ssl = ssl;
    c->fd  = fd;
    return (int64_t)(uintptr_t)c;
}

int64_t bars_tls_send(int64_t handle, bars_string_t* data) {
    bars_tls_conn_t* c = (bars_tls_conn_t*)(uintptr_t)handle;
    if (!c || !c->ssl || !data || !data->data) return -1;
    size_t left = data->len;
    const char* p = data->data;
    while (left > 0) {
        int n = SSL_write(c->ssl, p, (int)left);
        if (n <= 0) {
            int e = SSL_get_error(c->ssl, n);
            if (e == SSL_ERROR_WANT_READ || e == SSL_ERROR_WANT_WRITE) continue;
            return -1;
        }
        p += (size_t)n;
        left -= (size_t)n;
    }
    return (int64_t)data->len;
}

bars_string_t* bars_tls_recv(int64_t handle, int64_t max_len) {
    bars_tls_conn_t* c = (bars_tls_conn_t*)(uintptr_t)handle;
    if (!c || !c->ssl) return 0;
    size_t cap = 4096;
    if (max_len > 0 && max_len < (1 << 20)) cap = (size_t)max_len;
    char* buf = (char*)malloc(cap + 1);
    if (!buf) return 0;
    int n = SSL_read(c->ssl, buf, (int)cap);
    if (n <= 0) {
        free(buf);
        return 0;  /* orderly close or error — same contract as bars_tcp_recv */
    }
    buf[n] = '\0';
    bars_string_t* s = bars_string_new(buf);
    free(buf);
    return s;
}

int64_t bars_tls_close(int64_t handle) {
    bars_tls_conn_t* c = (bars_tls_conn_t*)(uintptr_t)handle;
    if (!c) return 0;
    if (c->ssl) { SSL_shutdown(c->ssl); SSL_free(c->ssl); c->ssl = NULL; }
    if (c->ctx) { SSL_CTX_free(c->ctx); c->ctx = NULL; }
    if (c->fd >= 0) { close(c->fd); c->fd = -1; }
    return 0;
}
