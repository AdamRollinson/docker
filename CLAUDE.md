# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Docker image build system that produces multi-architecture (amd64/arm64) PHP container images published to Docker Hub under `adamrollogi/`. Three layered images are built:

1. **`adamrollogi/base:latest`** — Alpine 3.21 base with common tools and Supervisor
2. **`adamrollogi/php:{version}`** — PHP CLI with Composer and extensions (builds on base)
3. **`adamrollogi/php-nginx:{version}`** — PHP-FPM + Nginx web stack (builds on php)

Supported PHP versions: **8.1, 8.2, 8.3, 8.4**

## Build Commands

### Local builds
```bash
# From the alpine/ directory:
cd alpine && ./build.sh
```
This builds all images sequentially: base → php (×4 versions) → php-nginx (×4 versions). Images are tagged locally (e.g., `adamrollogi/php:8.3`).

### Build a single image manually
```bash
# Base
docker build -t adamrollogi/base:latest ./alpine/base

# PHP (version without dots as build arg, e.g., 83 for 8.3)
docker build --build-arg PHP_VERSION=83 -t adamrollogi/php:8.3 ./alpine/php

# PHP-Nginx (needs both args)
docker build --build-arg PHP_IMAGE_TAG=8.3 --build-arg PHP_VERSION=83 -t adamrollogi/php-nginx:8.3 ./alpine/php-nginx
```

## Architecture

### Image Inheritance Chain
```
Alpine 3.21
  └── base (supervisor, bash, curl, git, envsubst)
        └── php:{version} (PHP CLI, Composer, extensions, php.ini.template)
              └── php-nginx:{version} (Nginx, PHP-FPM, config templates)
```

### Configuration via Environment Variables
All runtime configuration is done through environment variables substituted into templates at container startup via `envsubst` in entrypoint scripts. See `ENV.md` for the full variable reference.

Key convention in Nginx templates: `@@` placeholders are used instead of `$` to prevent premature variable expansion during `envsubst`, then replaced back to `$` by the entrypoint script.

### PHP Version Handling
PHP versions use two formats throughout the codebase:
- **Dotted** (`8.3`) — used for Docker image tags and `PHP_IMAGE_TAG` build arg
- **Stripped** (`83`) — used for `PHP_VERSION` build arg and Alpine package names (e.g., `php83-cli`)

The build script converts between them: `PHP_VERSION_ENV=$(echo "$version" | tr -d '.')`

### SSL / HTTPS (php-nginx only)
Optional HTTPS support via environment variables. Disabled by default (`NGINX_SSL_ENABLED=false`).

When enabled, the entrypoint selects which Nginx config templates to process:
- **SSL off** → `app.conf.template` (HTTP only)
- **SSL on** → `app-ssl.conf.template` (HTTPS) + optionally `app-ssl-redirect.conf.template` (HTTP→HTTPS redirect)

Key implementation details:
- `ssl_session_cache` and `ssl_session_timeout` are `http`-level directives in `nginx.conf` — the entrypoint patches them via `sed` rather than setting them per-server (shared memory zone names conflict otherwise)
- HSTS header is stripped from the rendered config via `sed` when `NGINX_SSL_HSTS=false`
- Self-signed certs are generated idempotently (skipped if files already exist)
- `healthcheck.sh` wrapper detects SSL mode and checks the appropriate endpoint

### Process Management
Supervisor manages all long-running processes inside containers:
- **base**: runs cron
- **php**: runs supervisord (inherits cron from base)
- **php-nginx**: adds php-fpm and nginx (with `daemon off`) as supervised programs

## CI/CD

GitHub Actions workflow (`.github/workflows/docker-build.yml`):
- **Triggers**: push to `main`, manual `workflow_dispatch`
- **Build strategy**: base image first, then PHP versions in parallel (matrix strategy)
- Uses **Docker Build Cloud** (`adamrollogi/medusa` endpoint) for multi-arch builds
- Publishes to Docker Hub with SBOM and provenance attestation
- VEX attestations via `docker/scout-action` (attestation-add command)
- Trivy vulnerability scanning (fails on CRITICAL/HIGH)
- **Required secrets/vars**: `DOCKER_USER` (variable), `DOCKER_PAT` (secret)

## Key Files

| Path | Purpose |
|------|---------|
| `alpine/build.sh` | Local build script for all images |
| `alpine/base/Dockerfile` | Base Alpine image with common tooling |
| `alpine/php/Dockerfile` | PHP image with extensions and Composer |
| `alpine/php/php.ini.template` | Runtime PHP configuration template |
| `alpine/php/php-entrypoint.sh` | PHP container entrypoint (envsubst) |
| `alpine/php-nginx/Dockerfile` | Nginx + PHP-FPM image |
| `alpine/php-nginx/app.conf.template` | Nginx HTTP-only server config template |
| `alpine/php-nginx/app-ssl.conf.template` | Nginx HTTPS server config template |
| `alpine/php-nginx/app-ssl-redirect.conf.template` | HTTP→HTTPS redirect template |
| `alpine/php-nginx/www.conf.template` | PHP-FPM pool configuration template |
| `alpine/php-nginx/php-nginx-entrypoint.sh` | Nginx container entrypoint (SSL logic, envsubst) |
| `alpine/php-nginx/healthcheck.sh` | Docker HEALTHCHECK wrapper (HTTP/HTTPS aware) |
| `ENV.md` | Complete environment variable reference |
| `SECURITY.md` | CVE details and VEX attestation documentation |
