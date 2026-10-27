ARG PHP_IMAGE_TAG=8.4
# Full reference of the php image to build on. Defaults to the tag above; CI passes the
# per-architecture digest it just built (rollogi/php@sha256:...), as for php-nginx.
ARG PHP_IMAGE=rollogi/php:${PHP_IMAGE_TAG}

FROM ${PHP_IMAGE}

# Switch to root for package installation
USER root

# PHP minor without dots, used in Alpine package names (e.g. 84). PHP_PATCH_VERSION is inherited
# from the php image so php-fpm is pinned to the same release.
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

# php-fpm pinned to the php image's release from the same scoped edge repositories, then
# cgi-fcgi from the stable branch for the healthcheck (it speaks FastCGI to the pool's ping path)
RUN set -eux; \
    apk update && apk upgrade; \
    apk add --no-cache \
        --repository=https://dl-cdn.alpinelinux.org/alpine/edge/main \
        --repository=https://dl-cdn.alpinelinux.org/alpine/edge/community \
        --repository=https://dl-cdn.alpinelinux.org/alpine/edge/testing \
        php${PHP_VERSION}-fpm${PHP_PATCH_VERSION:+~${PHP_PATCH_VERSION}}; \
    apk add --no-cache fcgi; \
    if [ -n "${PHP_PATCH_VERSION}" ]; then \
        installed="$(php-fpm${PHP_VERSION} -v | awk 'NR==1 {print tolower($2)}')"; \
        expected="$(printf '%s' "${PHP_PATCH_VERSION}" | tr -d '_' | tr 'A-Z' 'a-z')"; \
        if [ "${installed}" != "${expected}" ]; then \
            echo "ERROR: pinned PHP-FPM ${PHP_PATCH_VERSION} but ${installed} was installed"; exit 1; \
        fi; \
        mismatched="$(apk list -I 2>/dev/null | awk '{print $1}' | grep "^php${PHP_VERSION}" | grep -v -- '-pecl-' | grep -v -- "-${PHP_PATCH_VERSION}-r" || true)"; \
        if [ -n "${mismatched}" ]; then \
            echo "ERROR: these php${PHP_VERSION} packages do not match the pinned release ${PHP_PATCH_VERSION}:"; echo "${mismatched}"; exit 1; \
        fi; \
    fi; \
    find / -xdev -type f -perm /6000 -exec chmod a-s {} +

# OCI metadata labels
LABEL org.opencontainers.image.title="rollogi/php-fpm" \
      org.opencontainers.image.description="PHP-FPM without a web server, for nginx or Caddy in another container, on Alpine 3.24" \
      org.opencontainers.image.version="${PHP_PATCH_VERSION}" \
      org.opencontainers.image.source="https://github.com/AdamRollinson/docker" \
      org.opencontainers.image.licenses="MIT"

COPY php-fpm-entrypoint.sh php-fpm-healthcheck /usr/local/bin/
RUN chmod +x /usr/local/bin/php-fpm-entrypoint.sh /usr/local/bin/php-fpm-healthcheck && \
    ln -s /usr/sbin/php-fpm${PHP_VERSION} /usr/sbin/php-fpm

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
