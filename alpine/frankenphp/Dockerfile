# FrankenPHP: Caddy with PHP embedded, built from source in two build stages on the same base
# image as the runtime stage. The build context is alpine/ (not this directory) so the PHP
# keyring, php-ext-install and pecl-extensions.txt are shared with the php image, not copied.
#
#   docker build -f alpine/frankenphp/Dockerfile --build-arg PHP_PATCH_VERSION=8.4.27 alpine
#
# FrankenPHP needs a thread-safe PHP built as a library (libphp.so), which is why it compiles
# its own PHP instead of building on rollogi/php: same release, checks and extensions, but ZTS.
FROM rollogi/base:latest AS builder

USER root

# PHP_PATCH_VERSION, PHP_SOURCE_URL and PHP_SOURCE_SHA256 work exactly as in alpine/php/Dockerfile
ARG PHP_PATCH_VERSION
ARG PHP_SOURCE_URL=""
ARG PHP_SOURCE_SHA256=""

# Set by CI to a hash of the Alpine package indexes (alpine/apk-index-hash.sh) so this layer
# is rebuilt whenever Alpine publishes new packages instead of being reused from the cache
ARG APK_INDEX_HASH=""

# Toolchain plus the -dev packages of every library the extension set links against, brotli for
# Caddy's compression, and Alpine's Go, which only bootstraps the pinned toolchain below
RUN set -eux; \
    apk upgrade --no-cache; \
    apk add --no-cache \
        autoconf file g++ gcc make musl-dev linux-headers pkgconf \
        gnupg pax-utils xz go \
        argon2-dev brotli-dev curl-dev freetype-dev icu-dev imagemagick-dev libedit-dev \
        libjpeg-turbo-dev libpng-dev libpq-dev libsodium-dev libwebp-dev libxml2-dev libzip-dev \
        oniguruma-dev openssl-dev sqlite-dev zlib-dev

# Same verification as the php image (pinned checksum, then the release managers' signature),
# configured with the php image's extension set plus FrankenPHP's required flags: thread safety,
# the embed SAPI (libphp.so), no Zend signal handling, and per-thread execution timers
COPY php/php-keyring.asc /usr/src/php-keyring.asc
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
        --enable-embed \
        --enable-zts \
        --disable-zend-signals \
        --enable-zend-max-execution-timers \
        --disable-cgi \
        --disable-phpdbg \
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
    strip --strip-all /usr/local/bin/php /usr/local/lib/libphp.so; \
    rm -rf /usr/local/php; \
    mkdir -p /usr/local/etc/php/conf.d; \
    if [ -f "$(php-config --extension-dir)/opcache.so" ]; then \
        echo 'zend_extension=opcache' > /usr/local/etc/php/conf.d/10-opcache.ini; \
    fi

# The "php" PECL lines for this minor, exactly as in the php image
COPY php/php-ext-install /usr/local/bin/php-ext-install
COPY php/pecl-extensions.txt /usr/local/etc/php/pecl-extensions.txt
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
    php -m

# FrankenPHP from the pinned release tarball, built the way its own Alpine image does but with
# the go command directly. Build tags: nowatcher drops file-change worker restarts (a C library
# that is only useful in development) and nomercure keeps the AGPL-licensed Mercure hub out of
# the binary; the rest are FrankenPHP's own defaults. The larger thread stack matters on musl,
# whose 128 KiB default is too small for PHP's compiler on deep expressions.
COPY frankenphp/frankenphp-version.txt /usr/src/frankenphp-version.txt
RUN set -eux; \
    version="$(awk '$1 == "frankenphp" { print $2 }' /usr/src/frankenphp-version.txt)"; \
    sha256="$(awk '$1 == "frankenphp" { print $3 }' /usr/src/frankenphp-version.txt)"; \
    go_version="$(awk '$1 == "go" { print $2 }' /usr/src/frankenphp-version.txt)"; \
    cd /usr/src; \
    curl -fsSL -o frankenphp.tar.gz "https://github.com/php/frankenphp/archive/refs/tags/v${version}.tar.gz"; \
    echo "${sha256}  frankenphp.tar.gz" | sha256sum -c -; \
    mkdir frankenphp; \
    tar -xzf frankenphp.tar.gz -C frankenphp --strip-components=1; \
    cd frankenphp/caddy/frankenphp; \
    php_version="$(php-config --version)"; \
    hardening="-fstack-protector-strong -fpic -fpie -O2 -D_LARGEFILE_SOURCE -D_FILE_OFFSET_BITS=64"; \
    GOTOOLCHAIN="go${go_version}" \
    GOFLAGS="-tags=nobadger,nomysql,nopgx,deprecated_topic,deprecated_claim,nowatcher,nomercure" \
    CGO_ENABLED=1 \
    CGO_CFLAGS="-DFRANKENPHP_VERSION=${version} ${hardening} $(php-config --includes) $(sh ../../mtls-cflags.sh)" \
    CGO_CPPFLAGS="${hardening}" \
    CGO_LDFLAGS="-Wl,-O1 -pie $(php-config --ldflags) $(php-config --libs)" \
    go build -trimpath -o /usr/local/bin/frankenphp \
        -ldflags "-w -s -extldflags '-Wl,-z,stack-size=0x80000' -X 'github.com/caddyserver/caddy/v2.CustomVersion=FrankenPHP ${version} PHP ${php_version} Caddy' -X 'github.com/caddyserver/caddy/v2.CustomBinaryName=frankenphp' -X 'github.com/caddyserver/caddy/v2/modules/caddyhttp.ServerHeader=FrankenPHP'"; \
    rm -rf /root/go /root/.cache; \
    frankenphp version; \
    scanelf --needed --nobanner --format '%n#p' --recursive /usr/local \
        | tr ',' '\n' | sort -u \
        | awk 'system("[ -e /usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }' \
        > /usr/local/lib/php/runtime-deps.txt; \
    cat /usr/local/lib/php/runtime-deps.txt

