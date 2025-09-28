FROM alpine:latest

# Install required packages
RUN apk add --no-cache \
    bash \
    curl \
    nut \
    util-linux \
    && rm -rf /var/cache/apk/*

# Create non-root user for security
RUN addgroup -g 1000 monitor && \
    adduser -D -u 1000 -G monitor monitor

# Copy the monitoring script
COPY monitor.sh /usr/local/bin/monitor.sh
RUN chmod +x /usr/local/bin/monitor.sh

# Add healthcheck
HEALTHCHECK --interval=60s --timeout=10s --start-period=5s --retries=3 \
    CMD pgrep -f monitor.sh || exit 1

# Set labels for better container management
LABEL org.opencontainers.image.title="NUT Client Monitor" \
      org.opencontainers.image.description="Docker container to monitor NUT UPS server and shutdown host on critical battery" \
      org.opencontainers.image.vendor="awushensky" \
      org.opencontainers.image.source="https://github.com/awushensky/nut-client" \
      org.opencontainers.image.licenses="MIT"

# Environment variables with defaults
ENV UPS_SERVER=localhost \
    UPS_PORT=3493 \
    UPS_NAME=ups \
    CHECK_INTERVAL=30

# Note: This container requires privileged mode and pid=host to function
USER monitor
CMD ["/usr/local/bin/monitor.sh"]
