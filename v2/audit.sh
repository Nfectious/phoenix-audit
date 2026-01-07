#!/usr/bin/env bash
# PHOENIX AUDIT SYSTEM — Version 2.0 (Enhanced)
# Source: enhanced implementation with adaptive service detection, alerting, and drift detection
# Purpose: Phoenix-target reconnaissance with extensive service-specific checks
# Author: Travis — Phoenix CommandOps (copied into repo and hardened)

set -euo pipefail

VERSION="2.0 (Enhanced)"
OUTDIR="$HOME/contabo_audit"
STAMP="$(date +%Y%m%d_%H%M%S)"

# Main reports
TXT="$OUTDIR/server_audit_$STAMP.txt"
MD="$OUTDIR/server_audit_$STAMP.md"
LOG="$OUTDIR/files_$STAMP.txt"
TGZ="$OUTDIR/server_audit_$STAMP.tgz"
ZIP="$OUTDIR/server_audit_$STAMP.zip"

# Quick-summary artifacts
SUMTX="$OUTDIR/summary_$STAMP.txt"
SUMMD="$OUTDIR/summary_$STAMP.md"
SUMTX_LATEST="$OUTDIR/summary_latest.txt"
SUMMD_LATEST="$OUTDIR/summary_latest.md"

# Alert/drift tracking
ALERT_LOG="$OUTDIR/alerts_$STAMP.txt"
PREV_HASH="$OUTDIR/.last_audit_hash"

mkdir -p "$OUTDIR"

# ============================================================
# ENVIRONMENT DETECTION — Adaptive Service Fingerprinting
# ============================================================

HAS_NGINX=false
HAS_APACHE=false
HAS_DOCKER=false
HAS_NEXTCLOUD=false
HAS_N8N=false
HAS_HOMEASSISTANT=false
HAS_OPENWEBUI=false
HAS_OLLAMA=false
HAS_MYSQL=false

command -v nginx >/dev/null 2>&1 && HAS_NGINX=true
command -v apache2 >/dev/null 2>&1 && HAS_APACHE=true
command -v docker >/dev/null 2>&1 && HAS_DOCKER=true
command -v mysql >/dev/null 2>&1 && HAS_MYSQL=true

if $HAS_DOCKER; then
  docker ps --format '{{.Names}}' 2>/dev/null | grep -qi "nextcloud" && HAS_NEXTCLOUD=true
  docker ps --format '{{.Names}}' 2>/dev/null | grep -qi "n8n" && HAS_N8N=true
  docker ps --format '{{.Names}}' 2>/dev/null | grep -qi "homeassistant\|home-assistant" && HAS_HOMEASSISTANT=true
  docker ps --format '{{.Names}}' 2>/dev/null | grep -qi "openwebui\|open-webui" && HAS_OPENWEBUI=true
  docker ps --format '{{.Names}}' 2>/dev/null | grep -qi "ollama" && HAS_OLLAMA=true
fi

[ -d "/var/www/nextcloud" ] && HAS_NEXTCLOUD=true

# Server classification based on hostname and services
DETECTED_HOSTNAME=$(hostname 2>/dev/null | tr '[:upper:]' '[:lower:]')
SERVER_TYPE="UNKNOWN"

# Classify by hostname first, then by services
if [[ "$DETECTED_HOSTNAME" == *"phoenix"* ]]; then
  SERVER_TYPE="PHOENIX (AI-PROCESSING)"
elif [[ "$DETECTED_HOSTNAME" == *"phoenix"* ]]; then
  SERVER_TYPE="PHOENIX (LEGACY-PRODUCTION)"
elif $HAS_N8N && $HAS_NEXTCLOUD; then
  SERVER_TYPE="PHOENIX (LEGACY-PRODUCTION)"
elif $HAS_OLLAMA || $HAS_OPENWEBUI; then
  SERVER_TYPE="PHOENIX (AI-PROCESSING)"
else
  SERVER_TYPE="GENERIC"
fi

# ============================================================
# ALERT TRACKING INITIALIZATION
# ============================================================

CRITICAL_ALERTS=0
WARNING_ALERTS=0

alert_critical() {
  echo "[CRITICAL] $*" | tee -a "$ALERT_LOG" >&2
  ((CRITICAL_ALERTS++))
}

alert_warning() {
  echo "[WARNING] $*" | tee -a "$ALERT_LOG" >&2
  ((WARNING_ALERTS++))
}

# ============================================================
# PRELIMINARY CHECKS
# ============================================================

# Warn if not root
if [[ $EUID -ne 0 ]]; then
  alert_warning "Not running as root. Some data may be incomplete."
fi

# Check for missing tools
MISSING_TOOLS=()
for tool in ss sar iostat apachectl ufw iptables nft fail2ban-client aa-status curl timeout apt-get dpkg systemctl find python3; do
  command -v "$tool" >/dev/null 2>&1 || MISSING_TOOLS+=("$tool")
done

