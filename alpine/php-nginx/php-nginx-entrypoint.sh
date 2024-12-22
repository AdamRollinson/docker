#!/bin/bash
set -e

# Ensure PHP_VERSION is set
if [ -z "$PHP_VERSION" ]; then
  echo "Error: PHP_VERSION environment variable is not set."
  exit 1
fi

# Replace environment variables in Nginx configuration
envsubst < /etc/nginx/http.d/app.conf.template > /etc/nginx/http.d/app.conf
sed -i 's/@@/$/g' /etc/nginx/http.d/app.conf

# Replace environment variables in php.ini.template
envsubst < /usr/local/etc/php/php.ini.template > /etc/php${PHP_VERSION}/php.ini

# Replace fpm environment variables in the www.conf.template file
envsubst < /etc/php${PHP_VERSION}/php-fpm.d/www.conf.template > /etc/php${PHP_VERSION}/php-fpm.d/www.conf

# Check if OPcache logging directory exists, create if needed
if [ -n "$OPCACHE_ERROR_LOG" ]; then
    LOG_DIR=$(dirname "$OPCACHE_ERROR_LOG")
    mkdir -p "$LOG_DIR" && touch "$OPCACHE_ERROR_LOG"
    chmod 666 "$OPCACHE_ERROR_LOG"
fi

# Run the original command
exec "$@"
