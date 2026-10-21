# Docker PHP Images

Multi-architecture (amd64/arm64) PHP container images built on Alpine Linux 3.24 and published to Docker Hub under `adamrollogi/`.

Full documentation: the `docs/` site (Nuxt, deployed to Cloudflare Pages). This README is the short version.

## Images

| Image | Description |
|-------|-------------|
| `adamrollogi/base:latest` | Alpine 3.24 base with Supervisor, tini, bash, curl, git |
| `adamrollogi/php:{version}` | PHP CLI with Composer and common extensions |
| `adamrollogi/php-nginx:{version}` | PHP-FPM + Nginx web stack with optional HTTPS |
| `adamrollogi/php-nginx-dev:{version}` | php-nginx plus Xdebug, visible errors and uncached assets, for local development |

**Supported PHP versions:** 8.2, 8.3, 8.4, 8.5, and 8.6 as a pre-release

PHP 8.6 is published from Alpine's testing repository while it is in release candidate (tag `php:8.6`, and the exact tag follows Alpine's spelling, e.g. `php:8.6.0_rc3`). Treat it as experimental until 8.6.0 ships. The `imagick` extension is not yet packaged for 8.6, and from 8.5 onward OPcache is compiled into PHP itself rather than installed as a separate package.

Each image is published under two tags: the minor version (`php:8.4`, tracks the latest pinned release) and the exact release (`php:8.4.26`, immutable). Pin the exact tag in production if you want to control when PHP updates roll out.

### Image inheritance

```
Alpine 3.24
  └── base (supervisor, bash, curl, git, envsubst, tini)
        └── php:{version} (PHP CLI, Composer, extensions)
              └── php-nginx:{version} (Nginx, PHP-FPM, SSL support)
                    └── php-nginx-dev:{version} (Xdebug, dev defaults)
```

## Quick start

### PHP CLI

```bash
docker run --rm adamrollogi/php:8.4 php -v
```

### PHP-FPM + Nginx (HTTP)

```bash
docker run --rm -d -p 8080:8080 \
  -e NGINX_PORT=8080 \
  -v $(pwd):/var/www/html \
  adamrollogi/php-nginx:8.4
```

### PHP-FPM + Nginx (HTTPS with self-signed cert)

```bash
docker run --rm -d -p 8080:8080 -p 8443:8443 \
  -e NGINX_PORT=8080 \
  -e NGINX_SSL_ENABLED=true \
  -e NGINX_SSL_PORT=8443 \
  -e NGINX_SSL_SELF_SIGNED=true \
  -v $(pwd):/var/www/html \
  adamrollogi/php-nginx:8.4
```

### PHP-FPM + Nginx (HTTPS with your own certificate)

```bash
docker run --rm -d -p 80:80 -p 443:443 --user root \
  -e NGINX_SSL_ENABLED=true \
  -v /path/to/cert.pem:/etc/nginx/ssl/cert.pem:ro \
  -v /path/to/key.pem:/etc/nginx/ssl/key.pem:ro \
  -v $(pwd):/var/www/html \
  adamrollogi/php-nginx:8.4
```

## Non-root by default

All images default to running as `appuser` (UID 1000). When running as non-root:

- Ports below 1024 (80, 443) are unavailable — use `8080`, `8443`, etc.
- Cron is not available — use `--user root` for full Supervisor mode with cron
- PHP-FPM runs without `user`/`group` directives (automatically stripped)

Use `--user root` when you need privileged ports or cron.

### Running with a read-only root filesystem

Rendered configuration is written to `/run/nginx` and `/run/php` rather than `/etc`, so the image works with a read-only root filesystem. This also means any config tampering is discarded when the container restarts.

```bash
docker run --rm -d -p 8080:8080 \
  -e NGINX_PORT=8080 \
  --read-only \
  --tmpfs /run:uid=1000,gid=1000 \
  --tmpfs /var/log:uid=1000,gid=1000 \
  --tmpfs /var/lib/nginx:uid=1000,gid=1000 \
  --tmpfs /tmp \
  --cap-drop ALL --security-opt no-new-privileges \
  -v $(pwd):/var/www/html:ro \
  adamrollogi/php-nginx:8.4
```

The `uid`/`gid` options are required because Docker mounts tmpfs as root-owned by default. Add `--tmpfs /etc/nginx/ssl:uid=1000,gid=1000` if you use `NGINX_SSL_SELF_SIGNED=true`.

### Local development with Xdebug

```bash
docker run --rm -d -p 8080:8080 \
  -e NGINX_PORT=8080 \
  -e XDEBUG_START_WITH_REQUEST=yes \
  -v $(pwd):/var/www/html \
  adamrollogi/php-nginx-dev:8.4
```

