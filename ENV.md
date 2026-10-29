# Environment Variables Documentation

## `alpine/base/Dockerfile`

### Logging
- **`LOG_MODE`**: `stdout` (default) sends every service's output to the container's stdout/stderr; `file` writes one file per service under `/var/log` (`nginx/access.log`, `nginx/error.log`, `php-fpm/error.log`, `php-fpm/slow.log`, `cron.log`).
- **`LOG_FORMAT`**: `text` (default) prefixes each line with `[service]`; `json` emits one JSON object per line with `time`, `service`, `stream` and `message`, and switches the nginx access log to the structured `json_combined` format.
- **`LOG_TAG`**: `true` (default) adds the `[service]` prefixes in text mode; `false` leaves lines untouched. Ignored in json and file modes.
- Services are launched through `/usr/local/bin/run-service <name> <command>`, which implements the tagging; `container-logs [-f] [service|all]` tails the per-service files in file mode.

### Mail relay
- **`SMTP_HOST`**: SMTP server to relay through. When set, the entrypoint renders `/run/php/msmtprc` and sets `sendmail_path` to msmtp (unless `PHP_SENDMAIL_PATH` is given).
- **`SMTP_PORT`**: Default `587`.
- **`SMTP_USER`**, **`SMTP_PASSWORD`**: Credentials. AUTH is enabled automatically when a user is set.
- **`SMTP_FROM`**: Envelope sender. Default `noreply@<container hostname>`.
- **`SMTP_TLS`**, **`SMTP_TLS_STARTTLS`**, **`SMTP_AUTH`**: `on`/`off` overrides. Defaults: port 465 is TLS without STARTTLS, ports 25 and 1025 are plain, everything else is STARTTLS.

### Worker mode (php image)
- **`CLI_COMMAND`**: Command to run as a long-lived worker. Used when the image starts with its default command or the `worker` command; restarted whenever it exits. Output is tagged `[worker]`.
- **`CLI_RESTART_DELAY`**: Seconds to wait before restarting the worker. Default `2`.
- **`CLI_MAX_RESTARTS`**: Give up after this many restarts and exit with the worker's status. Default `0` (unlimited).

### Startup command
- **`APP_INSTALL`**: Command run once at startup, before the main command (php image) or before php-fpm and nginx start (php-nginx). Output tagged `[install]`; a non-zero exit stops the container with that status.
- **`APP_INSTALL_DIR`**: Directory the command runs in. Default `/app` (php) or `/var/www/html` (php-nginx).

### Composer
Standard Composer variables with container-friendly defaults: **`COMPOSER_HOME`** `/tmp/composer`, **`COMPOSER_CACHE_DIR`** `/tmp/composer/cache`, **`COMPOSER_ALLOW_SUPERUSER`** `1`, **`COMPOSER_NO_INTERACTION`** `1`, **`COMPOSER_FUND`** `0`, **`COMPOSER_MEMORY_LIMIT`** `-1`, **`COMPOSER_PROCESS_TIMEOUT`** `600`. Override any of them as usual.

### Cron
- **`CRON_SCHEDULE`**: Schedule for the single job defined by `CRON_COMMAND`. Default `* * * * *` (every minute). Standard five fields, or seven with leading seconds and trailing year.
- **`CRON_COMMAND`**: Command to run on `CRON_SCHEDULE`. When set, supercronic is started alongside the web services (php-nginx) or by the `cron` command (php image).
- **`CRONTAB_FILE`**: Path of a mounted crontab with any number of jobs. Default `/etc/crontabs/app`. Used in addition to `CRON_COMMAND` when both exist.

## `alpine/php/Dockerfile`

