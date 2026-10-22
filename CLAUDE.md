# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Docker image build system that produces multi-architecture (amd64/arm64) PHP container images published to Docker Hub under `adamrollogi/`. Three layered images are built:

1. **`adamrollogi/base:latest`** — Alpine 3.24 base with tini, supercronic and common tools
2. **`adamrollogi/php:{version}`** — PHP CLI with Composer and extensions (builds on base)
3. **`adamrollogi/php-nginx:{version}`** — PHP-FPM + Nginx web stack (builds on php)
4. **`adamrollogi/php-nginx-dev:{version}`** — php-nginx plus Xdebug and development defaults (builds on php-nginx)

Supported PHP versions: **8.2, 8.3, 8.4, 8.5**, plus **8.6** as a pre-release from Alpine edge/testing on the `8.6-rc` channel tag (no bare `8.6` tag until 8.6.0 is pinned)

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
  └── base (tini, supercronic, bash, curl, git, envsubst)
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
- **Channel tag** (`8.6-rc`) — the moving tag for a pre-release pin, derived from the release spelling (`8.6.0_rc3` → `8.6-rc`, `_beta2` → `-beta`); a final release uses the bare minor. Computed by `channel_tag` in `build.sh`, by the `tag` field of the CI matrix (jq in the `php-matrix` job), and by `test.sh all`. php-nginx and php-nginx-dev are built `FROM` the channel tag, and promote/sign/verify steps use `matrix.tag`; candidate tags, cache scopes and step names stay keyed by `matrix.minor`.

The build script converts between them: `PHP_VERSION_ENV=$(echo "$version" | tr -d '.')`

Pre-release pins use Alpine's spelling (`8.6.0_rc3`); PHP reports `8.6.0RC3`, so the post-install assertion lowercases PHP_VERSION and strips underscores from the pin before comparing. `check-php-versions.sh` treats a final release as newer than any pre-release of the same base. `opcache` and `pecl-imagick` are installed as optional packages (notice, not failure, when absent): opcache is built into the core package from PHP 8.5 and imagick is not yet packaged for 8.6.

Every real PHP package carries the pin: the core, every extension subpackage, `opcache` where it exists, and `php83-fpm` in php-nginx. This matters because Alpine's extension packages depend on `php83-common` **without** a version constraint, so an unpinned extension is installed from whichever repository has the newest build; when a security release lands in the stable branch or edge before the pin is bumped, that produces an older core with newer extensions and every extension fails to load with `symbol not found` (this broke the 8.3, 8.4 and 8.5 builds on 21 October 2026). `php83-cli` and `php83-json` are virtual names provided by the pinned core and common packages and cannot be constrained; `pecl-*` packages have their own version numbers and stay unpinned. `php83-common`, `php83-openssl`, `php83-sockets` and `php83-mysqlnd` are listed explicitly because apk pulls them in as dependencies and would otherwise take the newest build. Both Dockerfiles end the install step by asserting that every installed `php8x-*` package except `pecl-*` carries `-${PHP_PATCH_VERSION}-r`, so a mismatched set can never be published even if Alpine adds a new transitive dependency. php-nginx reads `PHP_PATCH_VERSION` from the php image's `ENV` rather than taking its own build arg, so php-fpm always matches the installed PHP. Both Dockerfiles assert the installed version after `apk add` and fail the build on a mismatch. If `PHP_PATCH_VERSION` is empty, the latest release in Alpine edge is installed unpinned.

Runtime state directories (`/run/php`, `/run/nginx`, `/run/cron`, `/run/php/conf.d`, `/etc/nginx/ssl`, `/var/log`, `/var/lib/nginx`) are owned by appuser and chmod `1777` (sticky, world-writable, like `/tmp`) so the images run under an arbitrary `--user uid:gid`; `test.sh` exercises both images as `4321:4321`. Nothing under `/etc` or `/usr` is writable by non-root.