Xdebug connects back to `host.docker.internal:9003` by default and only starts when triggered (browser extension, `XDEBUG_TRIGGER` cookie or query string). Set `XDEBUG_START_WITH_REQUEST=yes` to debug every request, or `PHP_DEBUGGER=none` to leave Xdebug unloaded. Static assets are served with `Cache-Control: no-store` so edits show up immediately.

## Configuration

All runtime configuration is done through environment variables. Templates are processed via `envsubst` at container startup.

### Any php.ini or PHP-FPM setting

Beyond the named variables below, any setting can be passed directly:

| Prefix | Target | Example |
|--------|--------|---------|
| `php.<setting>` | php.ini | `-e php.memory_limit=256M -e php.date.timezone=Europe/London` |
| `fpm.pool.<setting>` | FPM `[www]` pool | `-e fpm.pool.pm.max_children=50` |
| `fpm.global.<setting>` | FPM `[global]` section | `-e fpm.global.log_level=debug` |

These are appended after the templated settings, so they always win. Multi-line values are not supported.

### Nginx drop-in directories

| Directory | Scope | Use for |
|-----------|-------|---------|
| `/etc/nginx/http-conf.d/*.conf` | `http` block | `map`, `upstream`, `log_format`, rate-limit zones |
| `/etc/nginx/after.d/*.conf` | inside the app `server` block | extra `location` blocks, rewrites, headers |
| `/etc/nginx/http.d/*.conf` | additional `server` blocks | a second vhost on another port |

Mount files into these directories or `COPY` them in a derived image. They are root-owned and are read at startup.

### Logging

Everything logs to the container's stdout and stderr by default, and every line is tagged with the service that wrote it, so one `docker logs` stream stays readable and filterable.

| Tag | Stream | What you get |
|-----|--------|--------------|
| `[nginx]` | stdout | access log (combined format) |
| `[nginx]` | stderr | nginx errors and warnings |
| `[php-fpm]` | stderr | FPM master and pool messages, PHP `error_log()` output, slow-request traces |
| `[cron]` | stderr | crond output (root mode only) |
| `[entrypoint]` | stdout | startup messages from the entrypoint scripts |
| *(untagged)* | stderr | supervisord's own messages (root mode only), e.g. `INFO spawned: 'nginx'` |

```bash
docker logs -f app 2>&1                        # everything
docker logs app 2>&1 | grep '^\[php-fpm\]'     # one service
docker logs app 2>&1 | grep -v '^\[nginx\]'    # everything except the access log
```

Three variables control the layout:

| Variable | Default | Options |
|----------|---------|---------|
| `LOG_MODE` | `stdout` | `stdout` streams everything to the container; `file` writes one file per service under `/var/log` |
| `LOG_FORMAT` | `text` | `text` for tagged lines; `json` for one JSON object per line |
| `LOG_TAG` | `true` | `false` removes the `[service]` prefixes and gives raw output |

**JSON mode** (`LOG_FORMAT=json`) is for log shippers such as Loki, Datadog or CloudWatch. Service messages become `{"time":"...","service":"php-fpm","stream":"stderr","message":"..."}`, and the nginx access log switches to a structured `json_combined` format with `service`, `status`, `request_time`, `upstream_time` and the usual request fields.

```bash
docker logs app 2>&1 | jq -c 'select(.service == "nginx" and .status >= 500)'
```

**File mode** (`LOG_MODE=file`) writes `/var/log/nginx/access.log`, `/var/log/nginx/error.log`, `/var/log/php-fpm/error.log` and `/var/log/php-fpm/slow.log`, with no tags. Mount `/var/log` to keep them, and tail them in place with the bundled helper:

```bash
docker exec app container-logs -f php-fpm     # nginx | php-fpm | cron | supervisor | all
```

Individual destinations can still be overridden with `NGINX_ACCESS_LOG` (`off` disables it), `NGINX_ERROR_LOG`, `PHP_FPM_ERROR_LOG` and `PHP_FPM_SLOWLOG`.

### Health check

All modes expose a `/health` endpoint that returns `200 OK` — useful for Docker HEALTHCHECK, load balancers, and orchestrators.

```bash
curl -sf http://localhost:8080/health
```

### PHP settings

| Variable | Default | Description |
|----------|---------|-------------|
| `PHP_MEMORY_LIMIT` | `128M` | Maximum script memory |
| `PHP_UPLOAD_MAX_FILESIZE` | `2M` | Maximum upload file size |
| `PHP_POST_MAX_SIZE` | `2M` | Maximum POST data size |
| `PHP_MAX_EXECUTION_TIME` | `30` | Script execution limit (seconds) |
| `PHP_MAX_INPUT_TIME` | `60` | Input parsing limit (seconds) |
| `PHP_DISPLAY_ERRORS` | `Off` | Show errors on screen |
| `PHP_DATE_TIMEZONE` | `UTC` | Default timezone |
| `PHP_EXPOSE_PHP` | `Off` | `X-Powered-By` header |
| `PHP_SESSION_COOKIE_SECURE` | *(auto)* | `Secure` flag on session cookies. Defaults to `On` when `NGINX_SSL_ENABLED=true`, otherwise `Off` |
| `PHP_SENDMAIL_PATH` | *(PHP default)* | `sendmail_path`, e.g. `/usr/bin/msmtp -t` when an MTA or relay binary is present |

