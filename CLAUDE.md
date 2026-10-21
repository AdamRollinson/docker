# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Docker image build system that produces multi-architecture (amd64/arm64) PHP container images published to Docker Hub under `adamrollogi/`. Three layered images are built:

1. **`adamrollogi/base:latest`** — Alpine 3.24 base with tini, cron and common tools
2. **`adamrollogi/php:{version}`** — PHP CLI with Composer and extensions (builds on base)
3. **`adamrollogi/php-nginx:{version}`** — PHP-FPM + Nginx web stack (builds on php)
4. **`adamrollogi/php-nginx-dev:{version}`** — php-nginx plus Xdebug and development defaults (builds on php-nginx)

Supported PHP versions: **8.2, 8.3, 8.4, 8.5**, plus **8.6** as a pre-release from Alpine edge/testing

The exact release for each minor version is pinned in `alpine/php-versions.txt` (format: `<minor> <release>` per line). This file is the single source of truth for both `build.sh` and the CI matrix. `alpine/check-php-versions.sh` compares the pins with the APKINDEX of every repository apk sees in the Dockerfiles (the base image's stable branch, derived from `alpine/base/Dockerfile`, plus edge main/community/testing) for both architectures, taking the newest version across all of them exactly as apk resolves it, and shows the latest php.net release per branch so an upstream security fix that Alpine has not packaged yet is visible (`CHECK_UPSTREAM=false` skips the lookup); only Alpine availability drives `--update`, which rewrites the file. The `php-version-bump` workflow runs that script every four hours and commits the result.

## Build Commands

### Local builds
```bash
# From the alpine/ directory:
cd alpine && ./build.sh
```
This builds all images sequentially: base → php (×5 versions) → php-nginx (×5 versions) → php-nginx-dev (×5 versions). Images are tagged locally with both the minor and the pinned release (e.g., `adamrollogi/php:8.3` and `adamrollogi/php:8.3.35`).

### Build a single image manually
```bash
# Base
docker build -t adamrollogi/base:latest ./alpine/base

# PHP (version without dots as build arg, e.g., 83 for 8.3; PHP_PATCH_VERSION pins the release)
docker build --build-arg PHP_VERSION=83 --build-arg PHP_PATCH_VERSION=8.3.35 -t adamrollogi/php:8.3 ./alpine/php

# PHP-Nginx (needs both args)
docker build --build-arg PHP_IMAGE_TAG=8.3 --build-arg PHP_VERSION=83 -t adamrollogi/php-nginx:8.3 ./alpine/php-nginx
```

## Architecture

### Image Inheritance Chain
```
Alpine 3.24
  └── base (tini, cron, bash, curl, git, envsubst)
        └── php:{version} (PHP CLI, Composer, extensions, php.ini.template)
              └── php-nginx:{version} (Nginx, PHP-FPM, config templates)
                    └── php-nginx-dev:{version} (Xdebug, no-cache snippet, dev php defaults)
```

### Configuration via Environment Variables
All runtime configuration is done through environment variables substituted into templates at container startup via `envsubst` in entrypoint scripts. See `ENV.md` for the full variable reference.

Generic overrides: any `php.<setting>` env var is appended to the rendered php.ini, `fpm.pool.<setting>` to the `[www]` pool and `fpm.global.<setting>` to the FPM `[global]` section, via `apply_ini_overrides` in `/usr/local/lib/entrypoint-lib.sh` (shipped by the php image, sourced by every entrypoint). Drop-in directories: `/etc/nginx/http-conf.d` (http block), `/etc/nginx/after.d` (inside the app server block), `/etc/nginx/http.d` (extra server blocks), plus `/run/nginx/after.d` for runtime-rendered snippets such as the dev image's no-cache location. Logging is organised per service: every long-running process is started through `/usr/local/bin/run-service <name> <cmd>` (base image), which uses bash process substitution plus busybox awk to prefix each stdout/stderr line with `[name]` (`LOG_FORMAT=text`) or wrap it as `{"time","service","stream","message"}` (`LOG_FORMAT=json`, JSON lines pass through untouched so nginx's `json_combined` access log stays structured). The entrypoints log through `log()` from `/usr/local/lib/entrypoint-lib.sh`, tagged `[entrypoint]`. `LOG_MODE=file` disables tagging and resolves the empty `NGINX_ACCESS_LOG`, `NGINX_ERROR_LOG`, `PHP_FPM_ERROR_LOG`, `PHP_FPM_SLOWLOG` defaults to per-service files under `/var/log`; `container-logs` tails them. The access log directive is assembled in the entrypoint as `NGINX_ACCESS_LOG_DIRECTIVE` (handles `off` and the json format), and `json_combined` is defined in `/run/nginx/logging.conf`, included at the top of the http block. Every long-running process goes through `run-service`, so nothing is left untagged. IPv6 listeners are emitted by default and stripped with `sed` when `NGINX_LISTEN_IPV6=false`.