$HAS_NGINX && { command -v nginx >/dev/null 2>&1 || MISSING_TOOLS+=("nginx"); }
$HAS_DOCKER && { command -v docker >/dev/null 2>&1 || MISSING_TOOLS+=("docker"); }

if [ ${#MISSING_TOOLS[@]} -ne 0 ]; then
  alert_warning "Missing tools: ${MISSING_TOOLS[*]} - some data may be incomplete."
fi

# ============================================================
# OUTPUT HELPERS
# ============================================================

section_txt(){ echo -e "\n==================== $* ====================\n" | tee -a "$TXT"; }
section_md (){ echo -e "\n## $*\n" >> "$MD"; }
append_both(){ tee -a "$TXT" >> "$MD"; }
append_txt(){ cat >> "$TXT"; }
append_md (){ cat >> "$MD"; }

# ============================================================
# COLLECT SYSTEM FACTS
# ============================================================

HOSTNAME="$(hostname 2>/dev/null || echo UNKNOWN)"
IP4S="$(ip -4 -br addr 2>/dev/null | awk '{print $1,$3}' | sed "s|/.*||" | paste -sd', ' - || true)"
OS_NAME="$( (grep PRETTY_NAME= /etc/os-release | cut -d= -f2- | tr -d '"') 2>/dev/null || lsb_release -ds 2>/dev/null || uname -a )"
UPTIME="$(uptime -p 2>/dev/null || true)"
LOAD_AVG="$(uptime | awk -F'load average:' '{print $2}' || true)"

PORTS="$( (ss -ltnp | awk 'NR==1 || /LISTEN/ {print}' | head -n 20) 2>/dev/null || true )"

if $HAS_DOCKER; then
  DOCKER_SUMMARY="$( (docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' | head -n 25) 2>/dev/null || true )"
else
  DOCKER_SUMMARY="Docker not installed."
fi

if $HAS_NGINX; then
  NGINX_CONFIG_TEST="$(nginx -t 2>&1 || echo 'NGINX CONFIG INVALID')"
  NGINX_VHOSTS="$(grep -Hnr "server_name" /etc/nginx/sites-enabled/ 2>/dev/null | sed 's|/etc/nginx/sites-enabled/||' || true)"
fi

if $HAS_APACHE; then
  APACHE_VHOSTS="$( (apachectl -S 2>&1) 2>/dev/null || true )"
fi

UFW_STATE="$( (ufw status verbose) 2>/dev/null || echo "UFW not installed or not running." )"

# ============================================================
# RESOURCE THRESHOLD CHECKS
# ============================================================

# Disk usage check
ROOT_DISK_USAGE=$(df / | tail -1 | awk '{print $5}' | tr -d '%')
if [[ $ROOT_DISK_USAGE -gt 85 ]]; then
  alert_critical "Root disk usage at ${ROOT_DISK_USAGE}% (threshold: 85%)"
fi

# Swap usage check
SWAP_USED=$(free | grep Swap | awk '{print $3}')
if [[ $SWAP_USED -gt 0 ]]; then
  alert_warning "Swap is active (${SWAP_USED} KB in use) - potential memory pressure"
fi

# Load average check (warn if 15min avg > CPU count)
CPU_COUNT=$(nproc)
LOAD_15MIN=$(uptime | awk -F'load average:' '{print $2}' | awk -F, '{print $3}' | xargs)
if (( $(echo "$LOAD_15MIN > $CPU_COUNT" | bc -l 2>/dev/null || echo 0) )); then
  alert_warning "15-min load average ($LOAD_15MIN) exceeds CPU count ($CPU_COUNT)"
fi

# ============================================================
# QUICK SUMMARY (TXT + MD)
# ============================================================

{
  echo "╔════════════════════════════════════════════════════════════════╗"
  echo "║           PHOENIX SERVER AUDIT SUMMARY ($STAMP)            ║"
  echo "╚════════════════════════════════════════════════════════════════╝"
  echo
  echo "Server Type: $SERVER_TYPE"
  echo "Hostname: $HOSTNAME"
  echo "IPv4s: ${IP4S:-UNKNOWN}"
  echo "OS: $OS_NAME"
  echo "Uptime: ${UPTIME:-UNKNOWN}"
  echo "Load Avg:$LOAD_AVG"
  echo
  echo "ALERT SUMMARY"
  echo "----------------------------------------"
  echo "Critical Alerts: $CRITICAL_ALERTS"
  echo "Warnings: $WARNING_ALERTS"
  echo
  echo "SERVICE DETECTION"
  echo "----------------------------------------"
  echo "Nginx: $HAS_NGINX"
  echo "Apache: $HAS_APACHE"
  echo "Docker: $HAS_DOCKER"
  echo "n8n: $HAS_N8N"
  echo "Home Assistant: $HAS_HOMEASSISTANT"
  echo "Nextcloud: $HAS_NEXTCLOUD"
  echo "OpenWebUI: $HAS_OPENWEBUI"
  echo "Ollama: $HAS_OLLAMA"
  echo
  echo "TOP LISTENING PORTS (sample)"
  echo "----------------------------------------"
  printf '%s
' "${PORTS:-No listening sockets found}"
  echo
  echo "DOCKER CONTAINERS"
  echo "----------------------------------------"
  printf '%s
' "$DOCKER_SUMMARY"
  echo
  if $HAS_NGINX; then
    echo "NGINX CONFIG TEST"
    echo "----------------------------------------"
    printf '%s
' "$NGINX_CONFIG_TEST"
    echo
    echo "NGINX VHOSTS"
    echo "----------------------------------------"
    printf '%s
' "${NGINX_VHOSTS:-None found}"
    echo
  fi
  if $HAS_APACHE; then
    echo "APACHE VHOSTS"
    echo "----------------------------------------"
    printf '%s
' "${APACHE_VHOSTS:-apachectl not available}"
    echo
  fi
  echo "UFW FIREWALL"
  echo "----------------------------------------"
  printf '%s
' "$UFW_STATE"
} > "$SUMTX"

{
  echo "# PHOENIX Server Audit Summary ($STAMP)"
  echo
  echo "**Server Type:** $SERVER_TYPE  "
  echo "**Hostname:** $HOSTNAME  "
  echo "**IPv4s:** ${IP4S:-UNKNOWN}  "
  echo "**OS:** $OS_NAME  "
  echo "**Uptime:** ${UPTIME:-UNKNOWN}  "
  echo "**Load Avg:**$LOAD_AVG  "
  echo
  echo "## ALERT SUMMARY"
  echo "- **Critical Alerts:** $CRITICAL_ALERTS"
  echo "- **Warnings:** $WARNING_ALERTS"
  echo
  echo "## SERVICE DETECTION"
  echo "- Nginx: $HAS_NGINX"
  echo "- Apache: $HAS_APACHE"
  echo "- Docker: $HAS_DOCKER"
  echo "- n8n: $HAS_N8N"
  echo "- Home Assistant: $HAS_HOMEASSISTANT"
  echo "- Nextcloud: $HAS_NEXTCLOUD"
  echo "- OpenWebUI: $HAS_OPENWEBUI"
  echo "- Ollama: $HAS_OLLAMA"
  echo
  echo "### Top Listening Ports (sample)"
  echo '```'
  echo "${PORTS:-No listening sockets found}"
  echo '```'
  echo
  echo "### Docker Containers"
  echo '```'
  echo "$DOCKER_SUMMARY"
  echo '```'
  echo
  if $HAS_NGINX; then
    echo "### Nginx Config Test"
    echo '```'
    echo "$NGINX_CONFIG_TEST"
    echo '```'
    echo
    echo "### Nginx VirtualHosts"
    echo '```'
    echo "${NGINX_VHOSTS:-None found}"
    echo '```'
    echo
  fi
  if $HAS_APACHE; then
    echo "### Apache VirtualHosts"
    echo '```'
    echo "${APACHE_VHOSTS:-apachectl not available}"
    echo '```'
    echo
  fi
  echo "### UFW Firewall"
  echo '```'
  echo "$UFW_STATE"
  echo '```'
} > "$SUMMD"

# Update latest pointers
ln -sf "$(basename "$SUMTX")" "$SUMTX_LATEST"
ln -sf "$(basename "$SUMMD")" "$SUMMD_LATEST"

# ============================================================
# FULL REPORT HEADER
# ============================================================

{
  echo "# PHOENIX Server Audit — Full Report ($STAMP)"
  echo
  echo "**Server Type:** $SERVER_TYPE  "
  echo "**Hostname:** $HOSTNAME  "
  echo "**IPv4s:** ${IP4S:-UNKNOWN}  "
  echo "**OS:** $OS_NAME  "
  echo "**Uptime:** ${UPTIME:-UNKNOWN}  "
  echo "**Load Avg:**$LOAD_AVG  "
  echo
  echo "### Quick Navigation"
  echo "- [Host / OS / Time](#host--os--time)"
  echo "- [CPU / Memory / Disk](#cpu--memory--disk)"
  echo "- [Network / Ports](#network--ports)"
  echo "- [Firewall / Security](#firewall--security)"
  echo "- [Users / Cron / Timers](#users--cron--timers)"
  echo "- [Packages / Updates](#packages--updates)"
  if $HAS_NGINX; then
    echo "- [Nginx](#nginx)"
  fi
  if $HAS_APACHE; then
    echo "- [Apache2](#apache2)"
  fi
  if $HAS_DOCKER; then
    echo "- [Docker / Containers](#docker--containers)"
    echo "- [Docker Health Check](#docker-health-check)"
  fi
  if $HAS_N8N; then
    echo "- [n8n Workflows](#n8n-workflows)"
  fi
  if $HAS_HOMEASSISTANT; then
    echo "- [Home Assistant](#home-assistant)"
  fi
  if $HAS_NEXTCLOUD; then
    echo "- [Nextcloud](#nextcloud)"
  fi
  if $HAS_OPENWEBUI || $HAS_OLLAMA; then
    echo "- [AI Stack (OpenWebUI/Ollama)](#ai-stack)"
  fi
  if $HAS_MYSQL; then
    echo "- [Database Status](#database-status)"
  fi
  echo "- [Log Intelligence](#log-intelligence)"
  echo "- [Security Audit](#security-audit)"
  echo "- [File Inventory](#file-inventory)"
  echo "- [Resource Monitoring](#resource-monitoring)"
  echo
  echo "---"
} | tee "$MD" > "$TXT"

# ============================================================
# SECTION: HOST / OS / TIME
# ============================================================

section_txt "HOST / OS / TIME"; section_md "HOST / OS / TIME"
{
  hostnamectl || true
  echo
  [ -r /etc/os-release ] && cat /etc/os-release || lsb_release -a || true
  echo
  echo "Uptime:"; uptime -p
  echo
  echo "Time:"; date -Is
  echo
  echo "Last boots / logins (recent):"; last -n 10 -a || true
} | append_both

# ============================================================
# SECTION: CPU / MEMORY / DISK
# ============================================================

section_txt "CPU / MEMORY / DISK"; section_md "CPU / MEMORY / DISK"
{
  echo "Load Averages (1m, 5m, 15m):"
  uptime | awk -F'load average:' '{print $2}'
  echo
  echo "Top CPU/MEM processes:"
  ps aux --sort=-%mem | head -n 20
  echo
  echo "Memory usage:"
  free -h
  echo
  echo "Disk usage:"
  df -hT
  echo
  echo "Block devices:"
  lsblk -o NAME,SIZE,TYPE,MOUNTPOINT
  echo
  if command -v iostat >/dev/null 2>&1; then
    echo "Disk I/O statistics (5 samples, 1s interval):"
    iostat -x 1 5 | grep -A 5 "Device"
  else
    echo "iostat not available (install sysstat)"
  fi
} | append_both

# ============================================================
# SECTION: NETWORK / PORTS
# ============================================================

section_txt "NETWORK / PORTS"; section_md "NETWORK / PORTS"
{
  ip -br addr
  echo
  ip route
  echo
  echo "DNS Resolvers:"; cat /etc/resolv.conf | head -20
  echo
  echo "Listening TCP sockets:"; ss -ltnp || true
  echo
  echo "Listening UDP sockets:"; ss -lunp || true
  echo
  echo "Established connections (sample):"; ss -tunp | head -n 30 || true
} | append_both

# ============================================================
# SECTION: FIREWALL / SECURITY
# ============================================================

section_txt "FIREWALL / SECURITY"; section_md "FIREWALL / SECURITY"
{
  echo "UFW status:"; ufw status numbered || true
  echo
  echo "iptables (filter):"; iptables -S 2>/dev/null || true
  echo
  echo "nftables:"; nft list ruleset 2>/dev/null || true
  echo
  echo "Fail2ban:"; fail2ban-client status 2>/dev/null || echo "fail2ban not installed"
  echo
  echo "AppArmor:"; aa-status 2>/dev/null || echo "apparmor tools not installed"
  echo
  echo "SSH hardening check:"
  grep -HEn "^(PermitRootLogin|PasswordAuthentication|PubkeyAuthentication|Port|X11Forwarding|ChallengeResponseAuthentication)" \
      /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf 2>/dev/null || true
  echo
  echo "Dangerous sudo configurations:"
  grep -r NOPASSWD /etc/sudoers /etc/sudoers.d/ 2>/dev/null || echo "No NOPASSWD entries found"
} | append_both

# ============================================================
# SECTION: USERS / CRON / TIMERS
# ============================================================

section_txt "USERS / CRON / TIMERS"; section_md "USERS / CRON / TIMERS"
{
  echo "Users with UID 0:"; awk -F: '$3==0{print}' /etc/passwd
  echo
  echo "Sudo group:"; getent group sudo
  echo
  echo "Systemd running services (summary):"; systemctl --type=service --state=running --no-pager | head -n 50
  echo
  echo "Scheduled timers:"; systemctl list-timers --all --no-pager
  echo
  echo "Root crontab:"; sudo crontab -l 2>/dev/null || echo "(no root crontab)"
  echo
  echo "User crontab:"; crontab -l 2>/dev/null || echo "(no user crontab)"
  echo
  echo "/etc/cron.* directories:"; 
  for d in /etc/cron.hourly /etc/cron.daily /etc/cron.weekly /etc/cron.monthly; do 
    echo "--- $d ---"; ls -lah "$d" 2>/dev/null || true
  done
} | append_both

# ============================================================
# SECTION: PACKAGES / UPDATES
# ============================================================

section_txt "PACKAGES / UPDATES"; section_md "PACKAGES / UPDATES"
{
  echo "Available apt upgrades (simulation):"
  DEBIAN_FRONTEND=noninteractive apt-get -s upgrade 2>/dev/null | sed -n "1,200p" || true
  echo
  echo "Security tools present:"
  dpkg -l | grep -Ei "fail2ban|unattended-upgrades|rkhunter|clamav|lynis" || echo "No security tools detected"
} | append_both

# ============================================================
# SECTION: NGINX (if present)
# ============================================================

if $HAS_NGINX; then
  section_txt "NGINX"; section_md "NGINX"
  {
    echo "Nginx config test:"
    nginx -t 2>&1 || alert_critical "Nginx config validation FAILED"
    echo
    echo "Nginx version:"
    nginx -v 2>&1 || true
    echo
    echo "Enabled sites:"
    ls -lah /etc/nginx/sites-enabled/ 2>/dev/null || true
    echo
    echo "VirtualHost/Upstream mappings:"
    grep -Hnr "server_name\|proxy_pass\|upstream" /etc/nginx/sites-enabled/ 2>/dev/null | sed 's|/etc/nginx/sites-enabled/||' || true
    echo
    echo "SSL certificates in use:"
    grep -Hnr "ssl_certificate " /etc/nginx/sites-enabled/ 2>/dev/null | sed 's|/etc/nginx/sites-enabled/||' || true
    echo
    echo "SSL certificate expiry check:"
    for domain in $(grep -hr "server_name" /etc/nginx/sites-enabled/ 2>/dev/null | sed -n 's/.*server_name\s\+\(.*\);/\1/p' | tr ' ' '\n' | sed 's/;//g' | grep -v '^_' | sort -u); do
      if [[ "$domain" != "localhost" ]] && [[ "$domain" != "" ]]; then
        echo "--- $domain ---"
        echo | timeout 3 openssl s_client -servername "$domain" -connect "$domain":443 2>/dev/null | openssl x509 -noout -enddate 2>/dev/null || echo "Failed to retrieve cert"
      fi
    done
    echo
    echo "Local HTTP probes:"
    for p in 80 443 8080 8000 5000 5001 3000; do
      echo "--- curl -I http://127.0.0.1:$p/ ---"
      timeout 2 curl -I "http://127.0.0.1:$p/" 2>/dev/null | head -n5 || echo "No response on port $p"
    done
  } | append_both
fi

# ============================================================
# SECTION: APACHE2 (if present)
# ============================================================

if $HAS_APACHE; then
  section_txt "APACHE2"; section_md "APACHE2"
  {
    echo "Apache config test:"
    apachectl -t 2>&1 || alert_critical "Apache config validation FAILED"
    echo
    echo "Apache version:"
    apache2 -v 2>/dev/null || true
    echo
    echo "Enabled modules:"
    apache2ctl -M 2>/dev/null || true
    echo
    echo "VirtualHost map (apachectl -S):"
    apachectl -S 2>&1 || true
    echo
    echo "ServerName/Alias/DocumentRoot/ProxyPass (sites-enabled):"
    grep -HEnr "ServerName|ServerAlias|DocumentRoot|ProxyPass|ProxyPassReverse" /etc/apache2/sites-enabled 2>/dev/null | sed "s|/etc/apache2/sites-enabled/||" || true
  } | append_both
fi

# ============================================================
# SECTION: DOCKER / CONTAINERS (if present)
# ============================================================

if $HAS_DOCKER; then
  section_txt "DOCKER / CONTAINERS"; section_md "DOCKER / CONTAINERS"
  {
    echo "Docker version:"; docker version 2>/dev/null | head -20 || true
    echo
    echo "Docker info:"; docker info 2>/dev/null | head -50 || true
    echo
    echo "Containers (all - with status, ports, mounts):"
    docker ps -a --format "table {{.ID}}\t{{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}\t{{.Mounts}}" 2>/dev/null || true
    echo
    echo "Images:"; docker images 2>/dev/null || true
    echo
    echo "Networks:"; docker network ls 2>/dev/null || true
    echo
    echo "Volumes:"; docker volume ls 2>/dev/null || true
    echo
    echo "Compose files (detected):"
    find /opt /srv /var/www /home /root -maxdepth 4 -type f \
      \( -iname "docker-compose.yml" -o -iname "docker-compose.yaml" -o -iname "compose.yml" -o -iname "compose.yaml" \) \
      -print 2>/dev/null | sort || true
  } | append_both

  # Docker Health Check Section
  section_txt "DOCKER HEALTH CHECK"; section_md "DOCKER HEALTH CHECK"
  {
    echo "Container health status & restart counts:"
    for container in $(docker ps -aq 2>/dev/null); do
      NAME=$(docker inspect --format='{{.Name}}' "$container" 2>/dev/null | sed 's|^/||')
      HEALTH=$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}N/A{{end}}' "$container" 2>/dev/null)
      RESTARTS=$(docker inspect --format='{{.RestartCount}}' "$container" 2>/dev/null)
      STATUS=$(docker inspect --format='{{.State.Status}}' "$container" 2>/dev/null)
      
      echo "[$NAME] Status: $STATUS | Health: $HEALTH | Restarts: $RESTARTS"
      
      # Alert on high restart count
      if [[ "$RESTARTS" -gt 10 ]]; then
        alert_warning "Container $NAME has restarted $RESTARTS times"
      fi
    done
    echo
    echo "Container resource usage (live stats):"
    docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}" 2>/dev/null | head -25 || true
    echo
    echo "Recently crashed containers (exited/dead):"
    docker ps -a --filter "status=exited" --filter "status=dead" --format "{{.Names}}: {{.Status}}" 2>/dev/null | head -20 || echo "No crashed containers"
  } | append_both