### PHP General Settings
- **`PHP_VERSION`**: The PHP minor without the dot, e.g. `83`. Used for the Alpine-era command names (`php83`, `php-fpm83`, symlinks to the compiled binaries) and log directories.
- **`PHP_PATCH_VERSION`**: Build argument (also exported as an environment variable) naming the exact PHP release compiled into the image, e.g. `8.3.36`. Required. Set from `alpine/php-versions.txt` by the build script and CI.
- **`PHP_SOURCE_URL`** / **`PHP_SOURCE_SHA256`**: Build arguments for the tarball location and checksum, from `alpine/php-versions.txt`. The URL defaults to `www.php.net/distributions` (final releases only); the checksum is optional, the GPG signature is always checked.
- **`PHP_EXTRA_EXTENSIONS`** / **`PHP_EXTRA_BUILD_DEPS`**: Build arguments for extra extensions (bundled ones compiled from the PHP source, others from the latest stable PECL release) and any `-dev` packages they need beyond the built-in list.
- **`PHPRC`**: Set to `/run/php`, where the entrypoint renders `php.ini`. The compiled-in configuration under `/usr/local/etc/php` (including the `conf.d` scan directory) remains root-owned.
- **`PHP_EXPOSE_PHP`**: Controls the `X-Powered-By` header. Default is `Off`.
- **`PHP_SESSION_COOKIE_SECURE`**: Adds the `Secure` flag to session cookies. Empty by default, which resolves to `Off` in the CLI image and to `On` in php-nginx when `NGINX_SSL_ENABLED=true`.
- **`PHP_SENDMAIL_PATH`**: Sets `sendmail_path`. Empty by default, which keeps PHP's built-in default. Use `/usr/bin/msmtp -t` or similar when a mail relay binary is installed.
- **`php.<setting>`**: Any environment variable with this prefix is appended to php.ini as `<setting> = <value>` after the templated settings, e.g. `php.memory_limit=256M`. Works in every image.
- **`PHP_MEMORY_LIMIT`**: Sets the maximum amount of memory a script may consume. Default is `128M`.
- **`PHP_UPLOAD_MAX_FILESIZE`**: Defines the maximum size of an uploaded file. Default is `2M`.
- **`PHP_POST_MAX_SIZE`**: Sets the maximum size of POST data that PHP will accept. Default is `2M`.
- **`PHP_MAX_INPUT_TIME`**: Limits the time in seconds a script is allowed to parse input data. Default is `60`.
- **`PHP_MAX_EXECUTION_TIME`**: Limits the maximum execution time of each script in seconds. Default is `30`.
- **`PHP_DISPLAY_ERRORS`**: Determines whether errors should be printed to the screen. Default is `Off`.
- **`PHP_ERROR_REPORTING`**: Sets the error reporting level. Default is `"E_ALL & ~E_DEPRECATED & ~E_STRICT"`.
- **`PHP_DATE_TIMEZONE`**: Sets the default timezone used by all date/time functions. Default is `UTC`.

### PHP Security Settings
- **`PHP_EXPOSE_PHP`**: Controls whether PHP version is exposed via `X-Powered-By` header. Default is `On`. **Production recommended: `Off`**
- **`PHP_DISABLE_FUNCTIONS`**: Comma-separated list of functions to disable. Default is `""` (none disabled). **Production recommended: `exec,passthru,shell_exec,system,proc_open,popen`**
- **`PHP_ALLOW_URL_FOPEN`**: Whether to allow URL-aware fopen wrappers. Default is `On`. **Production recommended: `Off`** (unless needed)
- **`PHP_ALLOW_URL_INCLUDE`**: Whether to allow `include`/`require` for URL-aware fopen wrappers. Default is `Off`.
- **`PHP_OPEN_BASEDIR`**: Limits the files PHP can access to the specified directory tree. Default is `""` (unrestricted). **Production recommended: `/var/www/html:/tmp`**
- **`PHP_SESSION_COOKIE_HTTPONLY`**: Marks session cookies as HTTP-only (inaccessible to JavaScript). Default is `On`.
- **`PHP_SESSION_COOKIE_SAMESITE`**: Sets the SameSite attribute for session cookies. Default is `Lax`.
- **`PHP_SESSION_USE_STRICT_MODE`**: Enables strict session ID mode, rejecting uninitialized session IDs. Default is `On`.
- **`PHP_CGI_FIX_PATHINFO`**: Controls `cgi.fix_pathinfo` for proper path handling in PHP-FPM. Default is `0` (disabled).
- **`PHP_MAX_INPUT_VARS`**: Maximum number of input variables accepted per request. Default is `1000`.

### OPcache Settings
- **`OPCACHE_ENABLE`**: Enables or disables the OPcache. Default is `0`.
- **`OPCACHE_ENABLE_CLI`**: Enables or disables the OPcache for the CLI version of PHP. Default is `0`.
- **`OPCACHE_MEMORY_CONSUMPTION`**: Sets the OPcache memory consumption. Default is `128`.
- **`OPCACHE_INTERNED_STRINGS_BUFFER`**: Sets the amount of memory for interned strings in megabytes. Default is `8`.
- **`OPCACHE_MAX_ACCELERATED_FILES`**: Sets the maximum number of files that can be cached. Default is `10000`.
- **`OPCACHE_VALIDATE_TIMESTAMPS`**: Enables or disables the validation of timestamps. Default is `1`.
- **`OPCACHE_REVALIDATE_FREQ`**: Sets how often to check script timestamps for updates, in seconds. Default is `2`.
- **`OPCACHE_MAX_WASTED_PERCENTAGE`**: Sets the maximum percentage of wasted memory that is allowed before a restart is scheduled. Default is `5`.
- **`OPCACHE_LOG_VERBOSITY_LEVEL`**: Sets the verbosity level of the OPcache log. Default is `1`.
- **`OPCACHE_ERROR_LOG`**: Specifies the path to the OPcache error log. Default is `/var/log/php-opcache.log`.

