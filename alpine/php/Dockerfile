# PHP is compiled from the php.net source in this build stage, on the same base image as the
# runtime stage below, which copies /usr/local across and installs only the shared libraries
# PHP and its extensions link against.
FROM rollogi/base:latest AS builder

USER root

# PHP_PATCH_VERSION - exact release to build (e.g. 8.3.36, or 8.6.0_rc4 for a pre-release)
# PHP_SOURCE_URL    - tarball URL; defaults to www.php.net/distributions, which only carries
#                     final releases (pre-releases live under the release manager's path on
#                     downloads.php.net, recorded in php-versions.txt)
# PHP_SOURCE_SHA256 - checksum of the tarball; optional, the GPG signature is always checked
ARG PHP_PATCH_VERSION
ARG PHP_SOURCE_URL=""
ARG PHP_SOURCE_SHA256=""
# Space-separated extra extensions for a custom build, e.g. "ldap gmp memcached mongodb amqp".
# Bundled ones are compiled from the PHP source, anything else is the latest stable PECL
# release. The -dev packages for common ones are known below; name others in
# PHP_EXTRA_BUILD_DEPS. The default image adds none to stay small.
ARG PHP_EXTRA_EXTENSIONS=""
ARG PHP_EXTRA_BUILD_DEPS=""

# Set by CI to a hash of the Alpine package indexes (alpine/apk-index-hash.sh) so this layer
# is rebuilt whenever Alpine publishes new packages instead of being reused from the cache
ARG APK_INDEX_HASH=""

# Toolchain plus the -dev packages of every library the default extension set links against
RUN set -eux; \
    extra_deps=""; \
    for ext in ${PHP_EXTRA_EXTENSIONS}; do \
        case "$ext" in \
            amqp)      extra_deps="${extra_deps} rabbitmq-c-dev" ;; \
            bz2)       extra_deps="${extra_deps} bzip2-dev" ;; \
            ffi)       extra_deps="${extra_deps} libffi-dev" ;; \
            gettext)   extra_deps="${extra_deps} gettext-dev" ;; \
            gmp)       extra_deps="${extra_deps} gmp-dev" ;; \
            ldap)      extra_deps="${extra_deps} openldap-dev" ;; \
            memcached) extra_deps="${extra_deps} libmemcached-dev cyrus-sasl-dev" ;; \
            tidy)      extra_deps="${extra_deps} tidyhtml-dev" ;; \
            xsl)       extra_deps="${extra_deps} libxslt-dev" ;; \
            yaml)      extra_deps="${extra_deps} yaml-dev" ;; \
        esac; \
    done; \
    apk upgrade --no-cache; \
    apk add --no-cache \
        autoconf file g++ gcc make musl-dev linux-headers pkgconf \
        gnupg pax-utils xz \
        argon2-dev curl-dev freetype-dev icu-dev imagemagick-dev libedit-dev libjpeg-turbo-dev libpng-dev \
        libpq-dev libsodium-dev libwebp-dev libxml2-dev libzip-dev oniguruma-dev openssl-dev \
        sqlite-dev zlib-dev \
        ${extra_deps} ${PHP_EXTRA_BUILD_DEPS}

