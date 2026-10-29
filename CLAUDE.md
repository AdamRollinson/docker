# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Docker image build system that produces multi-architecture (amd64/arm64) PHP container images published to Docker Hub under the `rollogi/` organisation (`adamrollogi/` until 22 October 2026; those repositories no longer receive updates). These layered images are built:

1. **`rollogi/base:latest`** - Alpine 3.24 base with tini, supercronic and common tools
2. **`rollogi/php:{version}`** - PHP CLI and FPM compiled from the php.net source, with Composer and extensions (builds on base)
3. **`rollogi/php-nginx:{version}`** - PHP-FPM + Nginx web stack (builds on php)
4. **`rollogi/php-nginx-dev:{version}`** - php-nginx plus Xdebug and development defaults (builds on php-nginx)
5. **`rollogi/php-fpm:{version}`** - PHP-FPM only, listening on `0.0.0.0:9000`, for a web server in another container (builds on php)
6. **`rollogi/frankenphp:{version}`** - FrankenPHP (Caddy with PHP embedded), worker mode and automatic HTTPS; compiles its own thread-safe PHP (builds on base, not php)

Supported PHP versions: **8.2, 8.3, 8.4, 8.5**, plus **8.6** as a pre-release (php.net release candidate tarball) on the `8.6-rc` channel tag (no bare `8.6` tag until 8.6.0 is pinned)

The exact release for each minor version is pinned in `alpine/php-versions.txt` (format: `<minor> <release> <sha256> <tarball URL>` per line; final releases from `www.php.net/distributions`, pre-releases from the release manager's directory on `downloads.php.net`). This file is the single source of truth for both `build.sh` and the CI matrix. `alpine/check-php-versions.sh` compares the pins with php.net's releases feed (`releases/index.php?json&version=<minor>`), or the pre-release feed (`pre-release-builds.php?format=json`) for a minor without a final release, and `--update` rewrites the whole line (release, checksum, URL) using `jq`. It also compares `alpine/php/pecl-extensions.txt` with PECL's `stable.txt`: `--update` applies patch releases within the same major.minor (with a fresh checksum), while larger ones and `https://` URL lines are only reported. The `php-version-bump` workflow runs that script every four hours and commits the result.

## Build Commands

### Local builds
```bash
# From the alpine/ directory:
cd alpine && ./build.sh
```
This builds all images sequentially: base, then php, php-nginx, php-nginx-dev, php-fpm and frankenphp for each of the 5 versions. Images are tagged locally with both the minor and the pinned release (e.g., `rollogi/php:8.3` and `rollogi/php:8.3.36`). `build.sh` passes the sha256 and URL columns as `PHP_SOURCE_SHA256`/`PHP_SOURCE_URL` and forwards `PHP_EXTRA_EXTENSIONS`/`PHP_EXTRA_BUILD_DEPS` from the environment. PHP is compiled, so a cold build takes several minutes per version.

### Build a single image manually
```bash
# Base
docker build -t rollogi/base:latest ./alpine/base

# PHP (version without dots as build arg, e.g., 83 for 8.3; PHP_PATCH_VERSION is required, the
# sha256 is optional and PHP_SOURCE_URL defaults to www.php.net/distributions for final releases)
docker build --build-arg PHP_VERSION=83 --build-arg PHP_PATCH_VERSION=8.3.36 \
  --build-arg PHP_SOURCE_SHA256=dd54693aa334c5c4d72e9aee96b082c2473750a18a6c1d105789c93a3b1692fd -t rollogi/php:8.3 ./alpine/php

# PHP-Nginx (needs both args)
docker build --build-arg PHP_IMAGE_TAG=8.3 --build-arg PHP_VERSION=83 -t rollogi/php-nginx:8.3 ./alpine/php-nginx
```

## Architecture

### Image Inheritance Chain
```
Alpine 3.24
  └── base (tini, supercronic, bash, curl, git, envsubst)
        ├── php:{version} (PHP CLI + FPM compiled from source, Composer, extensions, php-ext-install, php.ini.template)
        │     ├── php-nginx:{version} (Nginx, PHP-FPM, config templates)
        │     │     └── php-nginx-dev:{version} (Xdebug, no-cache snippet, dev php defaults)
        │     └── php-fpm:{version} (PHP-FPM only, FastCGI healthcheck)
        └── frankenphp:{version} (ZTS PHP + libphp from the same tarball, FrankenPHP, Composer, Caddyfile)
```

### Configuration via Environment Variables
All runtime configuration is done through environment variables substituted into templates at container startup via `envsubst` in entrypoint scripts. See `ENV.md` for the full variable reference.

Generic overrides: any `php.<setting>` env var is appended to the rendered php.ini, `fpm.pool.<setting>` to the `[www]` pool and `fpm.global.<setting>` to the FPM `[global]` section, via `apply_ini_overrides` in `/usr/local/lib/entrypoint-lib.sh` (shipped by the php image, sourced by every entrypoint). Drop-in directories: `/etc/nginx/http-conf.d` (http block), `/etc/nginx/after.d` (inside the app server block), `/etc/nginx/http.d` (extra server blocks), plus `/run/nginx/after.d` for runtime-rendered snippets such as the dev image's no-cache location. Logging is organised per service: every long-running process is started through `/usr/local/bin/run-service <name> <cmd>` (base image), which uses bash process substitution plus busybox awk to prefix each stdout/stderr line with `[name]` (`LOG_FORMAT=text`) or wrap it as `{"time","service","stream","message"}` (`LOG_FORMAT=json`, JSON lines pass through untouched so nginx's `json_combined` access log stays structured). The entrypoints log through `log()` from `/usr/local/lib/entrypoint-lib.sh`, tagged `[entrypoint]`. `LOG_MODE=file` disables tagging and resolves the empty `NGINX_ACCESS_LOG`, `NGINX_ERROR_LOG`, `PHP_FPM_ERROR_LOG`, `PHP_FPM_SLOWLOG` defaults to per-service files under `/var/log`; `container-logs` tails them. The access log directive is assembled in the entrypoint as `NGINX_ACCESS_LOG_DIRECTIVE` (handles `off` and the json format), and `json_combined` is defined in `/run/nginx/logging.conf`, included at the top of the http block. Every long-running process goes through `run-service`, so nothing is left untagged. IPv6 listeners are emitted by default and stripped with `sed` when `NGINX_LISTEN_IPV6=false`.

