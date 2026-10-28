#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

# Define image names and tags
BASE_IMAGE="rollogi/base:latest"
PHP_IMAGE="rollogi/php"
PHP_NGINX_IMAGE="rollogi/php-nginx"
PHP_NGINX_DEV_IMAGE="rollogi/php-nginx-dev"
PHP_FPM_IMAGE="rollogi/php-fpm"
PHP_DEV_IMAGE="rollogi/php-dev"
PHP_SLIM_IMAGE="rollogi/php-slim"
PHP_VERSIONS_FILE="$(dirname "$0")/php-versions.txt"

# Read "<minor> <release> <sha256> <url>" lines from php-versions.txt, skipping comments and blank lines
read_php_versions() {
    grep -Ev '^[[:space:]]*(#|$)' "$PHP_VERSIONS_FILE"
}

# Moving tag for a minor: the minor itself for a final release, or a channel tag such as
# 8.6-rc for a pre-release (8.6.0_rc3), so the bare minor tag never points at a candidate
channel_tag() {
    local minor=$1 release=$2
    case "$release" in
        *_*) echo "${minor}-$(printf '%s' "${release#*_}" | tr -d '0-9')" ;;
        *)   echo "$minor" ;;
    esac
}

# Optional UID/GID for the runtime user (defaults to 1000:1000 inside the Dockerfile)
BASE_BUILD_ARGS=()
[ -n "${APP_UID:-}" ] && BASE_BUILD_ARGS+=(--build-arg "APP_UID=$APP_UID")
[ -n "${APP_GID:-}" ] && BASE_BUILD_ARGS+=(--build-arg "APP_GID=$APP_GID")

# Build base image
echo "🚀 Building base image: $BASE_IMAGE${APP_UID:+ (uid $APP_UID${APP_GID:+:$APP_GID})}"
docker build "${BASE_BUILD_ARGS[@]}" -t "$BASE_IMAGE" ./base

# Build PHP images (compiled from the pinned php.net tarball)
while read -r version patch sha256 url; do
    PHP_VERSION_ENV=$(echo "$version" | tr -d '.')
    CHANNEL=$(channel_tag "$version" "$patch")
    IMAGE_TAG="$PHP_IMAGE:$CHANNEL"
    PATCH_TAG="$PHP_IMAGE:$patch"

    echo "🐘 Building PHP image: $IMAGE_TAG ($PATCH_TAG) with PHP_VERSION=$PHP_VERSION_ENV PHP_PATCH_VERSION=$patch${PHP_EXTRA_EXTENSIONS:+ PHP_EXTRA_EXTENSIONS=\"$PHP_EXTRA_EXTENSIONS\"}"
    docker build \
        --build-arg PHP_VERSION="$PHP_VERSION_ENV" \
        --build-arg PHP_PATCH_VERSION="$patch" \
        --build-arg PHP_SOURCE_SHA256="$sha256" \
        --build-arg PHP_SOURCE_URL="$url" \
        --build-arg PHP_EXTRA_EXTENSIONS="${PHP_EXTRA_EXTENSIONS:-}" \
        --build-arg PHP_EXTRA_BUILD_DEPS="${PHP_EXTRA_BUILD_DEPS:-}" \
        -t "$IMAGE_TAG" \
        -t "$PATCH_TAG" \
        ./php

    # php-slim: the same build stage (reused from the cache), on plain Alpine
    echo "🪶 Building PHP-SLIM image: $PHP_SLIM_IMAGE:$CHANNEL ($PHP_SLIM_IMAGE:$patch)"
    docker build \
        --target slim \
        "${BASE_BUILD_ARGS[@]}" \
        --build-arg PHP_VERSION="$PHP_VERSION_ENV" \
        --build-arg PHP_PATCH_VERSION="$patch" \
        --build-arg PHP_SOURCE_SHA256="$sha256" \
        --build-arg PHP_SOURCE_URL="$url" \
        --build-arg PHP_EXTRA_EXTENSIONS="${PHP_EXTRA_EXTENSIONS:-}" \
        --build-arg PHP_EXTRA_BUILD_DEPS="${PHP_EXTRA_BUILD_DEPS:-}" \
        -t "$PHP_SLIM_IMAGE:$CHANNEL" \
        -t "$PHP_SLIM_IMAGE:$patch" \
        ./php