### Nginx settings

| Variable | Default | Description |
|----------|---------|-------------|
| `NGINX_PORT` | `80` | HTTP listen port |
| `NGINX_LISTEN_IPV6` | `true` | Also listen on `[::]`. Set `false` on hosts with IPv6 disabled |
| `NGINX_SERVER_NAME` | `_` | Nginx `server_name` |
| `NGINX_ACCESS_LOG` | *(by `LOG_MODE`)* | Access log destination (`off` to disable) |
| `NGINX_ERROR_LOG` | *(by `LOG_MODE`)* | Error log destination |
| `NGINX_DOCUMENT_ROOT` | `/var/www/html` | Web document root |
| `NGINX_FASTCGI_PASS` | `127.0.0.1:9000` | PHP-FPM upstream |

### PHP-FPM settings

| Variable | Default | Description |
|----------|---------|-------------|
| `PHP_FPM_MAX_CHILDREN` | `30` | Maximum worker processes |
| `PHP_FPM_START_SERVERS` | `5` | Workers created on startup |
| `PHP_FPM_MIN_SPARE_SERVERS` | `3` | Minimum idle workers |
| `PHP_FPM_MAX_SPARE_SERVERS` | `10` | Maximum idle workers |
| `PHP_FPM_MAX_REQUESTS` | `1000` | Requests before worker respawn |
| `PHP_FPM_ERROR_LOG` | *(by `LOG_MODE`)* | FPM master and pool error log |
| `PHP_FPM_SLOWLOG` | *(by `LOG_MODE`)* | Slow request log (requests over 5s) |

### SSL / HTTPS settings

SSL is opt-in. Set `NGINX_SSL_ENABLED=true` to enable. When disabled (default), all SSL variables are ignored.

| Variable | Default | Description |
|----------|---------|-------------|
| `NGINX_SSL_ENABLED` | `false` | Master switch |
| `NGINX_SSL_PORT` | `443` | HTTPS listen port (use `8443` for non-root) |
| `NGINX_SSL_CERTIFICATE` | `/etc/nginx/ssl/cert.pem` | Path to certificate |
| `NGINX_SSL_CERTIFICATE_KEY` | `/etc/nginx/ssl/key.pem` | Path to private key |
| `NGINX_SSL_PROTOCOLS` | `TLSv1.2 TLSv1.3` | Allowed TLS versions |
| `NGINX_SSL_REDIRECT` | `true` | HTTP-to-HTTPS redirect |
| `NGINX_SSL_REDIRECT_PORT` | *(inherits `NGINX_PORT`)* | Port for redirect listener |
| `NGINX_SSL_REDIRECT_HOST` | *(first `NGINX_SERVER_NAME`)* | Host used in the redirect `Location`. Falls back to the request `Host` header only when no server name is configured |
| `NGINX_SSL_SELF_SIGNED` | `false` | Auto-generate dev certificate |
| `NGINX_SSL_SELF_SIGNED_CN` | `localhost` | CN/SAN for self-signed cert |
| `NGINX_SSL_HSTS` | `true` | Strict-Transport-Security header |
| `NGINX_SSL_HSTS_MAX_AGE` | `63072000` | HSTS max-age (2 years) |

### Development image settings (`php-nginx-dev` only)

| Variable | Default | Description |
|----------|---------|-------------|
| `PHP_DEBUGGER` | `xdebug` | `xdebug` or `none` |
| `XDEBUG_MODE` | `develop,debug` | Xdebug modes (`debug`, `develop`, `coverage`, `profile`, `trace`) |
| `XDEBUG_START_WITH_REQUEST` | `trigger` | `yes`, `no` or `trigger` |
| `XDEBUG_CLIENT_HOST` | `host.docker.internal` | IDE host |
| `XDEBUG_CLIENT_PORT` | `9003` | IDE port |
| `XDEBUG_DISCOVER_CLIENT_HOST` | `false` | Derive the IDE host from the request |
| `XDEBUG_IDEKEY` | `PHPSTORM` | IDE key |
| `XDEBUG_OUTPUT_DIR` | `/tmp/xdebug` | Profiles and traces |
| `NGINX_NO_CACHE_PATTERN` | `\.(css\|js\|...)$` | Assets served with `no-store`; empty disables |

