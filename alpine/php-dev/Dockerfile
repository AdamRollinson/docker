ARG PHP_IMAGE_TAG=8.4
# Full reference of the php image to build on. Defaults to the tag above; CI passes the
# per-architecture digest it just built (rollogi/php@sha256:...), as for php-nginx.
ARG PHP_IMAGE=rollogi/php:${PHP_IMAGE_TAG}

FROM ${PHP_IMAGE}

# Switch to root for package installation
USER root

# PHP minor without dots (e.g. 84)
ARG PHP_VERSION

# Development and CI defaults for the CLI: Xdebug on demand (PHP_DEBUGGER=pcov for fast
# coverage, none for neither), errors shown, no memory limit for test suites and static
# analysis. PHP_INI_SCAN_DIR with a leading colon keeps the stock conf.d and adds the rendered
# debugger ini.
ENV PHP_DEBUGGER=xdebug \
    XDEBUG_MODE=develop,debug \
    XDEBUG_START_WITH_REQUEST=trigger \
    XDEBUG_CLIENT_HOST=host.docker.internal \
    XDEBUG_CLIENT_PORT=9003 \
    XDEBUG_DISCOVER_CLIENT_HOST=false \
    XDEBUG_IDEKEY=PHPSTORM \
    XDEBUG_OUTPUT_DIR=/tmp/xdebug \
    XDEBUG_LOG_LEVEL=3 \
    PCOV_DIRECTORY="" \
    PCOV_EXCLUDE="" \
    PHP_DISPLAY_ERRORS=On \
    PHP_ERROR_REPORTING=E_ALL \
    PHP_MEMORY_LIMIT=-1 \
    PHP_INI_SCAN_DIR=:/run/php/conf.d

# Set by CI to a hash of the Alpine package indexes (alpine/apk-index-hash.sh) so this layer
# is rebuilt whenever Alpine publishes new packages instead of being reused from the cache
ARG APK_INDEX_HASH=""

# Compile Xdebug and PCOV against the php image's headers, at the versions its
# pecl-extensions.txt lists for this minor (PCOV only where a line exists), with a throwaway
# toolchain. Neither gets an ini file, so render_debugger loads one of them at runtime
# according to PHP_DEBUGGER.
RUN set -eux; \
    apk upgrade --no-cache; \
    apk add --no-cache --virtual .debugger-build autoconf file g++ gcc make musl-dev linux-headers zlib-dev; \
    php-ext-install --no-enable --pinned xdebug; \
    if awk -v m="${PHP_PATCH_VERSION%.*}" '$1 == "dev" && $2 == "pcov" { for (i = 5; i <= NF; i++) if ($i == "*" || $i == m) f = 1 } END { exit !f }' /usr/local/etc/php/pecl-extensions.txt; then \
        php-ext-install --no-enable --pinned pcov; \
    fi; \
    apk del --no-network .debugger-build; \
    mkdir -p /run/php/conf.d; \
    chown appuser:appuser /run/php/conf.d; \
    chmod 1777 /run/php/conf.d; \
    find / -xdev -type f -perm /6000 -exec chmod a-s {} +

# OCI metadata labels
LABEL org.opencontainers.image.title="rollogi/php-dev" \
      org.opencontainers.image.description="PHP CLI with Xdebug and PCOV for development and CI, compiled from the php.net source, on Alpine 3.24" \
      org.opencontainers.image.version="${PHP_PATCH_VERSION}" \
      org.opencontainers.image.source="https://github.com/AdamRollinson/docker" \
      org.opencontainers.image.licenses="MIT"

COPY php-dev-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/php-dev-entrypoint.sh

# Default to non-root user
USER appuser

ENTRYPOINT ["/sbin/tini", "--", "php-dev-entrypoint.sh"]

# Same as php: report the version by default, run whatever command is given, or a worker
CMD ["php", "-v"]
