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

# Build base image
echo "🚀 Building base image: $BASE_IMAGE"
docker build -t "$BASE_IMAGE" ./base

# Build PHP images
while read -r version patch; do
    PHP_VERSION_ENV=$(echo "$version" | tr -d '.')
    IMAGE_TAG="$PHP_IMAGE:$version"
    PATCH_TAG="$PHP_IMAGE:$patch"

    echo "🐘 Building PHP image: $IMAGE_TAG ($PATCH_TAG) with PHP_VERSION=$PHP_VERSION_ENV PHP_PATCH_VERSION=$patch"
    docker build \
        --build-arg PHP_VERSION="$PHP_VERSION_ENV" \
        --build-arg PHP_PATCH_VERSION="$patch" \
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
