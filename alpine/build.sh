#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

# Define image names and tags
BASE_IMAGE="adamrollogi/base:latest"
PHP_VERSIONS=("8.1" "8.2" "8.3" "8.4")
PHP_IMAGE="adamrollogi/php"
PHP_NGINX_IMAGE="adamrollogi/php-nginx"

# Build base image
echo "🚀 Building base image: $BASE_IMAGE"
docker build -t "$BASE_IMAGE" ./base

# Build PHP images
for version in "${PHP_VERSIONS[@]}"; do
    PHP_VERSION_ENV=$(echo "$version" | tr -d '.')
    IMAGE_TAG="$PHP_IMAGE:$version"

    echo "🐘 Building PHP image: $IMAGE_TAG with PHP_VERSION=$PHP_VERSION_ENV"
    docker build \
        --build-arg PHP_VERSION=$PHP_VERSION_ENV \
        -t "$IMAGE_TAG" \
        ./php
done

# Build PHP-NGINX images
for version in "${PHP_VERSIONS[@]}"; do
    PHP_VERSION_ENV=$(echo "$version" | tr -d '.')
    IMAGE_TAG="$PHP_NGINX_IMAGE:$version"

    echo "🌐 Building PHP-NGINX image: $IMAGE_TAG with PHP_IMAGE_TAG=$version and PHP_VERSION=$PHP_VERSION_ENV"
    docker build \
        --build-arg PHP_IMAGE_TAG=$version \
        --build-arg PHP_VERSION=$PHP_VERSION_ENV \
        -t "$IMAGE_TAG" \
        ./php-nginx
done

echo "✅ All images built successfully!"