# Fetch the tarball, check it against the pinned checksum and the php.net release managers'
# signing keys (php-keyring.asc, from https://www.php.net/distributions/php-keyring.gpg, kept in
# the repository so a compromised download host cannot swap the keys as well), then compile.
# Every extension is built in statically except opcache, which PHP before 8.5 can only build
# as a shared zend_extension; the CLI and FPM SAPIs come from the same build.
COPY php-keyring.asc /usr/src/php-keyring.asc
RUN set -eux; \
    : "${PHP_PATCH_VERSION:?set PHP_PATCH_VERSION to the release to build, e.g. 8.3.36}"; \
    upstream="$(printf '%s' "${PHP_PATCH_VERSION}" | sed -e 's/_rc/RC/' -e 's/_alpha/alpha/' -e 's/_beta/beta/')"; \
    url="${PHP_SOURCE_URL:-https://www.php.net/distributions/php-${upstream}.tar.xz}"; \
    cd /usr/src; \
    curl -fsSL -o php.tar.xz "${url}"; \
    curl -fsSL -o php.tar.xz.asc "${url}.asc"; \
    if [ -n "${PHP_SOURCE_SHA256}" ]; then \
        echo "${PHP_SOURCE_SHA256}  php.tar.xz" | sha256sum -c -; \
    fi; \
    gpg --batch --dearmor < php-keyring.asc > php-keyring.gpg; \
    gpgv --keyring /usr/src/php-keyring.gpg php.tar.xz.asc php.tar.xz; \
    mkdir php; \
    tar -xJf php.tar.xz -C php --strip-components=1; \
    cd php; \
    ./configure \
        --prefix=/usr/local \
        --with-config-file-path=/usr/local/etc/php \
        --with-config-file-scan-dir=/usr/local/etc/php/conf.d \
        --disable-cgi \
        --disable-phpdbg \
        --enable-fpm \
        --enable-bcmath \
        --enable-exif \
        --enable-gd \
        --with-freetype \
        --with-jpeg \
        --with-webp \
        --enable-intl \
        --enable-mbstring \
        --enable-mysqlnd \
        --with-mysqli=mysqlnd \
        --with-pdo-mysql=mysqlnd \
        --with-pgsql \
        --with-pdo-pgsql \
        --with-sqlite3 \
        --with-pdo-sqlite \
        --enable-opcache \
        --enable-pcntl \
        --enable-soap \
        --enable-sockets \
        --with-curl \
        --with-openssl \
        --with-password-argon2 \
        --with-sodium \
        --with-libedit \
        --with-zip \
        --with-zlib; \
    make -j"$(nproc)"; \
    make install; \
    strip --strip-all /usr/local/bin/php /usr/local/sbin/php-fpm; \
    rm -rf /usr/local/php; \
    mkdir -p /usr/local/etc/php/conf.d; \
    if [ -f "$(php-config --extension-dir)/opcache.so" ]; then \
        echo 'zend_extension=opcache' > /usr/local/etc/php/conf.d/10-opcache.ini; \
    fi

# PECL extensions from pecl-extensions.txt (the "php" lines for this minor), then any extras.
# Finally record the shared libraries everything links against, for the runtime stage.
COPY php-ext-install /usr/local/bin/php-ext-install
COPY pecl-extensions.txt /usr/local/etc/php/pecl-extensions.txt
RUN set -eux; \
    minor="${PHP_PATCH_VERSION%.*}"; \
    grep -Ev '^[[:space:]]*(#|$)' /usr/local/etc/php/pecl-extensions.txt \
    | while read -r image name source sha256 minors; do \
        [ "$image" = php ] || continue; \
        case " ${minors} " in \
            *" * "*|*" ${minor} "*) ;; \
            *) continue ;; \
        esac; \
        opts=""; \
        [ "$name" = redis ] && opts="--enable-redis-igbinary --enable-redis-msgpack"; \
        php-ext-install "$name" "$source" "$sha256" -- ${opts}; \
    done; \
    for ext in ${PHP_EXTRA_EXTENSIONS}; do \
        php-ext-install "$ext"; \
    done; \
    scanelf --needed --nobanner --format '%n#p' --recursive /usr/local \
        | tr ',' '\n' | sort -u \
        | awk 'system("[ -e /usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }' \
        > /usr/local/lib/php/runtime-deps.txt; \
    cat /usr/local/lib/php/runtime-deps.txt; \
    php -m

FROM rollogi/base:latest

# Switch to root for package installation
USER root

# PHP_VERSION is the minor without dots (e.g. 83), kept for the Alpine-era command names
# (php83, php-fpm83) and log directories; PHP_PATCH_VERSION is the release compiled above
ARG PHP_VERSION
ARG PHP_PATCH_VERSION
ARG PHP_EXTRA_EXTENSIONS=""

# Expose both so downstream images (php-nginx, php-fpm) can check the release they run
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

# Composer: home and cache under /tmp so it works for any UID (including --user) and on a
# read-only root filesystem; non-interactive and quiet about funding; no superuser warning in
# root mode; no memory limit for dependency resolution. Mount the cache in your own builds with
# RUN --mount=type=cache,target=/tmp/composer/cache composer install
ENV COMPOSER_HOME=/tmp/composer \
    COMPOSER_CACHE_DIR=/tmp/composer/cache \
    COMPOSER_ALLOW_SUPERUSER=1 \
    COMPOSER_NO_INTERACTION=1 \
    COMPOSER_FUND=0 \
    COMPOSER_MEMORY_LIMIT=-1 \
    COMPOSER_PROCESS_TIMEOUT=600

