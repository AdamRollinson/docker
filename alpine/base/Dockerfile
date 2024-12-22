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
    envsubst && \
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
