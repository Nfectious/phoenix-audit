# PHOENIX AUDIT SYSTEM — QUICK REFERENCE

## Rapid Deployment

```bash
# Transfer to server
scp v3/audit.sh root@phoenix:/opt/phoenix/
scp v3/audit.sh root@phoenix:/opt/phoenix/

# Make executable & run
chmod +x /opt/phoenix/audit.sh
sudo /opt/phoenix/audit.sh

# Optional: install wrapper and logrotate configuration
scp deploy/run-phoenix-audit.sh root@phoenix:/usr/local/bin/run-phoenix-audit.sh
scp deploy/logrotate.d/phoenix-audit root@phoenix:/etc/logrotate.d/phoenix-audit
ssh root@phoenix 'chmod +x /usr/local/bin/run-phoenix-audit.sh'
```

... (rest unchanged) ...

# Force new audit
sudo /opt/phoenix/audit.sh
**Prerequisites:** see `REQUIREMENTS.md` for required packages and optional components. Use `deploy/check-requirements.sh` to verify missing commands and get suggested apt install commands.

## Essential Commands

```bash
# Quick status check
cat ~/contabo_audit/summary_latest.txt

# Check for alerts
cat ~/contabo_audit/alerts_*.txt | tail -20

# View full report
cat ~/contabo_audit/server_audit_*.txt | less

# Force new audit
sudo /opt/phoenix/audit.sh

# Check last run status
echo $?  # 0=clean, 1=critical alerts
```

## Automated Scheduling

```bash
# Add to cron (daily 3 AM)
sudo crontab -e
0 3 * * * /opt/phoenix/audit.sh 2>&1 | logger -t phoenix-audit

# With n8n webhook
0 3 * * * /opt/phoenix/audit.sh && curl -X POST "https://n8n.example.com/webhook/audit" -F "file=@$HOME/contabo_audit/summary_latest.txt"
```

## Alert Thresholds

| Condition | Level | Action |
|---|---|---|
| Disk >85% | CRITICAL | Free space immediately |
| Swap active | WARNING | Investigate memory pressure |
| Nginx config fail | CRITICAL | Fix config before restart |
| Container restarts >10 | WARNING | Check container logs |
| Config drift | WARNING | Review system changes |
| Load >CPU count | WARNING | Identify resource hog |

## File Locations

```bash
~/contabo_audit/summary_latest.txt      # Quick overview
~/contabo_audit/summary_latest.md       # Markdown format
~/contabo_audit/server_audit_*.txt      # Full report
~/contabo_audit/alerts_*.txt            # All alerts
~/contabo_audit/files_*.txt             # File inventory
~/contabo_audit/.last_audit_hash        # Drift detection baseline
```

## Troubleshooting One-Liners

```bash
# Missing tools
sudo apt install -y sysstat net-tools curl

# Verify Docker access
docker ps -a || sudo usermod -aG docker $USER

# Check disk space
df -h | grep -E '(Filesystem|/$)'

# View recent OOM kills
journalctl -k --since "24 hours ago" | grep -i "killed process"

# Failed SSH attempts (last hour)
journalctl -u ssh --since "1 hour ago" | grep "Failed password" | awk '{print $11}' | sort | uniq -c

# Container restart counts
docker ps -aq | xargs -I {} sh -c 'echo "$(docker inspect --format="{{.Name}}: {{.RestartCount}}" {})"'

# Check swap usage
free -h | grep Swap
```

## Emergency Response

```bash
# Critical disk space
du -sh /* | sort -h | tail -10          # Find largest directories
docker system prune -af --volumes       # Clean Docker (CAUTION)
apt autoremove && apt clean             # Clean package cache

# High memory pressure
ps aux --sort=-%mem | head -20          # Find memory hogs
docker stats --no-stream                # Container resource usage
systemctl restart [service]             # Restart leaking service

# Service failures
systemctl status [service] --no-pager   # Check service status
journalctl -u [service] -n 50           # Recent service logs
nginx -t && systemctl restart nginx     # Test & restart nginx
```

## Output Interpretation

### Server Type Classification
- **PHOENIX (LEGACY-PRODUCTION)** — Full service stack detected
- **PHOENIX (AI-PROCESSING)** — AI/LLM infrastructure detected
- **GENERIC** — Minimal services, hostname not recognized

### Alert Counts
```
Critical Alerts: 0     ✓ Good
Warnings: 2           ⚠ Review recommended
```

### Exit Codes
```bash
/opt/phoenix/audit.sh
if [ $? -eq 1 ]; then
    echo "CRITICAL - Immediate action required"
else
    echo "Clean or warnings only"
fi
```

## Integration Patterns

```bash
# Email results
mail -s "Audit: $(hostname)" admin@example.com < ~/contabo_audit/summary_latest.txt

# Telegram notification
curl -X POST "https://api.telegram.org/bot<TOKEN>/sendDocument" \
  -F "chat_id=<CHAT_ID>" \
  -F "document=@$HOME/contabo_audit/summary_latest.txt"

# Archive to backup server
scp ~/contabo_audit/server_audit_*.tgz backup@server:/archives/$(hostname)/
```

## Retention Policy
- **Automatic:** Keeps 4 most recent audits
- **Manual cleanup:** `rm ~/contabo_audit/server_audit_2024*`
- **Archive before purge:** `tar -czf archive.tgz ~/contabo_audit/`

---

**VIVA VERITAS AEQUITAS**  
Phoenix CommandOps — Field Operations Manual