FROM alpine:latest

# Metadata
LABEL org.opencontainers.image.title="Tailscale Token Manager" \
      org.opencontainers.image.description="OAuth token management proxy for Tailscale API access" \
      org.opencontainers.image.source="https://github.com/suluxan/tailscale-token-manager" \
      org.opencontainers.image.licenses="MIT"

# Install dependencies
RUN apk add --no-cache \
    curl \
    jq \
    bash \
    python3 \
    py3-pip \
    tzdata \
    && rm -rf /var/cache/apk/*

# Create non-root user for security
RUN addgroup -g 1000 tokenmanager && \
    adduser -u 1000 -G tokenmanager -s /bin/bash -D tokenmanager

# Copy application files
COPY --chown=tokenmanager:tokenmanager src/ /usr/local/bin/
RUN chmod +x /usr/local/bin/*.sh

# Create data directories with proper permissions
RUN mkdir -p /app/data && \
    chown -R tokenmanager:tokenmanager /app && \
    ln -sf /app/data /tokens

# Switch to non-root user
USER tokenmanager

# Working directory
WORKDIR /app/data

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:${PROXY_PORT:-1180}/devices > /dev/null 2>&1 || exit 1

# Expose port
EXPOSE 1180

# Set default environment variables
ENV PROXY_PORT=1180
ENV TZ=UTC

# Start the application
CMD ["/usr/local/bin/start.sh"]