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

# When running as non-root, php-fpm cannot switch to user/group — remove directives
if [ "$(id -u)" != "0" ]; then
    sed -i '/^user = /d; /^group = /d' /etc/php${PHP_VERSION}/php-fpm.d/www.conf
fi

# Check if OPcache logging directory exists, create if needed (best-effort for non-root)
if [ -n "$OPCACHE_ERROR_LOG" ]; then
    LOG_DIR=$(dirname "$OPCACHE_ERROR_LOG")
    mkdir -p "$LOG_DIR" 2>/dev/null || true
    touch "$OPCACHE_ERROR_LOG" 2>/dev/null || true
    chmod 666 "$OPCACHE_ERROR_LOG" 2>/dev/null || true
fi

# Create nginx log directory (best-effort for non-root)
mkdir -p /var/log/nginx 2>/dev/null || true

if [ "$(id -u)" = "0" ]; then
    # Root mode: full supervisor with cron, nginx, php-fpm
    exec "$@"
else
    # Non-root mode: run nginx + php-fpm directly (no supervisor/cron)
    if [[ "$*" == *supervisord* ]]; then
        echo "INFO: Running as non-root (UID $(id -u)). Starting nginx + php-fpm directly."
        echo "INFO: Cron is not available in non-root mode. Use --user root for full supervisor mode."

        # Start php-fpm in background
        /usr/sbin/php-fpm --nodaemonize &
        PHP_FPM_PID=$!

        # Start nginx in foreground-ish
        /usr/sbin/nginx -g 'daemon off;' &
        NGINX_PID=$!

        # Wait for either process to exit, then clean up
        wait -n "$PHP_FPM_PID" "$NGINX_PID" 2>/dev/null
        EXIT_CODE=$?
        kill "$PHP_FPM_PID" "$NGINX_PID" 2>/dev/null
        wait "$PHP_FPM_PID" "$NGINX_PID" 2>/dev/null
        exit "${EXIT_CODE}"
    else
        exec "$@"
    fi
fi
