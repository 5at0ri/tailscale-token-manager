#!/bin/bash

CLIENT_ID="${TAILSCALE_CLIENT_ID}"
CLIENT_SECRET="${TAILSCALE_CLIENT_SECRET}"
TOKEN_FILE="/tokens/tailscale_token.json"
TOKEN_VALUE_FILE="/tokens/token_value"

# Function to log with timestamp
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Function to get new token
get_new_token() {
    log "Requesting new OAuth token..."
    
    response=$(curl -s -w "%{http_code}" -X POST https://api.tailscale.com/api/v2/oauth/token \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "grant_type=client_credentials&client_id=${CLIENT_ID}&client_secret=${CLIENT_SECRET}&scope=devices:read")
    
    http_code="${response: -3}"
    response_body="${response%???}"
    
    if [ "$http_code" = "200" ]; then
        # Add expiry timestamp (tokens are valid for 1 hour, we refresh 5 minutes early)
        expires_at=$(($(date +%s) + 3300))
        
        # Write response to temp file first, then add expiry
        echo "$response_body" > "${TOKEN_FILE}.tmp"
        
        # Use jq to add expiry timestamp - Fixed syntax
        if command -v jq >/dev/null 2>&1; then
            if jq ". + {\"expires_at\": $expires_at}" "${TOKEN_FILE}.tmp" > "${TOKEN_FILE}.tmp2" 2>/dev/null; then
                mv "${TOKEN_FILE}.tmp2" "${TOKEN_FILE}"
                rm -f "${TOKEN_FILE}.tmp"
            else
                # Fallback: just use the original response without expiry timestamp
                rm -f "${TOKEN_FILE}.tmp2"  # Clean up potentially created but incomplete temp file
                mv "${TOKEN_FILE}.tmp" "${TOKEN_FILE}"
                log "Warning: jq failed, using token without expiry timestamp"
            fi
        else
            # jq not available, use original response
            mv "${TOKEN_FILE}.tmp" "${TOKEN_FILE}"
            log "Warning: jq not available, using token without expiry timestamp"
        fi
        
        # Extract just the token value for easy access (atomic, no trailing newline)
        access_token=$(jq -r '.access_token' "${TOKEN_FILE}" 2>/dev/null)
        if [ -n "$access_token" ]; then
            tmp_token_file="${TOKEN_VALUE_FILE}.tmp"
            # Write without newline and atomically replace the token file
            printf "%s" "$access_token" > "$tmp_token_file" 2>/dev/null && mv "$tmp_token_file" "${TOKEN_VALUE_FILE}"
            log "Token refreshed successfully"
            return 0
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
    expires_at=$(jq -r '.expires_at // empty' "$TOKEN_FILE" 2>/dev/null)
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
            token_age=$(($(date +%s) - $(stat -c %Y "$TOKEN_VALUE_FILE" 2>/dev/null || echo 0)))
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
    log "CLIENT_ID: $CLIENT_ID"
    log "CLIENT_SECRET: ${CLIENT_SECRET:0:10}..." # Only show first 10 chars for security
    exit 1
fi

# Debug: Show what we received
log "Starting with CLIENT_ID: $CLIENT_ID"

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
        access_token=$(jq -r '.access_token' "${TOKEN_FILE}" 2>/dev/null)
        if [ -n "$access_token" ]; then
            tmp_token_file="${TOKEN_VALUE_FILE}.tmp"
            printf "%s" "$access_token" > "$tmp_token_file" 2>/dev/null && mv "$tmp_token_file" "${TOKEN_VALUE_FILE}"
            log "Token value normalized"
        fi
    fi
fi
