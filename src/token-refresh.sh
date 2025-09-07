#!/bin/bash

# Simple file-based locking to prevent concurrent execution
LOCK_FILE="/tokens/.token-refresh.lock"
cleanup() {
    rm -f "$LOCK_FILE"
}
trap cleanup EXIT

if ! (set -C; echo $$ > "$LOCK_FILE") 2>/dev/null; then
    log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"; }
    log "Another instance is already running, exiting"
    exit 0
fi

CLIENT_ID="${TAILSCALE_CLIENT_ID}"
CLIENT_SECRET="${TAILSCALE_CLIENT_SECRET}"
TOKEN_FILE="/tokens/tailscale_token.json"
TOKEN_VALUE_FILE="/tokens/token_value"

# Function to log with timestamp
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Check disk space before writing
check_disk_space() {
    if command -v df >/dev/null 2>&1; then
        local available_kb
        available_kb=$(df /tokens | tail -1 | awk '{print $4}' 2>/dev/null || echo 0)
        if [ "$available_kb" -lt 1024 ]; then
            log "Error: Insufficient disk space (${available_kb}KB available)"
            return 1
        fi
    fi
    return 0
}

# Function to make API request with retry logic
make_api_request() {
    local max_retries=3
    local attempt=1
    
    while [ $attempt -le $max_retries ]; do
        if [ $attempt -gt 1 ]; then
            log "API request attempt $attempt/$max_retries"
        fi
        
        response=$(curl -s -w "%{http_code}" \
            --connect-timeout 10 --max-time 30 \
            -X POST https://api.tailscale.com/api/v2/oauth/token \
            -H "Content-Type: application/x-www-form-urlencoded" \
            -d "grant_type=client_credentials&client_id=${CLIENT_ID}&client_secret=${CLIENT_SECRET}&scope=devices:read" 2>/dev/null)
        
        http_code="${response: -3}"
        
        if [ "$http_code" = "200" ]; then
            echo "$response"
            return 0
        fi
        
        if [ $attempt -lt $max_retries ]; then
            local delay=$((attempt * 5))
            log "Request failed (HTTP $http_code), retrying in ${delay}s..."
            sleep $delay
        fi
        attempt=$((attempt + 1))
    done
    
    echo "$response"
    return 1
}

# Function to get new token
get_new_token() {
    log "Requesting new OAuth token..."
    
    # Check disk space first
    if ! check_disk_space; then
        return 1
    fi
    
    # Make API request with retries
    if ! response=$(make_api_request); then
        log "Error: Failed to get token after retries"
        return 1
    fi
    
    http_code="${response: -3}"
    response_body="${response%???}"
    
    if [ "$http_code" = "200" ]; then
        # Add expiry timestamp (tokens are valid for 1 hour, we refresh 5 minutes early)
        expires_at=$(($(date +%s) + 3300))
        
        # Write response to temp file first, then add expiry
        echo "$response_body" > "${TOKEN_FILE}.tmp"
        
        # Use jq to add expiry timestamp - Fixed syntax
        if command -v jq >/dev/null 2>&1; then
            if jq ". + {\"expires_at\": $expires_at}" "${TOKEN_FILE}.tmp" > "${TOKEN_FILE}.tmp2" 2>/dev/null && [ -s "${TOKEN_FILE}.tmp2" ]; then
                if mv "${TOKEN_FILE}.tmp2" "${TOKEN_FILE}"; then
                    rm -f "${TOKEN_FILE}.tmp"
                else
                    log "Error: Failed to move enhanced token file"
                    rm -f "${TOKEN_FILE}.tmp2"
                    return 1
                fi
            else
                # Fallback: just use the original response without expiry timestamp
                rm -f "${TOKEN_FILE}.tmp2"  # Clean up potentially created but incomplete temp file
                if mv "${TOKEN_FILE}.tmp" "${TOKEN_FILE}"; then
                    log "Warning: jq failed, using token without expiry timestamp"
                else
                    log "Error: Failed to move original token file"
                    rm -f "${TOKEN_FILE}.tmp"
                    return 1
                fi
            fi
        else
            # jq not available, use original response
            if mv "${TOKEN_FILE}.tmp" "${TOKEN_FILE}"; then
                log "Warning: jq not available, using token without expiry timestamp"
            else
                log "Error: Failed to move token file (jq not available)"
                rm -f "${TOKEN_FILE}.tmp"
                return 1
            fi
        fi
        
        # Extract just the token value for easy access (atomic, no trailing newline)
        if command -v jq >/dev/null 2>&1; then
            access_token=$(jq -r '.access_token' "${TOKEN_FILE}" 2>/dev/null)
        else
            access_token=""
        fi
        if [ -n "$access_token" ] && [ "$access_token" != "null" ]; then
            tmp_token_file="${TOKEN_VALUE_FILE}.tmp"
            # Write without newline and atomically replace the token file
            if printf "%s" "$access_token" > "$tmp_token_file" && [ -s "$tmp_token_file" ]; then
                if mv "$tmp_token_file" "${TOKEN_VALUE_FILE}"; then
                    log "Token refreshed successfully"
                    return 0
                else
                    log "Error: Failed to move token value file"
                    rm -f "$tmp_token_file"
                    return 1
                fi
            else
                log "Error: Failed to write token value to temp file"
                rm -f "$tmp_token_file"
                return 1
            fi
        else
            log "Error: Failed to extract token value"
            return 1
        fi
    else
        log "Error: HTTP $http_code - $response_body"
        return 1
    fi
}

