ARG PHP_IMAGE_TAG=8.3

FROM adamrollogi/php:${PHP_IMAGE_TAG}

# Switch to root for package installation
USER root

# Define a build-time argument for PHP version
ARG PHP_VERSION

# Set the PHP version as an environment variable
ENV PHP_VERSION=${PHP_VERSION}

ENV NGINX_PORT=80 \
    NGINX_SERVER_NAME=_ \
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
    PHP_FPM_REQUEST_TERMINATE_TIMEOUT=0

# Update, add testing repo, and install PHP and Nginx in a single RUN command
# Note: apk upgrade with edge repos replaces gettext-envsubst with a Go-based
# envsubst that strips semicolons after ${VAR} — reinstall gettext-envsubst to fix
RUN set -eux; \
    apk update && apk upgrade; \
    apk add --no-cache \
        --repository=http://dl-cdn.alpinelinux.org/alpine/edge/main \
        --repository=http://dl-cdn.alpinelinux.org/alpine/edge/community \
        --repository=http://dl-cdn.alpinelinux.org/alpine/edge/testing \
        nginx \
        openssl \
        php${PHP_VERSION}-fpm \
        gettext-envsubst; \
    rm /etc/nginx/http.d/default.conf; \
    mkdir -p /var/log/php${PHP_VERSION}-fpm; \
    touch /var/log/php${PHP_VERSION}-fpm/www-slow.log

# OCI metadata labels
LABEL org.opencontainers.image.title="adamrollogi/php-nginx" \
      org.opencontainers.image.description="PHP-FPM + Nginx web stack on Alpine 3.21" \
      org.opencontainers.image.source="https://github.com/adamrollogi/docker" \
      org.opencontainers.image.licenses="MIT"

# Copy configuration and entrypoint files
COPY app.conf.template /etc/nginx/http.d/app.conf.template
COPY app-ssl.conf.template /etc/nginx/http.d/app-ssl.conf.template
COPY app-ssl-redirect.conf.template /etc/nginx/http.d/app-ssl-redirect.conf.template
COPY www.conf.template /etc/php${PHP_VERSION}/php-fpm.d/www.conf.template
COPY supervisord-fpm.conf /etc/supervisord.d/supervisord-fpm.conf
COPY supervisord-nginx.conf /etc/supervisord.d/supervisord-nginx.conf
COPY index.php /var/www/html/index.php
COPY php-nginx-entrypoint.sh /usr/local/bin/
COPY healthcheck.sh /usr/local/bin/
RUN ln -s /usr/sbin/php-fpm${PHP_VERSION} /usr/sbin/php-fpm

# Make scripts executable
RUN chmod +x /usr/local/bin/php-nginx-entrypoint.sh /usr/local/bin/healthcheck.sh

# Set ownership of runtime-writable dirs for non-root mode
RUN mkdir -p /var/lib/nginx/logs /var/log/php${PHP_VERSION} /etc/nginx/ssl && \
    chown appuser:appuser /etc/nginx/nginx.conf && \
    chown -R appuser:appuser \
    /etc/nginx/http.d \
    /etc/nginx/ssl \
    /etc/php${PHP_VERSION}/php-fpm.d \
    /var/log/nginx \
    /var/log/php${PHP_VERSION} \
    /var/log/php${PHP_VERSION}-fpm \
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
