#!/bin/bash
set -e

# Ensure PHP_VERSION is set
if [ -z "$PHP_VERSION" ]; then
  echo "Error: PHP_VERSION environment variable is not set."
  exit 1
fi

# ---------------------------------------------------------------------------
# SSL defaults
# ---------------------------------------------------------------------------

# Default redirect port to the HTTP port if not explicitly set
export NGINX_SSL_REDIRECT_PORT="${NGINX_SSL_REDIRECT_PORT:-${NGINX_PORT:-80}}"

# ---------------------------------------------------------------------------
# Self-signed certificate generation
# ---------------------------------------------------------------------------

if [ "${NGINX_SSL_ENABLED}" = "true" ] && [ "${NGINX_SSL_SELF_SIGNED}" = "true" ]; then
    CERT_FILE="${NGINX_SSL_CERTIFICATE:-/etc/nginx/ssl/cert.pem}"
    KEY_FILE="${NGINX_SSL_CERTIFICATE_KEY:-/etc/nginx/ssl/key.pem}"
    CERT_CN="${NGINX_SSL_SELF_SIGNED_CN:-localhost}"
    CERT_DAYS="${NGINX_SSL_SELF_SIGNED_DAYS:-365}"

    if [ ! -f "$CERT_FILE" ] || [ ! -f "$KEY_FILE" ]; then
        echo "INFO: Generating self-signed certificate for CN=${CERT_CN} (valid ${CERT_DAYS} days)..."

        CERT_DIR=$(dirname "$CERT_FILE")
        KEY_DIR=$(dirname "$KEY_FILE")
        mkdir -p "$CERT_DIR" "$KEY_DIR" 2>/dev/null || {
            echo "ERROR: Cannot create SSL directory. Check volume mount permissions."
            exit 1
        }

        openssl req -x509 -nodes -newkey rsa:2048 \
            -days "$CERT_DAYS" \
            -keyout "$KEY_FILE" \
            -out "$CERT_FILE" \
            -subj "/CN=${CERT_CN}" \
            -addext "subjectAltName=DNS:${CERT_CN},IP:127.0.0.1" \
            2>/dev/null

        chmod 644 "$CERT_FILE"
        chmod 600 "$KEY_FILE"

        echo "INFO: Self-signed certificate generated at ${CERT_FILE}"
    else
        echo "INFO: Self-signed cert requested but files already exist — skipping generation."
    fi
fi

# ---------------------------------------------------------------------------
# Certificate validation
# ---------------------------------------------------------------------------

if [ "${NGINX_SSL_ENABLED}" = "true" ]; then
    CERT_FILE="${NGINX_SSL_CERTIFICATE:-/etc/nginx/ssl/cert.pem}"
    KEY_FILE="${NGINX_SSL_CERTIFICATE_KEY:-/etc/nginx/ssl/key.pem}"

    if [ ! -r "$CERT_FILE" ]; then
        echo "ERROR: SSL certificate not found or not readable: ${CERT_FILE}"
        echo "  Mount your certificate with: -v /path/to/cert.pem:${CERT_FILE}:ro"
        echo "  Or enable self-signed mode: -e NGINX_SSL_SELF_SIGNED=true"
        exit 1
    fi

    if [ ! -r "$KEY_FILE" ]; then
        echo "ERROR: SSL private key not found or not readable: ${KEY_FILE}"
        echo "  Mount your key with: -v /path/to/key.pem:${KEY_FILE}:ro"
        echo "  Or enable self-signed mode: -e NGINX_SSL_SELF_SIGNED=true"
        exit 1
    fi
fi

# ---------------------------------------------------------------------------
# Nginx template assembly
# ---------------------------------------------------------------------------

if [ "${NGINX_SSL_ENABLED}" = "true" ]; then
    # Process SSL server block
    envsubst < /etc/nginx/http.d/app-ssl.conf.template > /etc/nginx/http.d/app-ssl.conf
    sed -i 's/@@/$/g' /etc/nginx/http.d/app-ssl.conf

    # Strip HSTS header if disabled
    if [ "${NGINX_SSL_HSTS}" != "true" ]; then
        sed -i '/Strict-Transport-Security/d' /etc/nginx/http.d/app-ssl.conf
        echo "INFO: HSTS header disabled."
    fi

    # Process redirect or plain HTTP template
    if [ "${NGINX_SSL_REDIRECT}" = "true" ]; then
        envsubst < /etc/nginx/http.d/app-ssl-redirect.conf.template > /etc/nginx/http.d/app-ssl-redirect.conf
        sed -i 's/@@/$/g' /etc/nginx/http.d/app-ssl-redirect.conf
        echo "INFO: SSL enabled — HTTPS on port ${NGINX_SSL_PORT:-443}, HTTP->HTTPS redirect on port ${NGINX_SSL_REDIRECT_PORT}."
    else
        echo "INFO: SSL enabled — HTTPS on port ${NGINX_SSL_PORT:-443}, no HTTP redirect."
    fi

    # Remove the plain HTTP template output (not used in SSL mode)
    rm -f /etc/nginx/http.d/app.conf

    # Patch http-level SSL settings in nginx.conf (session cache/timeout are
    # defined there as shared memory zones and cannot be overridden per-server).
    # Use temp file + cp because sed -i needs write access to the directory.
    NGINX_CONF_TMP=$(mktemp)
    sed \
        -e "s|ssl_session_cache shared:SSL:[^;]*;|ssl_session_cache ${NGINX_SSL_SESSION_CACHE};|" \
        -e "s|ssl_session_timeout [^;]*;|ssl_session_timeout ${NGINX_SSL_SESSION_TIMEOUT};|" \
        -e "s|ssl_protocols [^;]*;|ssl_protocols ${NGINX_SSL_PROTOCOLS};|" \
        /etc/nginx/nginx.conf > "$NGINX_CONF_TMP"
    cat "$NGINX_CONF_TMP" > /etc/nginx/nginx.conf
    rm -f "$NGINX_CONF_TMP"
