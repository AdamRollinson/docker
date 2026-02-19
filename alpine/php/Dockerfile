# Use the updated base image
FROM adamrollogi/base:latest

# Switch to root for package installation
USER root

# Define a build-time argument for PHP version
ARG PHP_VERSION

# Set the PHP version as an environment variable
ENV PHP_VERSION=${PHP_VERSION}

# PHP General Settings
ENV PHP_MEMORY_LIMIT=128M
ENV PHP_UPLOAD_MAX_FILESIZE=2M
ENV PHP_POST_MAX_SIZE=2M
ENV PHP_MAX_INPUT_TIME=60
ENV PHP_MAX_EXECUTION_TIME=30
ENV PHP_DISPLAY_ERRORS=Off
ENV PHP_ERROR_REPORTING="E_ALL & ~E_DEPRECATED & ~E_STRICT"
ENV PHP_DATE_TIMEZONE=UTC

# OPcache Settings
ENV OPCACHE_ENABLE=0
ENV OPCACHE_ENABLE_CLI=0
ENV OPCACHE_MEMORY_CONSUMPTION=128
ENV OPCACHE_INTERNED_STRINGS_BUFFER=8
ENV OPCACHE_MAX_ACCELERATED_FILES=10000
ENV OPCACHE_VALIDATE_TIMESTAMPS=1
ENV OPCACHE_REVALIDATE_FREQ=2
ENV OPCACHE_MAX_WASTED_PERCENTAGE=5
ENV OPCACHE_LOG_VERBOSITY_LEVEL=1
ENV OPCACHE_ERROR_LOG=/var/log/php-opcache.log

# PHP Security Settings (configurable, permissive defaults for base image)
ENV PHP_EXPOSE_PHP=On \
    PHP_DISABLE_FUNCTIONS="" \
    PHP_ALLOW_URL_FOPEN=On \
    PHP_ALLOW_URL_INCLUDE=Off \
    PHP_OPEN_BASEDIR="" \
    PHP_SESSION_COOKIE_HTTPONLY=On \
    PHP_SESSION_COOKIE_SAMESITE=Lax \
    PHP_SESSION_USE_STRICT_MODE=On \
    PHP_CGI_FIX_PATHINFO=0 \
    PHP_MAX_INPUT_VARS=1000

# Install PHP with scoped edge repos (prevents edge repos leaking to downstream images)
RUN set -eux; \
    apk update && apk upgrade; \
    apk add --no-cache \
        --repository=http://dl-cdn.alpinelinux.org/alpine/edge/main \
        --repository=http://dl-cdn.alpinelinux.org/alpine/edge/community \
        --repository=http://dl-cdn.alpinelinux.org/alpine/edge/testing \
        php${PHP_VERSION} \
        php${PHP_VERSION}-cli \
        php${PHP_VERSION}-json \
        php${PHP_VERSION}-mbstring \
        php${PHP_VERSION}-curl \
        php${PHP_VERSION}-xml \
        php${PHP_VERSION}-pdo \
        php${PHP_VERSION}-pdo_mysql \
        php${PHP_VERSION}-zip \
        php${PHP_VERSION}-opcache \
        php${PHP_VERSION}-intl \
        php${PHP_VERSION}-simplexml \
        php${PHP_VERSION}-pcntl \
        php${PHP_VERSION}-fileinfo \
        php${PHP_VERSION}-tokenizer \
        php${PHP_VERSION}-dom \
        php${PHP_VERSION}-posix \
        php${PHP_VERSION}-xmlwriter \
        php${PHP_VERSION}-xmlreader \
        php${PHP_VERSION}-exif \
        php${PHP_VERSION}-soap \
        php${PHP_VERSION}-phar \
        php${PHP_VERSION}-pecl-redis \
        php${PHP_VERSION}-pecl-imagick \
        php${PHP_VERSION}-mysqli \
        php${PHP_VERSION}-gd \
        php${PHP_VERSION}-bcmath \
        php${PHP_VERSION}-ctype \
        php${PHP_VERSION}-iconv \
        php${PHP_VERSION}-session

# Symlink php binary
RUN rm -f /usr/bin/php && ln -s /usr/bin/php${PHP_VERSION} /usr/bin/php

# Install Composer with signature verification
RUN curl -sS https://getcomposer.org/installer -o composer-setup.php && \
    EXPECTED_SIGNATURE="$(curl -sS https://composer.github.io/installer.sig)" && \
    ACTUAL_SIGNATURE="$(php -r "echo hash_file('sha384', 'composer-setup.php');")" && \
    if [ "$EXPECTED_SIGNATURE" != "$ACTUAL_SIGNATURE" ]; then \
        echo "ERROR: Invalid Composer installer signature"; rm composer-setup.php; exit 1; \
    fi && \
    php composer-setup.php --install-dir=/usr/local/bin --filename=composer && \
    rm composer-setup.php

# OCI metadata labels
LABEL org.opencontainers.image.title="adamrollogi/php" \
      org.opencontainers.image.description="PHP CLI with Composer and extensions on Alpine 3.21" \
      org.opencontainers.image.source="https://github.com/adamrollogi/docker" \
      org.opencontainers.image.licenses="MIT"

# Copy entrypoint script
COPY php-entrypoint.sh /usr/local/bin/

# Make the entrypoint script executable
RUN chmod +x /usr/local/bin/php-entrypoint.sh

# Copy the custom PHP ini template
COPY php.ini.template /usr/local/etc/php/

# Set ownership of PHP config and log dirs for non-root runtime
RUN chown -R appuser:appuser \
    /etc/php${PHP_VERSION} \
    /var/log

# Default to non-root user
USER appuser

# Set the entrypoint
ENTRYPOINT ["/sbin/tini", "--", "php-entrypoint.sh"]

# Start Supervisord
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisord.conf"]