FROM rollogi/base:latest

USER root

# PHP_VERSION is the minor without dots (e.g. 84), as in the php image; PHP_PATCH_VERSION is the
# release compiled above
ARG PHP_VERSION
ARG PHP_PATCH_VERSION

ENV PHP_VERSION=${PHP_VERSION} \
    PHP_PATCH_VERSION=${PHP_PATCH_VERSION}

# Rendered php.ini lives in /run/php (see entrypoint), keeping /usr/local/etc/php root-owned
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

# FrankenPHP and Caddy. SERVER_NAME is Caddy's site address: the default ":80" serves plain HTTP
# on port 80; a host name (app.example.com) turns on Caddy's automatic HTTPS on 80 and 443.
# FRANKENPHP_WORKER is a worker script to keep in memory between requests (empty = classic
# mode); FRANKENPHP_CONFIG and the CADDY_* variables are spliced into the Caddyfile as they are.
# Caddy keeps certificates in XDG_DATA_HOME and its autosaved config in XDG_CONFIG_HOME.
ENV SERVER_NAME=":80" \
    SERVER_ROOT=/app/public \
    FRANKENPHP_WORKER="" \
    FRANKENPHP_WORKER_NUM="" \
    FRANKENPHP_NUM_THREADS="" \
    FRANKENPHP_CONFIG="" \
    CADDY_GLOBAL_OPTIONS="" \
    CADDY_EXTRA_CONFIG="" \
    CADDY_SERVER_EXTRA_DIRECTIVES="" \
    XDG_CONFIG_HOME=/config \
    XDG_DATA_HOME=/data \
    GODEBUG=cgocheck=0

# PHP, libphp.so, the frankenphp binary, headers and phpize (so php-ext-install works in derived
# images, against the ZTS build), and the scan directory with the ini files for the extensions
COPY --from=builder /usr/local /usr/local

# Set by CI to a hash of the Alpine package indexes (alpine/apk-index-hash.sh) so this layer
# is rebuilt whenever Alpine publishes new packages instead of being reused from the cache
ARG APK_INDEX_HASH=""

# Runtime libraries recorded by the build stage, msmtp for mail(), mailcap for the file server's
# MIME types, and the Alpine release's security fixes; then check the version both SAPIs report
RUN set -eux; \
    apk upgrade --no-cache; \
    apk add --no-cache $(cat /usr/local/lib/php/runtime-deps.txt) msmtp mailcap; \
    installed="$(php -r 'echo strtolower(PHP_VERSION);')"; \
    expected="$(printf '%s' "${PHP_PATCH_VERSION}" | tr -d '_' | tr 'A-Z' 'a-z')"; \
    if [ "${installed}" != "${expected}" ]; then \
        echo "ERROR: built PHP ${PHP_PATCH_VERSION} but ${installed} is installed"; exit 1; \
    fi; \
    php -r 'exit(PHP_ZTS ? 0 : 1);' || { echo "ERROR: PHP is not thread safe"; exit 1; }; \
    startup="$(php -r '' 2>&1)"; \
    if [ -n "${startup}" ]; then \
        echo "ERROR: PHP prints startup messages:"; echo "${startup}"; exit 1; \
    fi; \
    frankenphp version | tr 'A-Z' 'a-z' | grep -q "php ${installed}" \
        || { echo "ERROR: frankenphp does not embed PHP ${installed}: $(frankenphp version)"; exit 1; }; \
    ln -s /usr/local/bin/php /usr/bin/php; \
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
LABEL org.opencontainers.image.title="rollogi/frankenphp" \
      org.opencontainers.image.description="FrankenPHP (Caddy with PHP embedded) compiled from source, with Composer and extensions, on Alpine 3.24" \
      org.opencontainers.image.version="${PHP_PATCH_VERSION}" \
      org.opencontainers.image.source="https://github.com/AdamRollinson/docker" \
      org.opencontainers.image.licenses="MIT"

# Caddyfile (root-owned; Caddy resolves its {$VAR} placeholders itself, so nothing is rendered
# into /etc), entrypoint, healthcheck and the php.ini and msmtp templates the entrypoint renders
COPY frankenphp/Caddyfile /etc/frankenphp/Caddyfile
COPY frankenphp/frankenphp-entrypoint.sh frankenphp/frankenphp-healthcheck /usr/local/bin/
COPY php/php.ini.template php/msmtprc.template /usr/local/etc/php/
COPY frankenphp/index.php /app/public/index.php

# Runtime state directories are sticky and world-writable so any --user can render config, keep
# Caddy's data and write logs; /etc and /usr stay root-owned
RUN set -eux; \
    chmod 755 /usr/local/bin/frankenphp-entrypoint.sh /usr/local/bin/frankenphp-healthcheck; \
    chmod 644 /etc/frankenphp/Caddyfile /app/public/index.php; \
    mkdir -p /run/php /data /config /var/log/frankenphp /etc/frankenphp/Caddyfile.d; \
    for dir in /run/php /data /config /var/log; do \
        chown -R appuser:appuser "$dir"; \
        chmod -R a+rwX "$dir"; \
        find "$dir" -type d -exec chmod +t {} +; \
    done

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD frankenphp-healthcheck

ENTRYPOINT ["/sbin/tini", "--", "frankenphp-entrypoint.sh"]

EXPOSE 80 443 443/udp

WORKDIR /app

USER appuser

# "serve" runs FrankenPHP (plus cron when jobs are configured) under the entrypoint's
# supervision; any other command is executed as-is
CMD ["serve"]