Rendered config never lands in `/etc`. The php entrypoint writes `php.ini` to `/run/php` (PHP finds it via `PHPRC`); the php-nginx entrypoint writes `nginx.conf` plus server blocks to `/run/nginx` and the FPM pool plus a minimal `php-fpm.conf` to `/run/php`, then starts nginx with `-c` and php-fpm with `-y`/`-c`. Templates are shipped root-owned under `/usr/local/etc/{nginx,php}`. The stock `/etc/nginx/http.d/*.conf` include is kept so users can still mount extra server blocks there. This keeps `/etc` root-owned and makes the images work with `--read-only` plus tmpfs mounts on `/run`, `/tmp`, `/var/log` and `/var/lib/nginx`.

Key convention in Nginx templates: `@@` placeholders are used instead of `$` to prevent premature variable expansion during `envsubst`, then replaced back to `$` by the entrypoint script.

### PHP Version Handling
PHP versions use two formats throughout the codebase:
- **Dotted** (`8.3`) — used for Docker image tags and `PHP_IMAGE_TAG` build arg
- **Stripped** (`83`) — used for `PHP_VERSION` build arg and Alpine package names (e.g., `php83-cli`)
- **Release** (`8.3.35`) — `PHP_PATCH_VERSION` build arg, applied as an apk constraint (`php83~8.3.35`) and used as an extra image tag

The build script converts between them: `PHP_VERSION_ENV=$(echo "$version" | tr -d '.')`

Pre-release pins use Alpine's spelling (`8.6.0_rc3`); PHP reports `8.6.0RC3`, so the post-install assertion lowercases PHP_VERSION and strips underscores from the pin before comparing. `check-php-versions.sh` treats a final release as newer than any pre-release of the same base. `opcache` and `pecl-imagick` are installed as optional packages (notice, not failure, when absent): opcache is built into the core package from PHP 8.5 and imagick is not yet packaged for 8.6.

Every real PHP package carries the pin: the core, every extension subpackage, `opcache` where it exists, and `php83-fpm` in php-nginx. This matters because Alpine's extension packages depend on `php83-common` **without** a version constraint, so an unpinned extension is installed from whichever repository has the newest build; when a security release lands in the stable branch or edge before the pin is bumped, that produces an older core with newer extensions and every extension fails to load with `symbol not found` (this broke the 8.3, 8.4 and 8.5 builds on 21 October 2026). `php83-cli` and `php83-json` are virtual names provided by the pinned core and common packages and cannot be constrained; `pecl-*` packages have their own version numbers and stay unpinned. `php83-common`, `php83-openssl`, `php83-sockets` and `php83-mysqlnd` are listed explicitly because apk pulls them in as dependencies and would otherwise take the newest build. Both Dockerfiles end the install step by asserting that every installed `php8x-*` package except `pecl-*` carries `-${PHP_PATCH_VERSION}-r`, so a mismatched set can never be published even if Alpine adds a new transitive dependency. php-nginx reads `PHP_PATCH_VERSION` from the php image's `ENV` rather than taking its own build arg, so php-fpm always matches the installed PHP. Both Dockerfiles assert the installed version after `apk add` and fail the build on a mismatch. If `PHP_PATCH_VERSION` is empty, the latest release in Alpine edge is installed unpinned.

### Development image (php-nginx-dev)
`php-nginx-dev-entrypoint.sh` renders `/run/php/conf.d/50-xdebug.ini` (loaded through `PHP_INI_SCAN_DIR=:/run/php/conf.d`, which keeps the stock scan dir) when `PHP_DEBUGGER=xdebug`, renders the `NGINX_NO_CACHE_PATTERN` location into `/run/nginx/after.d/no-cache.conf`, then execs the php-nginx entrypoint. The Alpine `php8x-pecl-xdebug` package's own ini is deleted at build time so loading is runtime-controlled. Xdebug is installed from edge like PHP itself, unpinned.

