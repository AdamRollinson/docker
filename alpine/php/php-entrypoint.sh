#!/bin/bash
set -e

# Ensure PHP_VERSION is set
if [ -z "$PHP_VERSION" ]; then
  echo "Error: PHP_VERSION environment variable is not set."
  exit 1
fi

# Replace environment variables in the php.ini.template file
envsubst < /usr/local/etc/php/php.ini.template > /etc/php${PHP_VERSION}/php.ini

# Check if OPcache logging directory exists, create if needed
if [ -n "$OPCACHE_ERROR_LOG" ]; then
    LOG_DIR=$(dirname "$OPCACHE_ERROR_LOG")
    mkdir -p "$LOG_DIR" && touch "$OPCACHE_ERROR_LOG"
    chmod 666 "$OPCACHE_ERROR_LOG"
fi

# Run the original command
exec "$@"
