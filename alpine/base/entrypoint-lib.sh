#!/bin/bash
# Shared helpers sourced by the container entrypoints.

# Escape a string for use inside a JSON string literal.
json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\t'/\\t}"
    s="${s//$'\r'/}"
    s="${s//$'\n'/\\n}"
    printf '%s' "$s"
}

# Log a line from the entrypoint, tagged like the service streams:
#   text: "[entrypoint] INFO: ..."   json: {"time":...,"service":"entrypoint","message":"..."}
# Always written to stderr so that stdout of a CLI command (docker run ... php -r ... | jq)
# stays clean.
log() {
    if [ "${LOG_MODE:-stdout}" = "stdout" ] && [ "${LOG_FORMAT:-text}" = "json" ]; then
        printf '{"time":"%s","service":"entrypoint","stream":"stderr","message":"%s"}\n' \
            "$(date +%Y-%m-%dT%H:%M:%S%z)" "$(json_escape "$*")" >&2
    elif [ "${LOG_MODE:-stdout}" = "stdout" ] && [ "${LOG_TAG:-true}" = "true" ]; then
        echo "[entrypoint] $*" >&2
    else
        echo "$*" >&2
    fi
}

# Append "key = value" lines to an ini file for every environment variable named
# <prefix>.<key>. Example: php.memory_limit=256M becomes "memory_limit = 256M".
# Multi-line values are not supported.
apply_ini_overrides() {
    local prefix="$1" target="$2" matches line key value count
    matches=$(env | grep -E "^${prefix//./\\.}\.[][A-Za-z0-9_.]+=" | sort) || true
    [ -n "$matches" ] || return 0

    printf '\n; overrides from %s.* environment variables\n' "$prefix" >> "$target"
    count=0
    while IFS= read -r line; do
        key="${line%%=*}"
        value="${line#*=}"
        printf '%s = %s\n' "${key#"${prefix}".}" "$value" >> "$target"
        count=$((count + 1))
    done <<< "$matches"
    log "INFO: applied ${count} ${prefix}.* override(s) to ${target}"
}

# Cron is handled by supercronic, which runs as any user and logs to stdout. Jobs come from
# either a mounted crontab (CRONTAB_FILE, default /etc/crontabs/app) or the CRON_SCHEDULE and
# CRON_COMMAND pair for the common single-job case. Renders /run/cron/crontab and prints its
# path, or prints nothing when no cron jobs are configured.
render_crontab() {
    local file="${CRONTAB_FILE:-/etc/crontabs/app}" out=/run/cron/crontab
    mkdir -p /run/cron 2>/dev/null || true
    : > "$out"
    if [ -n "${CRON_COMMAND:-}" ]; then
        printf '%s %s\n' "${CRON_SCHEDULE:-* * * * *}" "${CRON_COMMAND}" >> "$out"
    fi
    if [ -f "$file" ]; then
        cat "$file" >> "$out"
    fi
    if [ -s "$out" ]; then
        if ! supercronic -test "$out" >/dev/null 2>&1; then
            log "ERROR: crontab is invalid (CRONTAB_FILE=$file, CRON_SCHEDULE='${CRON_SCHEDULE:-}', CRON_COMMAND='${CRON_COMMAND:-}')"
            supercronic -test "$out" 2>&1 | tail -3 >&2
            return 1
        fi
        echo "$out"
    fi
}

# Outbound mail relay. When SMTP_HOST is set, render /run/php/msmtprc from the SMTP_* variables
# and point sendmail_path at msmtp unless PHP_SENDMAIL_PATH was given explicitly. TLS defaults
# follow the port: 465 is implicit TLS, anything else uses STARTTLS; AUTH is on when a user is set.
render_msmtp() {
    [ -n "${SMTP_HOST:-}" ] || return 0
    local rc=/run/php/msmtprc
    export SMTP_PORT="${SMTP_PORT:-587}"
    export SMTP_FROM="${SMTP_FROM:-noreply@$(hostname)}"
    export SMTP_AUTH="${SMTP_AUTH:-$([ -n "${SMTP_USER:-}" ] && echo on || echo off)}"
    if [ "${SMTP_PORT}" = "465" ]; then
        export SMTP_TLS="${SMTP_TLS:-on}" SMTP_TLS_STARTTLS="${SMTP_TLS_STARTTLS:-off}"
    elif [ "${SMTP_PORT}" = "25" ] || [ "${SMTP_PORT}" = "1025" ]; then
        export SMTP_TLS="${SMTP_TLS:-off}" SMTP_TLS_STARTTLS="${SMTP_TLS_STARTTLS:-off}"
    else
        export SMTP_TLS="${SMTP_TLS:-on}" SMTP_TLS_STARTTLS="${SMTP_TLS_STARTTLS:-on}"
    fi
    mkdir -p "$(dirname "$rc")"
    (umask 077; envsubst < /usr/local/etc/php/msmtprc.template > "$rc")
    # msmtp rejects empty user/password lines, so drop them when unset
    [ -n "${SMTP_USER:-}" ] || sed -i '/^user $/d' "$rc"
    [ -n "${SMTP_PASSWORD:-}" ] || sed -i '/^password $/d' "$rc"
    if [ -z "${PHP_SENDMAIL_PATH:-}" ]; then
        export PHP_SENDMAIL_PATH="/usr/bin/msmtp -C ${rc} -t"
    fi
    log "INFO: Mail relay configured: ${SMTP_HOST}:${SMTP_PORT} (tls=${SMTP_TLS}, starttls=${SMTP_TLS_STARTTLS}, auth=${SMTP_AUTH}, from=${SMTP_FROM})."
}

