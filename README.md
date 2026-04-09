# zabbix-phpfpm-multi

Zabbix template and scripts for monitoring multiple PHP-FPM pools across multiple PHP versions on a single server.

## Features

- **Auto-discovery** of PHP-FPM pools via Zabbix Low Level Discovery (LLD)
- **Active socket verification** – only discovers pools with currently listening sockets (`ss`)
- **Multi-version support** – detects PHP 7.x / 8.x pools simultaneously, tagged with `{#PHPVERSION}`
- **Admin/status port pattern** – identifies status pools by configurable filename patterns
- **Ping health check** – HIGH priority alert if a pool stops responding
- **Configurable timeout** – prevents slow queries from blocking the agent
- **Direct FastCGI queries** – uses `cgi-fcgi` (no Nginx/Apache needed for status)
- Graphs for connections, processes, memory, queue, CPU, and max-children-reached

## Requirements

The following tools must be installed on the **monitored host**:

| Tool | Package (Debian/Ubuntu) | Package (RHEL/CentOS) |
|------|------------------------|----------------------|
| `cgi-fcgi` | `libfcgi-bin` | `fcgi` |
| `ss` | `iproute2` | `iproute` |
| `grep`, `sed`, `awk`, `find` | coreutils / findutils | coreutils / findutils |

```bash
# Debian / Ubuntu
apt-get install libfcgi-bin iproute2

# RHEL / CentOS / Fedora
yum install fcgi iproute
```

## Installation

### 1. Copy scripts to the monitored host

```bash
cp scripts/php_fpm_discover.sh /etc/zabbix/scripts/
cp scripts/php_fpm_status.sh   /etc/zabbix/scripts/
cp scripts/php_fpm_ping.sh     /etc/zabbix/scripts/
chmod +x /etc/zabbix/scripts/php_fpm_*.sh
```

### 2. Install the Zabbix agent UserParameter config

```bash
cp scripts/zabbix_agentd.d/php_fpm.conf /etc/zabbix/zabbix_agentd.d/
# Restart the Zabbix agent
systemctl restart zabbix-agent
```

### 3. Create admin/status pool configs for each PHP-FPM pool

Each pool you want to monitor needs a dedicated TCP listener for status queries.
See `examples/pool.d/www-statusport.conf` for a ready-to-use example.

```bash
cp examples/pool.d/www-statusport.conf /etc/php/8.2/fpm/pool.d/
# Edit the file to match your pool name and choose a free port
systemctl reload php8.2-fpm
```

### 4. Import the Zabbix template

Import `zbx_php_fpm_multi.yaml` into Zabbix (Configuration → Templates → Import).

### 5. Apply the template to your host

Link **Template App PHP-FPM Multi ACTIVE** to the host running PHP-FPM.

## Configuration

### Discovery script settings (`scripts/php_fpm_discover.sh`)

Two arrays at the top of the script can be customised:

#### `CONFIG_PATHS`
Glob patterns pointing to directories that contain PHP-FPM pool `.conf` files.

```bash
CONFIG_PATHS=(
    "/etc/php/*/fpm/pool.d"        # Debian/Ubuntu (multiple PHP versions)
    "/etc/php-fpm.d"               # RHEL/CentOS single-version
    "/etc/php/*/fpm/php-fpm.d"     # Alternative Debian path
    "/usr/local/etc/php-fpm.d"     # Compiled-from-source PHP
    "/etc/opt/remi/php*/php-fpm.d" # Remi repository
)
```

#### `ADMIN_PATTERNS`
Glob patterns matching the **filename** of admin/status-port pool configs (case-insensitive).
Files not matching any pattern are ignored.

```bash
ADMIN_PATTERNS=(
    "*statusport*"    # e.g. www-statusport.conf
    "*status-port*"   # e.g. www-status-port.conf
    "*admin*"         # e.g. www-admin.conf
    "*-status.conf"   # e.g. www-status.conf
)
```

### Zabbix template macros

| Macro | Default | Description |
|-------|---------|-------------|
| `{$PHP_FPM_STATUS_URL}` | `/php-fpm-status` | FastCGI status page path |
| `{$PHP_FPM_PING_URL}` | `/php-fpm-ping` | FastCGI ping page path |
| `{$PHP_FPM_TIMEOUT}` | `1` | Query timeout in seconds |

Adjust these macros per-host in Zabbix if needed.

## Example pool configuration

See `examples/pool.d/www-statusport.conf`:

```ini
[www]
listen = 127.0.0.1:9001
listen.allowed_clients = 127.0.0.1

pm = static
pm.max_children = 1

pm.status_path = /php-fpm-status
ping.path = /php-fpm-ping
ping.response = pong
```

**Naming convention:** the filename must match one of the `ADMIN_PATTERNS` (e.g. `www-statusport.conf`).

Choose a unique TCP port per pool (e.g. 9001 for `www`, 9002 for `app`, …).

## Troubleshooting

### No pools discovered

1. Check that the status pool configs exist and the filenames match `ADMIN_PATTERNS`.
2. Verify PHP-FPM is running and the admin port is listening:
   ```bash
   ss -tln | grep 9001
   ```
3. Test the query manually:
   ```bash
   SCRIPT_NAME=/php-fpm-status SCRIPT_FILENAME=/php-fpm-status \
     REQUEST_METHOD=GET QUERY_STRING=json \
     cgi-fcgi -bind -connect 127.0.0.1:9001
   ```
4. Run the discovery script directly:
   ```bash
   sudo -u zabbix /etc/zabbix/scripts/php_fpm_discover.sh
   ```

### Missing command error

Install the missing tool (see [Requirements](#requirements) above).

### Timeout issues

Increase `{$PHP_FPM_TIMEOUT}` in the Zabbix template macros, or investigate why the pool is responding slowly.