## `alpine/php-nginx/Dockerfile`

### PHP-FPM Settings
- **`PHP_VERSION`**: Specifies the PHP version to be installed. Default is `83`.
- **`PHP_FPM_ERROR_LOG`**: FPM master and pool error log. Empty by default, which resolves to `/proc/self/fd/2` (container stderr) or `/var/log/php-fpm/error.log` when `LOG_MODE=file`.
- **`PHP_FPM_SLOWLOG`**: Slow request log. Empty by default, which resolves to `/proc/self/fd/2` or `/var/log/php-fpm/slow.log` when `LOG_MODE=file`.
- **`fpm.pool.<setting>`**: Appended to the `[www]` pool, e.g. `fpm.pool.pm.max_children=50`.
- **`fpm.global.<setting>`**: Appended to the FPM `[global]` section, e.g. `fpm.global.log_level=debug`.
- **`PHP_FPM_LISTEN`**: Defines the address on which PHP-FPM will listen. Default is `127.0.0.1:9000` in php-nginx and `0.0.0.0:9000` in php-fpm. A path listens on a unix socket.
- **`PHP_FPM_LISTEN_ALLOWED_CLIENTS`**: Comma-separated addresses allowed to connect to a TCP listener (`listen.allowed_clients`). Empty allows any; `127.0.0.1` is always added so the healthcheck works.
- **`PHP_FPM_MAX_CHILDREN`**: Sets the maximum number of child processes to be created. Default is `30`.
- **`PHP_FPM_START_SERVERS`**: Sets the number of child processes created on startup. Default is `5`.
- **`PHP_FPM_MIN_SPARE_SERVERS`**: Sets the minimum number of idle child processes. Default is `3`.
- **`PHP_FPM_MAX_SPARE_SERVERS`**: Sets the maximum number of idle child processes. Default is `10`.
- **`PHP_FPM_MAX_REQUESTS`**: Limits the number of requests each child process should execute before respawning. Default is `1000`.
- **`PHP_FPM_REQUEST_TERMINATE_TIMEOUT`**: Sets the timeout for terminating a request. Default is `0`.

### Nginx Settings
- **`NGINX_PORT`**: Specifies the port on which Nginx will listen. Default is `80`.
- **`NGINX_SERVER_NAME`**: Sets the server name for Nginx. Default is `_`.
- **`NGINX_FASTCGI_PASS`**: Defines the address to which FastCGI requests will be sent. Default is `127.0.0.1:9000`.
- **`NGINX_DOCUMENT_ROOT`**: Sets the document root for Nginx. Default is `/var/www/html`.

### SSL / HTTPS Settings

All SSL settings are opt-in. When `NGINX_SSL_ENABLED` is `false` (the default), these variables are ignored and the image behaves identically to previous versions.

- **`NGINX_SSL_ENABLED`**: Master switch for HTTPS support. Default is `false`.
- **`NGINX_SSL_PORT`**: Port for the HTTPS listener. Default is `443`. Use `8443` when running as non-root.
- **`NGINX_SSL_CERTIFICATE`**: Path to the SSL certificate file. Default is `/etc/nginx/ssl/cert.pem`.
- **`NGINX_SSL_CERTIFICATE_KEY`**: Path to the SSL private key file. Default is `/etc/nginx/ssl/key.pem`.
- **`NGINX_SSL_PROTOCOLS`**: Allowed TLS protocol versions. Default is `TLSv1.2 TLSv1.3` (Mozilla Intermediate).
- **`NGINX_SSL_CIPHERS`**: Allowed cipher suites. Default is Mozilla Intermediate cipher string.
- **`NGINX_SSL_PREFER_SERVER_CIPHERS`**: Whether to prefer server ciphers over client ciphers. Default is `off` (modern recommendation).
- **`NGINX_SSL_SESSION_TIMEOUT`**: SSL session timeout duration. Default is `1d`.
- **`NGINX_SSL_SESSION_CACHE`**: SSL session cache configuration. Default is `shared:SSL:10m`.
- **`NGINX_SSL_REDIRECT`**: Whether to redirect HTTP requests to HTTPS when SSL is enabled. Default is `true`.
- **`NGINX_SSL_REDIRECT_PORT`**: Port for the HTTP-to-HTTPS redirect listener. Defaults to the value of `NGINX_PORT`.
- **`NGINX_METRICS_PORT`**: When set, nginx opens an extra listener on this port serving `/nginx_status` (stub_status), `/fpm-status`, `/fpm-ping` and `/health`. Empty (disabled) by default. Never exposed on the application port.
- **`NGINX_METRICS_ALLOW`**: Address or CIDR allowed to reach the metrics listener (`allow` directive). Default `all`.
- **`NGINX_LISTEN_IPV6`**: Adds `listen [::]:<port>` alongside the IPv4 listener. Default is `true`; set `false` on hosts where IPv6 is disabled in the kernel.
- **`NGINX_ACCESS_LOG`**: Access log destination. Empty by default, which resolves to `/dev/stdout` or `/var/log/nginx/access.log` when `LOG_MODE=file`. Use `off` to disable.
- **`NGINX_ERROR_LOG`**: Error log destination for both the `http` block and the app server. Empty by default, which resolves to `/dev/stderr` or `/var/log/nginx/error.log` when `LOG_MODE=file`.
- **`NGINX_SSL_REDIRECT_HOST`**: Host written into the HTTP-to-HTTPS redirect. Defaults to the first entry of `NGINX_SERVER_NAME`; when that is `_`, a wildcard or a regex, the request `Host` header is used and a warning is logged at startup.
- **`NGINX_SSL_SELF_SIGNED`**: Auto-generate a self-signed certificate at startup (for development). Default is `false`.
- **`NGINX_SSL_SELF_SIGNED_CN`**: Common Name and SAN for the self-signed certificate. Default is `localhost`.
- **`NGINX_SSL_SELF_SIGNED_DAYS`**: Validity period in days for the self-signed certificate. Default is `365`.
- **`NGINX_SSL_HSTS`**: Enable `Strict-Transport-Security` header on HTTPS responses. Default is `true`.
- **`NGINX_SSL_HSTS_MAX_AGE`**: HSTS max-age value in seconds. Default is `63072000` (2 years).

