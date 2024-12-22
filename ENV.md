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