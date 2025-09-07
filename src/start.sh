#!/bin/bash
set -euo pipefail

# Function to log with timestamp
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Graceful shutdown handler
handle_shutdown() {
    log "Received shutdown signal, cleaning up..."
    
    # Kill background refresh process
    if [ -n "${TOKEN_REFRESH_PID:-}" ]; then
        kill "$TOKEN_REFRESH_PID" 2>/dev/null || true
        wait "$TOKEN_REFRESH_PID" 2>/dev/null || true
    fi
    
    # Clean up lock files
    rm -f /tokens/.token-refresh.lock
    
    log "Cleanup complete, exiting"
    exit 0
}

trap handle_shutdown TERM INT

# Fix ownership of /tokens directory if needed
log "Checking /tokens directory permissions..."
if [ ! -w "/tokens" ]; then
    log "WARNING: Cannot write to /tokens directory."
    log "To fix: sudo chown -R 1000:1000 /path/to/your/docker/volume"
    log "Attempting to fix permissions..."
    chown -R tokenmanager:tokenmanager /tokens 2>/dev/null || log "Could not fix permissions automatically"
fi

# Start the token refresh loop (55 minutes) in the background
( while true; do /usr/local/bin/token-refresh.sh; sleep 3300; done ) &
TOKEN_REFRESH_PID=$!

# Run an immediate refresh on start to ensure token_value exists
/usr/local/bin/token-refresh.sh || true

# Start the Python proxy that reads the token file and calls Tailscale
exec python3 /usr/local/bin/proxy.py