# Run the one-off APP_INSTALL command (composer install, migrations, cache warmup) before the
# main command or the services start. Runs in APP_INSTALL_DIR (default: the working directory)
# with output tagged [install]. A non-zero exit stops the container with that status, so a
# failed install never results in a serving container with half-installed code.
run_app_install() {
    [ -n "${APP_INSTALL:-}" ] || return 0
    local dir="${APP_INSTALL_DIR:-$PWD}" status
    log "INFO: Running APP_INSTALL in ${dir}: ${APP_INSTALL}"
    if (cd "$dir" && run-service install sh -c "${APP_INSTALL}"); then
        log "INFO: APP_INSTALL finished."
    else
        status=$?
        log "ERROR: APP_INSTALL exited with status ${status}; not starting."
        exit "$status"
    fi
}

# PHP-FPM master config and [www] pool, rendered into /run/php from the pool template the php
# image ships (/usr/local/etc/php/www.conf.template), then fpm.global.* and fpm.pool.* overrides.
# Shared by php-nginx and php-fpm. PHP_FPM_LISTEN_ALLOWED_CLIENTS restricts which addresses may
# connect to a TCP listener; 127.0.0.1 is always added so the local healthcheck keeps working.
render_fpm_config() {
    local run=/run/php pool=/run/php/php-fpm.d/www.conf clients
    mkdir -p "${run}/php-fpm.d"
    envsubst < /usr/local/etc/php/www.conf.template > "$pool"

    # A non-root master cannot switch to the pool user, so drop the directives
    if [ "$(id -u)" != "0" ]; then
        sed -i '/^user = /d; /^group = /d' "$pool"
    fi

    clients="${PHP_FPM_LISTEN_ALLOWED_CLIENTS:-}"
    if [ -n "$clients" ]; then
        case ",${clients}," in *,127.0.0.1,*) ;; *) clients="127.0.0.1,${clients}" ;; esac
        printf '\nlisten.allowed_clients = %s\n' "$clients" >> "$pool"
    fi

    printf '[global]\nerror_log = %s\n' "${PHP_FPM_ERROR_LOG}" > "${run}/php-fpm.conf"
    apply_ini_overrides fpm.global "${run}/php-fpm.conf"
    printf '\ninclude=%s/php-fpm.d/*.conf\n' "${run}" >> "${run}/php-fpm.conf"
    apply_ini_overrides fpm.pool "$pool"
}

# Development images: load Xdebug or PCOV (or neither) for this container by rendering an ini
# into /run/php/conf.d, which PHP_INI_SCAN_DIR=:/run/php/conf.d adds to the stock scan directory.
# PHP_DEBUGGER is xdebug, pcov or none; the two are never loaded together because both hook
# code coverage. Templates ship in the php image. Shared by php-dev and php-nginx-dev. Every
# step checks its own result: callers use "render_debugger || exit 1", which disables set -e here.
render_debugger() {
    local dir=/run/php/conf.d templates=/usr/local/etc/php/debug debugger="${PHP_DEBUGGER:-none}"
    case "$debugger" in
        xdebug|pcov|none) ;;
        *)
            log "ERROR: PHP_DEBUGGER must be 'xdebug', 'pcov' or 'none' (got '${debugger}')."
            return 1
            ;;
    esac
    if ! mkdir -p "$dir" 2>/dev/null || ! rm -f "${dir}/50-xdebug.ini" "${dir}/50-pcov.ini"; then
        log "ERROR: cannot write ${dir}. On a read-only root filesystem mount /run as a tmpfs the runtime user owns, e.g. --tmpfs /run:uid=$(id -u),gid=$(id -g)."
        return 1
    fi
    if [ "$debugger" = "none" ]; then
        log "INFO: PHP_DEBUGGER=none, no debugger or coverage driver is loaded."
        return 0
    fi
    if [ ! -f "$(php-config --extension-dir)/${debugger}.so" ]; then
        log "ERROR: ${debugger} is not built for PHP $(php-config --version) in this image; use PHP_DEBUGGER=xdebug or none."
        return 1
    fi
    if ! envsubst < "${templates}/${debugger}.ini.template" > "${dir}/50-${debugger}.ini"; then
        log "ERROR: could not render ${dir}/50-${debugger}.ini."
        return 1
    fi
    if [ "$debugger" = "xdebug" ]; then
        mkdir -p "${XDEBUG_OUTPUT_DIR:-/tmp/xdebug}" 2>/dev/null || true
        log "INFO: Xdebug enabled (mode=${XDEBUG_MODE}, start_with_request=${XDEBUG_START_WITH_REQUEST}, client=${XDEBUG_CLIENT_HOST}:${XDEBUG_CLIENT_PORT})."
    else
        log "INFO: PCOV enabled (directory=${PCOV_DIRECTORY:-auto})."
    fi
}