Rendered config never lands in `/etc`. The php entrypoint writes `php.ini` to `/run/php` (PHP finds it via `PHPRC`); the php-nginx entrypoint writes `nginx.conf` plus server blocks to `/run/nginx` and the FPM pool plus a minimal `php-fpm.conf` to `/run/php`, then starts nginx with `-c` and php-fpm with `-y`/`-c`. Templates are shipped root-owned under `/usr/local/etc/{nginx,php}`. The stock `/etc/nginx/http.d/*.conf` include is kept so users can still mount extra server blocks there. This keeps `/etc` root-owned and makes the images work with `--read-only` plus tmpfs mounts on `/run`, `/tmp`, `/var/log` and `/var/lib/nginx`.

Key convention in Nginx templates: `@@` placeholders are used instead of `$` to prevent premature variable expansion during `envsubst`, then replaced back to `$` by the entrypoint script.

### PHP Version Handling
PHP versions use two formats throughout the codebase:
- **Dotted** (`8.3`) - used for Docker image tags and `PHP_IMAGE_TAG` build arg
- **Stripped** (`83`) - used for `PHP_VERSION` build arg, the Alpine-era symlinks (`php83`, `php-fpm83`) and `/var/log/php83`
- **Release** (`8.3.36`) - `PHP_PATCH_VERSION` build arg, the source release compiled, and an extra image tag
- **Channel tag** (`8.6-rc`) - the moving tag for a pre-release pin, derived from the release spelling (`8.6.0_rc3` → `8.6-rc`, `_beta2` → `-beta`); a final release uses the bare minor. Computed by `channel_tag` in `build.sh`, by the `tag` field of the CI matrix (jq in the `php-matrix` job), and by `test.sh all`. php-nginx and php-nginx-dev are built `FROM` the channel tag, and promote/sign/verify steps use `matrix.tag`; candidate tags, cache scopes and step names stay keyed by `matrix.minor`.