`PHP_EXTRA_EXTENSIONS` (build arg, default empty, forwarded by `build.sh` from the environment) installs additional extensions: each name is tried as `php8x-<name>~<release>` then as `php8x-pecl-<name>`, and the build fails if neither exists; the set is recorded in the `io.rollogi.php.extra-extensions` label. CI builds the default (empty) set only.

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
- `NGINX_METRICS_PORT` renders `metrics.conf.template` into `/run/nginx/http.d/metrics.conf`: a separate server block with `stub_status` at `/nginx_status`, FPM `pm.status_path` at `/fpm-status` and `ping.path` at `/fpm-ping` (both always configured in the pool but only routed by this listener), guarded by `allow ${NGINX_METRICS_ALLOW}; deny all;`

### Hardening conventions
- No setuid/setgid binaries: every Dockerfile ends its package step with `find / -xdev -type f -perm /6000 -exec chmod a-s {} +`, and `busybox-suid` is not installed
- `index.php` is a static placeholder, never `phpinfo()` (it would print every environment variable, including secrets)
- `PHP_EXPOSE_PHP` defaults to `Off`; `PHP_SESSION_COOKIE_SECURE` is empty and resolved by the entrypoints (`On` under SSL)
- Alpine repositories are referenced over `https://`

### Process Management
There is no supervisord (and therefore no Python) in the images since October 2026. The php-nginx entrypoint's `start_services` launches php-fpm and nginx, plus supercronic when cron jobs are configured, each via `run-service`, waits on them with `wait -n`, and exits with the first one to die so the orchestrator restarts the container. `CMD ["serve"]` triggers it; the old `supervisord` CMD is accepted for compatibility; any other command is exec'd. The php image's CMD is `php -v`. Cron is supercronic in every mode (works as any user): `render_crontab` in `entrypoint-lib.sh` builds `/run/cron/crontab` from `CRON_SCHEDULE`/`CRON_COMMAND` and/or the file at `CRONTAB_FILE` (default `/etc/crontabs/app`), validates it with `supercronic -test`, and the php image's `cron` command runs it standalone. Output is tagged `[cron]`. busybox crond is not used. The php image has a worker mode: with `CLI_COMMAND` set and the default command (`php -v`) or `worker`, `php-entrypoint.sh` runs the command in a restart loop (`CLI_RESTART_DELAY`, `CLI_MAX_RESTARTS`) with output tagged `[worker]`; an explicit command always bypasses it. Mail: `render_msmtp` in `entrypoint-lib.sh` writes `/run/php/msmtprc` (mode 600) from `SMTP_*` when `SMTP_HOST` is set and exports `PHP_SENDMAIL_PATH="/usr/bin/msmtp -C /run/php/msmtprc -t"` unless already set; both entrypoints call it before rendering php.ini. `alpine/test.sh` verifies delivery end to end against a Mailpit container. `run_app_install` in `entrypoint-lib.sh` runs `APP_INSTALL` (in `APP_INSTALL_DIR`, default `/app` for php and `/var/www/html` for php-nginx) through `run-service install` before the php image's cron/worker/exec dispatch and before `start_services` in php-nginx; a non-zero exit stops the container with that status. Composer defaults (`COMPOSER_HOME=/tmp/composer`, `COMPOSER_ALLOW_SUPERUSER=1`, `COMPOSER_NO_INTERACTION=1`, `COMPOSER_FUND=0`, `COMPOSER_MEMORY_LIMIT=-1`, `COMPOSER_PROCESS_TIMEOUT=600`) are set as ENV in the php Dockerfile so composer works for any `--user` and on a read-only rootfs.

## CI/CD

### Automatic PHP release bumps (`.github/workflows/php-version-bump.yml`)
- **Triggers**: cron every four hours (`17 */4 * * *`), manual `workflow_dispatch`
- Runs `alpine/check-php-versions.sh --update`. A minor is only bumped when the same release exists in edge for both `x86_64` and `aarch64`
- Runs `alpine/changelog.sh`, which reads the unstaged diff of the versions file and inserts one line per changed pin under today's date (newest first, same-day entries merged) after the `<!-- entries -->` marker in `docs/content/5.releases/4.changelog.md`; BSD awk compatible (entries passed via `ENVIRON`)
- Commits the change (pins and changelog) to `main` as `github-actions[bot]`, then dispatches `docker-build.yml` with `gh workflow run` (pushes made with `GITHUB_TOKEN` do not trigger other workflows on their own)
- Needs `contents: write` and `actions: write`, which the workflow requests itself