# Optional one-off command run before the main command or the services start (see entrypoint-lib)
ENV APP_INSTALL="" \
    APP_INSTALL_DIR=/app


# PHP itself: binaries, extensions, headers and phpize (so php-ext-install works in derived
# images), and the scan directory with the ini files that load the shared extensions
COPY --from=builder /usr/local /usr/local

# Set by CI to a hash of the Alpine package indexes (alpine/apk-index-hash.sh) so this layer
# is rebuilt whenever Alpine publishes new packages instead of being reused from the cache
ARG APK_INDEX_HASH=""

# Runtime libraries recorded by the build stage, msmtp for mail(), and the Alpine release's
# security fixes. The installed version is checked against the pin, and the Alpine-era command
# names keep working for scripts that call php83 or /usr/sbin/php-fpm.
RUN set -eux; \
    apk upgrade --no-cache; \
    apk add --no-cache $(cat /usr/local/lib/php/runtime-deps.txt) msmtp; \
    installed="$(php -r 'echo strtolower(PHP_VERSION);')"; \
    expected="$(printf '%s' "${PHP_PATCH_VERSION}" | tr -d '_' | tr 'A-Z' 'a-z')"; \
    if [ "${installed}" != "${expected}" ]; then \
        echo "ERROR: built PHP ${PHP_PATCH_VERSION} but ${installed} is installed"; exit 1; \
    fi; \
    startup="$(php -r '' 2>&1)"; \
    if [ -n "${startup}" ]; then \
        echo "ERROR: PHP prints startup messages:"; echo "${startup}"; exit 1; \
    fi; \
    ln -s /usr/local/bin/php /usr/bin/php; \
    ln -s /usr/local/sbin/php-fpm /usr/sbin/php-fpm; \
    if [ -n "${PHP_VERSION}" ]; then \
        ln -s /usr/local/bin/php "/usr/bin/php${PHP_VERSION}"; \
        ln -s /usr/local/sbin/php-fpm "/usr/sbin/php-fpm${PHP_VERSION}"; \
    fi; \
    find / -xdev -type f -perm /6000 -exec chmod a-s {} +

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
LABEL org.opencontainers.image.title="rollogi/php" \
      org.opencontainers.image.description="PHP CLI and FPM compiled from the php.net source, with Composer and extensions, on Alpine 3.24" \
      org.opencontainers.image.version="${PHP_PATCH_VERSION}" \
      org.opencontainers.image.source="https://github.com/AdamRollinson/docker" \
      org.opencontainers.image.licenses="MIT" \
      io.rollogi.php.extra-extensions="${PHP_EXTRA_EXTENSIONS}"

# Copy entrypoint script (shared helpers come from the base image at /usr/local/lib/entrypoint-lib.sh)
COPY php-entrypoint.sh /usr/local/bin/

# Make the entrypoint script executable
RUN chmod +x /usr/local/bin/php-entrypoint.sh

# Copy the PHP ini, msmtp and PHP-FPM pool templates (the pool template is used by php-nginx
# and php-fpm through render_fpm_config in entrypoint-lib.sh)
COPY php.ini.template msmtprc.template www.conf.template /usr/local/etc/php/

# Runtime-rendered config goes to /run/php; /etc/php* stays root-owned. Runtime state
# directories are sticky and world-writable so any --user can render its config and write logs.
RUN mkdir -p /run/php && \
    chown -R appuser:appuser /run/php /var/log && \
    chmod -R a+rwX /run/php /var/log && \
    find /run/php /var/log -type d -exec chmod +t {} +

# Default to non-root user
USER appuser

# Set the entrypoint
ENTRYPOINT ["/sbin/tini", "--", "php-entrypoint.sh"]

# A CLI image: the default command just reports the PHP version. Pass your own command, or set
# CLI_COMMAND to run a long-lived worker (see php-entrypoint.sh).
CMD ["php", "-v"]
