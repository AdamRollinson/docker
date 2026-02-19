# Environment Variables Documentation

## `alpine/php/Dockerfile`

### PHP General Settings
- **`PHP_VERSION`**: Specifies the PHP version to be installed. Default is `83`.
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
- **`PHP_FPM_LISTEN`**: Defines the address on which PHP-FPM will listen. Default is `127.0.0.1:9000`.
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
- **`NGINX_SSL_SELF_SIGNED`**: Auto-generate a self-signed certificate at startup (for development). Default is `false`.
- **`NGINX_SSL_SELF_SIGNED_CN`**: Common Name and SAN for the self-signed certificate. Default is `localhost`.
- **`NGINX_SSL_SELF_SIGNED_DAYS`**: Validity period in days for the self-signed certificate. Default is `365`.
- **`NGINX_SSL_HSTS`**: Enable `Strict-Transport-Security` header on HTTPS responses. Default is `true`.
- **`NGINX_SSL_HSTS_MAX_AGE`**: HSTS max-age value in seconds. Default is `63072000` (2 years).
