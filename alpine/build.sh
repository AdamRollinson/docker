#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

# Define image names and tags
BASE_IMAGE="adamrollogi/base:latest"
PHP_VERSIONS=("8.1" "8.2" "8.3" "8.4")
PHP_IMAGE="adamrollogi/php"
PHP_NGINX_IMAGE="adamrollogi/php-nginx"

# Check for --push flag
PUSH_IMAGES=false
if [[ "$1" == "--push" ]]; then
    PUSH_IMAGES=true
    echo "🔄 Push flag detected. Images will be pushed to the registry after building."
fi

# Build base image
echo "🚀 Building base image: $BASE_IMAGE"
docker build -t "$BASE_IMAGE" ./base

if [ "$PUSH_IMAGES" = true ]; then
    echo "📤 Pushing base image: $BASE_IMAGE"
    docker push "$BASE_IMAGE"
fi

# Build PHP images
for version in "${PHP_VERSIONS[@]}"; do
    PHP_VERSION_ENV=$(echo "$version" | tr -d '.')
    IMAGE_TAG="$PHP_IMAGE:$version"

    echo "🐘 Building PHP image: $IMAGE_TAG with PHP_VERSION=$PHP_VERSION_ENV"
    docker build \
        --build-arg PHP_VERSION=$PHP_VERSION_ENV \
        -t "$IMAGE_TAG" \
        ./php

    if [ "$PUSH_IMAGES" = true ]; then
        echo "📤 Pushing PHP image: $IMAGE_TAG"
        docker push "$IMAGE_TAG"
    fi
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

    if [ "$PUSH_IMAGES" = true ]; then
        echo "📤 Pushing PHP-NGINX image: $IMAGE_TAG"
        docker push "$IMAGE_TAG"
    fi
done

echo "✅ All images built successfully!"

if [ "$PUSH_IMAGES" = true ]; then
    echo "🚀 All images pushed successfully!"
fi