# Function to check if token is valid
check_token() {
    if [ ! -f "$TOKEN_FILE" ]; then
        log "Token file not found"
        return 1
    fi
    
    # Check if we have an expiry timestamp
    if command -v jq >/dev/null 2>&1; then
        expires_at=$(jq -r '.expires_at // empty' "$TOKEN_FILE" 2>/dev/null)
    else
        expires_at=""
    fi
    current_time=$(date +%s)
    
    if [ -n "$expires_at" ] && [ "$expires_at" -gt 0 ]; then
        # We have a timestamp, use it with 5 minute buffer
        buffer_time=$((current_time + 300))
        if [ "$expires_at" -lt "$buffer_time" ]; then
            log "Token will expire soon (timestamp: $expires_at, current: $current_time, buffer: $buffer_time)"
            return 1
        fi
    else
        # No timestamp available, check if token is older than 50 minutes (3000 seconds)
        if [ -f "$TOKEN_VALUE_FILE" ]; then
            if command -v stat >/dev/null 2>&1; then
                # Try GNU stat first, then BSD/macOS stat
                file_time=$(stat -c %Y "$TOKEN_VALUE_FILE" 2>/dev/null || stat -f %m "$TOKEN_VALUE_FILE" 2>/dev/null || echo 0)
                token_age=$(($(date +%s) - file_time))
            else
                token_age=3001  # Force refresh if stat unavailable
            fi
            if [ "$token_age" -gt 3000 ]; then
                log "Token file is older than 50 minutes (${token_age}s), assuming expired"
                return 1
            fi
        else
            log "Token value file not found"
            return 1
        fi
    fi
    
    log "Token is still valid"
    return 0
}

# Validate environment variables
if [ -z "$CLIENT_ID" ] || [ -z "$CLIENT_SECRET" ]; then
    log "Error: TAILSCALE_CLIENT_ID and TAILSCALE_CLIENT_SECRET must be set"
    log "CLIENT_ID is $([ -n "$CLIENT_ID" ] && echo 'set' || echo 'empty')"
    log "CLIENT_SECRET is $([ -n "$CLIENT_SECRET" ] && echo 'set' || echo 'empty')"
    exit 1
fi

# Debug: Show that we're starting (don't log credentials)
log "Token refresh script starting"

# Main logic
if ! check_token; then
    if ! get_new_token; then
        log "Failed to get new token, retrying in 60 seconds..."
        sleep 60
        exit 1
    fi
else
    log "Token is valid, no refresh needed"
    # Ensure token_value file exists and is normalized (no trailing newline)
    if [ -f "$TOKEN_FILE" ]; then
        if command -v jq >/dev/null 2>&1; then
            access_token=$(jq -r '.access_token' "${TOKEN_FILE}" 2>/dev/null)
        else
            access_token=""
        fi
        if [ -n "$access_token" ] && [ "$access_token" != "null" ]; then
            tmp_token_file="${TOKEN_VALUE_FILE}.tmp"
            if printf "%s" "$access_token" > "$tmp_token_file" && [ -s "$tmp_token_file" ]; then
                if mv "$tmp_token_file" "${TOKEN_VALUE_FILE}"; then
                    log "Token value normalized"
                else
                    log "Warning: Failed to move normalized token value"
                    rm -f "$tmp_token_file"
                fi
            else
                log "Warning: Failed to write normalized token value"
                rm -f "$tmp_token_file"
            fi
        fi
    fi
fi
