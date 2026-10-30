#!/bin/bash
set -e

# shellcheck source=../base/entrypoint-lib.sh
. /usr/local/lib/entrypoint-lib.sh

# Renders the development-only config (debugger ini, no-cache nginx snippet) into /run,
# then hands over to the regular php-nginx entrypoint.

TEMPLATE_DIR=/usr/local/etc/php-nginx-dev
mkdir -p /run/nginx/after.d
rm -f /run/nginx/after.d/no-cache.conf

render_debugger || exit 1

if [ -n "${NGINX_NO_CACHE_PATTERN}" ]; then
    envsubst '${NGINX_NO_CACHE_PATTERN}' < "${TEMPLATE_DIR}/no-cache.conf.template" > /run/nginx/after.d/no-cache.conf
    sed -i 's/@@/$/g' /run/nginx/after.d/no-cache.conf
    log "INFO: Browser caching disabled for assets matching ${NGINX_NO_CACHE_PATTERN}"
fi

exec php-nginx-entrypoint.sh "$@"
