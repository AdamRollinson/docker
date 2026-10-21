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
