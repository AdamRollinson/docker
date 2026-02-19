#!/bin/bash
set -e

# Ensure PHP_VERSION is set
if [ -z "$PHP_VERSION" ]; then
  echo "Error: PHP_VERSION environment variable is not set."
  exit 1
fi

# Replace environment variables in the php.ini.template file
envsubst < /usr/local/etc/php/php.ini.template > /etc/php${PHP_VERSION}/php.ini

# Check if OPcache logging directory exists, create if needed (best-effort for non-root)
if [ -n "$OPCACHE_ERROR_LOG" ]; then
    LOG_DIR=$(dirname "$OPCACHE_ERROR_LOG")
    mkdir -p "$LOG_DIR" 2>/dev/null || true
    touch "$OPCACHE_ERROR_LOG" 2>/dev/null || true
    chmod 666 "$OPCACHE_ERROR_LOG" 2>/dev/null || true
fi

# If non-root and CMD is supervisord, exit with guidance
if [ "$(id -u)" != "0" ] && [[ "$*" == *supervisord* ]]; then
    echo "ERROR: supervisord requires root privileges."
    echo "  Run with: docker run --user root <image>"
    echo "  Or override CMD: docker run <image> php <your-script>"
    exit 1
fi

# Run the original command
exec "$@"
