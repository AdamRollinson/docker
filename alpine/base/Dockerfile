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
    shadow \
    gcompat \
    gettext-envsubst \
    supercronic \
    tini && \
    # Remove setuid/setgid bits: nothing in these images needs privilege escalation helpers
    find / -xdev -type f -perm /6000 -exec chmod a-s {} + && \
    # Set timezone
    ln -sf /usr/share/zoneinfo/${TZ} /etc/localtime && \
    echo "${TZ}" > /etc/timezone && \
    mkdir -p /var/log

# OCI metadata labels
LABEL org.opencontainers.image.title="rollogi/base" \
      org.opencontainers.image.description="Alpine 3.24 base with tini, supercronic and common tools" \
      org.opencontainers.image.source="https://github.com/AdamRollinson/docker" \
      org.opencontainers.image.licenses="MIT"

# Create the non-root application user. Override the IDs at build time so bind-mounted
# files owned by your host user are writable without chown gymnastics:
#   docker build --build-arg APP_UID=$(id -u) --build-arg APP_GID=$(id -g) ...
ARG APP_UID=1000
ARG APP_GID=1000
ENV APP_UID=${APP_UID} \
    APP_GID=${APP_GID}
RUN addgroup -g "${APP_GID}" -S appuser && \
    adduser -u "${APP_UID}" -S appuser -G appuser

# Set working directory
WORKDIR /app

# Set ownership of the working directory and the runtime directory for the rendered crontab.
# Runtime state directories are world-writable with the sticky bit (like /tmp) so the images
# also work under an arbitrary --user, not only as UID 1000.
RUN mkdir -p /run/cron && chown appuser:appuser /app /run/cron && chmod 1777 /run/cron

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