fi

# ============================================================
# SECTION: n8n WORKFLOWS (if present)
# ============================================================

if $HAS_N8N; then
  section_txt "n8n WORKFLOWS"; section_md "n8n WORKFLOWS"
  {
    echo "n8n container status:"
    docker ps --filter "name=n8n" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || true
    echo
    echo "n8n logs (last 50 lines):"
    docker logs --tail 50 "$(docker ps -q --filter 'name=n8n')" 2>/dev/null || echo "Unable to retrieve n8n logs"
    echo
    echo "Note: Workflow execution status requires n8n API access"
    echo "Consider adding API-based workflow health checks in Phase 2"
  } | append_both
fi

# ============================================================
# SECTION: HOME ASSISTANT (if present)
# ============================================================

if $HAS_HOMEASSISTANT; then
  section_txt "HOME ASSISTANT"; section_md "HOME ASSISTANT"
  {
    echo "Home Assistant container status:"
    docker ps --filter "name=homeassistant" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || \
    docker ps --filter "name=home-assistant" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || true
    echo
    echo "Home Assistant logs (last 50 lines):"
    docker logs --tail 50 "$(docker ps -q --filter 'name=homeassistant' 2>/dev/null || docker ps -q --filter 'name=home-assistant' 2>/dev/null)" 2>/dev/null || echo "Unable to retrieve HA logs"
    echo
    echo "Note: Entity count and integration health require HA API access"
    echo "Consider adding API-based checks in Phase 2"
  } | append_both
