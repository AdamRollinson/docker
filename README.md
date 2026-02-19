# Docker PHP Images

Multi-architecture (amd64/arm64) PHP container images built on Alpine Linux 3.21 and published to Docker Hub under `adamrollogi/`.

## Images

| Image | Description |
|-------|-------------|
| `adamrollogi/base:latest` | Alpine 3.21 base with Supervisor, tini, bash, curl, git |
| `adamrollogi/php:{version}` | PHP CLI with Composer and common extensions |
| `adamrollogi/php-nginx:{version}` | PHP-FPM + Nginx web stack with optional HTTPS |

**Supported PHP versions:** 8.1, 8.2, 8.3, 8.4

### Image inheritance

```
Alpine 3.21
  └── base (supervisor, bash, curl, git, envsubst, tini)
        └── php:{version} (PHP CLI, Composer, extensions)
              └── php-nginx:{version} (Nginx, PHP-FPM, SSL support)
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

## Configuration

All runtime configuration is done through environment variables. Templates are processed via `envsubst` at container startup.

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
| `PHP_EXPOSE_PHP` | `On` | `X-Powered-By` header (`Off` for production) |

### Nginx settings

| Variable | Default | Description |
|----------|---------|-------------|
| `NGINX_PORT` | `80` | HTTP listen port |
| `NGINX_SERVER_NAME` | `_` | Nginx `server_name` |
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
| `NGINX_SSL_SELF_SIGNED` | `false` | Auto-generate dev certificate |
| `NGINX_SSL_SELF_SIGNED_CN` | `localhost` | CN/SAN for self-signed cert |
| `NGINX_SSL_HSTS` | `true` | Strict-Transport-Security header |
| `NGINX_SSL_HSTS_MAX_AGE` | `63072000` | HSTS max-age (2 years) |

See [ENV.md](ENV.md) for the complete variable reference including OPcache, security settings, and additional SSL options.

### PHP extensions (included)

bcmath, ctype, curl, dom, exif, fileinfo, gd, iconv, intl, json, mbstring, mysqli, opcache, pcntl, pdo, pdo_mysql, phar, posix, redis, session, simplexml, soap, tokenizer, xml, xmlreader, xmlwriter, zip, imagick

## Security

- Non-root execution by default (UID 1000)
- Hidden files (`.env`, `.git`, `.htaccess`) are blocked by Nginx
- Security headers set out of the box (X-Frame-Options, X-Content-Type-Options, Referrer-Policy, Permissions-Policy)
- HSTS enabled by default when SSL is active
- SSL session tickets disabled (security best practice)
- Mozilla Intermediate TLS cipher configuration
- Base image pins to Alpine digest for supply chain integrity
- CI builds include SBOM, provenance attestation, and Trivy scanning

See [SECURITY.md](SECURITY.md) for CVE details and VEX attestations.

## Building locally

```bash
cd alpine && ./build.sh
```

This builds all 9 images sequentially: base, php (x4 versions), php-nginx (x4 versions).

### Build a single image

```bash
# Base
docker build -t adamrollogi/base:latest ./alpine/base

# PHP 8.4
docker build --build-arg PHP_VERSION=84 -t adamrollogi/php:8.4 ./alpine/php

# PHP-Nginx 8.4
docker build \
  --build-arg PHP_IMAGE_TAG=8.4 \
  --build-arg PHP_VERSION=84 \
  -t adamrollogi/php-nginx:8.4 \
  ./alpine/php-nginx
```

## CI/CD

GitHub Actions (`.github/workflows/docker-build.yml`) builds and publishes all images on push to `main`:

- Multi-arch builds via Docker Build Cloud
- PHP versions build in parallel (matrix strategy)
- SBOM and provenance attestation on every image
- VEX attestations for known false positives
- Trivy vulnerability scanning (fails on CRITICAL/HIGH)

## License

MIT
