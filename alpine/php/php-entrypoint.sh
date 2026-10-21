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

# Render php.ini into /run/php (PHPRC points PHP at it); /etc/php* stays root-owned
mkdir -p /run/php
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

# If non-root and CMD is supervisord, exit with guidance
if [ "$(id -u)" != "0" ] && [[ "$*" == *supervisord* ]]; then
    log "ERROR: supervisord requires root privileges."
    log "  Run with: docker run --user root <image>"
    log "  Or override CMD: docker run <image> php <your-script>"
    exit 1
fi

# Run the original command
exec "$@"
