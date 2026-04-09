#!/bin/bash
#
# PHP-FPM Pool Ping Script for Zabbix
# Returns 1 if the pool responds to a ping request, 0 otherwise.
# Fails silently (returns 0) if required commands are missing.
#
# Usage: php_fpm_ping.sh <socket> <ping_url> [timeout]
#   socket    - TCP address (127.0.0.1:9001) or Unix socket path (/var/run/php/fpm.sock)
#   ping_url  - FastCGI ping path (e.g. /php-fpm-ping)
#   timeout   - Query timeout in seconds (default: 1)
#

# =============================================================================
# REQUIRED COMMANDS CHECK (silent failure)
# =============================================================================

for cmd in cgi-fcgi timeout; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "0"
        exit 0
    fi
done

# =============================================================================
# PARAMETERS
# =============================================================================

SOCKET="$1"
PING_URL="$2"
TIMEOUT="${3:-1}"

if [ -z "$SOCKET" ] || [ -z "$PING_URL" ]; then
    echo "0"
    exit 0
fi

# =============================================================================
# PING POOL
# =============================================================================

response=$(timeout "$TIMEOUT" env \
    SCRIPT_NAME="$PING_URL" \
    SCRIPT_FILENAME="$PING_URL" \
    REQUEST_METHOD=GET \
    QUERY_STRING= \
    cgi-fcgi -bind -connect "$SOCKET" 2>/dev/null)

if printf '%s' "$response" | grep -qi "pong"; then
    echo "1"
else
    echo "0"
fi
