# Use Alpine as the base image
FROM alpine:3.21

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
    envsubst && \
    # Upgrade curl from Alpine edge to fix CVE-2025-14017, CVE-2025-13034,
    # CVE-2025-15079, CVE-2025-14819, CVE-2025-14524, CVE-2025-10966, CVE-2025-15224
    apk add --no-cache --upgrade \
        --repository=http://dl-cdn.alpinelinux.org/alpine/edge/main \
        curl libcurl && \
    # Upgrade setuptools to fix CVE-2025-47273 (path traversal in PackageIndex)
    pip3 install --no-cache-dir --break-system-packages 'setuptools>=78.1.1' && \
    apk del py3-pip && \
    # Set timezone
    ln -sf /usr/share/zoneinfo/${TZ} /etc/localtime && \
    echo "${TZ}" > /etc/timezone && \
    # Clean up and set permissions
    mkdir -p /etc/cron.d /var/log && \
    touch /var/log/cron.log && \
    chmod 0644 /var/log/cron.log

# Set working directory
WORKDIR /app

# Copy only necessary configuration files
COPY --chown=root:root supervisord.conf /etc/supervisord.conf

# Default entrypoint for debugging (can be overridden)
ENTRYPOINT ["bash"]

# Default command
CMD ["bash"]
