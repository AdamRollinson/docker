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
