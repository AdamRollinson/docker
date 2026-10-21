# Use Alpine as the base image, pinned to digest for supply chain security
FROM alpine:3.24@sha256:294b683cb724975bec92580e1e685676bd4b50bda910ddb8c51d4cabeaec77e6

# Set environment variables
ENV LANG=C.UTF-8 \
    TZ=UTC

# Logging: LOG_MODE stdout (tagged per service on the container's stdout/stderr) or file
# (one file per service under /var/log); LOG_FORMAT text or json; LOG_TAG adds [service] prefixes
ENV LOG_MODE=stdout \
    LOG_FORMAT=text \
    LOG_TAG=true

# Upgrade the Alpine release packages first so security fixes land before our own installs
RUN apk upgrade --no-cache && \
    apk add --no-cache \
    bash \
    curl \
    tzdata \
    ca-certificates \
    openssl \
    git \
    wget \
    nano \
    supervisor \
    shadow \
    gcompat \
    py3-pip \
    gettext-envsubst \
    tini && \
    # Alpine's py3-setuptools (80.x) is affected by CVE-2026-59890, fixed in 83.0.0.
    # supervisor 4.3.0 uses importlib rather than pkg_resources, so no upper bound is needed.
    pip3 install --no-cache-dir --break-system-packages --root-user-action=ignore 'setuptools>=83.0.0' && \
    apk del py3-pip && \
    # Remove setuid/setgid bits: nothing in these images needs privilege escalation helpers
    find / -xdev -type f -perm /6000 -exec chmod a-s {} + && \
    # Set timezone
    ln -sf /usr/share/zoneinfo/${TZ} /etc/localtime && \
    echo "${TZ}" > /etc/timezone && \
    # Clean up and set permissions
    mkdir -p /etc/cron.d /var/log && \
    touch /var/log/cron.log && \
    chmod 0644 /var/log/cron.log

# OCI metadata labels
LABEL org.opencontainers.image.title="adamrollogi/base" \
      org.opencontainers.image.description="Alpine 3.23 base with Supervisor and common tools" \
      org.opencontainers.image.source="https://github.com/adamrollogi/docker" \
      org.opencontainers.image.licenses="MIT"

# Create non-root application user
RUN addgroup -g 1000 -S appuser && \
    adduser -u 1000 -S appuser -G appuser

# Set working directory
WORKDIR /app

# Set ownership of working directory
RUN chown appuser:appuser /app

# Copy only necessary configuration files
COPY --chown=root:root supervisord.conf /etc/supervisord.conf

# Shared entrypoint helpers and the service wrapper that tags log lines per service
COPY --chown=root:root entrypoint-lib.sh /usr/local/lib/entrypoint-lib.sh
COPY --chown=root:root run-service container-logs /usr/local/bin/
RUN chmod 755 /usr/local/bin/run-service /usr/local/bin/container-logs

# Default to non-root user
USER appuser

# Use tini as init for proper signal handling
ENTRYPOINT ["/sbin/tini", "--", "bash"]

# Default command
CMD ["bash"]
