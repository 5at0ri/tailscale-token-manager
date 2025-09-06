#!/bin/bash
  set -euo pipefail

  # Fix ownership of /tokens directory if needed
  echo "Checking /tokens directory permissions..."
  if [ ! -w "/tokens" ]; then
      echo "WARNING: Cannot write to /tokens directory."
      echo "To fix: sudo chown -R 1000:1000 /path/to/your/docker/volume"
      echo "Attempting to fix permissions..."
      chown -R tokenmanager:tokenmanager /tokens 2>/dev/null || echo "Could not 
  fix permissions automatically"
  fi

  # Start the token refresh loop (55 minutes) in the background
  ( while true; do /usr/local/bin/token-refresh.sh; sleep 3300; done ) &

  # Run an immediate refresh on start to ensure token_value exists
  /usr/local/bin/token-refresh.sh || true

  # Start the Python proxy that reads the token file and calls Tailscale
  exec python3 /usr/local/bin/proxy.py
