#!/usr/bin/env bash
# PHOENIX AUDIT SYSTEM — Version 1.0 (Original)
# Source: original implementation (baseline)
# Purpose: Basic system information collection and status checks
# Author: Travis — Phoenix CommandOps (copied into repo)

set -euo pipefail

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

mkdir -p "$OUTDIR"

# Warn if not root
if [[ $EUID -ne 0 ]]; then
  echo "⚠️  Warning: Not running as root. Some data may be incomplete." >&2
fi

# Check for missing tools
MISSING_TOOLS=()
for tool in docker ss sar apachectl ufw iptables nft fail2ban-client aa-status sestatus curl timeout apt-get dpkg systemctl find python3 nginx; do
  command -v "$tool" >/dev/null 2>&1 || MISSING_TOOLS+=("$tool")
done
if [ ${#MISSING_TOOLS[@]} -ne 0 ]; then
  echo "⚠️  Missing tools: ${MISSING_TOOLS[*]} - some data may be incomplete." >&2
fi

# Helper writers
section_txt(){ echo -e "\n==================== $* ====================\n" | tee -a "$TXT"; }
section_md (){ echo -e "\n## $*\n" >> "$MD"; }
append_both(){ tee -a "$TXT" >> "$MD"; }
append_txt(){ cat >> "$TXT"; }
append_md (){ cat >> "$MD"; }

# Facts for Summary
HOSTNAME="$(hostname 2>/dev/null || echo UNKNOWN)"
IP4S="$(ip -4 -br addr 2>/dev/null | awk '{print $1,$3}' | sed "s|/.*||" | paste -sd', ' - || true)"
OS_NAME="$( (grep PRETTY_NAME= /etc/os-release | cut -d= -f2- | tr -d '"') 2>/dev/null || lsb_release -ds 2>/dev/null || uname -a )"
UPTIME="$(uptime -p 2>/dev/null || true)"

PORTS="$( (ss -ltnp | awk 'NR==1 || /LISTEN/ {print}' | head -n 15) 2>/dev/null || true )"

if command -v docker >/dev/null 2>&1; then
  DOCKER_SUMMARY="$( (docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Ports}}' | head -n 20) 2>/dev/null || true )"
else
  DOCKER_SUMMARY="Docker not installed."
fi

APACHE_VHOSTS="$( (apachectl -S 2>&1) 2>/dev/null || true )"
UFW_STATE="$( (ufw status verbose) 2>/dev/null || echo "UFW not installed or not running." )"

# ---------- Write stand-alone QUICK SUMMARY (txt + md) ----------
{
  echo "Server Audit Summary ($STAMP)"
  echo
  echo "Hostname: $HOSTNAME"
  echo "IPv4s: ${IP4S:-UNKNOWN}"
  echo "OS: $OS_NAME"
  echo "Uptime: ${UPTIME:-UNKNOWN}"
  echo
  echo "Top Listening Ports (sample)"
  echo "----------------------------------------"
  printf '%s\n' "${PORTS:-No listening sockets found}"
  echo
  echo "Docker (names / image / ports)"
  echo "----------------------------------------"
  printf '%s\n' "$DOCKER_SUMMARY"
  echo
  echo "Apache VirtualHosts / Routing (apachectl -S)"
  echo "----------------------------------------"
  printf '%s\n' "${APACHE_VHOSTS:-apachectl not available}"
  echo
  echo "UFW"
  echo "----------------------------------------"
  printf '%s\n' "$UFW_STATE"
} > "$SUMTX"

{
  echo "# Server Audit Summary ($STAMP)"
  echo
  echo "**Hostname:** $HOSTNAME  "
  echo "**IPv4s:** ${IP4S:-UNKNOWN}  "
  echo "**OS:** $OS_NAME  "
  echo "**Uptime:** ${UPTIME:-UNKNOWN}  "
  echo
  echo "### Top Listening Ports (sample)"
  echo '```'
  echo "${PORTS:-No listening sockets found}"
  echo '```'
  echo
  echo "### Docker (names / image / ports)"
  echo '```'
  echo "$DOCKER_SUMMARY"
  echo '```'
  echo
  echo "### Apache VirtualHosts / Routing (apachectl -S)"
  echo '```'
  echo "${APACHE_VHOSTS:-apachectl not available}"
  echo '```'
  echo
  echo "### UFW"
  echo '```'
  echo "$UFW_STATE"
  echo '```'
} > "$SUMMD"

# Update latest pointers for quick checks
ln -sf "$(basename "$SUMTX")" "$SUMTX_LATEST"
ln -sf "$(basename "$SUMMD")" "$SUMMD_LATEST"

# ---------- Full report (Summary at top + TOC) ----------
{
  echo "# Server Audit Summary ($STAMP)"
  echo
  echo "**Hostname:** $HOSTNAME  "
  echo "**IPv4s:** ${IP4S:-UNKNOWN}  "
  echo "**OS:** $OS_NAME  "
  echo "**Uptime:** ${UPTIME:-UNKNOWN}  "
  echo
  echo "### Quick Links"
  echo "- [HOST / OS / TIME](#host--os--time)"
  echo "- [CPU / MEM / DISK](#cpu--mem--disk)"
  echo "- [NETWORK / PORTS](#network--ports)"
  echo "- [FIREWALL / SECURITY](#firewall--security)"
  echo "- [USERS / CRON / TIMERS](#users--cron--timers)"
  echo "- [PACKAGES / UPDATES](#packages--updates)"
  echo "- [APACHE2](#apache2)"
  echo "- [DOCKER / CONTAINERS](#docker--containers)"
  echo "- [LOG HOTSPOTS](#log-hotspots)"
  echo "- [FILE INVENTORY](#file-inventory)"
  echo "- [SECURITY TOOLS / SCANNERS](#security-tools--scanners)"
  echo "- [DB / SERVICE STATUS](#db--service-status)"
  echo "- [LOG PARSE SUMMARY](#log-parse-summary)"
  echo "- [RESOURCE MONITORING](#resource-monitoring)"
  echo
  echo "### Top Listening Ports (sample)"
  echo '```'
  echo "${PORTS:-No listening sockets found}"
  echo '```'
  echo
  echo "### Docker (names / image / ports)"
  echo '```'
  echo "$DOCKER_SUMMARY"
  echo '```'
  echo
  echo "### Apache VirtualHosts / Routing (apachectl -S)"
  echo '```'
  echo "${APACHE_VHOSTS:-apachectl not available}"
  echo '```'
  echo
  echo "### UFW"
  echo '```'
  echo "$UFW_STATE"
  echo '```'
  echo
  echo "---"
} | tee "$MD" > "$TXT"

# ========== FULL SECTIONS ==========
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

section_txt "CPU / MEM / DISK"; section_md "CPU / MEM / DISK"
{
  echo "Top CPU/MEM:"; ps aux --sort=-%mem | head -n 20
  echo
  free -h
  echo
  df -hT
  echo
  lsblk -o NAME,SIZE,TYPE,MOUNTPOINT
} | append_both

section_txt "NETWORK / PORTS"; section_md "NETWORK / PORTS"
{
  ip -br addr
  echo
  ip route
  echo
  echo "Resolvers:"; sed -n "1,200p" /etc/resolv.conf
  echo
  echo "Listening TCP sockets:"; ss -ltnp || true
  echo
  echo "Listening UDP sockets:"; ss -lunp || true
} | append_both

section_txt "FIREWALL / SECURITY"; section_md "FIREWALL / SECURITY"
{
  echo "UFW:"; ufw status verbose || true
  echo
  echo "iptables (filter):"; iptables -S 2>/dev/null || true
  echo
  echo "nftables:"; nft list ruleset 2>/dev/null || true
  echo
  echo "Fail2ban:"; fail2ban-client status 2>/dev/null || echo "fail2ban not installed"
  echo
  echo "AppArmor:"; aa-status 2>/dev/null || echo "apparmor tools not installed"
  echo
  echo "SSH hardening:"
  grep -HEn "^(PermitRootLogin|PasswordAuthentication|PubkeyAuthentication|Port|X11Forwarding|ChallengeResponseAuthentication)" \
      /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf 2>/dev/null || true
} | append_both

section_txt "USERS / CRON / TIMERS"; section_md "USERS / CRON / TIMERS"
{
  echo "Users with UID 0:"; awk -F: '$3==0{print}' /etc/passwd
  echo
  echo "Sudo group:"; getent group sudo
  echo
  echo "Systemd running services (summary):"; systemctl --type=service --state=running --no-pager
  echo
  echo "Scheduled timers:"; systemctl list-timers --all --no-pager
  echo
  echo "Root crontab:"; sudo crontab -l 2>/dev/null || echo "(no root crontab)"
  echo
  echo "User crontab:"; crontab -l 2>/dev/null || echo "(no user crontab)"
  echo
  echo "/etc/cron.* dirs:"; for d in /etc/cron.hourly /etc/cron.daily /etc/cron.weekly /etc/cron.monthly; do echo "--- $d ---"; ls -lah $d 2>/dev/null || true; done
} | append_both

section_txt "PACKAGES / UPDATES"; section_md "PACKAGES / UPDATES"
{
  echo "Apt upgrades (simulation):"
  DEBIAN_FRONTEND=noninteractive apt-get -s upgrade | sed -n "1,200p" || true
  echo
  echo "Security tools present:"
  dpkg -l | egrep -i "fail2ban|unattended-upgrades|rkhunter|clamav" || true
} | append_both

section_txt "APACHE2"; section_md "APACHE2"
{
  echo "Apache sanity:"; apachectl -t 2>&1 || true
  echo
  echo "Enabled modules:"; apache2ctl -M 2>/dev/null || true
  echo
  echo "VirtualHost map (apachectl -S):"; apachectl -S 2>&1 || true
  echo
  echo "ServerName/Alias/DocumentRoot/ProxyPass (sites-enabled):"
  grep -HEnr "ServerName|ServerAlias|DocumentRoot|ProxyPass|ProxyPassReverse" /etc/apache2/sites-enabled 2>/dev/null | sed "s|/etc/apache2/sites-enabled/||"
  echo
  echo "Local HTTP probes:"
  for p in 80 8080 8000 5000 5001 3000; do
    echo "--- curl -I http://127.0.0.1:$p/ ---"
    timeout 2 curl -I "http://127.0.0.1:$p/" 2>/dev/null | head -n5 || true
  done
} | append_both

section_txt "DOCKER / CONTAINERS"; section_md "DOCKER / CONTAINERS"
{
  if command -v docker >/dev/null 2>&1; then
    echo "Docker info:"; docker info 2>/dev/null || true
    echo
    echo "Containers (all):"; docker ps -a --format "table {{.ID}}\t{{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"
    echo
    echo "Images:"; docker images
    echo
    echo "Networks:"; docker network ls
    echo
    echo "Volumes:"; docker volume ls
    echo
    echo "Compose files (search):"
    /usr/bin/find /opt /srv /var/www /home /root -maxdepth 4 -type f \( -iname "docker-compose.yml" -o -iname "docker-compose.yaml" -o -iname "compose.yml" -o -iname "compose.yaml" \) -print 2>/dev/null
  else
    echo "Docker not installed or not in PATH."
  fi
} | append_both

section_txt "LOG HOTSPOTS"; section_md "LOG HOTSPOTS"
{
  for f in /var/log/syslog /var/log/auth.log /var/log/apache2/access.log /var/log/apache2/error.log; do
    [ -f "$f" ] && { echo "---- tail -n 60 $f ----"; tail -n 60 "$f"; echo; }
  done
} | append_both

section_txt "FILE INVENTORY"; section_md "FILE INVENTORY"
{
  echo "=== Candidate web roots and app dirs ==="
  ls -ld /var/www /srv /opt 2>/dev/null || true
  find /var/www /srv /opt -maxdepth 2 -mindepth 1 -type d -printf "%p\n" 2>/dev/null | sort
  echo
  echo "=== Compose files (paths) ==="
  /usr/bin/find /opt /srv /var/www /home /root -maxdepth 4 -type f \
    \( -iname "docker-compose.yml" -o -iname "docker-compose.yaml" -o -iname "compose.yml" -o -iname "compose.yaml" \) -print 2>/dev/null | sort
} | tee "$LOG" | append_both

section_txt "SECURITY TOOLS / SCANNERS"; section_md "SECURITY TOOLS / SCANNERS"
{
  echo "SELinux:"
  if command -v sestatus >/dev/null 2>&1; then
    sestatus
  else
    echo "SELinux not installed or not applicable (Ubuntu typically uses AppArmor)"
  fi
  echo

  echo "auditd:"
  systemctl status auditd --no-pager 2>/dev/null || echo "auditd not installed or not running"
  echo

  echo "Security/Vulnerability scanners installed:"
  dpkg -l | grep -Ei 'lynis|rkhunter|chkrootkit|clamav' || echo "No known scanners found"
} | append_both

section_txt "DB / SERVICE STATUS"; section_md "DB / SERVICE STATUS"
{
  echo "Common service statuses:"
  for svc in mysql mariadb postgresql redis mongod nginx php7.4-fpm php8.0-fpm php8.1-fpm; do
    echo "--- $svc ---"
    systemctl is-active --quiet "$svc" && echo "Active" || echo "Inactive or not installed"
    echo
  done
} | append_both

section_txt "LOG PARSE SUMMARY"; section_md "LOG PARSE SUMMARY"
{
  echo "Parsing logs for keywords: error, fail, critical, denied"
  echo

  for log in /var/log/syslog /var/log/auth.log /var/log/nginx/error.log /var/log/apache2/error.log /var/log/mysql/error.log /var/log/php*/fpm.log; do
    [ -f "$log" ] || continue
    echo "---- $log ----"
    grep -iE 'error|fail|denied|critical' "$log" | tail -n 20 || echo "(no matching entries)"
    echo
  done
} | append_both

section_txt "RESOURCE MONITORING"; section_md "RESOURCE MONITORING"
{
  echo "Historical resource usage via sysstat (sar):"
  if command -v sar >/dev/null 2>&1; then
    sar -u 1 3 || echo "sar ran but failed to collect"
  else
    echo "sar not installed (package: sysstat)"
  fi
  echo

  if command -v docker >/dev/null 2>&1; then
    echo "Docker container live stats (docker stats --no-stream):"
    docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" | head -n 10
  else
    echo "Docker not installed or not available"
  fi
} | append_both

# Bundles
tar -C "$OUTDIR" -czf "$TGZ" "$(basename "$TXT")" "$(basename "$LOG")" "$(basename "$MD")" "$(basename "$SUMTX")" "$(basename "$SUMMD")" 2>/dev/null || true

if command -v zip >/dev/null 2>&1; then
  (cd "$OUTDIR" && zip -q -9 "$(basename "$ZIP")" "$(basename "$TXT")" "$(basename "$LOG")" "$(basename "$MD")" "$(basename "$SUMTX")" "$(basename "$SUMMD")") || true
else
  python3 - "$OUTDIR" "$ZIP" "$TXT" "$LOG" "$MD" "$SUMTX" "$SUMMD" <<'PY' || true
import sys, os, zipfile
od, z, *files = sys.argv[1:]
with zipfile.ZipFile(z, "w", compression=zipfile.ZIP_DEFLATED) as zf:
    for f in files:
        zf.write(f, arcname=os.path.basename(f))
print(z)
PY
fi

# Retention: keep only 4 newest of each artifact
for pat in "server_audit_*.txt" "server_audit_*.md" "server_audit_*.tgz" "server_audit_*.zip" "files_*.txt" "summary_*.txt" "summary_*.md"; do
  ls -1t "$OUTDIR"/$pat 2>/dev/null | tail -n +5 | xargs -r rm --
done

echo
echo "Quick Summary (TXT): $SUMTX"
echo "Quick Summary (MD):  $SUMMD"
echo "Latest Summary links: $SUMTX_LATEST , $SUMMD_LATEST"
echo "Full Report (TXT):   $TXT"
echo "Full Report (MD):    $MD"
echo "Files list:          $LOG"
echo "Bundle TGZ:          $TGZ"
echo "Bundle ZIP:          $ZIP"

```
