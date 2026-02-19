# Use Alpine as the base image, pinned to digest for supply chain security
FROM alpine:3.21@sha256:c3f8e73fdb79deaebaa2037150150191b9dcbfba68b4a46d70103204c53f4709

# Set environment variables
ENV LANG=C.UTF-8 \
    TZ=UTC

# Install dependencies
RUN apk add --no-cache \
    bash \
    curl \
    tzdata \
    ca-certificates \
    openssl \
    git \
    wget \
    nano \
    supervisor \
    busybox-suid \
    shadow \
    libc6-compat \
    py3-pip \
    envsubst \
    tini && \
    # Upgrade curl from Alpine edge to fix CVE-2025-14017, CVE-2025-13034,
    # CVE-2025-15079, CVE-2025-14819, CVE-2025-14524, CVE-2025-10966, CVE-2025-15224
    apk add --no-cache --upgrade \
        --repository=http://dl-cdn.alpinelinux.org/alpine/edge/main \
        curl libcurl && \
    # Upgrade setuptools to fix CVE-2025-47273 (path traversal in PackageIndex)
    pip3 install --no-cache-dir --break-system-packages 'setuptools>=78.1.1,<81' && \
    apk del py3-pip && \
    # Set timezone
    ln -sf /usr/share/zoneinfo/${TZ} /etc/localtime && \
    echo "${TZ}" > /etc/timezone && \
    # Clean up and set permissions
    mkdir -p /etc/cron.d /var/log && \
    touch /var/log/cron.log && \
    chmod 0644 /var/log/cron.log

# OCI metadata labels
LABEL org.opencontainers.image.title="adamrollogi/base" \
      org.opencontainers.image.description="Alpine 3.21 base with Supervisor and common tools" \
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

# Default to non-root user
USER appuser

# Use tini as init for proper signal handling
ENTRYPOINT ["/sbin/tini", "--", "bash"]

# Default command
CMD ["bash"]
