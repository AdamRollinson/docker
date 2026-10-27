#!/bin/bash
set -e

# shellcheck source=../base/entrypoint-lib.sh
. /usr/local/lib/entrypoint-lib.sh

if [ -z "$PHP_VERSION" ]; then
    log "ERROR: PHP_VERSION environment variable is not set."
    exit 1
fi

# TLS terminates in the web server container, so session cookies are only marked Secure on
# request (set PHP_SESSION_COOKIE_SECURE=On behind HTTPS)
export PHP_SESSION_COOKIE_SECURE="${PHP_SESSION_COOKIE_SECURE:-Off}"

# Empty log variables resolve from LOG_MODE, as in php-nginx
if [ "${LOG_MODE:-stdout}" = "file" ]; then
    export PHP_FPM_ERROR_LOG="${PHP_FPM_ERROR_LOG:-/var/log/php-fpm/error.log}"
    export PHP_FPM_SLOWLOG="${PHP_FPM_SLOWLOG:-/var/log/php-fpm/slow.log}"
else
    export PHP_FPM_ERROR_LOG="${PHP_FPM_ERROR_LOG:-/proc/self/fd/2}"
    export PHP_FPM_SLOWLOG="${PHP_FPM_SLOWLOG:-/proc/self/fd/2}"
fi

# Mail relay, php.ini, then the FPM master config and pool into /run/php
mkdir -p /run/php
render_msmtp
envsubst < /usr/local/etc/php/php.ini.template > /run/php/php.ini
render_fpm_config
apply_ini_overrides php /run/php/php.ini

if [ -n "$OPCACHE_ERROR_LOG" ]; then
    mkdir -p "$(dirname "$OPCACHE_ERROR_LOG")" 2>/dev/null || true
    touch "$OPCACHE_ERROR_LOG" 2>/dev/null || true
    chmod 666 "$OPCACHE_ERROR_LOG" 2>/dev/null || true
fi
mkdir -p /var/log/php-fpm "/var/log/php${PHP_VERSION}" 2>/dev/null || true

# One-off setup command (composer install, migrations) before php-fpm starts
run_app_install

# "serve" starts php-fpm, plus supercronic when cron jobs are configured, each through
# run-service so their output is tagged, and exits with the first one to stop
start_services() {
    local pids=() crontab
    run-service php-fpm /usr/sbin/php-fpm --nodaemonize -y /run/php/php-fpm.conf -c /run/php/php.ini &
    pids+=($!)

    crontab=$(render_crontab) || exit 1
    if [ -n "$crontab" ]; then
        run-service cron supercronic -passthrough-logs -quiet -no-reap "$crontab" &
        pids+=($!)
        log "INFO: Running as UID $(id -u). Starting php-fpm on ${PHP_FPM_LISTEN} and cron ($(grep -c . "$crontab") job(s))."
    else
        log "INFO: Running as UID $(id -u). Starting php-fpm on ${PHP_FPM_LISTEN}."
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
