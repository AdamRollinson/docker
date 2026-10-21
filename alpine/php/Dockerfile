# Use the updated base image
FROM adamrollogi/base:latest

# Switch to root for package installation
USER root

# Define build-time arguments for the PHP version:
#   PHP_VERSION       - minor version without dots, used in Alpine package names (e.g. 83)
#   PHP_PATCH_VERSION - exact release to pin (e.g. 8.3.35); empty installs whatever edge has
ARG PHP_VERSION
ARG PHP_PATCH_VERSION

# Expose both so downstream images (php-nginx) install a matching php-fpm
ENV PHP_VERSION=${PHP_VERSION} \
    PHP_PATCH_VERSION=${PHP_PATCH_VERSION}

# Rendered php.ini lives in /run/php (see entrypoint), keeping /etc/php* root-owned
ENV PHPRC=/run/php

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
ENV PHP_EXPOSE_PHP=Off \
    PHP_DISABLE_FUNCTIONS="" \
    PHP_ALLOW_URL_FOPEN=On \
    PHP_ALLOW_URL_INCLUDE=Off \
    PHP_OPEN_BASEDIR="" \
    PHP_SESSION_COOKIE_HTTPONLY=On \
    PHP_SESSION_COOKIE_SECURE="" \
    PHP_SESSION_COOKIE_SAMESITE=Lax \
    PHP_SESSION_USE_STRICT_MODE=On \
    PHP_CGI_FIX_PATHINFO=0 \
    PHP_MAX_INPUT_VARS=1000 \
    PHP_SENDMAIL_PATH=""

# Outbound mail: when SMTP_HOST is set the entrypoint renders an msmtp configuration and points
# PHP's sendmail_path at it, so mail() and framework "sendmail" transports relay through SMTP
ENV SMTP_HOST="" \
    SMTP_PORT=587 \
    SMTP_USER="" \
    SMTP_PASSWORD="" \
    SMTP_FROM="" \
    SMTP_TLS="" \
    SMTP_TLS_STARTTLS="" \
    SMTP_AUTH=""

# Worker mode: when CLI_COMMAND is set and the image is started with its default command,
# the entrypoint runs CLI_COMMAND and restarts it whenever it exits (see php-entrypoint.sh)
ENV CLI_COMMAND="" \
    CLI_RESTART_DELAY=2 \
    CLI_MAX_RESTARTS=0

