#!/bin/sh
# Entrypoint for php-slim: POSIX sh only (busybox), no bash, no envsubst. Renders php.ini into
# /run/php with php.* overrides, runs APP_INSTALL, then either runs php-fpm ("serve") or execs
# the command. Worker restarts, cron, mail relay and per-service log tagging are left to the
# full php image.
set -eu

RENDER="php -n /usr/local/lib/php-slim/render.php"

log() {
    echo "[entrypoint] $*" >&2
}

# Session cookies are only marked Secure on request (set PHP_SESSION_COOKIE_SECURE=On behind HTTPS)
export PHP_SESSION_COOKIE_SECURE="${PHP_SESSION_COOKIE_SECURE:-Off}"

mkdir -p /run/php
$RENDER /usr/local/etc/php/php.ini.template /run/php/php.ini
$RENDER --append php /run/php/php.ini

if [ -n "${OPCACHE_ERROR_LOG:-}" ]; then
    touch "$OPCACHE_ERROR_LOG" 2>/dev/null || true
fi

# One-off setup command (composer install, migrations) before anything else runs; a failure
# stops the container with its exit status
if [ -n "${APP_INSTALL:-}" ]; then
    dir="${APP_INSTALL_DIR:-$PWD}"
    log "INFO: Running APP_INSTALL in ${dir}: ${APP_INSTALL}"
    status=0
    (cd "$dir" && sh -c "$APP_INSTALL") || status=$?
    if [ "$status" -ne 0 ]; then
        log "ERROR: APP_INSTALL exited with status ${status}; not starting."
        exit "$status"
    fi
    log "INFO: APP_INSTALL finished."
fi

# "serve" renders the FPM master config and pool into /run/php and runs php-fpm in the
# foreground as the only process (tini is PID 1)
if [ "${1:-}" = "serve" ]; then
    pool=/run/php/php-fpm.d/www.conf
    mkdir -p /run/php/php-fpm.d
    $RENDER /usr/local/etc/php/www.conf.template "$pool"

    # A non-root master cannot switch to the pool user, so drop the directives
    if [ "$(id -u)" != "0" ]; then
        sed -i '/^user = /d; /^group = /d' "$pool"
    fi

    clients="${PHP_FPM_LISTEN_ALLOWED_CLIENTS:-}"
    if [ -n "$clients" ]; then
        case ",${clients}," in *,127.0.0.1,*) ;; *) clients="127.0.0.1,${clients}" ;; esac
        printf '\nlisten.allowed_clients = %s\n' "$clients" >> "$pool"
    fi

    printf '[global]\nerror_log = %s\n' "${PHP_FPM_ERROR_LOG}" > /run/php/php-fpm.conf
    $RENDER --append fpm.global /run/php/php-fpm.conf
    printf '\ninclude=/run/php/php-fpm.d/*.conf\n' >> /run/php/php-fpm.conf
    $RENDER --append fpm.pool "$pool"

    log "INFO: Running as UID $(id -u). Starting php-fpm on ${PHP_FPM_LISTEN}."
    exec php-fpm --nodaemonize -y /run/php/php-fpm.conf -c /run/php/php.ini
fi

exec "$@"
