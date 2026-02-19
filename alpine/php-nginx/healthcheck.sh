#!/bin/bash
# Docker HEALTHCHECK wrapper that checks the correct endpoint based on SSL mode

if [ "${NGINX_SSL_ENABLED}" = "true" ]; then
    if [ "${NGINX_SSL_REDIRECT}" = "true" ]; then
        # SSL with redirect: check HTTP health endpoint on redirect port
        curl -sf "http://localhost:${NGINX_SSL_REDIRECT_PORT:-${NGINX_PORT:-80}}/health" || exit 1
    else
        # SSL without redirect: check HTTPS health endpoint (skip cert verification)
        curl -sfk "https://localhost:${NGINX_SSL_PORT:-443}/health" || exit 1
    fi
else
    # HTTP-only mode
    curl -sf "http://localhost:${NGINX_PORT:-80}/" || exit 1
fi
