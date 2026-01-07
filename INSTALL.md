PHOENIX SERVER AUDIT SYSTEM — DEPLOYMENT KIT

CONTENTS:
- v1/audit.sh        Main audit script (v1.0 Original)
- v2/audit.sh        Enhanced script (v2.0)
- README.md          Documentation and install instructions
- CHANGELOG.md       Version history and roadmap
- QUICKREF.md        Field operations quick reference

TARGET SERVERS:
- PHOENIX (Hostname: phoenix) — Legacy production (n8n, HA, Nextcloud)
  - PHOENIX (Hostname: phoenix) — AI processing (OpenWebUI, Ollama)

QUICK START:

STEP 1: Transfer to Servers
  scp v2/audit.sh root@phoenix:/opt/phoenix/
  scp v2/audit.sh root@phoenix:/opt/phoenix/

STEP 2: Make Executable
  ssh root@phoenix
  chmod +x /opt/phoenix/audit_enhanced.sh

  ssh root@phoenix
  chmod +x /opt/phoenix/audit_enhanced.sh

STEP 3: Run Initial Audit
  sudo /opt/phoenix/audit_enhanced.sh

STEP 4: Review Results
  cat ~/contabo_audit/summary_latest.txt

STEP 5: Check for Alerts
  cat ~/contabo_audit/alerts_*.txt

STEP 6: Schedule Daily Audits
  sudo crontab -e
  # Add: 0 3 * * * /opt/phoenix/audit_enhanced.sh 2>&1 | logger -t phoenix-audit

Optional: wrapper-based file logging with rotation
  # Copy wrapper and logrotate config to server
  scp deploy/run-phoenix-audit.sh root@phoenix:/usr/local/bin/run-phoenix-audit.sh
  scp deploy/logrotate.d/phoenix-audit root@phoenix:/etc/logrotate.d/phoenix-audit
  ssh root@phoenix 'chmod +x /usr/local/bin/run-phoenix-audit.sh'

  # Cron using wrapper (rotates locally):
  # 0 3 * * * /usr/local/bin/run-phoenix-audit.sh

VERIFICATION:
  ls -lh /opt/phoenix/audit.sh
  sudo /opt/phoenix/audit.sh
  ls -lh ~/contabo_audit/
  cat ~/contabo_audit/summary_latest.txt

EXIT CODES:
  0 = Clean run (no critical alerts)
  1 = Critical alerts detected (requires immediate action)

SUPPORT:
  See README.md and QUICKREF.md for usage and troubleshooting.