fi

# ============================================================
# SECTION: NEXTCLOUD (if present)
# ============================================================

if $HAS_NEXTCLOUD; then
  section_txt "NEXTCLOUD"; section_md "NEXTCLOUD"
  {
    echo "Nextcloud container/directory detection:"
    if docker ps --filter "name=nextcloud" --format "{{.Names}}" 2>/dev/null | grep -q nextcloud; then
      echo "Nextcloud running as Docker container:"
      docker ps --filter "name=nextcloud" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || true
      echo
      echo "Nextcloud logs (last 50 lines):"
      docker logs --tail 50 "$(docker ps -q --filter 'name=nextcloud')" 2>/dev/null || true
    elif [ -d "/var/www/nextcloud" ]; then
      echo "Nextcloud directory found at /var/www/nextcloud"
      echo "Note: Use 'sudo -u www-data php /var/www/nextcloud/occ status' for detailed status"
    else
      echo "Nextcloud detection failed"
    fi
  } | append_both
fi

# ============================================================
# SECTION: AI STACK (OpenWebUI/Ollama) (if present)
# ============================================================

if $HAS_OPENWEBUI || $HAS_OLLAMA; then
  section_txt "AI STACK (OpenWebUI/Ollama)"; section_md "AI STACK (OpenWebUI/Ollama)"
  {
    if $HAS_OPENWEBUI; then
      echo "OpenWebUI container status:"
      docker ps --filter "name=openwebui" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || \
      docker ps --filter "name=open-webui" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || true
      echo
      echo "OpenWebUI logs (last 50 lines):"
      docker logs --tail 50 "$(docker ps -q --filter 'name=openwebui' 2>/dev/null || docker ps -q --filter 'name=open-webui' 2>/dev/null)" 2>/dev/null || echo "Unable to retrieve OpenWebUI logs"
      echo
    fi
    
    if $HAS_OLLAMA; then
      echo "Ollama container status:"
      docker ps --filter "name=ollama" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || true
      echo
      echo "Ollama logs (last 50 lines):"
      docker logs --tail 50 "$(docker ps -q --filter 'name=ollama')" 2>/dev/null || echo "Unable to retrieve Ollama logs"
      echo
      echo "Ollama models (if accessible):"
      OL_CONTAINER=$(docker ps -q --filter 'name=ollama' 2>/dev/null | head -n1)
      if [ -n "$OL_CONTAINER" ]; then
        docker exec "$OL_CONTAINER" ollama list 2>/dev/null || echo "Unable to list Ollama models (container exec failed or ollama CLI unavailable)"
      else
        echo "Ollama container not found"
      fi
      echo
      echo "Note: VRAM usage tracking requires nvidia-smi integration"
    fi
  } | append_both
