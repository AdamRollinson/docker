#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

# Define image names and tags
BASE_IMAGE="adamrollogi/base:latest"
PHP_IMAGE="adamrollogi/php"
PHP_NGINX_IMAGE="adamrollogi/php-nginx"
PHP_NGINX_DEV_IMAGE="adamrollogi/php-nginx-dev"
PHP_VERSIONS_FILE="$(dirname "$0")/php-versions.txt"

# Read "<minor> <release>" pairs from php-versions.txt, skipping comments and blank lines
read_php_versions() {
    grep -Ev '^[[:space:]]*(#|$)' "$PHP_VERSIONS_FILE"
}

# Optional UID/GID for the runtime user (defaults to 1000:1000 inside the Dockerfile)
BASE_BUILD_ARGS=()
[ -n "${APP_UID:-}" ] && BASE_BUILD_ARGS+=(--build-arg "APP_UID=$APP_UID")
[ -n "${APP_GID:-}" ] && BASE_BUILD_ARGS+=(--build-arg "APP_GID=$APP_GID")

# Build base image
echo "🚀 Building base image: $BASE_IMAGE${APP_UID:+ (uid $APP_UID${APP_GID:+:$APP_GID})}"
docker build "${BASE_BUILD_ARGS[@]}" -t "$BASE_IMAGE" ./base

# Build PHP images
while read -r version patch; do
    PHP_VERSION_ENV=$(echo "$version" | tr -d '.')
    IMAGE_TAG="$PHP_IMAGE:$version"
    PATCH_TAG="$PHP_IMAGE:$patch"

    echo "🐘 Building PHP image: $IMAGE_TAG ($PATCH_TAG) with PHP_VERSION=$PHP_VERSION_ENV PHP_PATCH_VERSION=$patch${PHP_EXTRA_EXTENSIONS:+ PHP_EXTRA_EXTENSIONS=\"$PHP_EXTRA_EXTENSIONS\"}"
    docker build \
        --build-arg PHP_VERSION="$PHP_VERSION_ENV" \
        --build-arg PHP_PATCH_VERSION="$patch" \
        --build-arg PHP_EXTRA_EXTENSIONS="${PHP_EXTRA_EXTENSIONS:-}" \
        -t "$IMAGE_TAG" \
        -t "$PATCH_TAG" \
        ./php
done < <(read_php_versions)

# Build PHP-NGINX images
while read -r version patch; do
    PHP_VERSION_ENV=$(echo "$version" | tr -d '.')
    IMAGE_TAG="$PHP_NGINX_IMAGE:$version"
    PATCH_TAG="$PHP_NGINX_IMAGE:$patch"

    echo "🌐 Building PHP-NGINX image: $IMAGE_TAG ($PATCH_TAG) with PHP_IMAGE_TAG=$version and PHP_VERSION=$PHP_VERSION_ENV"
    docker build \
        --build-arg PHP_IMAGE_TAG="$version" \
        --build-arg PHP_VERSION="$PHP_VERSION_ENV" \
        -t "$IMAGE_TAG" \
        -t "$PATCH_TAG" \
        ./php-nginx
done < <(read_php_versions)

# Build PHP-NGINX-DEV images
while read -r version patch; do
    PHP_VERSION_ENV=$(echo "$version" | tr -d '.')
    IMAGE_TAG="$PHP_NGINX_DEV_IMAGE:$version"
    PATCH_TAG="$PHP_NGINX_DEV_IMAGE:$patch"

    echo "🐞 Building PHP-NGINX-DEV image: $IMAGE_TAG ($PATCH_TAG) with PHP_IMAGE_TAG=$version and PHP_VERSION=$PHP_VERSION_ENV"
    docker build \
        --build-arg PHP_IMAGE_TAG="$version" \
        --build-arg PHP_VERSION="$PHP_VERSION_ENV" \
        -t "$IMAGE_TAG" \
        -t "$PATCH_TAG" \
        ./php-nginx-dev
done < <(read_php_versions)

echo "✅ All images built successfully!"
