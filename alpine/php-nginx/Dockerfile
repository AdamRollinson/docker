ARG PHP_IMAGE_TAG=8.3
# Full reference of the php image to build on. Defaults to the tag above; CI passes the
# per-architecture digest it just built (rollogi/php@sha256:...) so each native runner
# chains php -> php-nginx -> php-nginx-dev without waiting for the manifest list.
ARG PHP_IMAGE=rollogi/php:${PHP_IMAGE_TAG}

FROM ${PHP_IMAGE}

# Switch to root for package installation
USER root

# Define a build-time argument for PHP version
ARG PHP_VERSION

# Set the PHP version as an environment variable.
# PHP_PATCH_VERSION is inherited from the php image, which also provides php-fpm.
ENV PHP_VERSION=${PHP_VERSION}

ENV NGINX_PORT=80 \
    NGINX_LISTEN_IPV6=true \
    NGINX_SERVER_NAME=_ \
    NGINX_ACCESS_LOG="" \
    NGINX_ERROR_LOG="" \
    NGINX_FASTCGI_PASS=127.0.0.1:9000 \
    NGINX_METRICS_PORT="" \
    NGINX_METRICS_ALLOW=all \
    NGINX_DOCUMENT_ROOT=/var/www/html \
    APP_INSTALL_DIR=/var/www/html \
    NGINX_SSL_ENABLED=false \
    NGINX_SSL_PORT=443 \
    NGINX_SSL_CERTIFICATE=/etc/nginx/ssl/cert.pem \
    NGINX_SSL_CERTIFICATE_KEY=/etc/nginx/ssl/key.pem \
    NGINX_SSL_PROTOCOLS="TLSv1.2 TLSv1.3" \
    NGINX_SSL_CIPHERS="ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384" \
    NGINX_SSL_PREFER_SERVER_CIPHERS=off \
    NGINX_SSL_SESSION_TIMEOUT=1d \
    NGINX_SSL_SESSION_CACHE="shared:SSL:10m" \
    NGINX_SSL_REDIRECT=true \
    NGINX_SSL_REDIRECT_HOST="" \
    NGINX_SSL_SELF_SIGNED=false \
    NGINX_SSL_SELF_SIGNED_CN=localhost \
    NGINX_SSL_SELF_SIGNED_DAYS=365 \
    NGINX_SSL_HSTS=true \
    NGINX_SSL_HSTS_MAX_AGE=63072000 \
    PHP_FPM_LISTEN=127.0.0.1:9000 \
    PHP_FPM_MAX_CHILDREN=30 \
    PHP_FPM_START_SERVERS=5 \
    PHP_FPM_MIN_SPARE_SERVERS=3 \
    PHP_FPM_MAX_SPARE_SERVERS=10 \
    PHP_FPM_MAX_REQUESTS=1000 \
    PHP_FPM_REQUEST_TERMINATE_TIMEOUT=0 \
    PHP_FPM_ERROR_LOG="" \
    PHP_FPM_SLOWLOG=""

# Set by CI to a hash of the Alpine package indexes (alpine/apk-index-hash.sh) so this layer
# is rebuilt whenever Alpine publishes new packages instead of being reused from the cache
ARG APK_INDEX_HASH=""

# Nginx from the Alpine release. php-fpm is already in the php image, compiled from the same
# source as the CLI, so it is checked here rather than installed.
RUN set -eux; \
    apk upgrade --no-cache; \
    apk add --no-cache \
        nginx \
        openssl \
        gettext-envsubst; \
    installed="$(php-fpm -v | awk 'NR==1 {print tolower($2)}')"; \
    expected="$(printf '%s' "${PHP_PATCH_VERSION}" | tr -d '_' | tr 'A-Z' 'a-z')"; \
    if [ "${installed}" != "${expected}" ]; then \
        echo "ERROR: php-fpm reports ${installed}, expected ${PHP_PATCH_VERSION}"; exit 1; \
    fi; \
    rm /etc/nginx/http.d/default.conf; \
    mkdir -p /var/log/php-fpm /etc/nginx/after.d /etc/nginx/http-conf.d; \
    find / -xdev -type f -perm /6000 -exec chmod a-s {} +

# OCI metadata labels
LABEL org.opencontainers.image.title="rollogi/php-nginx" \
      org.opencontainers.image.description="PHP-FPM + Nginx web stack on Alpine 3.24" \
      org.opencontainers.image.version="${PHP_PATCH_VERSION}" \
      org.opencontainers.image.source="https://github.com/AdamRollinson/docker" \
      org.opencontainers.image.licenses="MIT"

# Copy configuration templates (root-owned; rendered into /run at startup) and entrypoint files
COPY app.conf.template app-ssl.conf.template app-ssl-redirect.conf.template metrics.conf.template /usr/local/etc/nginx/
COPY index.php /var/www/html/index.php
COPY php-nginx-entrypoint.sh /usr/local/bin/
COPY healthcheck.sh /usr/local/bin/

# Make scripts executable
RUN chmod +x /usr/local/bin/php-nginx-entrypoint.sh /usr/local/bin/healthcheck.sh

# Set ownership of runtime-writable dirs for non-root mode. Config under /etc stays root-owned;
# rendered config is written to /run/nginx and /run/php. The state directories are sticky and
# world-writable (like /tmp) so the image also runs under an arbitrary --user.
RUN set -eux; \
    mkdir -p /var/lib/nginx/logs /var/lib/nginx/tmp /var/log/php${PHP_VERSION} /var/log/php-fpm /etc/nginx/ssl \
        /run/nginx/http.d /run/nginx/after.d /run/php/php-fpm.d; \
    for dir in /run/nginx /run/php /etc/nginx/ssl /var/log/nginx /var/log/php${PHP_VERSION} /var/log/php-fpm /var/lib/nginx; do \
        chown -R appuser:appuser "$dir"; \
        chmod -R a+rwX "$dir"; \
        find "$dir" -type d -exec chmod +t {} +; \
    done

# Healthcheck using wrapper script (handles HTTP and HTTPS modes)
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD healthcheck.sh

# Set the entrypoint with tini for signal handling
ENTRYPOINT ["/sbin/tini", "--", "php-nginx-entrypoint.sh"]

# Expose ports
EXPOSE 80 443

# Set working directory
WORKDIR /var/www

# Default to non-root user
USER appuser

# "serve" starts php-fpm and nginx (plus crond when running as root) under the entrypoint's
# own supervision; any other command is executed as-is
CMD ["serve"]