### SSL / HTTPS (php-nginx only)
Optional HTTPS support via environment variables. Disabled by default (`NGINX_SSL_ENABLED=false`).

When enabled, the entrypoint selects which Nginx config templates to process:
- **SSL off** → `app.conf.template` (HTTP only)
- **SSL on** → `app-ssl.conf.template` (HTTPS) + optionally `app-ssl-redirect.conf.template` (HTTP→HTTPS redirect)

Key implementation details:
- `ssl_session_cache` and `ssl_session_timeout` are `http`-level directives in `nginx.conf` — the entrypoint patches them via `sed` rather than setting them per-server (shared memory zone names conflict otherwise)
- HSTS header is stripped from the rendered config via `sed` when `NGINX_SSL_HSTS=false`
- Self-signed certs are generated idempotently (skipped if files already exist)
- `healthcheck.sh` wrapper detects SSL mode and always checks `/health`, never a PHP page
- The HTTP-to-HTTPS redirect target is fixed by the entrypoint: `NGINX_SSL_REDIRECT_HOST`, else the first non-wildcard `NGINX_SERVER_NAME`, else `$host` with a startup warning (Host header reflection would otherwise be an open redirect)
- `/.well-known/` is served (not denied as a hidden path) in all templates so ACME HTTP-01 works, including on the redirect listener

### Hardening conventions
- No setuid/setgid binaries: every Dockerfile ends its package step with `find / -xdev -type f -perm /6000 -exec chmod a-s {} +`, and `busybox-suid` is not installed
- `index.php` is a static placeholder, never `phpinfo()` (it would print every environment variable, including secrets)
- `PHP_EXPOSE_PHP` defaults to `Off`; `PHP_SESSION_COOKIE_SECURE` is empty and resolved by the entrypoints (`On` under SSL)
- Alpine repositories are referenced over `https://`

### Process Management
There is no supervisord (and therefore no Python) in the images since October 2026. The php-nginx entrypoint's `start_services` launches php-fpm and nginx, plus busybox `crond` when running as root, each via `run-service`, waits on them with `wait -n`, and exits with the first one to die so the orchestrator restarts the container. `CMD ["serve"]` triggers it; the old `supervisord` CMD is accepted for compatibility; any other command is exec'd. The php image's CMD is `php -v`. `[cron]` lines come from crond in root mode.

## CI/CD

### Automatic PHP release bumps (`.github/workflows/php-version-bump.yml`)
- **Triggers**: cron every four hours (`17 */4 * * *`), manual `workflow_dispatch`
- Runs `alpine/check-php-versions.sh --update`. A minor is only bumped when the same release exists in edge for both `x86_64` and `aarch64`
- Commits the change to `main` as `github-actions[bot]`, then dispatches `docker-build.yml` with `gh workflow run` (pushes made with `GITHUB_TOKEN` do not trigger other workflows on their own)
- Needs `contents: write` and `actions: write`, which the workflow requests itself

### Image build (`.github/workflows/docker-build.yml`)
- **Triggers**: push to `main` (ignoring `docs/**`, Markdown, `LICENSE`, `docs-ci.yml` and `dependabot.yml`, so documentation changes never rebuild images), manual `workflow_dispatch`, weekly cron (so Alpine fixes ship without a code change)
- **Scan and test before publish**: every image is pushed as `:candidate-<sha>[-<minor>]`, Trivy-scanned, smoke-tested with `alpine/test.sh` (health endpoint, PHP version, extensions, package consistency, no setuid files, tagged logs, read-only recipe, root mode, redirect host, Xdebug toggle) and VEX-attested, then promoted to its real tags with `docker buildx imagetools create`. After promotion the manifest list is signed keylessly with cosign (`sigstore/cosign-installer`, workflow has `id-token: write`); verify with `cosign verify --certificate-oidc-issuer https://token.actions.githubusercontent.com --certificate-identity-regexp '^https://github.com/AdamRollinson/docker/\.github/workflows/docker-build\.yml@refs/heads/main$' <image>`. Candidate tags are deleted via the Docker Hub API afterwards (best effort)
- `DOCKER_PAT` is only exposed to the login and candidate-cleanup steps, never at workflow scope
- Buildx is pinned to a mainline release via `BUILDX_VERSION`. Dependabot covers both GitHub Actions and the `alpine/base` Docker digest
- **Build strategy**: a `php-matrix` job turns `alpine/php-versions.txt` into a matrix (`minor`/`patch`), base image builds first, then PHP versions in parallel
- Each image is pushed with two tags: `:{minor}` and `:{patch}`
- Multi-arch builds use plain **buildx** with the `docker-container` driver on `ubuntu-latest`; arm64 layers are emulated with QEMU (`docker/setup-qemu-action`). Layer cache lives in the GitHub Actions cache (`type=gha`, one scope per image). Docker Build Cloud was dropped in October 2026 after its builder started refusing builds (`concurrent build limit of 0`)
- Publishes to Docker Hub with SBOM and provenance attestation
- VEX attestations via `docker/scout-action` (attestation-add command)
- Trivy vulnerability scanning (fails on CRITICAL/HIGH)
- **Required secrets/vars**: `DOCKER_USER` (variable), `DOCKER_PAT` (secret, needs read/write/delete scope so candidate tags can be removed)

