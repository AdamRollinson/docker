ARG PHP_IMAGE_TAG=8.3

FROM adamrollogi/php:${PHP_IMAGE_TAG}

# Switch to root for package installation
USER root

# Define a build-time argument for PHP version
ARG PHP_VERSION

# Set the PHP version as an environment variable.
# PHP_PATCH_VERSION is inherited from the php image so php-fpm is pinned to the same release.
ENV PHP_VERSION=${PHP_VERSION}

ENV NGINX_PORT=80 \
    NGINX_LISTEN_IPV6=true \
    NGINX_SERVER_NAME=_ \
    NGINX_ACCESS_LOG="" \
    NGINX_ERROR_LOG="" \
    NGINX_FASTCGI_PASS=127.0.0.1:9000 \
    NGINX_DOCUMENT_ROOT=/var/www/html \
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

# Update, add testing repo, and install PHP and Nginx in a single RUN command
# Note: apk upgrade with edge repos replaces gettext-envsubst with a Go-based
# envsubst that strips semicolons after ${VAR} — reinstall gettext-envsubst to fix
RUN set -eux; \
    apk update && apk upgrade; \
    apk add --no-cache \
        --repository=https://dl-cdn.alpinelinux.org/alpine/edge/main \
        --repository=https://dl-cdn.alpinelinux.org/alpine/edge/community \
        --repository=https://dl-cdn.alpinelinux.org/alpine/edge/testing \
        nginx \
        openssl \
        php${PHP_VERSION}-fpm${PHP_PATCH_VERSION:+~${PHP_PATCH_VERSION}} \
        gettext-envsubst; \
    if [ -n "${PHP_PATCH_VERSION}" ]; then \
        installed="$(php-fpm${PHP_VERSION} -v | awk 'NR==1 {print $2}')"; \
        if [ "${installed}" != "${PHP_PATCH_VERSION}" ]; then \
            echo "ERROR: pinned PHP-FPM ${PHP_PATCH_VERSION} but ${installed} was installed"; exit 1; \
        fi; \
    fi; \
    rm /etc/nginx/http.d/default.conf; \
    mkdir -p /var/log/php-fpm /etc/nginx/after.d /etc/nginx/http-conf.d; \
    find / -xdev -type f -perm /6000 -exec chmod a-s {} +

# OCI metadata labels
LABEL org.opencontainers.image.title="adamrollogi/php-nginx" \
      org.opencontainers.image.description="PHP-FPM + Nginx web stack on Alpine 3.23" \
      org.opencontainers.image.version="${PHP_PATCH_VERSION}" \
      org.opencontainers.image.source="https://github.com/adamrollogi/docker" \
      org.opencontainers.image.licenses="MIT"

# Copy configuration templates (root-owned; rendered into /run at startup) and entrypoint files
COPY app.conf.template app-ssl.conf.template app-ssl-redirect.conf.template /usr/local/etc/nginx/
COPY www.conf.template /usr/local/etc/php/www.conf.template
COPY supervisord-fpm.conf /etc/supervisord.d/supervisord-fpm.conf
COPY supervisord-nginx.conf /etc/supervisord.d/supervisord-nginx.conf
COPY index.php /var/www/html/index.php
COPY php-nginx-entrypoint.sh /usr/local/bin/
COPY healthcheck.sh /usr/local/bin/
RUN ln -s /usr/sbin/php-fpm${PHP_VERSION} /usr/sbin/php-fpm

# Make scripts executable
RUN chmod +x /usr/local/bin/php-nginx-entrypoint.sh /usr/local/bin/healthcheck.sh

# Set ownership of runtime-writable dirs for non-root mode.
# Config under /etc stays root-owned; rendered config is written to /run/nginx and /run/php.
RUN mkdir -p /var/lib/nginx/logs /var/log/php${PHP_VERSION} /etc/nginx/ssl /run/nginx/http.d /run/nginx/after.d /run/php/php-fpm.d && \
    chown -R appuser:appuser \
    /run/nginx \
    /run/php \
    /etc/nginx/ssl \
    /var/log/nginx \
    /var/log/php${PHP_VERSION} \
    /var/log/php-fpm \
    /run/nginx \
    /var/lib/nginx

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

# Start Supervisord
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisord.conf"]
