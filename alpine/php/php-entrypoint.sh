#!/bin/bash
set -e

# shellcheck source=../base/entrypoint-lib.sh
. /usr/local/lib/entrypoint-lib.sh

# Ensure PHP_VERSION is set
if [ -z "$PHP_VERSION" ]; then
  log "ERROR: PHP_VERSION environment variable is not set."
  exit 1
fi

# Session cookies are only marked Secure when explicitly requested for the CLI image
export PHP_SESSION_COOKIE_SECURE="${PHP_SESSION_COOKIE_SECURE:-Off}"

# Mail relay (sets PHP_SENDMAIL_PATH when SMTP_HOST is given), then php.ini
mkdir -p /run/php
render_msmtp
envsubst < /usr/local/etc/php/php.ini.template > /run/php/php.ini

# Any php.<setting>=<value> environment variable is appended as an override
apply_ini_overrides php /run/php/php.ini

# Check if OPcache logging directory exists, create if needed (best-effort for non-root)
if [ -n "$OPCACHE_ERROR_LOG" ]; then
    LOG_DIR=$(dirname "$OPCACHE_ERROR_LOG")
    mkdir -p "$LOG_DIR" 2>/dev/null || true
    touch "$OPCACHE_ERROR_LOG" 2>/dev/null || true
    chmod 666 "$OPCACHE_ERROR_LOG" 2>/dev/null || true
fi

# One-off setup command (composer install, migrations) before anything else runs
run_app_install

# "cron" runs the configured cron jobs (CRON_COMMAND or CRONTAB_FILE) as the only process,
# for a dedicated scheduler container. Everything else is executed as given.
if [ "${1:-}" = "cron" ]; then
    crontab=$(render_crontab) || exit 1
    if [ -z "$crontab" ]; then
        log "ERROR: no cron jobs configured. Set CRON_SCHEDULE and CRON_COMMAND, or mount a crontab at ${CRONTAB_FILE:-/etc/crontabs/app}."
        exit 1
    fi
    log "INFO: Starting cron with $(grep -c . "$crontab") job(s)."
    exec run-service cron supercronic -passthrough-logs -quiet -no-reap "$crontab"
fi

# Worker mode: CLI_COMMAND is run and restarted whenever it exits, so a queue worker or
# scheduler loop that crashes or exits after its max-jobs limit comes straight back without
# the container restarting. Active when CLI_COMMAND is set and the image default command
# (php -v) or the explicit "worker" command is used; an explicit command always wins.
if [ -n "${CLI_COMMAND:-}" ] && { [ "${1:-}" = "worker" ] || [ "$*" = "php -v" ]; }; then
    run_worker() {
        local restarts=0 status
        log "INFO: Worker mode: running '${CLI_COMMAND}' (restart delay ${CLI_RESTART_DELAY:-2}s, max restarts ${CLI_MAX_RESTARTS:-0}; 0 = unlimited)."
        trap 'kill -TERM "$child" 2>/dev/null; wait "$child" 2>/dev/null; exit 143' TERM INT
        while true; do
            # the command's own output is tagged [worker]; entrypoint messages keep their tag
            run-service worker sh -c "${CLI_COMMAND}" &
            child=$!
            # capture the status without tripping set -e
            if wait "$child"; then status=0; else status=$?; fi
            restarts=$((restarts + 1))
            if [ "${CLI_MAX_RESTARTS:-0}" -gt 0 ] && [ "$restarts" -gt "${CLI_MAX_RESTARTS}" ]; then
                log "ERROR: Worker exited with status ${status} and the restart limit (${CLI_MAX_RESTARTS}) is reached; giving up."
                exit "$status"
            fi
            log "WARNING: Worker exited with status ${status}; restarting in ${CLI_RESTART_DELAY:-2}s (restart ${restarts})."
            sleep "${CLI_RESTART_DELAY:-2}"
        done
    }
    run_worker
fi

# Run the original command
exec "$@"
