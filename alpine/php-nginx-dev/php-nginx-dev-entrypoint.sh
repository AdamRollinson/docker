#!/bin/bash
set -e

# shellcheck source=../base/entrypoint-lib.sh
. /usr/local/lib/entrypoint-lib.sh

# Renders the development-only config (Xdebug ini, no-cache nginx snippet) into /run,
# then hands over to the regular php-nginx entrypoint.

TEMPLATE_DIR=/usr/local/etc/php-nginx-dev
mkdir -p /run/php/conf.d /run/nginx/after.d
mkdir -p "${XDEBUG_OUTPUT_DIR:-/tmp/xdebug}" 2>/dev/null || true
rm -f /run/php/conf.d/50-xdebug.ini /run/nginx/after.d/no-cache.conf

case "${PHP_DEBUGGER}" in
    xdebug)
        envsubst < "${TEMPLATE_DIR}/xdebug.ini.template" > /run/php/conf.d/50-xdebug.ini
        log "INFO: Xdebug enabled (mode=${XDEBUG_MODE}, start_with_request=${XDEBUG_START_WITH_REQUEST}, client=${XDEBUG_CLIENT_HOST}:${XDEBUG_CLIENT_PORT})."
        ;;
    none)
        log "INFO: PHP_DEBUGGER=none, Xdebug is not loaded."
        ;;
    *)
        log "ERROR: PHP_DEBUGGER must be 'xdebug' or 'none' (got '${PHP_DEBUGGER}')."
        exit 1
        ;;
esac

if [ -n "${NGINX_NO_CACHE_PATTERN}" ]; then
    envsubst '${NGINX_NO_CACHE_PATTERN}' < "${TEMPLATE_DIR}/no-cache.conf.template" > /run/nginx/after.d/no-cache.conf
    sed -i 's/@@/$/g' /run/nginx/after.d/no-cache.conf
    log "INFO: Browser caching disabled for assets matching ${NGINX_NO_CACHE_PATTERN}"
fi

exec php-nginx-entrypoint.sh "$@"