fi

# ============================================================
# SECTION: DATABASE STATUS (if MySQL present)
# ============================================================

if $HAS_MYSQL; then
  section_txt "DATABASE STATUS"; section_md "DATABASE STATUS"
  {
    echo "MySQL service status:"
    systemctl status mysql --no-pager 2>/dev/null || systemctl status mariadb --no-pager 2>/dev/null || echo "MySQL/MariaDB not found via systemctl"
    echo
    echo "MySQL connection test:"
    mysql -e "SELECT VERSION(); SHOW DATABASES;" 2>/dev/null || echo "MySQL connection failed (check credentials)"
    echo
    echo "Database sizes:"
    mysql -e "SELECT table_schema AS 'Database', ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) AS 'Size (MB)' FROM information_schema.TABLES GROUP BY table_schema;" 2>/dev/null || echo "Unable to retrieve database sizes"
  } | append_both
fi

# ============================================================
# SECTION: LOG INTELLIGENCE
# ============================================================

section_txt "LOG INTELLIGENCE"; section_md "LOG INTELLIGENCE"
{
  echo "OOM (Out of Memory) kills (last 7 days):"
  journalctl -k --since "7 days ago" 2>/dev/null | grep -i "killed process" | tail -n 20 || echo "No OOM kills detected"
  echo
  echo "Segmentation faults (last 7 days):"
  journalctl --since "7 days ago" 2>/dev/null | grep -i "segfault" | tail -n 20 || echo "No segfaults detected"
  echo
  echo "Failed SSH login attempts (last 24 hours, grouped by IP):"
  { journalctl -u ssh.service --since "24 hours ago" 2>/dev/null || journalctl -u sshd.service --since "24 hours ago" 2>/dev/null || true; } | grep "Failed password" | awk '{print $11}' | sort | uniq -c | sort -rn | head -20 || echo "No failed SSH attempts detected"
  echo
  echo "Systemd service failures (last 7 days):"
  journalctl -p err --since "7 days ago" --no-pager 2>/dev/null | head -50 || echo "No systemd errors detected"
  echo
  echo "Recent syslog errors/warnings (last 100 lines):"
  grep -Ei 'error|fail|critical|warn' /var/log/syslog 2>/dev/null | tail -n 100 || echo "No syslog errors found"
  echo
  if $HAS_NGINX; then
    echo "Nginx error log (last 50 lines):"
    tail -n 50 /var/log/nginx/error.log 2>/dev/null || echo "Nginx error log not accessible"
    echo
  fi
  if $HAS_APACHE; then
    echo "Apache error log (last 50 lines):"
    tail -n 50 /var/log/apache2/error.log 2>/dev/null || echo "Apache error log not accessible"
  fi
} | append_both

