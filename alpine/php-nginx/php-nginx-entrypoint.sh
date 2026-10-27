#!/bin/bash
set -e

# shellcheck source=../base/entrypoint-lib.sh
. /usr/local/lib/entrypoint-lib.sh

# Ensure PHP_VERSION is set
if [ -z "$PHP_VERSION" ]; then
  log "ERROR: PHP_VERSION environment variable is not set."
  exit 1
fi

# ---------------------------------------------------------------------------
# SSL defaults
# ---------------------------------------------------------------------------

# Default redirect port to the HTTP port if not explicitly set
export NGINX_SSL_REDIRECT_PORT="${NGINX_SSL_REDIRECT_PORT:-${NGINX_PORT:-80}}"

# Fix the HTTPS redirect target so the client-supplied Host header is never reflected.
# Priority: NGINX_SSL_REDIRECT_HOST, then the first non-wildcard server_name, then $host.
if [ -z "${NGINX_SSL_REDIRECT_HOST}" ]; then
    FIRST_SERVER_NAME="${NGINX_SERVER_NAME%% *}"
    case "${FIRST_SERVER_NAME}" in
        ""|_|*\**|~*) NGINX_SSL_REDIRECT_HOST='@@host' ;;
        *)             NGINX_SSL_REDIRECT_HOST="${FIRST_SERVER_NAME}" ;;
    esac
fi
export NGINX_SSL_REDIRECT_HOST

# Omit the port from the redirect when HTTPS is on the default port
if [ "${NGINX_SSL_PORT:-443}" = "443" ]; then
    export NGINX_SSL_REDIRECT_PORT_SUFFIX=""
else
    export NGINX_SSL_REDIRECT_PORT_SUFFIX=":${NGINX_SSL_PORT}"
fi

# Session cookies default to Secure whenever HTTPS is enabled
if [ -z "${PHP_SESSION_COOKIE_SECURE}" ]; then
    if [ "${NGINX_SSL_ENABLED}" = "true" ]; then
        export PHP_SESSION_COOKIE_SECURE=On
    else
        export PHP_SESSION_COOKIE_SECURE=Off
    fi
fi

# ---------------------------------------------------------------------------
# Log destinations
# ---------------------------------------------------------------------------

# Empty log variables resolve from LOG_MODE: stdout streams by default, one file per
# service under /var/log when LOG_MODE=file.
if [ "${LOG_MODE:-stdout}" = "file" ]; then
    export NGINX_ACCESS_LOG="${NGINX_ACCESS_LOG:-/var/log/nginx/access.log}"
    export NGINX_ERROR_LOG="${NGINX_ERROR_LOG:-/var/log/nginx/error.log}"
    export PHP_FPM_ERROR_LOG="${PHP_FPM_ERROR_LOG:-/var/log/php-fpm/error.log}"
    export PHP_FPM_SLOWLOG="${PHP_FPM_SLOWLOG:-/var/log/php-fpm/slow.log}"
else
    export NGINX_ACCESS_LOG="${NGINX_ACCESS_LOG:-/dev/stdout}"
    export NGINX_ERROR_LOG="${NGINX_ERROR_LOG:-/dev/stderr}"
    export PHP_FPM_ERROR_LOG="${PHP_FPM_ERROR_LOG:-/proc/self/fd/2}"
    export PHP_FPM_SLOWLOG="${PHP_FPM_SLOWLOG:-/proc/self/fd/2}"
fi

# Access log directive: "off" disables it; json mode uses the json_combined format
# (defined in /run/nginx/logging.conf) so each line is a self-describing JSON object.
if [ "${NGINX_ACCESS_LOG}" = "off" ]; then
    export NGINX_ACCESS_LOG_DIRECTIVE="access_log off"
elif [ "${LOG_FORMAT:-text}" = "json" ] && [ "${LOG_MODE:-stdout}" = "stdout" ]; then
    export NGINX_ACCESS_LOG_DIRECTIVE="access_log ${NGINX_ACCESS_LOG} json_combined"
else
    export NGINX_ACCESS_LOG_DIRECTIVE="access_log ${NGINX_ACCESS_LOG} combined"
fi

# ---------------------------------------------------------------------------
# Runtime config locations (kept out of /etc so the config tree stays root-owned)
# ---------------------------------------------------------------------------

