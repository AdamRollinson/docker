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
        nginx \
        php${PHP_VERSION}-fpm \
        gettext-envsubst; \
    rm /etc/nginx/http.d/default.conf; \
    mkdir -p /var/log/php${PHP_VERSION}-fpm; \
    touch /var/log/php${PHP_VERSION}-fpm/www-slow.log

# Copy configuration and entrypoint files
COPY app.conf.template /etc/nginx/http.d/app.conf.template
COPY www.conf.template /etc/php${PHP_VERSION}/php-fpm.d/www.conf.template
COPY supervisord-fpm.conf /etc/supervisord.d/supervisord-fpm.conf
COPY supervisord-nginx.conf /etc/supervisord.d/supervisord-nginx.conf
COPY index.php /var/www/html/index.php
COPY php-nginx-entrypoint.sh /usr/local/bin/
RUN ln -s /usr/sbin/php-fpm${PHP_VERSION} /usr/sbin/php-fpm

# Make the entrypoint script executable
RUN chmod +x /usr/local/bin/php-nginx-entrypoint.sh

# Set ownership of runtime-writable dirs for non-root mode
RUN mkdir -p /var/lib/nginx/logs /var/log/php${PHP_VERSION} && \
    chown -R appuser:appuser \
    /etc/nginx/http.d \
    /etc/php${PHP_VERSION}/php-fpm.d \
    /var/log/nginx \
    /var/log/php${PHP_VERSION} \
    /var/log/php${PHP_VERSION}-fpm \
    /run/nginx \
    /var/lib/nginx

# Set the entrypoint
ENTRYPOINT ["php-nginx-entrypoint.sh"]

# Expose ports
EXPOSE 80

# Set working directory
WORKDIR /var/www

# Default to non-root user
USER appuser

# Start Supervisord
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisord.conf"]