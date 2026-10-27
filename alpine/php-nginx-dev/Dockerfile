ARG PHP_IMAGE_TAG=8.4
# Full reference of the php-nginx image to build on (see php-nginx/Dockerfile)
ARG PHP_IMAGE=rollogi/php-nginx:${PHP_IMAGE_TAG}

FROM ${PHP_IMAGE}

# Switch to root for package installation
USER root

# PHP minor without dots (e.g. 84)
ARG PHP_VERSION

# Development defaults: Xdebug on demand, errors shown, static assets never cached.
# PHP_INI_SCAN_DIR with a leading colon keeps the stock conf.d and adds the rendered Xdebug ini.
ENV PHP_DEBUGGER=xdebug \
    XDEBUG_MODE=develop,debug \
    XDEBUG_START_WITH_REQUEST=trigger \
    XDEBUG_CLIENT_HOST=host.docker.internal \
    XDEBUG_CLIENT_PORT=9003 \
    XDEBUG_DISCOVER_CLIENT_HOST=false \
    XDEBUG_IDEKEY=PHPSTORM \
    XDEBUG_OUTPUT_DIR=/tmp/xdebug \
    XDEBUG_LOG_LEVEL=3 \
    NGINX_NO_CACHE_PATTERN='\.(css|js|map|json|svg|png|jpe?g|gif|webp|avif|ico|woff2?)$' \
    PHP_DISPLAY_ERRORS=On \
    PHP_ERROR_REPORTING=E_ALL \
    PHP_INI_SCAN_DIR=:/run/php/conf.d

# Set by CI to a hash of the Alpine package indexes (alpine/apk-index-hash.sh) so this layer
# is rebuilt whenever Alpine publishes new packages instead of being reused from the cache
ARG APK_INDEX_HASH=""

# Compile Xdebug against the php image's headers, at the version its pecl-extensions.txt lists
# for this minor, with a throwaway toolchain. It is installed without an ini file so loading is
# controlled at runtime by PHP_DEBUGGER.
RUN set -eux; \
    apk upgrade --no-cache; \
    apk add --no-cache --virtual .xdebug-build autoconf file g++ gcc make musl-dev linux-headers zlib-dev; \
    minor="${PHP_PATCH_VERSION%.*}"; \
    xdebug="$(awk -v m="${minor}" '$1 == "dev" && $2 == "xdebug" { for (i = 5; i <= NF; i++) if ($i == "*" || $i == m) { print $3, $4; exit } }' /usr/local/etc/php/pecl-extensions.txt)"; \
    if [ -z "${xdebug}" ]; then \
        echo "ERROR: /usr/local/etc/php/pecl-extensions.txt has no xdebug line for PHP ${minor}"; exit 1; \
    fi; \
    php-ext-install --no-enable xdebug ${xdebug}; \
    apk del --no-network .xdebug-build; \
    mkdir -p /run/php/conf.d; \
    chown appuser:appuser /run/php/conf.d; \
    chmod 1777 /run/php/conf.d; \
    find / -xdev -type f -perm /6000 -exec chmod a-s {} +

# OCI metadata labels
LABEL org.opencontainers.image.title="rollogi/php-nginx-dev" \
      org.opencontainers.image.description="PHP-FPM + Nginx development stack with Xdebug on Alpine 3.24" \
      org.opencontainers.image.version="${PHP_PATCH_VERSION}" \
      org.opencontainers.image.source="https://github.com/AdamRollinson/docker" \
      org.opencontainers.image.licenses="MIT"

COPY xdebug.ini.template no-cache.conf.template /usr/local/etc/php-nginx-dev/
COPY php-nginx-dev-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/php-nginx-dev-entrypoint.sh

# Default to non-root user
USER appuser

ENTRYPOINT ["/sbin/tini", "--", "php-nginx-dev-entrypoint.sh"]

# Same as php-nginx: "serve" runs the stack under the entrypoint's supervision
CMD ["serve"]