else
    # HTTP-only mode (default, backward compatible)
    envsubst < /etc/nginx/http.d/app.conf.template > /etc/nginx/http.d/app.conf
    sed -i 's/@@/$/g' /etc/nginx/http.d/app.conf
fi

# ---------------------------------------------------------------------------
# Non-root port warnings
# ---------------------------------------------------------------------------

if [ "$(id -u)" != "0" ]; then
    if [ "${NGINX_SSL_ENABLED}" = "true" ]; then
        SSL_PORT="${NGINX_SSL_PORT:-443}"
        if [ "$SSL_PORT" -lt 1024 ] 2>/dev/null; then
            echo "WARNING: SSL port ${SSL_PORT} requires root. Use --user root or set NGINX_SSL_PORT to 8443+."
        fi
        if [ "${NGINX_SSL_REDIRECT}" = "true" ]; then
            REDIR_PORT="${NGINX_SSL_REDIRECT_PORT}"
            if [ "$REDIR_PORT" -lt 1024 ] 2>/dev/null; then
                echo "WARNING: Redirect port ${REDIR_PORT} requires root. Use --user root or set NGINX_SSL_REDIRECT_PORT to 8080+."
            fi
        fi
    fi
fi

# ---------------------------------------------------------------------------
# PHP / FPM config (unchanged)
# ---------------------------------------------------------------------------

# Replace environment variables in php.ini.template
envsubst < /usr/local/etc/php/php.ini.template > /etc/php${PHP_VERSION}/php.ini

# Replace fpm environment variables in the www.conf.template file
envsubst < /etc/php${PHP_VERSION}/php-fpm.d/www.conf.template > /etc/php${PHP_VERSION}/php-fpm.d/www.conf

# When running as non-root, php-fpm cannot switch to user/group — remove directives
if [ "$(id -u)" != "0" ]; then
    sed -i '/^user = /d; /^group = /d' /etc/php${PHP_VERSION}/php-fpm.d/www.conf
fi

# Check if OPcache logging directory exists, create if needed (best-effort for non-root)
if [ -n "$OPCACHE_ERROR_LOG" ]; then
    LOG_DIR=$(dirname "$OPCACHE_ERROR_LOG")
    mkdir -p "$LOG_DIR" 2>/dev/null || true
    touch "$OPCACHE_ERROR_LOG" 2>/dev/null || true
    chmod 666 "$OPCACHE_ERROR_LOG" 2>/dev/null || true
fi

# Create nginx log directory (best-effort for non-root)
mkdir -p /var/log/nginx 2>/dev/null || true

if [ "$(id -u)" = "0" ]; then
    # Root mode: full supervisor with cron, nginx, php-fpm
    exec "$@"
else
    # Non-root mode: run nginx + php-fpm directly (no supervisor/cron)
    if [[ "$*" == *supervisord* ]]; then
        echo "INFO: Running as non-root (UID $(id -u)). Starting nginx + php-fpm directly."
        echo "INFO: Cron is not available in non-root mode. Use --user root for full supervisor mode."

        # Start php-fpm in background
        /usr/sbin/php-fpm --nodaemonize &
        PHP_FPM_PID=$!

        # Start nginx in foreground-ish
        /usr/sbin/nginx -g 'daemon off;' &
        NGINX_PID=$!

        # Trap signals for clean shutdown
        trap 'kill -TERM $PHP_FPM_PID $NGINX_PID 2>/dev/null; wait' TERM INT

        # Wait for either process to exit, then clean up
        wait -n "$PHP_FPM_PID" "$NGINX_PID" 2>/dev/null
        EXIT_CODE=$?
        kill "$PHP_FPM_PID" "$NGINX_PID" 2>/dev/null
        wait "$PHP_FPM_PID" "$NGINX_PID" 2>/dev/null
        exit "${EXIT_CODE}"
    else
        exec "$@"
    fi
fi
