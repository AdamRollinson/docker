ARG PHP_IMAGE_TAG=8.4

FROM adamrollogi/php-nginx:${PHP_IMAGE_TAG}

# Switch to root for package installation
USER root

# PHP minor without dots, used in Alpine package names (e.g. 84)
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

# Install Xdebug from the same edge repos as PHP, then remove the package's always-on ini so
# loading is controlled at runtime by PHP_DEBUGGER
RUN set -eux; \
    apk add --no-cache \
        --repository=https://dl-cdn.alpinelinux.org/alpine/edge/main \
        --repository=https://dl-cdn.alpinelinux.org/alpine/edge/community \
        --repository=https://dl-cdn.alpinelinux.org/alpine/edge/testing \
        php${PHP_VERSION}-pecl-xdebug; \
    rm -f /etc/php${PHP_VERSION}/conf.d/*xdebug*.ini; \
    mkdir -p /run/php/conf.d; \
    chown appuser:appuser /run/php/conf.d; \
    find / -xdev -type f -perm /6000 -exec chmod a-s {} +

# OCI metadata labels
LABEL org.opencontainers.image.title="adamrollogi/php-nginx-dev" \
      org.opencontainers.image.description="PHP-FPM + Nginx development stack with Xdebug on Alpine 3.24" \
      org.opencontainers.image.version="${PHP_PATCH_VERSION}" \
      org.opencontainers.image.source="https://github.com/adamrollogi/docker" \
      org.opencontainers.image.licenses="MIT"

COPY xdebug.ini.template no-cache.conf.template /usr/local/etc/php-nginx-dev/
COPY php-nginx-dev-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/php-nginx-dev-entrypoint.sh

# Default to non-root user
USER appuser

ENTRYPOINT ["/sbin/tini", "--", "php-nginx-dev-entrypoint.sh"]

# Same as php-nginx: "serve" runs the stack under the entrypoint's supervision
CMD ["serve"]