NGINX_RUN_DIR=/run/nginx
PHP_RUN_DIR=/run/php
NGINX_TEMPLATE_DIR=/usr/local/etc/nginx
mkdir -p "${NGINX_RUN_DIR}/http.d" "${NGINX_RUN_DIR}/after.d" "${PHP_RUN_DIR}/php-fpm.d"

# ---------------------------------------------------------------------------
# Self-signed certificate generation
# ---------------------------------------------------------------------------

if [ "${NGINX_SSL_ENABLED}" = "true" ] && [ "${NGINX_SSL_SELF_SIGNED}" = "true" ]; then
    CERT_FILE="${NGINX_SSL_CERTIFICATE:-/etc/nginx/ssl/cert.pem}"
    KEY_FILE="${NGINX_SSL_CERTIFICATE_KEY:-/etc/nginx/ssl/key.pem}"
    CERT_CN="${NGINX_SSL_SELF_SIGNED_CN:-localhost}"
    CERT_DAYS="${NGINX_SSL_SELF_SIGNED_DAYS:-365}"

    if [ ! -f "$CERT_FILE" ] || [ ! -f "$KEY_FILE" ]; then
        log "INFO: Generating self-signed certificate for CN=${CERT_CN} (valid ${CERT_DAYS} days)..."

        CERT_DIR=$(dirname "$CERT_FILE")
        KEY_DIR=$(dirname "$KEY_FILE")
        mkdir -p "$CERT_DIR" "$KEY_DIR" 2>/dev/null || {
            log "ERROR: Cannot create SSL directory. Check volume mount permissions."
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

        log "INFO: Self-signed certificate generated at ${CERT_FILE}"
    else
        log "INFO: Self-signed cert requested but files already exist — skipping generation."
    fi
fi

# ---------------------------------------------------------------------------
# Certificate validation
# ---------------------------------------------------------------------------

if [ "${NGINX_SSL_ENABLED}" = "true" ]; then
    CERT_FILE="${NGINX_SSL_CERTIFICATE:-/etc/nginx/ssl/cert.pem}"
    KEY_FILE="${NGINX_SSL_CERTIFICATE_KEY:-/etc/nginx/ssl/key.pem}"

    if [ ! -r "$CERT_FILE" ]; then
        log "ERROR: SSL certificate not found or not readable: ${CERT_FILE}"
        log "  Mount your certificate with: -v /path/to/cert.pem:${CERT_FILE}:ro"
        log "  Or enable self-signed mode: -e NGINX_SSL_SELF_SIGNED=true"
        exit 1
    fi

    if [ ! -r "$KEY_FILE" ]; then
        log "ERROR: SSL private key not found or not readable: ${KEY_FILE}"
        log "  Mount your key with: -v /path/to/key.pem:${KEY_FILE}:ro"
        log "  Or enable self-signed mode: -e NGINX_SSL_SELF_SIGNED=true"
        exit 1
    fi
fi

# ---------------------------------------------------------------------------
# Nginx template assembly
# ---------------------------------------------------------------------------

# Start from the stock nginx.conf: route the http-level error log, add the http-level
# drop-in directory (/etc/nginx/http-conf.d) and point the server-block include at the
# rendered directory while still honouring custom server blocks in /etc/nginx/http.d.
rm -f "${NGINX_RUN_DIR}"/http.d/*.conf
cat > "${NGINX_RUN_DIR}/logging.conf" <<'NGINX_LOGGING'
log_format json_combined escape=json
    '{"time":"$time_iso8601","service":"nginx","stream":"access",'
    '"remote_addr":"$remote_addr","x_forwarded_for":"$http_x_forwarded_for","host":"$host",'
    '"method":"$request_method","uri":"$request_uri","protocol":"$server_protocol",'
    '"status":$status,"bytes_sent":$body_bytes_sent,"request_time":$request_time,'
    '"upstream_time":"$upstream_response_time","referer":"$http_referer","user_agent":"$http_user_agent"}';
NGINX_LOGGING
sed \
    -e "s|^error_log [^;]*;|error_log ${NGINX_ERROR_LOG} warn;|" \
    -e "s|include /etc/nginx/http.d/\*.conf;|include ${NGINX_RUN_DIR}/logging.conf;\n    include /etc/nginx/http-conf.d/*.conf;\n    include /etc/nginx/http.d/*.conf;\n    include ${NGINX_RUN_DIR}/http.d/*.conf;|" \
    /etc/nginx/nginx.conf > "${NGINX_RUN_DIR}/nginx.conf"

# The "user" directive only applies when the master runs as root; drop it otherwise so
# nginx does not emit a warning on every non-root start
if [ "$(id -u)" != "0" ]; then
    sed -i '/^user /d' "${NGINX_RUN_DIR}/nginx.conf"
fi

if [ "${NGINX_SSL_ENABLED}" = "true" ]; then
    # Process SSL server block
    envsubst < "${NGINX_TEMPLATE_DIR}/app-ssl.conf.template" > "${NGINX_RUN_DIR}/http.d/app-ssl.conf"
    sed -i 's/@@/$/g' "${NGINX_RUN_DIR}/http.d/app-ssl.conf"

    # Strip HSTS header if disabled
    if [ "${NGINX_SSL_HSTS}" != "true" ]; then
        sed -i '/Strict-Transport-Security/d' "${NGINX_RUN_DIR}/http.d/app-ssl.conf"
        log "INFO: HSTS header disabled."
    fi

    # Process redirect or plain HTTP template
    if [ "${NGINX_SSL_REDIRECT}" = "true" ]; then
        envsubst < "${NGINX_TEMPLATE_DIR}/app-ssl-redirect.conf.template" > "${NGINX_RUN_DIR}/http.d/app-ssl-redirect.conf"
        sed -i 's/@@/$/g' "${NGINX_RUN_DIR}/http.d/app-ssl-redirect.conf"
        if [ "${NGINX_SSL_REDIRECT_HOST}" = '@@host' ]; then
            log "WARNING: HTTP->HTTPS redirect reflects the request Host header. Set NGINX_SERVER_NAME or NGINX_SSL_REDIRECT_HOST to pin it."
        fi
        log "INFO: SSL enabled — HTTPS on port ${NGINX_SSL_PORT:-443}, HTTP->HTTPS redirect on port ${NGINX_SSL_REDIRECT_PORT}."
    else
        log "INFO: SSL enabled — HTTPS on port ${NGINX_SSL_PORT:-443}, no HTTP redirect."
    fi

    # Patch http-level SSL settings (session cache/timeout are defined there as
    # shared memory zones and cannot be overridden per-server).
    sed -i \
        -e "s|ssl_session_cache shared:SSL:[^;]*;|ssl_session_cache ${NGINX_SSL_SESSION_CACHE};|" \
        -e "s|ssl_session_timeout [^;]*;|ssl_session_timeout ${NGINX_SSL_SESSION_TIMEOUT};|" \
        -e "s|ssl_protocols [^;]*;|ssl_protocols ${NGINX_SSL_PROTOCOLS};|" \
        "${NGINX_RUN_DIR}/nginx.conf"
else
    # HTTP-only mode (default, backward compatible)
    envsubst < "${NGINX_TEMPLATE_DIR}/app.conf.template" > "${NGINX_RUN_DIR}/http.d/app.conf"
    sed -i 's/@@/$/g' "${NGINX_RUN_DIR}/http.d/app.conf"
fi

# Optional metrics listener with nginx stub_status and PHP-FPM status/ping
if [ -n "${NGINX_METRICS_PORT}" ]; then
    envsubst < "${NGINX_TEMPLATE_DIR}/metrics.conf.template" > "${NGINX_RUN_DIR}/http.d/metrics.conf"
    sed -i 's/@@/$/g' "${NGINX_RUN_DIR}/http.d/metrics.conf"
    log "INFO: Metrics listener on port ${NGINX_METRICS_PORT} (allow ${NGINX_METRICS_ALLOW}): /nginx_status, /fpm-status, /fpm-ping, /health."
fi

# Drop the IPv6 listeners when disabled (e.g. hosts with net.ipv6.conf.all.disable_ipv6=1)
if [ "${NGINX_LISTEN_IPV6}" != "true" ]; then
    sed -i '/listen \[::\]/d' "${NGINX_RUN_DIR}"/http.d/*.conf
    log "INFO: IPv6 listeners disabled."
fi

# ---------------------------------------------------------------------------
# Non-root port warnings
# ---------------------------------------------------------------------------

if [ "$(id -u)" != "0" ]; then
    if [ "${NGINX_SSL_ENABLED}" = "true" ]; then
        SSL_PORT="${NGINX_SSL_PORT:-443}"
        if [ "$SSL_PORT" -lt 1024 ] 2>/dev/null; then
            log "WARNING: SSL port ${SSL_PORT} requires root. Use --user root or set NGINX_SSL_PORT to 8443+."
        fi
        if [ "${NGINX_SSL_REDIRECT}" = "true" ]; then
            REDIR_PORT="${NGINX_SSL_REDIRECT_PORT}"
            if [ "$REDIR_PORT" -lt 1024 ] 2>/dev/null; then
                log "WARNING: Redirect port ${REDIR_PORT} requires root. Use --user root or set NGINX_SSL_REDIRECT_PORT to 8080+."
            fi
        fi
    fi
fi

# ---------------------------------------------------------------------------
# PHP / FPM config (unchanged)
# ---------------------------------------------------------------------------

# Mail relay first (sets PHP_SENDMAIL_PATH when SMTP_HOST is given), then php.ini
# (PHPRC points PHP at /run/php) and the FPM pool into /run/php
render_msmtp
envsubst < /usr/local/etc/php/php.ini.template > "${PHP_RUN_DIR}/php.ini"

# FPM master config and pool (with fpm.global.* and fpm.pool.* overrides), shared with php-fpm
render_fpm_config

# Generic overrides: php.<setting> into php.ini
apply_ini_overrides php "${PHP_RUN_DIR}/php.ini"

# Check if OPcache logging directory exists, create if needed (best-effort for non-root)
if [ -n "$OPCACHE_ERROR_LOG" ]; then
    LOG_DIR=$(dirname "$OPCACHE_ERROR_LOG")
    mkdir -p "$LOG_DIR" 2>/dev/null || true
    touch "$OPCACHE_ERROR_LOG" 2>/dev/null || true
    chmod 666 "$OPCACHE_ERROR_LOG" 2>/dev/null || true
fi

# Create log directories (best-effort for non-root; needed when /var/log is a tmpfs)
mkdir -p /var/log/nginx "/var/log/php${PHP_VERSION}" /var/log/php-fpm /var/lib/nginx/tmp /var/lib/nginx/logs 2>/dev/null || true

# One-off setup command (composer install, migrations) before the services start
run_app_install

# ---------------------------------------------------------------------------
# Process supervision
# ---------------------------------------------------------------------------
# "serve" (the image default) starts php-fpm and nginx, plus supercronic when cron jobs are
# configured (CRON_COMMAND or a crontab at CRONTAB_FILE), each through run-service so their log
# lines are tagged. The entrypoint waits on all of them and exits with the first one to die, so
# the container restarts cleanly under any orchestrator. Cron works as any user; no root needed.
# The old supervisord CMD is accepted for backward compatibility.

start_services() {
    local pids=()

    run-service php-fpm /usr/sbin/php-fpm --nodaemonize -y "${PHP_RUN_DIR}/php-fpm.conf" -c "${PHP_RUN_DIR}/php.ini" &
    pids+=($!)

    run-service nginx /usr/sbin/nginx -c "${NGINX_RUN_DIR}/nginx.conf" -g 'daemon off;' &
    pids+=($!)

    local crontab
    crontab=$(render_crontab) || exit 1
    if [ -n "$crontab" ]; then
        run-service cron supercronic -passthrough-logs -quiet -no-reap "$crontab" &
        pids+=($!)
        log "INFO: Running as UID $(id -u). Starting php-fpm, nginx and cron ($(grep -c . "$crontab") job(s))."
    else
        log "INFO: Running as UID $(id -u). Starting php-fpm and nginx."
    fi

    # Forward termination to every service, then wait for them to finish
    trap 'kill -TERM "${pids[@]}" 2>/dev/null; wait' TERM INT

    # Exit as soon as any service exits, propagating its status
    wait -n "${pids[@]}" 2>/dev/null
    local status=$?
    kill -TERM "${pids[@]}" 2>/dev/null
    wait "${pids[@]}" 2>/dev/null
    exit "${status}"
}

case "${1:-serve}" in
    serve|/usr/bin/supervisord|supervisord)
        start_services
        ;;
    *)
        exec "$@"
        ;;
esac