# ============================================================
# SECTION: SECURITY AUDIT
# ============================================================

section_txt "SECURITY AUDIT"; section_md "SECURITY AUDIT"
{
  echo "Exposed ports vs firewall rules cross-check:"
  echo "Listening ports not explicitly allowed in UFW:"
  comm -23 \
    <(ss -ltn 2>/dev/null | awk '/LISTEN/{print $4}' | grep -oE '[0-9]+$' | sort -u) \
    <(ufw status numbered 2>/dev/null | grep -oE '[0-9]+' | sort -u) \
    2>/dev/null || echo "Unable to perform cross-check"
  echo
  echo "World-writable files in critical paths (top 20):"
  find /var/www /srv /opt /etc/nginx /etc/apache2 -type f -perm -002 -ls 2>/dev/null | head -20 || echo "No world-writable files detected (or insufficient permissions)"
  echo
  echo "SUID/SGID binaries (non-standard):"
  find / -type f \( -perm -4000 -o -perm -2000 \) -ls 2>/dev/null | grep -v "/usr/bin\|/bin\|/usr/lib" | head -20 || echo "No unusual SUID/SGID binaries detected"
  echo
  echo "Recently modified files in /etc (last 7 days):"
  find /etc -type f -mtime -7 -ls 2>/dev/null | head -30 || echo "No recent /etc modifications"
} | append_both