done < <(read_php_versions)

# Build PHP-NGINX images
while read -r version patch _; do
    PHP_VERSION_ENV=$(echo "$version" | tr -d '.')
    CHANNEL=$(channel_tag "$version" "$patch")
    IMAGE_TAG="$PHP_NGINX_IMAGE:$CHANNEL"
    PATCH_TAG="$PHP_NGINX_IMAGE:$patch"

    echo "🌐 Building PHP-NGINX image: $IMAGE_TAG ($PATCH_TAG) with PHP_IMAGE_TAG=$CHANNEL and PHP_VERSION=$PHP_VERSION_ENV"
    docker build \
        --build-arg PHP_IMAGE_TAG="$CHANNEL" \
        --build-arg PHP_VERSION="$PHP_VERSION_ENV" \
        -t "$IMAGE_TAG" \
        -t "$PATCH_TAG" \
        ./php-nginx
done < <(read_php_versions)

# Build PHP-NGINX-DEV images
while read -r version patch _; do
    PHP_VERSION_ENV=$(echo "$version" | tr -d '.')
    CHANNEL=$(channel_tag "$version" "$patch")
    IMAGE_TAG="$PHP_NGINX_DEV_IMAGE:$CHANNEL"
    PATCH_TAG="$PHP_NGINX_DEV_IMAGE:$patch"

    echo "🐞 Building PHP-NGINX-DEV image: $IMAGE_TAG ($PATCH_TAG) with PHP_IMAGE_TAG=$CHANNEL and PHP_VERSION=$PHP_VERSION_ENV"
    docker build \
        --build-arg PHP_IMAGE_TAG="$CHANNEL" \
        --build-arg PHP_VERSION="$PHP_VERSION_ENV" \
        -t "$IMAGE_TAG" \
        -t "$PATCH_TAG" \
        ./php-nginx-dev
done < <(read_php_versions)

# Build PHP-FPM images (on the php image, without a web server)
while read -r version patch _; do
    PHP_VERSION_ENV=$(echo "$version" | tr -d '.')
    CHANNEL=$(channel_tag "$version" "$patch")
    IMAGE_TAG="$PHP_FPM_IMAGE:$CHANNEL"
    PATCH_TAG="$PHP_FPM_IMAGE:$patch"

    echo "⚙️  Building PHP-FPM image: $IMAGE_TAG ($PATCH_TAG) with PHP_IMAGE_TAG=$CHANNEL and PHP_VERSION=$PHP_VERSION_ENV"
    docker build \
        --build-arg PHP_IMAGE_TAG="$CHANNEL" \
        --build-arg PHP_VERSION="$PHP_VERSION_ENV" \
        -t "$IMAGE_TAG" \
        -t "$PATCH_TAG" \
        ./php-fpm
done < <(read_php_versions)

# Build PHP-DEV images (the CLI with Xdebug and PCOV, on the php image)
while read -r version patch _; do
    PHP_VERSION_ENV=$(echo "$version" | tr -d '.')
    CHANNEL=$(channel_tag "$version" "$patch")
    IMAGE_TAG="$PHP_DEV_IMAGE:$CHANNEL"
    PATCH_TAG="$PHP_DEV_IMAGE:$patch"

    echo "🧪 Building PHP-DEV image: $IMAGE_TAG ($PATCH_TAG) with PHP_IMAGE_TAG=$CHANNEL and PHP_VERSION=$PHP_VERSION_ENV"
    docker build \
        --build-arg PHP_IMAGE_TAG="$CHANNEL" \
        --build-arg PHP_VERSION="$PHP_VERSION_ENV" \
        -t "$IMAGE_TAG" \
        -t "$PATCH_TAG" \
        ./php-dev
done < <(read_php_versions)

echo "✅ All images built successfully!"