The dev image also sets `PHP_DISPLAY_ERRORS=On` and `PHP_ERROR_REPORTING=E_ALL`.

See [ENV.md](ENV.md) for the complete variable reference including OPcache, security settings, and additional SSL options.

### PHP extensions (included)

bcmath, ctype, curl, dom, exif, fileinfo, gd, iconv, intl, json, mbstring, mysqli, opcache, pcntl, pdo, pdo_mysql, phar, posix, redis, session, simplexml, soap, tokenizer, xml, xmlreader, xmlwriter, zip, imagick

`opcache` and `imagick` are installed when Alpine packages them for the PHP version (opcache is built in from 8.5; imagick is missing on 8.6 for now). The build logs a notice rather than failing when one is unavailable.

## Security

- Non-root execution by default (UID 1000), no setuid or setgid binaries in any image
- Configuration under `/etc` is root-owned; runtime config is rendered into `/run` so a compromised PHP worker cannot rewrite php.ini or the Nginx config persistently
- Default landing page is a static message, not `phpinfo()`, so environment variables are never exposed by accident
- Hidden files (`.env`, `.git`, `.htaccess`) are blocked by Nginx; `/.well-known/` is allowed for ACME challenges
- Security headers set out of the box (X-Frame-Options, X-Content-Type-Options, Referrer-Policy, Permissions-Policy)
- `expose_php` off by default, session cookies `HttpOnly`, `SameSite=Lax` and `Secure` when HTTPS is enabled
- HSTS enabled by default when SSL is active
- SSL session tickets disabled, TLS 1.2 and 1.3 only
- Mozilla Intermediate TLS cipher configuration
- HTTP-to-HTTPS redirect targets a configured host rather than reflecting the request `Host` header
- Base image pins to Alpine digest for supply chain integrity, Alpine repositories fetched over HTTPS
- CI builds every image under a candidate tag, scans it with Trivy, and only promotes it to the public tags when the scan passes
- SBOM, provenance and VEX attestations on every image; images are rebuilt weekly so Alpine fixes ship without a code change

See [SECURITY.md](SECURITY.md) for CVE details and VEX attestations.

## Building locally

```bash
cd alpine && ./build.sh
```

This builds all 16 images sequentially: base, php (x5 versions), php-nginx (x5 versions), php-nginx-dev (x5 versions).

### Pinned PHP releases

The exact PHP release for each minor version lives in [`alpine/php-versions.txt`](alpine/php-versions.txt). Both `build.sh` and the CI workflow read it, pass the release to the Dockerfiles as `PHP_PATCH_VERSION`, and install the Alpine package with a version constraint (`php84~8.4.26`). A build fails if Alpine edge no longer carries that release, rather than silently shipping a different PHP.

New releases are picked up automatically. The `php-version-bump` workflow runs every four hours, compares the pins against the Alpine edge package index for both amd64 and arm64, and when a newer release is available on both it commits the bump to `main` and dispatches the build workflow. Alpine edge usually lags php.net by a few days, so a release announced today typically ships within the week, and within four hours of Alpine packaging it.

To check or bump manually:

```bash
# Report pinned release vs Alpine edge vs php.net for each minor
alpine/check-php-versions.sh
# PHP 8.4: pinned 8.4.26, Alpine edge 8.4.26, php.net 8.4.27 (security release, waiting on Alpine)

# Rewrite alpine/php-versions.txt with the newest releases, then push to main
alpine/check-php-versions.sh --update
```

You can also trigger the bump workflow from the Actions tab via "Run workflow".

### Build a single image

```bash
# Base
docker build -t adamrollogi/base:latest ./alpine/base

# PHP 8.4 (omit PHP_PATCH_VERSION to install whatever Alpine edge currently has)
docker build \
  --build-arg PHP_VERSION=84 \
  --build-arg PHP_PATCH_VERSION=8.4.26 \
  -t adamrollogi/php:8.4 \
  ./alpine/php

# PHP-Nginx 8.4 (php-fpm is pinned to the release baked into the php image)
docker build \
  --build-arg PHP_IMAGE_TAG=8.4 \
  --build-arg PHP_VERSION=84 \
  -t adamrollogi/php-nginx:8.4 \
  ./alpine/php-nginx
```

## CI/CD

GitHub Actions (`.github/workflows/docker-build.yml`) builds and publishes all images on push to `main`:

- Multi-arch builds with buildx (`docker-container` driver), arm64 via QEMU, layers cached in GitHub Actions cache
- PHP versions build in parallel (matrix generated from `alpine/php-versions.txt`)
- SBOM and provenance attestation on every image
- VEX attestations for known false positives
- Trivy vulnerability scanning (fails on CRITICAL/HIGH)

## License

MIT