# ============================================================
# SECTION: FILE INVENTORY
# ============================================================

section_txt "FILE INVENTORY"; section_md "FILE INVENTORY"
{
  echo "=== Web roots and application directories ==="
  ls -ld /var/www /srv /opt 2>/dev/null || true
  find /var/www /srv /opt -maxdepth 2 -mindepth 1 -type d -printf "%p\n" 2>/dev/null | sort
  echo
  echo "=== Docker Compose files (detected paths) ==="
  find /opt /srv /var/www /home /root -maxdepth 4 -type f \
    \( -iname "docker-compose.yml" -o -iname "docker-compose.yaml" -o -iname "compose.yml" -o -iname "compose.yaml" \) \
    -print 2>/dev/null | sort
} | tee "$LOG" | append_both

# ============================================================
# SECTION: RESOURCE MONITORING
# ============================================================

section_txt "RESOURCE MONITORING"; section_md "RESOURCE MONITORING"
{
  echo "Historical resource usage via sysstat (sar):"
  if command -v sar >/dev/null 2>&1; then
    sar -u 1 5 2>/dev/null || echo "sar ran but failed to collect CPU stats"
    echo
    sar -r 1 5 2>/dev/null || echo "sar ran but failed to collect memory stats"
  else
    echo "sar not installed (package: sysstat)"
  fi
} | append_both