### Image build (`.github/workflows/docker-build.yml`)
- **Triggers**: push to `main` (ignoring `docs/**`, Markdown, `LICENSE`, `docs-ci.yml` and `dependabot.yml`, so documentation changes never rebuild images), manual `workflow_dispatch`, weekly cron (so Alpine fixes ship without a code change)
- **Scan and test before publish**: each single-platform image is pushed by digest only (`push-by-digest`), Trivy-scanned and smoke-tested with `alpine/test.sh` on the architecture that built it (health endpoint, PHP version, extensions, package consistency, no setuid files, tagged logs, read-only recipe, root and arbitrary-user modes, redirect host, metrics, cron, mail, worker, APP_INSTALL, Xdebug toggle). The publish job joins the two digests into a manifest list as `:candidate-<sha>[-<minor>]`, VEX-attests it and promotes it to its real tags with `docker buildx imagetools create`. After promotion the manifest list is signed keylessly with cosign (`sigstore/cosign-installer`, workflow has `id-token: write`); verify with `cosign verify --certificate-oidc-issuer https://token.actions.githubusercontent.com --certificate-identity-regexp '^https://github.com/AdamRollinson/docker/\.github/workflows/docker-build\.yml@refs/heads/main$' <image>`. Candidate tags are deleted via the Docker Hub API afterwards (best effort)
- `DOCKER_PAT` is only exposed to the login and candidate-cleanup steps, never at workflow scope
- Buildx is pinned to a mainline release via `BUILDX_VERSION`. Dependabot covers both GitHub Actions and the `alpine/base` Docker digest
- **Build strategy**: `php-matrix` turns `alpine/php-versions.txt` into two matrices (`matrix`: one entry per minor with `minor`/`patch`/`tag`/`prerelease`; `build_matrix`: the same crossed with `arch`/`platform`/`runner`). `build-base` (per arch) → `publish-base` → `build-php` (per minor × arch, chains php → php-nginx → php-nginx-dev on one runner, each `FROM` the digest just pushed via the `PHP_IMAGE` build arg) → `publish-php` (per minor, `if: !cancelled()` so one failing minor does not block the others). Digests travel between jobs as artifacts named `digests-<image>-<minor>-<arch>`, one empty file per image named `"<image> <digest>"`
- Each image is promoted with two tags: `:{tag}` (minor or channel) and `:{patch}`
- **Native multi-arch**: amd64 on `ubuntu-24.04`, arm64 on `ubuntu-24.04-arm` (free for public repos), plain **buildx** with the `docker-container` driver, no QEMU. Layer cache lives in the GitHub Actions cache (`type=gha`, one scope per image and arch). Docker Build Cloud was dropped in October 2026 after its builder started refusing builds (`concurrent build limit of 0`); QEMU emulation was dropped for native runners in the same month
- Publishes to Docker Hub with SBOM and provenance attestation
- VEX attestations via `docker/scout-action` (attestation-add command)
- Trivy vulnerability scanning (fails on CRITICAL/HIGH)
- **Releases and notifications**: the `release` job (`contents: write`, `if: !cancelled()`) runs after `publish-php` and, for every matrix entry whose exact tag is published and has no `php-<patch>` GitHub release yet, creates one with `gh release create --target $GITHUB_SHA --latest=false` (plus `--prerelease` for `_` pins) using notes from `alpine/release-notes.sh` (image digests via `imagetools inspect`, cosign verify snippet; exits 3 when the tag is not on Hub). The `notify` job (`if: always()`) and the bump workflow call `alpine/notify.sh <status> <title> <message> [url]`, which POSTs JSON (`text` and `content` plus structured fields) to `NOTIFY_WEBHOOK_URL` and is a no-op when the secret is unset
- **Required secrets/vars**: `DOCKER_USER` (variable), `DOCKER_PAT` (secret, needs read/write/delete scope so candidate tags can be removed), `NOTIFY_WEBHOOK_URL` (optional secret)

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
