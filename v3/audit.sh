#!/usr/bin/env bash
# PHOENIX AUDIT SYSTEM — Version 2.1 (Production-Grade)
# Purpose: Phoenix-target reconnaissance with extensive service-specific checks
# Author: Travis — Phoenix CommandOps (repo version, hardened)

set -euo pipefail

VERSION="2.1 (Production-Grade)"
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
# SAFETY HELPERS (PRODUCTION HARDENING)
# ============================================================

# Run command, never fail script; capture errors as warnings where appropriate.
safe() { "$@" 2>/dev/null || true; }

# Print command output even if it errors, without killing the audit.
safe_out() { "$@" 2>&1 || true; }

# Check if a command exists
hascmd() { command -v "$1" >/dev/null 2>&1; }

# Preflight: avoid running heavy audit if disk is too full (prevents no-space failures)
preflight_storage() {
  local mount="${1:-/}"
  local min_free_mb="${2:-2048}"    # 2GB
  local max_use_pct="${3:-90}"      # if >= 90% used, abort
  local max_inode_pct="${4:-95}"    # if >= 95% inodes used, abort

  local used_pct free_mb inode_pct
  used_pct="$(df -P "$mount" | awk 'NR==2 {gsub("%","",$5); print $5}')"
  free_mb="$(df -Pm "$mount" | awk 'NR==2 {print $4}')"
  inode_pct="$(df -Pi "$mount" | awk 'NR==2 {gsub("%","",$5); print $5}')"

  if [[ -z "${used_pct:-}" || -z "${free_mb:-}" || -z "${inode_pct:-}" ]]; then
    echo "[WARNING] Storage preflight could not read df output for $mount" >> "$ALERT_LOG"
    return 0
  fi

  if (( used_pct >= max_use_pct )); then
    echo "[CRITICAL] Preflight: disk usage ${used_pct}% on $mount (>= ${max_use_pct}%). Aborting audit to prevent failures." | tee -a "$ALERT_LOG" >&2
    exit 1
  fi

  if (( free_mb < min_free_mb )); then
    echo "[CRITICAL] Preflight: only ${free_mb}MB free on $mount (< ${min_free_mb}MB). Aborting audit to prevent failures." | tee -a "$ALERT_LOG" >&2
    exit 1
  fi

  if (( inode_pct >= max_inode_pct )); then
    echo "[CRITICAL] Preflight: inode usage ${inode_pct}% on $mount (>= ${max_inode_pct}%). Aborting audit to prevent failures." | tee -a "$ALERT_LOG" >&2
    exit 1
  fi
}

# Trap unexpected errors and log them (still exits because -e is enabled)
trap 'echo "[CRITICAL] Script error at line $LINENO. Check $TXT / $MD for last completed section." | tee -a "$ALERT_LOG" >&2' ERR

# Run preflight early
preflight_storage "/"

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

hascmd nginx && HAS_NGINX=true
hascmd apache2 && HAS_APACHE=true
hascmd docker && HAS_DOCKER=true
hascmd mysql && HAS_MYSQL=true

if $HAS_DOCKER; then
  safe docker ps --format '{{.Names}}' | grep -qi "nextcloud" && HAS_NEXTCLOUD=true || true
  safe docker ps --format '{{.Names}}' | grep -qi "n8n" && HAS_N8N=true || true
  safe docker ps --format '{{.Names}}' | grep -qi "homeassistant\|home-assistant" && HAS_HOMEASSISTANT=true || true
  safe docker ps --format '{{.Names}}' | grep -qi "openwebui\|open-webui" && HAS_OPENWEBUI=true || true
  safe docker ps --format '{{.Names}}' | grep -qi "ollama" && HAS_OLLAMA=true || true
fi

[ -d "/var/www/nextcloud" ] && HAS_NEXTCLOUD=true

# Server classification based on hostname and services
DETECTED_HOSTNAME="$(safe hostname | tr '[:upper:]' '[:lower:]')"
SERVER_TYPE="UNKNOWN"

# FIXED: duplicate phoenix condition removed; classification is deterministic.
if [[ "$DETECTED_HOSTNAME" == *"phoenix"* ]]; then
  # If hostname is phoenix, prefer AI classification when AI stack present
  if $HAS_OLLAMA || $HAS_OPENWEBUI; then
    SERVER_TYPE="PHOENIX (AI-PROCESSING)"
  else
    SERVER_TYPE="PHOENIX (LEGACY-PRODUCTION)"
  fi
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
if [[ ${EUID:-9999} -ne 0 ]]; then
  alert_warning "Not running as root. Some data may be incomplete."
fi

# Check for missing tools (advisory only)
MISSING_TOOLS=()
for tool in ss sar iostat apachectl ufw iptables nft fail2ban-client aa-status curl timeout apt-get dpkg systemctl find python3 awk sed grep; do
  hascmd "$tool" || MISSING_TOOLS+=("$tool")
done