# ============================================================
# DRIFT DETECTION
# ============================================================

section_txt "DRIFT DETECTION"; section_md "DRIFT DETECTION"
{
  echo "Configuration drift analysis:"
  if command -v md5sum >/dev/null 2>&1; then
    CURR_HASH=$(md5sum "$TXT" 2>/dev/null | awk '{print $1}')
  elif command -v sha256sum >/dev/null 2>&1; then
    CURR_HASH=$(sha256sum "$TXT" 2>/dev/null | awk '{print $1}')
  else
    CURR_HASH="0"
  fi
  
  if [ -f "$PREV_HASH" ]; then
    PREV_HASH_VAL=$(cat "$PREV_HASH")
    if [ "$CURR_HASH" != "$PREV_HASH_VAL" ]; then
      echo "DRIFT DETECTED: Server configuration has changed since last audit"
      alert_warning "Configuration drift detected"
    else
      echo "No drift detected - configuration matches last audit"
    fi
  else
    echo "First run - baseline hash established"
  fi
  
  echo "$CURR_HASH" > "$PREV_HASH"
} | append_both

# ============================================================
# ALERT SUMMARY
# ============================================================

section_txt "ALERT SUMMARY"; section_md "ALERT SUMMARY"
{
  echo "Total Critical Alerts: $CRITICAL_ALERTS"
  echo "Total Warnings: $WARNING_ALERTS"
  echo
  if [ $CRITICAL_ALERTS -gt 0 ] || [ $WARNING_ALERTS -gt 0 ]; then
    echo "Alert details:"
    cat "$ALERT_LOG" 2>/dev/null || echo "Alert log empty"
  else
    echo "No alerts generated - system appears healthy"
  fi
} | append_both

# ============================================================
# BUNDLE CREATION
# ============================================================

tar -C "$OUTDIR" -czf "$TGZ" \
  "$(basename "$TXT")" \
  "$(basename "$LOG")" \
  "$(basename "$MD")" \
  "$(basename "$SUMTX")" \
  "$(basename "$SUMMD")" \
  "$(basename "$ALERT_LOG")" \
  2>/dev/null || true

if command -v zip >/dev/null 2>&1; then
  (cd "$OUTDIR" && zip -q -9 "$(basename "$ZIP")" \
    "$(basename "$TXT")" \
    "$(basename "$LOG")" \
    "$(basename "$MD")" \
    "$(basename "$SUMTX")" \
    "$(basename "$SUMMD")" \
    "$(basename "$ALERT_LOG")") || true
else
  python3 - "$OUTDIR" "$ZIP" "$TXT" "$LOG" "$MD" "$SUMTX" "$SUMMD" "$ALERT_LOG" <<'PY' || true
import sys, os, zipfile
od, z, *files = sys.argv[1:]
with zipfile.ZipFile(z, "w", compression=zipfile.ZIP_DEFLATED) as zf:
    for f in files:
        zf.write(f, arcname=os.path.basename(f))
print(z)
PY
fi

# ============================================================
# RETENTION POLICY (keep 4 newest)
# ============================================================

for pat in "server_audit_*.txt" "server_audit_*.md" "server_audit_*.tgz" "server_audit_*.zip" "files_*.txt" "summary_*.txt" "summary_*.md" "alerts_*.txt"; do
  ls -1t "$OUTDIR"/$pat 2>/dev/null | tail -n +5 | xargs -r rm --
done

# ============================================================
# OUTPUT SUMMARY
# ============================================================

echo
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                    AUDIT COMPLETE                              ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo
echo "Server Type: $SERVER_TYPE"
echo "Critical Alerts: $CRITICAL_ALERTS"
echo "Warnings: $WARNING_ALERTS"
echo
echo "Quick Summary (TXT): $SUMTX"
echo "Quick Summary (MD):  $SUMMD"
echo "Latest Summary links: $SUMTX_LATEST , $SUMMD_LATEST"
echo
echo "Full Report (TXT):   $TXT"
echo "Full Report (MD):    $MD"
echo "Files list:          $LOG"
echo "Alert log:           $ALERT_LOG"
echo
echo "Bundle TGZ:          $TGZ"
echo "Bundle ZIP:          $ZIP"
echo
if [ $CRITICAL_ALERTS -gt 0 ]; then
  echo "⚠️  CRITICAL ALERTS DETECTED - Review alert log immediately"
  exit 1
elif [ $WARNING_ALERTS -gt 0 ]; then
  echo "⚠️  Warnings present - review recommended"
  exit 0
else
  echo "✓ No critical issues detected"
  exit 0
fi