## `alpine/php-fpm/Dockerfile`

PHP-FPM without a web server. Uses the PHP-FPM settings above with `PHP_FPM_LISTEN=0.0.0.0:9000` and `APP_INSTALL_DIR=/var/www/html`; `PHP_SESSION_COOKIE_SECURE` defaults to `Off` because TLS terminates in the web server container.

## `alpine/php-nginx-dev/Dockerfile`

Inherits everything from php-nginx and adds:

- **`PHP_DEBUGGER`**: `xdebug` (default) loads Xdebug with the settings below, `pcov` loads PCOV instead, `none` loads neither. Any other value stops the container, as does `pcov` on PHP 8.6, where PCOV is not built yet (its 8.6 fixes are unmerged upstream). The ini is rendered by `render_debugger` in `entrypoint-lib.sh` from templates in `/usr/local/etc/php/debug/`.
- **`PCOV_DIRECTORY`**: Directory PCOV collects coverage for. Default empty, which lets PCOV detect `src`, `lib` or `app`.
- **`PCOV_EXCLUDE`**: Regex of paths PCOV skips. Default empty.
- **`XDEBUG_MODE`**: Default `develop,debug`.
- **`XDEBUG_START_WITH_REQUEST`**: Default `trigger`. Use `yes` to debug every request.
- **`XDEBUG_CLIENT_HOST`** / **`XDEBUG_CLIENT_PORT`**: Default `host.docker.internal` / `9003`.
- **`XDEBUG_DISCOVER_CLIENT_HOST`**: Default `false`.
- **`XDEBUG_IDEKEY`**: Default `PHPSTORM`.
- **`XDEBUG_OUTPUT_DIR`**: Default `/tmp/xdebug`.
- **`XDEBUG_LOG_LEVEL`**: Default `3`.
- **`NGINX_NO_CACHE_PATTERN`**: Regex of asset paths served with `Cache-Control: no-store` and `sendfile off`. Default matches common static extensions; empty disables the snippet.
- **`PHP_INI_SCAN_DIR`**: Set to `:/run/php/conf.d` so the rendered debugger ini is loaded in addition to the stock `conf.d`.
- Overrides `PHP_DISPLAY_ERRORS=On` and `PHP_ERROR_REPORTING=E_ALL`.

## `alpine/php-dev/Dockerfile`

The php CLI image plus Xdebug and PCOV, for test suites, coverage and static analysis locally or in CI. Its entrypoint loads the debugger and then runs the php entrypoint, so every php image variable (worker mode, cron, `APP_INSTALL`, `php.*` overrides) applies unchanged. Adds:

- **`PHP_DEBUGGER`**, **`PCOV_DIRECTORY`**, **`PCOV_EXCLUDE`** and every **`XDEBUG_*`** variable, with the same meaning and defaults as php-nginx-dev above.
- **`PHP_INI_SCAN_DIR`**: Set to `:/run/php/conf.d`, as in php-nginx-dev.
- Overrides `PHP_DISPLAY_ERRORS=On`, `PHP_ERROR_REPORTING=E_ALL` and `PHP_MEMORY_LIMIT=-1` (no limit, for test suites and static analysis).