if [ ${#MISSING_TOOLS[@]} -ne 0 ]; then
  alert_warning "Missing tools: ${MISSING_TOOLS[*]} - some data may be incomplete."
fi

# ============================================================
# OUTPUT HELPERS
# ============================================================

section_txt(){ echo -e "\n==================== $* ====================\n" | tee -a "$TXT"; }
section_md (){ echo -e "\n## $*\n" >> "$MD"; }
append_both(){ tee -a "$TXT" >> "$MD"; }

# ============================================================
# COLLECT SYSTEM FACTS
# ============================================================

HOSTNAME="$(safe hostname || echo UNKNOWN)"
IP4S="$(safe ip -4 -br addr | awk '{print $1,$3}' | sed "s|/.*||" | paste -sd', ' - || true)"
OS_NAME="$( (safe_out grep PRETTY_NAME= /etc/os-release | cut -d= -f2- | tr -d '"') || safe_out lsb_release -ds || safe_out uname -a )"
UPTIME="$(safe uptime -p)"
LOAD_AVG="$(safe uptime | awk -F'load average:' '{print $2}' || true)"

PORTS="$(safe_out ss -ltnp | awk 'NR==1 || /LISTEN/ {print}' | head -n 20)"

if $HAS_DOCKER; then
  DOCKER_SUMMARY="$(safe_out docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' | head -n 25)"
else
  DOCKER_SUMMARY="Docker not installed."
fi

if $HAS_NGINX; then
  NGINX_CONFIG_TEST="$(safe_out nginx -t)"
  NGINX_VHOSTS="$(safe_out grep -Hnr "server_name" /etc/nginx/sites-enabled/ | sed 's|/etc/nginx/sites-enabled/||' || true)"
fi

if $HAS_APACHE; then
  APACHE_VHOSTS="$(safe_out apachectl -S)"
fi

UFW_STATE="$(safe_out ufw status verbose | sed -e 's/\r$//')"
[[ -z "$UFW_STATE" ]] && UFW_STATE="UFW not installed or not running."

# ============================================================
# RESOURCE THRESHOLD CHECKS
# ============================================================

# Disk usage check
ROOT_DISK_USAGE="$(df -P / | awk 'NR==2 {gsub("%","",$5); print $5}')"
if [[ -n "${ROOT_DISK_USAGE:-}" ]] && (( ROOT_DISK_USAGE > 85 )); then
  alert_critical "Root disk usage at ${ROOT_DISK_USAGE}% (threshold: 85%)"
fi

# Swap usage check
SWAP_USED="$(free 2>/dev/null | awk '/Swap:/ {print $3}' || echo 0)"
if [[ -n "${SWAP_USED:-0}" ]] && (( SWAP_USED > 0 )); then
  alert_warning "Swap is active (${SWAP_USED} KB in use) - potential memory pressure"
fi

# Load average check without bc (15min avg > CPU count)
CPU_COUNT="$(nproc 2>/dev/null || echo 1)"
LOAD_15MIN="$(uptime 2>/dev/null | awk -F'load average:' '{print $2}' | awk -F, '{print $3}' | xargs || echo "")"
if [[ -n "${LOAD_15MIN:-}" ]]; then
  if awk -v l="$LOAD_15MIN" -v c="$CPU_COUNT" 'BEGIN { exit !(l > c) }'; then
    alert_warning "15-min load average ($LOAD_15MIN) exceeds CPU count ($CPU_COUNT)"
  fi
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
  printf '%s\n' "${PORTS:-No listening sockets found}"
  echo
  echo "DOCKER CONTAINERS"
  echo "----------------------------------------"
  printf '%s\n' "$DOCKER_SUMMARY"
  echo
  if $HAS_NGINX; then
    echo "NGINX CONFIG TEST"
    echo "----------------------------------------"
    printf '%s\n' "$NGINX_CONFIG_TEST"
    echo
    echo "NGINX VHOSTS"
    echo "----------------------------------------"
    printf '%s\n' "${NGINX_VHOSTS:-None found}"
    echo
  fi
  if $HAS_APACHE; then
    echo "APACHE VHOSTS"
    echo "----------------------------------------"
    printf '%s\n' "${APACHE_VHOSTS:-apachectl not available}"
    echo
  fi
  echo "UFW FIREWALL"
  echo "----------------------------------------"
  printf '%s\n' "$UFW_STATE"
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
  echo "**Version:** $VERSION  "
  echo "**Server Type:** $SERVER_TYPE  "
  echo "**Hostname:** $HOSTNAME  "
  echo "**IPv4s:** ${IP4S:-UNKNOWN}  "
  echo "**OS:** $OS_NAME  "
  echo "**Uptime:** ${UPTIME:-UNKNOWN}  "
  echo "**Load Avg:**$LOAD_AVG  "
  echo
  echo "---"
} | tee "$MD" > "$TXT"

# ============================================================
# (The remainder of your original sections can stay as-is)
# If you want, paste the rest of your repo version and I’ll merge it cleanly
# while preserving every section + adding safe() where needed.
# ============================================================

echo
echo "Audit outputs:"
echo "  TXT: $TXT"
echo "   MD: $MD"
echo "  SUM: $SUMTX_LATEST / $SUMMD_LATEST"
echo "Alerts:"
echo "  $ALERT_LOG"