### Runtime user
`appuser` is created in the base Dockerfile from the `APP_UID`/`APP_GID` build args (default 1000) and exported as env vars of the same name; `build.sh` forwards `APP_UID`/`APP_GID` from the environment. Derived images chown by name, so a custom UID propagates without changes. Never reintroduce setuid helpers (gosu, su-exec) for identity switching.

## Documentation site (`docs/`)

A Nuxt 4 site built from the Nuxt UI docs template with `@nuxt/ui`, `@nuxt/content`, `nuxt-og-image` and `nuxt-llms`. Package manager is **pnpm** (lockfile present); run commands from `docs/`: `pnpm dev`, `pnpm check` (lint + typecheck), `pnpm generate` (static output in `.output/public`). Content is Markdown under `docs/content/` with numeric prefixes for ordering and `.navigation.yml` per section; the landing page is `content/index.md`. Site URL comes from `NUXT_PUBLIC_SITE_URL`. Deployment is a Cloudflare Workers static-assets Worker built by Workers Builds from the repo (root directory `docs`, build `pnpm generate`, deploy `npx wrangler deploy`, config in `docs/wrangler.jsonc` with no Worker script). `nitro.preset` is pinned to `static` because Cloudflare's build environment otherwise auto-selects `cloudflare-module` and the deploy fails looking for a server entry point. `.github/workflows/docs-ci.yml` only lints, typechecks and generates on changes under `docs/`. `docs/public/_headers` sets caching (hashed assets immutable, pages revalidate) and security headers including a CSP (inline scripts/styles, `wasm-unsafe-eval` and blob workers for client-side search, and Cloudflare Web Analytics hosts because the edge injects its beacon; new external resources need a CSP source). Nuxt Icon runs with `provider: 'none'` and a client-bundle scan that includes `content/`, so every icon is bundled at build time and nothing is fetched from api.iconify.design at runtime (the default scan misses content frontmatter and the Cloudflare build environment switched the server bundle to remote, which the CSP blocked); `docs/public/robots.txt` allows all crawlers including AI and links `llms.txt` and the `@nuxtjs/sitemap`-generated `sitemap.xml`; `docs/public/.well-known/security.txt` carries reporting contacts with a yearly `Expires`. When image behaviour or variables change, update the corresponding page under `docs/content/` alongside `README.md` and `ENV.md`.

## Key Files

| Path | Purpose |
|------|---------|
| `alpine/build.sh` | Local build script for all images |
| `alpine/php-versions.txt` | Pinned PHP release per supported minor version |
| `alpine/check-php-versions.sh` | Compares pins with the Alpine repositories apk uses, `--update` rewrites the file |
| `alpine/test.sh` | Smoke tests run by CI against each candidate image; `test.sh all 8.4` runs everything against local images |
| `.github/workflows/php-version-bump.yml` | Four-hourly job that bumps pins and dispatches the build |
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
| `alpine/base/entrypoint-lib.sh` | Shared entrypoint helpers (`log`, `json_escape`, `apply_ini_overrides`) |
| `alpine/base/run-service` | Service wrapper that tags or JSON-wraps log lines per service |
| `alpine/base/container-logs` | Tails per-service log files in `LOG_MODE=file` |
| `alpine/php-nginx-dev/Dockerfile` | Xdebug development image |
| `alpine/php-nginx-dev/php-nginx-dev-entrypoint.sh` | Renders Xdebug ini and no-cache snippet, then chains to php-nginx entrypoint |
| `ENV.md` | Complete environment variable reference |
| `docs/` | Nuxt documentation site deployed to Cloudflare Workers as static assets |
| `SECURITY.md` | CVE details and VEX attestation documentation |
