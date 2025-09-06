#!/bin/bash
set -euo pipefail

# Start the token refresh loop (55 minutes) in the background
( while true; do /usr/local/bin/token-refresh.sh; sleep 3300; done ) &

# Run an immediate refresh on start to ensure token_value exists
/usr/local/bin/token-refresh.sh || true

# Start the Python proxy that reads the token file and calls Tailscale
exec python3 /usr/local/bin/proxy.py
