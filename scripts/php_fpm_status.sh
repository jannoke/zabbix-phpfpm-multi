#!/bin/bash
#
# PHP-FPM Pool Status Script for Zabbix
# Queries a pool's status endpoint via cgi-fcgi and returns the JSON body.
#
# Usage: php_fpm_status.sh <socket> <status_url> [timeout]
#   socket      - TCP address (127.0.0.1:9001) or Unix socket path (/var/run/php/fpm.sock)
#   status_url  - FastCGI status path (e.g. /php-fpm-status)
#   timeout     - Query timeout in seconds (default: 1)
#

# =============================================================================
# REQUIRED COMMANDS CHECK
# =============================================================================

for cmd in cgi-fcgi timeout; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "ERROR: Missing required command: $cmd" >&2
        exit 1
    fi
done

# =============================================================================
# PARAMETERS
# =============================================================================

SOCKET="$1"
STATUS_URL="$2"
TIMEOUT="${3:-1}"

if [ -z "$SOCKET" ] || [ -z "$STATUS_URL" ]; then
    echo "Usage: $0 <socket> <status_url> [timeout]" >&2
    exit 1
fi

# =============================================================================
# QUERY STATUS
# =============================================================================

response=$(timeout "$TIMEOUT" env \
    SCRIPT_NAME="$STATUS_URL" \
    SCRIPT_FILENAME="$STATUS_URL" \
    REQUEST_METHOD=GET \
    QUERY_STRING=json \
    cgi-fcgi -bind -connect "$SOCKET" 2>/dev/null)

# Strip HTTP headers: everything up to and including the first blank line
json_body=$(printf '%s' "$response" | sed '1,/^\r\{0,1\}$/d')

if [ -z "$json_body" ]; then
    echo "ERROR: Failed to get status from $SOCKET" >&2
    exit 1
fi

if ! printf '%s' "$json_body" | grep -q '"pool"'; then
    echo "ERROR: Invalid response from $SOCKET" >&2
    exit 1
fi

printf '%s\n' "$json_body"
