#!/bin/bash
#
# PHP-FPM Pool Discovery Script for Zabbix
# Discovers pools with admin/status ports across multiple PHP versions.
# Only includes pools whose sockets are actively listening (verified via ss).
#
# Usage: php_fpm_discover.sh [status_url] [timeout]
#   status_url  - FastCGI status path (default: /php-fpm-status)
#   timeout     - Query timeout in seconds (default: 1)
#

# =============================================================================
# CONFIGURATION - Adjust these settings as needed
# =============================================================================

# Paths to scan for PHP-FPM pool configuration files (glob patterns supported)
CONFIG_PATHS=(
    "/etc/php/*/fpm/pool.d"
    "/etc/php-fpm.d"
    "/etc/php/*/fpm/php-fpm.d"
    "/usr/local/etc/php-fpm.d"
    "/etc/opt/remi/php*/php-fpm.d"
)

# Filename patterns identifying admin/status-port pool configs (case-insensitive)
ADMIN_PATTERNS=(
    "*statusport*"
    "*status-port*"
    "*admin*"
    "*-status.conf"
)

# =============================================================================
# PARAMETERS
# =============================================================================

STATUS_URL="${1:-/php-fpm-status}"
TIMEOUT="${2:-1}"

# =============================================================================
# REQUIRED COMMANDS CHECK
# =============================================================================

REQUIRED_COMMANDS=("cgi-fcgi" "ss" "grep" "sed" "awk" "find")
for cmd in "${REQUIRED_COMMANDS[@]}"; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "ERROR: Missing required command: $cmd" >&2
        echo "Install hint:" >&2
        case "$cmd" in
            cgi-fcgi) echo "  Debian/Ubuntu: apt-get install libfcgi-bin" >&2
                      echo "  RHEL/CentOS:   yum install fcgi" >&2 ;;
            ss)       echo "  Debian/Ubuntu: apt-get install iproute2" >&2
                      echo "  RHEL/CentOS:   yum install iproute" >&2 ;;
        esac
        exit 1
    fi
done

# =============================================================================
# CACHE LISTENING SOCKETS
# =============================================================================

# Cache TCP listening addresses (format: host:port)
TCP_LISTEN=$(ss -tln 2>/dev/null | awk 'NR>1 {print $4}')

# Cache Unix domain socket paths
UNIX_LISTEN=$(ss -xl 2>/dev/null | awk 'NR>1 {print $5}')

# =============================================================================
# FUNCTIONS
# =============================================================================

# Returns 0 if a TCP address (host:port) is listening
is_tcp_listening() {
    local address="$1"
    echo "$TCP_LISTEN" | grep -qF "$address"
}

# Returns 0 if a Unix socket path is listening
is_unix_listening() {
    local socket="$1"
    echo "$UNIX_LISTEN" | grep -qF "$socket"
}

# Returns 0 if the listen address (TCP or Unix) has an active socket
is_socket_listening() {
    local listen="$1"
    if [[ "$listen" == /* ]]; then
        is_unix_listening "$listen"
    else
        is_tcp_listening "$listen"
    fi
}

# Extract pool name from the first [section] header in the config file
get_pool_name() {
    grep -m1 '^\[' "$1" 2>/dev/null | sed 's/\[\(.*\)\]/\1/' | tr -d '[:space:]'
}

# Extract the listen address from the config file
get_listen_address() {
    grep -E '^listen\s*=' "$1" 2>/dev/null | head -1 | sed 's/^listen\s*=\s*//' | tr -d '[:space:]'
}

# Detect PHP version from config file path
# Supports paths like /etc/php/8.2/fpm/pool.d/ and /etc/opt/remi/php82/
get_php_version() {
    local config_file="$1"
    local version

    # Standard Debian/Ubuntu path: /etc/php/8.2/... (separator required)
    version=$(echo "$config_file" | grep -oE 'php[/_-][0-9]+\.[0-9]+' | grep -oE '[0-9]+\.[0-9]+' | head -1)

    if [ -z "$version" ]; then
        # Remi-style path: /etc/opt/remi/php82/ or /etc/opt/remi/php80/
        version=$(echo "$config_file" | grep -oE 'php[0-9]{2,3}' | grep -oE '[0-9]+' | \
            sed 's/^\([0-9]\)\([0-9]\+\)$/\1.\2/' | head -1)
    fi

    echo "${version:-unknown}"
}

# Returns 0 if the config filename matches any admin pattern (case-insensitive)
is_admin_config() {
    local basename_lower
    basename_lower=$(basename "$1" | tr '[:upper:]' '[:lower:]')
    local pattern_lower
    for pattern in "${ADMIN_PATTERNS[@]}"; do
        pattern_lower=$(echo "$pattern" | tr '[:upper:]' '[:lower:]')
        if [[ "$basename_lower" == $pattern_lower ]]; then
            return 0
        fi
    done
    return 1
}

# Returns 0 if the pool responds to a status query via cgi-fcgi
test_pool_status() {
    local listen="$1"
    local status_url="$2"
    local timeout="$3"
    timeout "$timeout" env \
        SCRIPT_NAME="$status_url" \
        SCRIPT_FILENAME="$status_url" \
        REQUEST_METHOD=GET \
        QUERY_STRING=json \
        cgi-fcgi -bind -connect "$listen" 2>/dev/null | grep -q '"pool"'
}

# =============================================================================
# MAIN DISCOVERY LOGIC
# =============================================================================

declare -A DISCOVERED_POOLS
FIRST=1

echo '{"data":['

for path_pattern in "${CONFIG_PATHS[@]}"; do
    # Use nullglob so unmatched patterns produce no iterations
    shopt -s nullglob
    for expanded_path in $path_pattern; do
        shopt -u nullglob
        [ -d "$expanded_path" ] || continue

        while IFS= read -r -d '' config_file; do
            # Only process files matching admin patterns
            is_admin_config "$config_file" || continue

            pool_name=$(get_pool_name "$config_file")
            listen=$(get_listen_address "$config_file")
            php_version=$(get_php_version "$config_file")

            # Skip entries missing essential information
            [ -z "$pool_name" ] && continue
            [ -z "$listen" ] && continue

            # Only include pools with an actively listening socket
            is_socket_listening "$listen" || continue

            # Deduplicate by pool name + socket
            pool_key="${pool_name}:${listen}"
            [ -n "${DISCOVERED_POOLS[$pool_key]}" ] && continue
            DISCOVERED_POOLS[$pool_key]=1

            # Verify pool actually responds to the status query
            test_pool_status "$listen" "$STATUS_URL" "$TIMEOUT" || continue

            [ $FIRST -eq 0 ] && echo ","
            FIRST=0

            printf '    {"{#POOLNAME}":"%s","{#POOLSOCKET}":"%s","{#PHPVERSION}":"%s"}' \
                "$pool_name" "$listen" "$php_version"

        done < <(find "$expanded_path" -maxdepth 1 -name "*.conf" -type f -print0 2>/dev/null)
    done
done

echo ''
echo ']}'