The build script converts between them: `PHP_VERSION_ENV=$(echo "$version" | tr -d '.')`

Pre-release pins keep Alpine's spelling (`8.6.0_rc4`) so image tags are unchanged; php.net and PHP say `8.6.0RC4`. The php Dockerfile converts the pin to php.net spelling for the default URL (`_rc` to `RC`, `_alpha`/`_beta` lose the underscore), `check-php-versions.sh` converts php.net's spelling back (`alpine_spelling`), and the post-install assertion lowercases PHP_VERSION and strips underscores from the pin before comparing. `check-php-versions.sh` treats a final release as newer than any pre-release of the same base.

PHP is compiled from source in a multi-stage `alpine/php/Dockerfile`. The `builder` stage (`FROM rollogi/base:latest`) installs the toolchain and `-dev` packages, downloads the tarball and its `.asc`, checks `PHP_SOURCE_SHA256` (when given) and the GPG signature with `gpgv` against `alpine/php/php-keyring.asc` (the php.net release managers' keyring from `https://www.php.net/distributions/php-keyring.gpg`, vendored so a compromised download host cannot swap the keys too; refresh it when new release managers start signing), then configures with `--prefix=/usr/local`, `--with-config-file-path=/usr/local/etc/php`, `--with-config-file-scan-dir=/usr/local/etc/php/conf.d`, `--enable-fpm`, `--disable-cgi --disable-phpdbg` and every default extension static. Only opcache is shared before 8.5 (`zend_extension` in `conf.d/10-opcache.ini`); from 8.5 it is built in. PECL extensions come from `alpine/php/pecl-extensions.txt` (`<image> <ext> <version or https URL> <sha256> <minors or *>`); the `php` lines are built in the builder in file order, so igbinary and msgpack precede redis, which is configured with `--enable-redis-igbinary --enable-redis-msgpack`, and imagick is not listed for 8.6. The released igbinary, msgpack, apcu and redis do not compile against 8.6 (`zval_dtor`, `XtOffsetOf` and `php_verror` changes, `unserialize_callback_func` becoming a `zend_string`), so their 8.6 lines pin GitHub archive tarballs of upstream commits that carry the fixes; swap them for PECL releases once those ship (the check script skips URL lines). Each goes through `alpine/php/php-ext-install`, which writes `conf.d/20-<ext>.ini`. `scanelf` records the shared libraries everything links against as `so:` names in `/usr/local/lib/php/runtime-deps.txt`. The runtime stage copies `/usr/local` from the builder, `apk add`s those `so:` names plus msmtp, asserts the version and that `php -r ''` prints nothing, and creates the Alpine-era symlinks `/usr/bin/php`, `/usr/bin/php8x`, `/usr/sbin/php-fpm` and `/usr/sbin/php-fpm8x`. Headers, `phpize`, `php-config`, `php-ext-install` and `pecl-extensions.txt` stay in the image so derived images (and php-nginx-dev) can compile extensions. php-nginx and php-fpm use the `php-fpm` binary from the php image and only assert that `php-fpm -v` matches `PHP_PATCH_VERSION`. No image uses Alpine edge any more; every apk install comes from the base image's release branch.

Runtime state directories (`/run/php`, `/run/nginx`, `/run/cron`, `/run/php/conf.d`, `/etc/nginx/ssl`, `/var/log`, `/var/lib/nginx`) are owned by appuser and chmod `1777` (sticky, world-writable, like `/tmp`) so the images run under an arbitrary `--user uid:gid`; `test.sh` exercises both images as `4321:4321`. Nothing under `/etc` or `/usr` is writable by non-root.

`PHP_EXTRA_EXTENSIONS` (build arg, default empty, forwarded by `build.sh` from the environment) compiles additional extensions in the builder via `php-ext-install`: a bundled extension (`/usr/src/php/ext/<name>`) from the PHP source, anything else from the latest stable PECL release, and the build fails if one cannot be built. A `case` map adds `-dev` packages for common ones (amqp, bz2, ffi, gettext, gmp, ldap, memcached, tidy, xsl, yaml); `PHP_EXTRA_BUILD_DEPS` adds others. Runtime libraries are picked up by the `scanelf` step. The set is recorded in the `io.rollogi.php.extra-extensions` label. CI builds the default (empty) set only.

### FPM-only image (php-fpm)
`php-fpm` is php (which already contains the `php-fpm` binary from the same source build) plus `fcgi` (for `cgi-fcgi`), with no web server. The pool template `www.conf.template` lives in the php image at `/usr/local/etc/php/` and both php-nginx and php-fpm render it through `render_fpm_config` in `entrypoint-lib.sh` (pool, non-root user/group stripping, `PHP_FPM_LISTEN_ALLOWED_CLIENTS` as `listen.allowed_clients` with `127.0.0.1` always added, master `php-fpm.conf`, `fpm.global.*` and `fpm.pool.*` overrides), so the two images cannot drift. php-fpm defaults `PHP_FPM_LISTEN=0.0.0.0:9000` and `APP_INSTALL_DIR=/var/www/html`, `serve` starts php-fpm plus supercronic when cron is configured, and `HEALTHCHECK` runs `php-fpm-healthcheck`, which sends `/fpm-ping` over FastCGI with `env -i cgi-fcgi` to the port (or socket) from `PHP_FPM_LISTEN`. `test.sh php-fpm` drives it from a second container on a private Docker network, the way a sidecar would.

### FrankenPHP image (frankenphp)
`alpine/frankenphp/Dockerfile` is built with the **`alpine/` directory as context** (`-f alpine/frankenphp/Dockerfile alpine`, `context: ./alpine` in CI) so it reuses `php/php-keyring.asc`, `php/php-ext-install`, `php/pecl-extensions.txt`, `php/php.ini.template` and `php/msmtprc.template` without copies. It does not build on rollogi/php: FrankenPHP needs a thread-safe PHP built as a library, so the builder compiles the same pinned tarball (same checksum and `gpgv` checks, same extension flags and PECL `php` lines) with `--enable-embed --enable-zts --disable-zend-signals --enable-zend-max-execution-timers` and no FPM. It then builds FrankenPHP from the release tarball pinned (with sha256) in `alpine/frankenphp/frankenphp-version.txt` using `go build` directly (not xcaddy), with `GOTOOLCHAIN=go<version>` from the same file (Alpine's `go` only bootstraps; the toolchain is verified against sum.golang.org), FrankenPHP's own cgo flags and its musl stack-size linker flag, and tags `nobadger,nomysql,nopgx,deprecated_topic,deprecated_claim,nowatcher,nomercure` (no e-dant watcher C library, no AGPL Mercure). `scanelf` runs after the Go build so brotli and libphp's dependencies land in `runtime-deps.txt`. The runtime stage asserts `PHP_ZTS` and that `frankenphp version` embeds the pinned release. Config is the root-owned `/etc/frankenphp/Caddyfile`, which uses Caddy's own `{$VAR}` substitution (nothing rendered): `SERVER_NAME` (default `:80`, plain HTTP; a host name enables automatic HTTPS), `SERVER_ROOT` (`/app/public`), `/health` via `respond`, hidden files 403 except `/.well-known/`, security headers with `-Server`/`-X-Powered-By`, `{$CADDY_*}` and `{$FRANKENPHP_CONFIG}` splice points, and `import Caddyfile.d/*.caddyfile`. `frankenphp-entrypoint.sh` derives `CADDY_LOG_OUTPUT`/`CADDY_LOG_FORMAT` from `LOG_MODE`/`LOG_FORMAT`, prepends `num_threads`/`worker` lines built from `FRANKENPHP_NUM_THREADS`, `FRANKENPHP_WORKER` and `FRANKENPHP_WORKER_NUM` to `FRANKENPHP_CONFIG`, defaults `PHP_SESSION_COOKIE_SECURE` from `SERVER_NAME`, renders php.ini into `/run/php`, runs `APP_INSTALL` in `/app`, and `serve` starts `frankenphp run` (plus supercronic) through `run-service frankenphp`. `HEALTHCHECK` runs `frankenphp-healthcheck` against Caddy's admin `/metrics` on `localhost:2019`, which works with or without HTTPS. Caddy state lives in `/data` and `/config` (XDG dirs, sticky 1777). Port 80 is bound without file capabilities thanks to Docker's default unprivileged-port sysctl. `check-php-versions.sh` reports and `--update` applies new FrankenPHP releases (GitHub, with a fresh checksum) and Go stable releases (go.dev), and the bump workflow commits that file too.

### Development image (php-nginx-dev)
`php-nginx-dev-entrypoint.sh` renders `/run/php/conf.d/50-xdebug.ini` (loaded through `PHP_INI_SCAN_DIR=:/run/php/conf.d`, which keeps the stock scan dir) when `PHP_DEBUGGER=xdebug`, renders the `NGINX_NO_CACHE_PATTERN` location into `/run/nginx/after.d/no-cache.conf`, then execs the php-nginx entrypoint. Xdebug is compiled in the dev Dockerfile with a throwaway `.xdebug-build` toolchain via `php-ext-install --no-enable`, at the `dev xdebug` version `/usr/local/etc/php/pecl-extensions.txt` lists for the minor (3.5.x for 8.2 to 8.5, the 3.6.0alpha1 tarball from xdebug.org for 8.6), so nothing loads it until the entrypoint renders an ini.

### SSL / HTTPS (php-nginx only)
Optional HTTPS support via environment variables. Disabled by default (`NGINX_SSL_ENABLED=false`).

When enabled, the entrypoint selects which Nginx config templates to process:
- **SSL off** → `app.conf.template` (HTTP only)
- **SSL on** → `app-ssl.conf.template` (HTTPS) + optionally `app-ssl-redirect.conf.template` (HTTP→HTTPS redirect)

Key implementation details:
- `ssl_session_cache` and `ssl_session_timeout` are `http`-level directives in `nginx.conf` - the entrypoint patches them via `sed` rather than setting them per-server (shared memory zone names conflict otherwise)
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
- Runs `alpine/check-php-versions.sh --update`, which follows php.net and applies PECL patch releases to `alpine/php/pecl-extensions.txt`
- Runs `alpine/changelog.sh`, which reads the unstaged diff of the versions file and inserts one line per changed pin under today's date (newest first, same-day entries merged) after the `<!-- entries -->` marker in `docs/content/5.releases/4.changelog.md`; BSD awk compatible (entries passed via `ENVIRON`)
- Commits the change (pins, PECL pins and changelog) to `main` as `github-actions[bot]`, then dispatches `docker-build.yml` with `gh workflow run` (pushes made with `GITHUB_TOKEN` do not trigger other workflows on their own)
- Needs `contents: write` and `actions: write`, which the workflow requests itself

### Image build (`.github/workflows/docker-build.yml`)
- **Triggers**: push to `main` (ignoring `docs/**`, Markdown, `LICENSE`, `docs-ci.yml` and `dependabot.yml`, so documentation changes never rebuild images), manual `workflow_dispatch`, weekly cron (so Alpine fixes ship without a code change)
- **Scan and test before publish**: each single-platform image is first built with `load: true` and no attestations as `local/<image>` (a classic Docker daemon cannot load the manifest list that provenance and SBOM attestations produce, so one build with two exporters fails with `docker exporter does not currently support exporting manifest lists`), Trivy scans and `alpine/test.sh` tests that local copy on the architecture that built it, and only then is the same build repeated from the cache with attestations and pushed by digest only (`push-by-digest`), so nothing reaches Docker Hub before it passes and nothing is pulled back from Hub (the run on 22 October 2026 exhausted a Personal account's 200 pulls per six hours in the sign step; images have published under the `rollogi` organisation on a Docker Team plan, which has no pull limit, since that day, while `DOCKER_USER` remains the member account that logs in) (a Personal Hub account has 200 pulls per six hours and the run on 22 October 2026 exhausted them in the sign step; `test.sh` pulls Mailpit from `ghcr.io` for the same reason) (health endpoint, PHP version, extensions, package consistency, no setuid files, tagged logs, read-only recipe, root and arbitrary-user modes, redirect host, metrics, cron, mail, worker, APP_INSTALL, Xdebug toggle). The publish job joins the two digests into a manifest list as `:candidate-<sha>[-<minor>]`, VEX-attests it and promotes it to its real tags with `docker buildx imagetools create`. After promotion the manifest list is signed keylessly with cosign (`sigstore/cosign-installer`, workflow has `id-token: write`); verify with `cosign verify --certificate-oidc-issuer https://token.actions.githubusercontent.com --certificate-identity-regexp '^https://github.com/AdamRollinson/docker/\.github/workflows/docker-build\.yml@refs/heads/main$' <image>`. Candidate tags are deleted via the Docker Hub API afterwards (best effort)
- `DOCKER_PAT` is only exposed to the login and candidate-cleanup steps, never at workflow scope
- **apk cache busting**: `php-matrix` runs `alpine/apk-index-hash.sh` (no arguments: sha256 of the sorted repo/arch/name/version tuples from the base image's release branch, main and community, both architectures; fails if any index cannot be fetched) and exposes it as `apk`. Every build step (local and by-digest, which must match so the push build hits the cache) passes it as `APK_INDEX_HASH`, an `ARG` declared just before the `apk` step in each Dockerfile (php-fpm included), so the GHA layer cache never serves stale packages; before this the 26 October 2026 weekly run reused a cached base layer with `curl 8.22.0` and failed Trivy on CVE-2026-92392 although `8.23.0` was in v3.24. `build-base` therefore needs `php-matrix`. The PHP source and PECL archives are pinned by version and checksum, so their layers only rebuild when the pins or the apk hash change. Compiling PHP makes a cold php build take several minutes per minor and architecture
- Buildx is pinned to a mainline release via `BUILDX_VERSION`. Dependabot covers both GitHub Actions and the `alpine/base` Docker digest
- **Build strategy**: `php-matrix` turns `alpine/php-versions.txt` into two matrices (`matrix`: one entry per minor with `minor`/`patch`/`sha256`/`url`/`tag`/`prerelease`, the php builds passing `sha256`/`url` as `PHP_SOURCE_SHA256`/`PHP_SOURCE_URL`; `build_matrix`: the same crossed with `arch`/`platform`/`runner`). `build-base` (per arch) → `publish-base` → `build-php` (per minor × arch, chains php → php-nginx → php-nginx-dev and php → php-fpm on one runner, each `FROM` the digest just pushed via the `PHP_IMAGE` build arg) → `publish-php` (per minor, `if: !cancelled()` so one failing minor does not block the others, but skipped outright when `build-php` was skipped); its first step writes the space-separated `IMAGES` list to `GITHUB_ENV` and every candidate, promote, sign, verify and cleanup loop iterates over it. Digests travel between jobs as artifacts named `digests-<image>-<minor>-<arch>`, one empty file per image named `"<image> <digest>"`
- Each image is promoted with two tags: `:{tag}` (minor or channel) and `:{patch}`
- **Native multi-arch**: amd64 on `ubuntu-24.04`, arm64 on `ubuntu-24.04-arm` (free for public repos), plain **buildx** with the `docker-container` driver, no QEMU. Layer cache lives in the GitHub Actions cache (`type=gha`, one scope per image and arch). Docker Build Cloud was dropped in October 2026 after its builder started refusing builds (`concurrent build limit of 0`); QEMU emulation was dropped for native runners in the same month
- Publishes to Docker Hub with SBOM and provenance attestation
- VEX attestations via `docker/scout-action` (attestation-add command)
- Trivy vulnerability scanning (fails on CRITICAL/HIGH)
- **Releases and notifications**: the `release` job (`contents: write`, `if: !cancelled()`) runs after `publish-php` (skipped when that job was skipped) and, for every matrix entry that `publish-php` promoted in this run (it uploads a `published-<minor>` marker artifact after the verify step) and that has no `php-<patch>` GitHub release yet, creates one with `gh release create --target $GITHUB_SHA --latest=false` (plus `--prerelease` for `_` pins) using notes from `alpine/release-notes.sh` (image digests via `imagetools inspect`, cosign verify snippet; exits 3 when the tag is not on Hub). The `notify` job (`if: always()`) and the bump workflow call `alpine/notify.sh <status> <title> <message> [url]`, which POSTs JSON (`text` and `content` plus structured fields) to `NOTIFY_WEBHOOK_URL` and is a no-op when the secret is unset
- **Required secrets/vars**: `DOCKER_USER` (variable: the Hub account that logs in, a member of the `rollogi` organisation; the namespace itself is `DOCKER_REGISTRY` in the workflow env), `DOCKER_PAT` (secret for that account, needs read/write/delete scope so candidate tags can be removed), `NOTIFY_WEBHOOK_URL` (optional secret)

### Runtime user
`appuser` is created in the base Dockerfile from the `APP_UID`/`APP_GID` build args (default 1000) and exported as env vars of the same name; `build.sh` forwards `APP_UID`/`APP_GID` from the environment. Derived images chown by name, so a custom UID propagates without changes. Never reintroduce setuid helpers (gosu, su-exec) for identity switching.

## Documentation site (`docs/`)

A Nuxt 4 site built from the Nuxt UI docs template with `@nuxt/ui`, `@nuxt/content`, `nuxt-og-image` and `nuxt-llms`. Package manager is **pnpm** (lockfile present); run commands from `docs/`: `pnpm dev`, `pnpm check` (lint + typecheck), `pnpm generate` (static output in `.output/public`). Content is Markdown under `docs/content/` with numeric prefixes for ordering and `.navigation.yml` per section; the landing page is `content/index.md`. Site URL comes from `NUXT_PUBLIC_SITE_URL`. Deployment is a Cloudflare Workers static-assets Worker built by Workers Builds from the repo (root directory `docs`, build `pnpm generate`, deploy `npx wrangler deploy`, config in `docs/wrangler.jsonc` with no Worker script). `nitro.preset` is pinned to `static` because Cloudflare's build environment otherwise auto-selects `cloudflare-module` and the deploy fails looking for a server entry point. `.github/workflows/docs-ci.yml` only lints, typechecks and generates on changes under `docs/`. `docs/public/_headers` sets caching (hashed assets immutable, pages revalidate) and security headers including a CSP (inline scripts/styles, `wasm-unsafe-eval` and blob workers for client-side search, and Cloudflare Web Analytics hosts because the edge injects its beacon; new external resources need a CSP source). Nuxt Icon runs with `provider: 'none'` and a client-bundle scan that includes `content/`, so every icon is bundled at build time and nothing is fetched from api.iconify.design at runtime (the default scan misses content frontmatter and the Cloudflare build environment switched the server bundle to remote, which the CSP blocked); `docs/public/robots.txt` allows all crawlers including AI and links `llms.txt` and the `@nuxtjs/sitemap`-generated `sitemap.xml`; `docs/public/.well-known/security.txt` carries reporting contacts with a yearly `Expires`. When image behaviour or variables change, update the corresponding page under `docs/content/` alongside `README.md` and `ENV.md`.

## Key Files

| Path | Purpose |
|------|---------|
| `alpine/build.sh` | Local build script for all images |
| `alpine/php-versions.txt` | Pinned PHP release, tarball sha256 and URL per supported minor version |
| `alpine/check-php-versions.sh` | Compares pins with php.net (and PECL pins with PECL), `--update` rewrites them |
| `alpine/apk-index-hash.sh` | Hashes the Alpine package indexes for the `APK_INDEX_HASH` cache-busting build arg |
| `alpine/test.sh` | Smoke tests run by CI against each candidate image; `test.sh all 8.4` runs everything against local images |
| `.github/workflows/php-version-bump.yml` | Four-hourly job that bumps pins and dispatches the build |
| `alpine/base/Dockerfile` | Base Alpine image with common tooling |
| `alpine/php/Dockerfile` | Multi-stage PHP image: compiles PHP CLI + FPM and PECL extensions from source, adds Composer |
| `alpine/php/php-ext-install` | Builds a bundled or PECL extension with phpize and enables it (used by the builder, php-nginx-dev and derived images) |
| `alpine/php/pecl-extensions.txt` | PECL extensions with pinned version, sha256 and minors, per image (php or dev) |
| `alpine/php/php-keyring.asc` | php.net release managers' GPG keyring used to verify the PHP tarball |
| `alpine/php/php.ini.template` | Runtime PHP configuration template |
| `alpine/php/php-entrypoint.sh` | PHP container entrypoint (envsubst) |
| `alpine/php-nginx/Dockerfile` | Nginx + PHP-FPM image |
| `alpine/php-nginx/app.conf.template` | Nginx HTTP-only server config template |
| `alpine/php-nginx/app-ssl.conf.template` | Nginx HTTPS server config template |
| `alpine/php-nginx/app-ssl-redirect.conf.template` | HTTP→HTTPS redirect template |
| `alpine/php/www.conf.template` | PHP-FPM pool configuration template (shipped by php, rendered by php-nginx and php-fpm) |
| `alpine/php-nginx/php-nginx-entrypoint.sh` | Nginx container entrypoint (SSL logic, envsubst) |
| `alpine/php-nginx/healthcheck.sh` | Docker HEALTHCHECK wrapper (HTTP/HTTPS aware) |
| `alpine/base/entrypoint-lib.sh` | Shared entrypoint helpers (`log`, `json_escape`, `apply_ini_overrides`, `render_crontab`, `render_msmtp`, `run_app_install`, `render_fpm_config`) |
| `alpine/base/run-service` | Service wrapper that tags or JSON-wraps log lines per service |
| `alpine/base/container-logs` | Tails per-service log files in `LOG_MODE=file` |
| `alpine/php-nginx-dev/Dockerfile` | Xdebug development image |
| `alpine/php-nginx-dev/php-nginx-dev-entrypoint.sh` | Renders Xdebug ini and no-cache snippet, then chains to php-nginx entrypoint |
| `alpine/php-fpm/Dockerfile` | PHP-FPM only image |
| `alpine/php-fpm/php-fpm-entrypoint.sh` | Renders php.ini and the pool, runs php-fpm (and cron) |
| `alpine/php-fpm/php-fpm-healthcheck` | FastCGI ping healthcheck |
| `alpine/frankenphp/Dockerfile` | FrankenPHP image: ZTS PHP + FrankenPHP from source (build context `alpine/`) |
| `alpine/frankenphp/frankenphp-version.txt` | Pinned FrankenPHP release (with sha256) and Go toolchain version |
| `alpine/frankenphp/Caddyfile` | Caddy config with `{$VAR}` placeholders, shipped as is |
| `alpine/frankenphp/frankenphp-entrypoint.sh` | Renders php.ini, derives Caddy log and worker settings, runs FrankenPHP (and cron) |
| `ENV.md` | Complete environment variable reference |
| `docs/` | Nuxt documentation site deployed to Cloudflare Workers as static assets |
| `SECURITY.md` | CVE details and VEX attestation documentation |
