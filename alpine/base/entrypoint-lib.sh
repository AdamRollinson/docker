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
