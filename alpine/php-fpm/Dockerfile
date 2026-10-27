ARG PHP_IMAGE_TAG=8.4
# Full reference of the php image to build on. Defaults to the tag above; CI passes the
# per-architecture digest it just built (rollogi/php@sha256:...), as for php-nginx.
ARG PHP_IMAGE=rollogi/php:${PHP_IMAGE_TAG}

FROM ${PHP_IMAGE}

# Switch to root for package installation
USER root

# PHP minor without dots (e.g. 84). PHP_PATCH_VERSION is inherited from the php image, which
# also provides php-fpm.
ARG PHP_VERSION
ENV PHP_VERSION=${PHP_VERSION}

# PHP-FPM on its own, for a web server in another container (a Kubernetes sidecar, a separate
# nginx or Caddy service in Compose). It listens on every interface so the web server can reach
# it; keep port 9000 on a private network and never publish it.
ENV PHP_FPM_LISTEN=0.0.0.0:9000 \
    PHP_FPM_LISTEN_ALLOWED_CLIENTS="" \
    PHP_FPM_MAX_CHILDREN=30 \
    PHP_FPM_START_SERVERS=5 \
    PHP_FPM_MIN_SPARE_SERVERS=3 \
    PHP_FPM_MAX_SPARE_SERVERS=10 \
    PHP_FPM_MAX_REQUESTS=1000 \
    PHP_FPM_REQUEST_TERMINATE_TIMEOUT=0 \
    PHP_FPM_ERROR_LOG="" \
    PHP_FPM_SLOWLOG="" \
    APP_INSTALL_DIR=/var/www/html

# Set by CI to a hash of the Alpine package indexes (alpine/apk-index-hash.sh) so this layer
# is rebuilt whenever Alpine publishes new packages instead of being reused from the cache
ARG APK_INDEX_HASH=""

# php-fpm is already in the php image, compiled from the same source as the CLI, so it is only
# checked here; cgi-fcgi comes from the Alpine release for the healthcheck (it speaks FastCGI
# to the pool's ping path)
RUN set -eux; \
    apk upgrade --no-cache; \
    apk add --no-cache fcgi; \
    installed="$(php-fpm -v | awk 'NR==1 {print tolower($2)}')"; \
    expected="$(printf '%s' "${PHP_PATCH_VERSION}" | tr -d '_' | tr 'A-Z' 'a-z')"; \
    if [ "${installed}" != "${expected}" ]; then \
        echo "ERROR: php-fpm reports ${installed}, expected ${PHP_PATCH_VERSION}"; exit 1; \
    fi; \
    find / -xdev -type f -perm /6000 -exec chmod a-s {} +

# OCI metadata labels
LABEL org.opencontainers.image.title="rollogi/php-fpm" \
      org.opencontainers.image.description="PHP-FPM without a web server, for nginx or Caddy in another container, on Alpine 3.24" \
      org.opencontainers.image.version="${PHP_PATCH_VERSION}" \
      org.opencontainers.image.source="https://github.com/AdamRollinson/docker" \
      org.opencontainers.image.licenses="MIT"

COPY php-fpm-entrypoint.sh php-fpm-healthcheck /usr/local/bin/
RUN chmod +x /usr/local/bin/php-fpm-entrypoint.sh /usr/local/bin/php-fpm-healthcheck

# Runtime state directories are sticky and world-writable so any --user can render config and
# write logs; /etc stays root-owned
RUN set -eux; \
    mkdir -p /run/php/php-fpm.d /var/log/php-fpm /var/log/php${PHP_VERSION} /var/www/html; \
    for dir in /run/php /var/log/php-fpm /var/log/php${PHP_VERSION}; do \
        chown -R appuser:appuser "$dir"; \
        chmod -R a+rwX "$dir"; \
        find "$dir" -type d -exec chmod +t {} +; \
    done

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD php-fpm-healthcheck

ENTRYPOINT ["/sbin/tini", "--", "php-fpm-entrypoint.sh"]

EXPOSE 9000

WORKDIR /var/www

USER appuser

# "serve" runs php-fpm (plus cron when jobs are configured) under the entrypoint's supervision;
# any other command is executed as-is
CMD ["serve"]