# Install PHP with scoped edge repos (prevents edge repos leaking to downstream images).
# Every PHP package carries the same release pin. Alpine's extension packages depend on
# php${PHP_VERSION}-common WITHOUT a version constraint, so when edge rolls to a new release
# an unpinned extension would be installed against the pinned (older) core and fail to load
# (ABI mismatch). -cli and -json are virtual names provided by the pinned core/common packages
# and cannot be constrained; pecl-* packages have their own version numbers. common, openssl,
# sockets and mysqlnd are listed explicitly because apk would otherwise pull them in unpinned
# as dependencies, and a final check below rejects any php package at a different release.
RUN set -eux; \
    apk update && apk upgrade; \
    apk add --no-cache \
        --repository=https://dl-cdn.alpinelinux.org/alpine/edge/main \
        --repository=https://dl-cdn.alpinelinux.org/alpine/edge/community \
        --repository=https://dl-cdn.alpinelinux.org/alpine/edge/testing \
        php${PHP_VERSION}${PHP_PATCH_VERSION:+~${PHP_PATCH_VERSION}} \
        php${PHP_VERSION}-common${PHP_PATCH_VERSION:+~${PHP_PATCH_VERSION}} \
        php${PHP_VERSION}-openssl${PHP_PATCH_VERSION:+~${PHP_PATCH_VERSION}} \
        php${PHP_VERSION}-sockets${PHP_PATCH_VERSION:+~${PHP_PATCH_VERSION}} \
        php${PHP_VERSION}-mysqlnd${PHP_PATCH_VERSION:+~${PHP_PATCH_VERSION}} \
        php${PHP_VERSION}-cli \
        php${PHP_VERSION}-json \
        php${PHP_VERSION}-mbstring${PHP_PATCH_VERSION:+~${PHP_PATCH_VERSION}} \
        php${PHP_VERSION}-curl${PHP_PATCH_VERSION:+~${PHP_PATCH_VERSION}} \
        php${PHP_VERSION}-xml${PHP_PATCH_VERSION:+~${PHP_PATCH_VERSION}} \
        php${PHP_VERSION}-pdo${PHP_PATCH_VERSION:+~${PHP_PATCH_VERSION}} \
        php${PHP_VERSION}-pdo_mysql${PHP_PATCH_VERSION:+~${PHP_PATCH_VERSION}} \
        php${PHP_VERSION}-zip${PHP_PATCH_VERSION:+~${PHP_PATCH_VERSION}} \
        php${PHP_VERSION}-intl${PHP_PATCH_VERSION:+~${PHP_PATCH_VERSION}} \
        php${PHP_VERSION}-simplexml${PHP_PATCH_VERSION:+~${PHP_PATCH_VERSION}} \
        php${PHP_VERSION}-pcntl${PHP_PATCH_VERSION:+~${PHP_PATCH_VERSION}} \
        php${PHP_VERSION}-fileinfo${PHP_PATCH_VERSION:+~${PHP_PATCH_VERSION}} \
        php${PHP_VERSION}-tokenizer${PHP_PATCH_VERSION:+~${PHP_PATCH_VERSION}} \
        php${PHP_VERSION}-dom${PHP_PATCH_VERSION:+~${PHP_PATCH_VERSION}} \
        php${PHP_VERSION}-posix${PHP_PATCH_VERSION:+~${PHP_PATCH_VERSION}} \
        php${PHP_VERSION}-xmlwriter${PHP_PATCH_VERSION:+~${PHP_PATCH_VERSION}} \
        php${PHP_VERSION}-xmlreader${PHP_PATCH_VERSION:+~${PHP_PATCH_VERSION}} \
        php${PHP_VERSION}-exif${PHP_PATCH_VERSION:+~${PHP_PATCH_VERSION}} \
        php${PHP_VERSION}-soap${PHP_PATCH_VERSION:+~${PHP_PATCH_VERSION}} \
        php${PHP_VERSION}-phar${PHP_PATCH_VERSION:+~${PHP_PATCH_VERSION}} \
        php${PHP_VERSION}-pecl-redis \
        php${PHP_VERSION}-mysqli${PHP_PATCH_VERSION:+~${PHP_PATCH_VERSION}} \
        php${PHP_VERSION}-gd${PHP_PATCH_VERSION:+~${PHP_PATCH_VERSION}} \
        php${PHP_VERSION}-bcmath${PHP_PATCH_VERSION:+~${PHP_PATCH_VERSION}} \
        php${PHP_VERSION}-ctype${PHP_PATCH_VERSION:+~${PHP_PATCH_VERSION}} \
        php${PHP_VERSION}-iconv${PHP_PATCH_VERSION:+~${PHP_PATCH_VERSION}} \
        php${PHP_VERSION}-session${PHP_PATCH_VERSION:+~${PHP_PATCH_VERSION}}; \
    # Optional packages: opcache is compiled into the core package from PHP 8.5, and
    # pecl-imagick lags new PHP majors in Alpine. Missing ones are reported, not fatal.
    for optional in "opcache${PHP_PATCH_VERSION:+~${PHP_PATCH_VERSION}}" pecl-imagick; do \
        apk add --no-cache \
            --repository=https://dl-cdn.alpinelinux.org/alpine/edge/main \
            --repository=https://dl-cdn.alpinelinux.org/alpine/edge/community \
            --repository=https://dl-cdn.alpinelinux.org/alpine/edge/testing \
            "php${PHP_VERSION}-${optional}" 2>/dev/null \
            || echo "NOTICE: php${PHP_VERSION}-${optional%%~*} is not packaged for this PHP version"; \
    done; \
    apk add --no-cache msmtp; \
    # Pre-releases differ in spelling between apk (8.6.0_rc3) and PHP (8.6.0RC3); normalise both
    if [ -n "${PHP_PATCH_VERSION}" ]; then \
        installed="$(php${PHP_VERSION} -r 'echo strtolower(PHP_VERSION);')"; \
        expected="$(printf '%s' "${PHP_PATCH_VERSION}" | tr -d '_' | tr 'A-Z' 'a-z')"; \
        if [ "${installed}" != "${expected}" ]; then \
            echo "ERROR: pinned PHP ${PHP_PATCH_VERSION} but ${installed} was installed"; exit 1; \
        fi; \
        # Every php package that is not a PECL extension must carry the pinned release, including
        # ones apk pulled in as dependencies; a stray newer package means mismatched extensions
        mismatched="$(apk list -I 2>/dev/null | awk '{print $1}' | grep "^php${PHP_VERSION}" | grep -v -- '-pecl-' | grep -v -- "-${PHP_PATCH_VERSION}-r" || true)"; \
        if [ -n "${mismatched}" ]; then \
            echo "ERROR: these php${PHP_VERSION} packages do not match the pinned release ${PHP_PATCH_VERSION}:"; echo "${mismatched}"; exit 1; \
        fi; \
    fi; \
    find / -xdev -type f -perm /6000 -exec chmod a-s {} +

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
      org.opencontainers.image.description="PHP CLI with Composer and extensions on Alpine 3.24" \
      org.opencontainers.image.version="${PHP_PATCH_VERSION}" \
      org.opencontainers.image.source="https://github.com/adamrollogi/docker" \
      org.opencontainers.image.licenses="MIT"

# Copy entrypoint script (shared helpers come from the base image at /usr/local/lib/entrypoint-lib.sh)
COPY php-entrypoint.sh /usr/local/bin/

# Make the entrypoint script executable
RUN chmod +x /usr/local/bin/php-entrypoint.sh

# Copy the custom PHP ini and msmtp templates
COPY php.ini.template msmtprc.template /usr/local/etc/php/

# Runtime-rendered config goes to /run/php; /etc/php* stays root-owned
RUN mkdir -p /run/php && \
    chown -R appuser:appuser /run/php /var/log

# Default to non-root user
USER appuser

# Set the entrypoint
ENTRYPOINT ["/sbin/tini", "--", "php-entrypoint.sh"]

# A CLI image: the default command just reports the PHP version. Pass your own command, or set
# CLI_COMMAND to run a long-lived worker (see php-entrypoint.sh).
CMD ["php", "-v"]
