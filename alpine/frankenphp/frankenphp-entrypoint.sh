#!/bin/bash
set -e

# shellcheck source=../base/entrypoint-lib.sh
. /usr/local/lib/entrypoint-lib.sh

if [ -z "$PHP_VERSION" ]; then
    log "ERROR: PHP_VERSION environment variable is not set."
    exit 1
fi

# Caddy's own log follows LOG_MODE and LOG_FORMAT: console lines (tagged [frankenphp] by
# run-service) or JSON objects on stderr, or a file under /var/log/frankenphp
if [ "${LOG_MODE:-stdout}" = "file" ]; then
    export CADDY_LOG_OUTPUT="${CADDY_LOG_OUTPUT:-file /var/log/frankenphp/caddy.log}"
else
    export CADDY_LOG_OUTPUT="${CADDY_LOG_OUTPUT:-stderr}"
fi
if [ "${LOG_FORMAT:-text}" = "json" ]; then
    export CADDY_LOG_FORMAT="${CADDY_LOG_FORMAT:-json}"
else
    export CADDY_LOG_FORMAT="${CADDY_LOG_FORMAT:-console}"
fi

# Session cookies are marked Secure when Caddy terminates TLS, which it does for a host name
# but not for a bare port (":80") or an explicit http:// address
case "${SERVER_NAME:-:80}" in
    :*|http://*) export PHP_SESSION_COOKIE_SECURE="${PHP_SESSION_COOKIE_SECURE:-Off}" ;;
    *)           export PHP_SESSION_COOKIE_SECURE="${PHP_SESSION_COOKIE_SECURE:-On}" ;;
esac

# The frankenphp global block: thread count and the worker script, then FRANKENPHP_CONFIG as is
config=""
if [ -n "${FRANKENPHP_NUM_THREADS}" ]; then
    config+="num_threads ${FRANKENPHP_NUM_THREADS}"$'\n'
fi
if [ -n "${FRANKENPHP_WORKER}" ]; then
    [ -f "${FRANKENPHP_WORKER}" ] || log "WARNING: FRANKENPHP_WORKER ${FRANKENPHP_WORKER} does not exist yet"
    config+="worker ${FRANKENPHP_WORKER}${FRANKENPHP_WORKER_NUM:+ ${FRANKENPHP_WORKER_NUM}}"$'\n'
fi
export FRANKENPHP_CONFIG="${config}${FRANKENPHP_CONFIG}"

# Mail relay and php.ini into /run/php (PHPRC), read by both the embedded PHP and the CLI
mkdir -p /run/php
render_msmtp
envsubst < /usr/local/etc/php/php.ini.template > /run/php/php.ini
apply_ini_overrides php /run/php/php.ini

if [ -n "$OPCACHE_ERROR_LOG" ]; then
    mkdir -p "$(dirname "$OPCACHE_ERROR_LOG")" 2>/dev/null || true
    touch "$OPCACHE_ERROR_LOG" 2>/dev/null || true
    chmod 666 "$OPCACHE_ERROR_LOG" 2>/dev/null || true
fi
mkdir -p /var/log/frankenphp "${XDG_DATA_HOME:-/data}/caddy" "${XDG_CONFIG_HOME:-/config}/caddy" 2>/dev/null || true

# One-off setup command (composer install, migrations) before FrankenPHP starts
run_app_install

# "serve" starts FrankenPHP, plus supercronic when cron jobs are configured, each through
# run-service so their output is tagged, and exits with the first one to stop
start_services() {
    local pids=() crontab mode="classic mode"
    [ -n "${FRANKENPHP_WORKER}" ] && mode="worker mode (${FRANKENPHP_WORKER})"
    run-service frankenphp frankenphp run --config /etc/frankenphp/Caddyfile --adapter caddyfile &
    pids+=($!)

    crontab=$(render_crontab) || exit 1
    if [ -n "$crontab" ]; then
        run-service cron supercronic -passthrough-logs -quiet -no-reap "$crontab" &
        pids+=($!)
        log "INFO: Running as UID $(id -u). Starting FrankenPHP on ${SERVER_NAME} in ${mode} and cron ($(grep -c . "$crontab") job(s))."
    else
        log "INFO: Running as UID $(id -u). Starting FrankenPHP on ${SERVER_NAME} in ${mode}."
    fi

    trap 'kill -TERM "${pids[@]}" 2>/dev/null; wait' TERM INT
    wait -n "${pids[@]}" 2>/dev/null
    local status=$?
    kill -TERM "${pids[@]}" 2>/dev/null
    wait "${pids[@]}" 2>/dev/null
    exit "${status}"
}

case "${1:-serve}" in
    serve) start_services ;;
    *)     exec "$@" ;;
esac
