#!/bin/bash

# Smoke tests for the published images. Every check here was once done by hand; CI runs
# them against each candidate image before it is promoted to a public tag.
#
#   alpine/test.sh base          IMAGE
#   alpine/test.sh php           IMAGE EXPECTED_PHP_VERSION
#   alpine/test.sh php-nginx     IMAGE EXPECTED_PHP_VERSION
#   alpine/test.sh php-nginx-dev IMAGE EXPECTED_PHP_VERSION
#   alpine/test.sh all           MINOR            # local images rollogi/*:MINOR (or *:MINOR-rc for a pre-release), version from php-versions.txt
#
# Exits non-zero on the first failing check. Needs docker and curl.

set -euo pipefail

PREFIX="${IMAGE_PREFIX:-rollogi}"
WORK=$(mktemp -d)
CONTAINERS=()
cleanup() {
    for c in "${CONTAINERS[@]:-}"; do [ -n "$c" ] && docker rm -f "$c" >/dev/null 2>&1 || true; done
    rm -rf "$WORK"
}
trap cleanup EXIT

pass() { echo "  ok   $1"; }
fail() { echo "  FAIL $1"; [ $# -gt 1 ] && printf '%s\n' "$2" | sed 's/^/       /'; exit 1; }

# Pick a free TCP port on the host
free_port() {
    python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()' 2>/dev/null \
        || echo $((20000 + RANDOM % 20000))
}

# Start a container, record it for cleanup, wait for /health and then for PHP-FPM to answer
# (nginx comes up a moment before php-fpm, so /health alone is not proof that PHP is ready)
start_web() {
    local port=$1; shift
    local cid
    cid=$(docker run -d --rm -p "127.0.0.1:${port}:8080" -e NGINX_PORT=8080 "$@")
    CONTAINERS+=("$cid")
    for _ in $(seq 1 40); do
        curl -sf "http://127.0.0.1:${port}/health" >/dev/null 2>&1 && break
        sleep 0.5
    done
    for _ in $(seq 1 40); do
        local code
        code=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${port}/")
        [ "$code" = "200" ] && { echo "$cid"; return 0; }
        sleep 0.5
    done
    echo "container did not become ready; last status $code; logs:" >&2
    docker logs "$cid" 2>&1 | tail -20 >&2
    return 1
}

normalise() { printf '%s' "$1" | tr -d '_' | tr 'A-Z' 'a-z'; }

# Fixture web root: a PHP page, a hidden file, a static asset
make_fixture() {
    mkdir -p "$WORK/www/.well-known/acme-challenge"
    printf '<?php header("Content-Type: text/plain"); echo PHP_VERSION, " ", ini_get("memory_limit"), " ", (int)extension_loaded("xdebug");' > "$WORK/www/index.php"
    printf 'SECRET=1\n' > "$WORK/www/.env"
    printf 'token\n' > "$WORK/www/.well-known/acme-challenge/abc"
    printf 'body{}\n' > "$WORK/www/app.css"
    chmod -R a+rX "$WORK/www"
}

test_common() { # IMAGE  - checks shared by every image
    local img=$1
    local n
    n=$(docker run --rm --entrypoint sh "$img" -c 'find / -xdev -type f -perm /6000 2>/dev/null | wc -l | tr -d " "')
    [ "$n" = "0" ] && pass "no setuid or setgid binaries" || fail "found $n setuid/setgid binaries"
    docker run --rm --entrypoint sh "$img" -c 'test -x /usr/local/bin/run-service && test -r /usr/local/lib/entrypoint-lib.sh' \
        && pass "logging helpers present" || fail "run-service or entrypoint-lib.sh missing"
    local uid
    uid=$(docker run --rm --entrypoint sh "$img" -c 'id -u')
    [ "$uid" != "0" ] && pass "default user is unprivileged (uid $uid)" || fail "default user is root"
    docker run --rm --entrypoint sh "$img" -c '! command -v python3 >/dev/null && ! command -v supervisord >/dev/null' \
        && pass "no python or supervisord in the image" || fail "python or supervisord present"
}

test_base() {
    local img=$1
    echo "== base: $img"
    test_common "$img"
    docker run --rm --entrypoint sh "$img" -c 'command -v tini >/dev/null && command -v envsubst >/dev/null && command -v curl >/dev/null' \
        && pass "tini, envsubst and curl present" || fail "expected tooling missing"
}

test_php() {
    local img=$1 expected; expected=$(normalise "$2")
    echo "== php: $img (expect $2)"
    test_common "$img"
    local got
    got=$(docker run --rm "$img" php -r 'echo strtolower(PHP_VERSION);' 2>/dev/null)
    [ "$got" = "$expected" ] && pass "php reports $2" || fail "php reports '$got', expected '$expected'"
    local warnings
    warnings=$(docker run --rm "$img" php -r 'echo 1;' 2>&1 | grep -c "Warning" || true)
    [ "$warnings" = "0" ] && pass "no startup warnings" || fail "$warnings startup warning(s)" "$(docker run --rm "$img" php -r 'echo 1;' 2>&1 | head -5)"
    local missing
    missing=$(docker run --rm "$img" php -r 'foreach (["curl","mbstring","intl","pdo_mysql","mysqli","gd","zip","soap","redis","openssl","sockets","Zend OPcache"] as $e) if (!extension_loaded($e)) echo $e, " ";')
    [ -z "$missing" ] && pass "required extensions loaded" || fail "extensions missing: $missing"
    local mismatched
    mismatched=$(docker run --rm --entrypoint sh "$img" -c 'apk list -I 2>/dev/null | awk "{print \$1}" | grep "^php" | grep -v -- "-pecl-" | grep -v -- "-$(php -r "echo PHP_VERSION;" | tr "A-Z" "a-z" | sed -E "s/([0-9])(rc|beta|alpha)/\1_\2/")-r" || true')
    [ -z "$mismatched" ] && pass "every php package at the same release" || fail "mismatched php packages" "$mismatched"
    docker run --rm "$img" composer --version >/dev/null 2>&1 && pass "composer runs" || fail "composer does not run"
    docker run --rm --user 4321:4321 "$img" composer --version >/dev/null 2>&1 && pass "composer runs as an arbitrary --user (COMPOSER_HOME under /tmp)" || fail "composer fails for --user 4321" "$(docker run --rm --user 4321:4321 "$img" composer --version 2>&1 | tail -3)"
    docker run --rm --user 0 "$img" composer --version 2>&1 | grep -qi "superuser" && fail "composer warns about running as root in root mode" || pass "composer silent about root in root mode"
    local inst
    inst=$(docker run --rm -e APP_INSTALL='echo prepared in $(pwd)' "$img" php -r 'echo "main";' 2>&1)
    echo "$inst" | grep -q '^\[install\] prepared in /app$' && echo "$inst" | grep -q 'main$' && pass "APP_INSTALL runs in /app before the command, tagged [install]" || fail "APP_INSTALL output unexpected" "$inst"
    inst=$(docker run --rm -e APP_INSTALL='echo prepared in $(pwd)' -e APP_INSTALL_DIR=/tmp "$img" php -r 'echo "main";' 2>&1)
    echo "$inst" | grep -q '^\[install\] prepared in /tmp$' && pass "APP_INSTALL_DIR changes the install directory" || fail "APP_INSTALL_DIR ignored" "$inst"
    local st
    st=$(docker run --rm -e APP_INSTALL='echo broken >&2; exit 7' "$img" php -r 'echo "main";' 2>/dev/null; echo "exit=$?")
    [ "$st" = "exit=7" ] && pass "failed APP_INSTALL stops the container with its exit status and runs nothing else" || fail "failed APP_INSTALL did not stop the container ('$st')"
    local ml
    ml=$(docker run --rm -e "php.memory_limit=321M" "$img" php -r 'echo ini_get("memory_limit");' 2>/dev/null)
    [ "$ml" = "321M" ] && pass "php.* override applies (memory_limit=321M)" || fail "php.* override ignored (got '$ml')"
    local noise
    noise=$(docker run --rm -e "php.memory_limit=321M" "$img" php -r 'echo "x";' 2>/dev/null)
    [ "$noise" = "x" ] && pass "entrypoint keeps stdout clean for CLI output" || fail "entrypoint wrote to stdout: '$noise'"
    docker run --rm "$img" php --ini 2>/dev/null | grep -q "/run/php/php.ini" && pass "php.ini loaded from /run/php" || fail "php.ini not loaded from /run/php"
    # mail relay: php mail() through msmtp to a Mailpit sink on a private network
    local net mp cid
    net="imgtest-$$-$RANDOM"
    docker network create "$net" >/dev/null
    mp=$(docker run -d --rm --network "$net" --name "mailpit-$$" -p 127.0.0.1::8025 ghcr.io/axllent/mailpit:latest)
    CONTAINERS+=("$mp")
    local mpport
    mpport=$(docker port "$mp" 8025/tcp | head -1 | sed 's/.*://')
    for _ in $(seq 1 30); do curl -sf "http://127.0.0.1:${mpport}/api/v1/info" >/dev/null 2>&1 && break; sleep 0.5; done
    local mail_out
    mail_out=$(docker run --rm --network "$net" -e SMTP_HOST="mailpit-$$" -e SMTP_PORT=1025 -e SMTP_FROM=test@example.test "$img" \
        php -r 'var_dump(mail("to@example.test", "smoke test", "hello from the image"));' 2>&1)
    local count
    count=$(curl -s "http://127.0.0.1:${mpport}/api/v1/messages" | grep -o '"total":[0-9]*' | head -1 | cut -d: -f2)
    docker rm -f "$mp" >/dev/null 2>&1; docker network rm "$net" >/dev/null 2>&1
    [ "${count:-0}" = "1" ] && pass "mail() relays through msmtp to SMTP_HOST" || fail "mail relay did not deliver (messages=${count:-0})" "$mail_out"
    local sp
    sp=$(docker run --rm "$img" php -r 'echo ini_get("sendmail_path");' 2>/dev/null)
    [ -z "$sp" ] && pass "sendmail_path untouched without SMTP_HOST" || fail "sendmail_path set without SMTP_HOST: '$sp'"
    cid=$(docker run -d --rm -e CRON_SCHEDULE='*/1 * * * * * *' -e CRON_COMMAND='echo cli-cron-tick' "$img" cron)
    CONTAINERS+=("$cid")
    sleep 4
    docker logs "$cid" 2>&1 | grep -q '^\[cron\] cli-cron-tick' && pass "cron command runs a scheduler container" || fail "cron command did not run jobs" "$(docker logs "$cid" 2>&1 | tail -5)"
    docker rm -f "$cid" >/dev/null
    # worker mode restarts the command when it exits
    cid=$(docker run -d --rm -e CLI_COMMAND='echo worker-run; exit 1' -e CLI_RESTART_DELAY=1 "$img")
    CONTAINERS+=("$cid")
    sleep 4
    local runs
    runs=$(docker logs "$cid" 2>&1 | grep -c '^\[worker\] worker-run' || true)
    [ "$runs" -ge 2 ] && pass "worker mode restarts the command ($runs runs in 4s)" || fail "worker mode did not restart" "$(docker logs "$cid" 2>&1 | tail -5)"
    docker rm -f "$cid" >/dev/null
    cid=$(docker run -d -e CLI_COMMAND='exit 3' -e CLI_RESTART_DELAY=0 -e CLI_MAX_RESTARTS=2 "$img")
    CONTAINERS+=("$cid")
    local st=""
    for _ in $(seq 1 20); do
        st=$(docker inspect "$cid" --format '{{.State.Status}}:{{.State.ExitCode}}')
        case "$st" in exited:*) break ;; esac
        sleep 0.5
    done
    [ "$st" = "exited:3" ] && pass "worker mode gives up after CLI_MAX_RESTARTS and propagates the exit status" || fail "worker did not stop after the restart limit (state $st)" "$(docker logs "$cid" 2>&1 | tail -4)"
    docker logs "$cid" 2>&1 | grep -q '^\[worker\] \[entrypoint\]' && fail "entrypoint messages double-tagged in worker mode" || pass "worker and entrypoint streams tagged separately"
    docker rm -f "$cid" >/dev/null 2>&1 || true
    local out
    out=$(docker run --rm -e CLI_COMMAND='echo should-not-run' "$img" php -r 'echo "explicit";' 2>/dev/null)
    [ "$out" = "explicit" ] && pass "an explicit command overrides CLI_COMMAND" || fail "CLI_COMMAND hijacked an explicit command: '$out'"
    # arbitrary --user: the run directories must be writable by any uid
    out=$(docker run --rm --user 4321:4321 -e "php.memory_limit=345M" "$img" php -r 'echo posix_getuid(), " ", ini_get("memory_limit");' 2>/dev/null)
    [ "$out" = "4321 345M" ] && pass "runs under an arbitrary --user with config rendered" || fail "arbitrary --user failed" "$out"
}

test_php_nginx() {
    local img=$1 expected; expected=$(normalise "$2")
    echo "== php-nginx: $img (expect $2)"
    test_common "$img"
    make_fixture
    local port cid
    port=$(free_port)
    cid=$(start_web "$port" -e "php.memory_limit=222M" -e "fpm.pool.pm.max_children=40" -v "$WORK/www:/var/www/html:ro" "$img") || fail "non-root container did not start"
    pass "non-root container healthy on /health"
    local body
    body=$(curl -s "http://127.0.0.1:${port}/")
    case "$body" in "$2 222M "*) pass "php via fpm reports $2 and php.* override applied" ;; *) [ "$(normalise "${body%% *}")" = "$expected" ] && [[ "$body" == *" 222M "* ]] && pass "php via fpm reports $2 and php.* override applied" || fail "unexpected response from fpm: '$body'" ;; esac
    local code
    code=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${port}/.env")
    [ "$code" = "403" ] && pass "hidden files denied (/.env -> 403)" || fail "/.env returned $code"
    code=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${port}/.well-known/acme-challenge/abc")
    [ "$code" = "200" ] && pass "/.well-known served" || fail "/.well-known returned $code"
    code=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${port}/app.css/evil.php")
    [ "$code" = "404" ] && pass "path-info attack rejected" || fail "/app.css/evil.php returned $code"
    local hdrs
    hdrs=$(curl -sI "http://127.0.0.1:${port}/" | tr -d '\r')
    for h in "X-Frame-Options" "X-Content-Type-Options" "Referrer-Policy" "Permissions-Policy"; do
        echo "$hdrs" | grep -qi "^$h:" || fail "missing security header $h"
    done
    pass "security headers present"
    echo "$hdrs" | grep -qi "^X-Powered-By" && fail "X-Powered-By header exposed" || pass "X-Powered-By hidden"
    local children
    children=$(docker exec "$cid" sh -c 'grep -E "^pm.max_children" /run/php/php-fpm.d/www.conf | tail -1')
    [[ "$children" == *"40"* ]] && pass "fpm.pool.* override applied" || fail "fpm.pool.* override ignored ('$children')"
    local untagged
    untagged=$(docker logs "$cid" 2>&1 | grep -cvE '^\[(entrypoint|nginx|php-fpm)\]' || true)
    [ "$untagged" = "0" ] && pass "all log lines tagged by service" || fail "$untagged untagged log line(s)" "$(docker logs "$cid" 2>&1 | grep -vE '^\[(entrypoint|nginx|php-fpm)\]' | head -3)"
    docker exec "$cid" sh -c '! test -w /etc/nginx/nginx.conf && ! test -w /etc/php*/php.ini' \
        && pass "/etc config not writable by runtime user" || fail "/etc config writable by runtime user"
    docker rm -f "$cid" >/dev/null

    # read-only root filesystem recipe
    port=$(free_port)
    cid=$(docker run -d --rm -p "127.0.0.1:${port}:8080" -e NGINX_PORT=8080 --read-only \
        --tmpfs /run:uid=1000,gid=1000 --tmpfs /tmp --tmpfs /var/log:uid=1000,gid=1000 --tmpfs /var/lib/nginx:uid=1000,gid=1000 \
        --cap-drop ALL --security-opt no-new-privileges -v "$WORK/www:/var/www/html:ro" "$img")
    CONTAINERS+=("$cid")
    for _ in $(seq 1 40); do curl -sf "http://127.0.0.1:${port}/health" >/dev/null 2>&1 && break; sleep 0.5; done
    curl -sf "http://127.0.0.1:${port}/health" >/dev/null && pass "read-only rootfs recipe works" || fail "read-only rootfs recipe failed" "$(docker logs "$cid" 2>&1 | tail -5)"
    docker rm -f "$cid" >/dev/null

    # arbitrary --user: every process runs as that uid and config is rendered into the run dirs
    port=$(free_port)
    cid=$(start_web "$port" --user 4321:4321 -e "php.memory_limit=345M" -v "$WORK/www:/var/www/html:ro" "$img") || fail "container did not start under --user 4321"
    body=$(curl -s "http://127.0.0.1:${port}/")
    [[ "$body" == *" 345M "* ]] && pass "arbitrary --user serves php with config rendered" || fail "arbitrary --user response unexpected: '$body'"
    docker exec "$cid" sh -c 'ps -o user,args | grep -E "nginx|php-fpm" | grep -v grep | grep -vq "^4321 "' && fail "a process is not running as uid 4321" "$(docker exec "$cid" ps -o user,args)" || pass "nginx and php-fpm run as uid 4321"
    docker rm -f "$cid" >/dev/null

    # root mode
    port=$(free_port)
    cid=$(docker run -d --rm --user root -p "127.0.0.1:${port}:80" "$img")
    CONTAINERS+=("$cid")
    for _ in $(seq 1 40); do curl -sf "http://127.0.0.1:${port}/health" >/dev/null 2>&1 && break; sleep 0.5; done
    curl -sf "http://127.0.0.1:${port}/health" >/dev/null && pass "root mode healthy on port 80" || fail "root mode failed" "$(docker logs "$cid" 2>&1 | tail -5)"
    docker exec "$cid" sh -c 'ps -o user,args | grep -E "nginx: worker" | grep -v grep | grep -q "^nginx"' && pass "nginx workers dropped to nginx user" || fail "nginx workers not running as nginx"
    docker rm -f "$cid" >/dev/null

    # APP_INSTALL runs in the document root before the services start, and a failure stops the container
    cid=$(start_web "$port" -e APP_INSTALL='echo web prepared in $(pwd)' -v "$WORK/www:/var/www/html:ro" "$img") || fail "container with APP_INSTALL did not start"
    docker logs "$cid" 2>&1 | grep -q '^\[install\] web prepared in /var/www/html$' && pass "APP_INSTALL runs in /var/www/html before the services" || fail "APP_INSTALL output missing" "$(docker logs "$cid" 2>&1 | head -5)"
    docker logs "$cid" 2>&1 | awk '/^\[install\]/ {i=NR} /Starting php-fpm/ {s=NR} END {exit !(i && s && i < s)}' && pass "APP_INSTALL finished before php-fpm and nginx were started" || fail "services started before APP_INSTALL finished" "$(docker logs "$cid" 2>&1 | head -8)"
    docker rm -f "$cid" >/dev/null
    cid=$(docker run -d -e NGINX_PORT=8080 -e APP_INSTALL='exit 5' "$img"); CONTAINERS+=("$cid")
    for _ in $(seq 1 20); do [ "$(docker inspect -f '{{.State.Status}}' "$cid")" = "exited" ] && break; sleep 0.5; done
    st="$(docker inspect -f '{{.State.Status}}:{{.State.ExitCode}}' "$cid")"
    [ "$st" = "exited:5" ] && pass "failed APP_INSTALL stops php-nginx with its exit status" || fail "php-nginx kept running after a failed APP_INSTALL (state $st)" "$(docker logs "$cid" 2>&1 | tail -4)"
    docker rm -f "$cid" >/dev/null
    port=$(free_port)

    # metrics listener on its own port, absent from the app port
    port=$(free_port); local mport; mport=$(free_port)
    cid=$(docker run -d --rm -p "127.0.0.1:${port}:8080" -p "127.0.0.1:${mport}:9090" -e NGINX_PORT=8080 -e NGINX_METRICS_PORT=9090 "$img")
    CONTAINERS+=("$cid")
    for _ in $(seq 1 40); do curl -sf "http://127.0.0.1:${port}/health" >/dev/null 2>&1 && break; sleep 0.5; done
    curl -s "http://127.0.0.1:${mport}/nginx_status" | grep -q "Active connections" && pass "nginx stub_status on the metrics port" || fail "nginx_status missing" "$(curl -s "http://127.0.0.1:${mport}/nginx_status" | head -3)"
    curl -s "http://127.0.0.1:${mport}/fpm-status" | grep -q "^pool:" && pass "php-fpm status on the metrics port" || fail "fpm-status missing" "$(curl -s "http://127.0.0.1:${mport}/fpm-status" | head -3)"
    [ "$(curl -s "http://127.0.0.1:${mport}/fpm-ping")" = "pong" ] && pass "php-fpm ping answers pong" || fail "fpm-ping did not answer pong"
    curl -s "http://127.0.0.1:${port}/nginx_status" | grep -q "Active connections" && fail "nginx_status exposed on the application port"
    curl -s "http://127.0.0.1:${port}/fpm-status" | grep -q "^pool:" && fail "fpm-status exposed on the application port"
    [ "$(curl -s "http://127.0.0.1:${port}/fpm-ping")" != "pong" ] || fail "fpm-ping exposed on the application port"
    pass "status endpoints are not served on the application port"
    docker rm -f "$cid" >/dev/null

    # cron as non-root via supercronic (7-field schedule = seconds granularity)
    port=$(free_port)
    cid=$(docker run -d --rm -p "127.0.0.1:${port}:8080" -e NGINX_PORT=8080 -e CRON_SCHEDULE='*/1 * * * * * *' -e CRON_COMMAND='echo cron-tick' "$img")
    CONTAINERS+=("$cid")
    sleep 4
    docker logs "$cid" 2>&1 | grep -q '^\[cron\] cron-tick' && pass "cron job runs as non-root with tagged output" || fail "cron job did not run" "$(docker logs "$cid" 2>&1 | tail -5)"
    docker rm -f "$cid" >/dev/null
    cid=$(docker run -d --rm -e NGINX_PORT=8080 -e CRON_SCHEDULE='not a schedule' -e CRON_COMMAND='true' "$img")
    CONTAINERS+=("$cid")
    sleep 3
    docker inspect "$cid" >/dev/null 2>&1 && fail "container kept running with an invalid crontab" || pass "invalid crontab fails fast"

    # HTTPS redirect does not reflect the Host header when a server name is set
    port=$(free_port)
    cid=$(docker run -d --rm -p "127.0.0.1:${port}:8080" -e NGINX_PORT=8080 -e NGINX_SERVER_NAME=app.example.com -e NGINX_SSL_ENABLED=true -e NGINX_SSL_PORT=8443 -e NGINX_SSL_SELF_SIGNED=true "$img")
    CONTAINERS+=("$cid")
    for _ in $(seq 1 40); do curl -sf "http://127.0.0.1:${port}/health" >/dev/null 2>&1 && break; sleep 0.5; done
    local loc
    loc=$(curl -sI -H "Host: evil.example.com" "http://127.0.0.1:${port}/x" | grep -i '^location' | tr -d '\r')
    [[ "$loc" == *"https://app.example.com:8443/x"* ]] && pass "HTTPS redirect pinned to configured host" || fail "redirect reflects Host header: '$loc'"
    docker rm -f "$cid" >/dev/null
}

test_php_nginx_dev() {
    local img=$1 expected; expected=$(normalise "$2")
    echo "== php-nginx-dev: $img (expect $2)"
    test_common "$img"
    make_fixture
    local port cid body
    port=$(free_port)
    cid=$(start_web "$port" -v "$WORK/www:/var/www/html:ro" "$img") || fail "dev container did not start"
    body=$(curl -s "http://127.0.0.1:${port}/")
    [[ "$body" == *" 1" ]] && pass "xdebug loaded in php-fpm" || fail "xdebug not loaded via fpm: '$body'"
    curl -sI "http://127.0.0.1:${port}/app.css" | grep -qi "no-store" && pass "assets served with no-store" || fail "asset caching not disabled"
    docker rm -f "$cid" >/dev/null
    port=$(free_port)
    cid=$(start_web "$port" -e PHP_DEBUGGER=none -v "$WORK/www:/var/www/html:ro" "$img") || fail "dev container (PHP_DEBUGGER=none) did not start"
    body=$(curl -s "http://127.0.0.1:${port}/")
    [[ "$body" == *" 0" ]] && pass "PHP_DEBUGGER=none leaves xdebug unloaded" || fail "xdebug still loaded with PHP_DEBUGGER=none: '$body'"
    docker rm -f "$cid" >/dev/null
}

case "${1:-}" in
    base)          test_base "$2" ;;
    php)           test_php "$2" "$3" ;;
    php-nginx)     test_php_nginx "$2" "$3" ;;
    php-nginx-dev) test_php_nginx_dev "$2" "$3" ;;
    all)
        minor="${2:?usage: test.sh all MINOR}"
        version=$(grep -E "^${minor//./\\.} " "$(dirname "$0")/php-versions.txt" | awk '{print $2}')
        [ -n "$version" ] || { echo "no pin for $minor in php-versions.txt" >&2; exit 2; }
        # pre-releases are tagged on a channel (8.6-rc), not the bare minor
        case "$version" in *_*) tag="${minor}-$(printf '%s' "${version#*_}" | tr -d '0-9')" ;; *) tag="$minor" ;; esac
        test_base "$PREFIX/base:latest"
        test_php "$PREFIX/php:$tag" "$version"
        test_php_nginx "$PREFIX/php-nginx:$tag" "$version"
        test_php_nginx_dev "$PREFIX/php-nginx-dev:$tag" "$version"
        ;;
    *) sed -n '3,12p' "$0"; exit 2 ;;
esac
echo "all checks passed"
