# Phoenix Audit System

A lightweight, extensible server audit system for Debian/Ubuntu hosts. This repository packages two releases:

- **v1.0 (Original)** — basic system information collection and status checks (in `v1/audit.sh`).
- **v2.0 (Enhanced)** — adaptive service fingerprinting (Phoenix), alerting, drift detection, service-specific checks and Docker health inspection (in `v2/audit.sh`).

---

## Quick comparison

- v1.0: Minimal, conservative, fewer dependencies, easier to run on constrained systems.
- v2.0: Adds service discovery (nginx/apache/docker/n8n/Nextcloud/HomeAssistant/OpenWebUI/Ollama/MySQL), alerting (warning / critical), drift detection, SSL expiry probing, and richer Docker inspection.


## Installation (example)

1. Clone the repository:

```bash
git clone <your-repo-url> phoenix-audit
cd phoenix-audit
```

2. Copy the script you want to the target servers, make executable and run once to create baseline reports:

```bash
# Example: install enhanced audit to /opt/valkyrie
scp v2/audit.sh root@yourserver:/opt/valkyrie/audit.sh
ssh root@yourserver 'chmod +x /opt/valkyrie/audit.sh && /opt/valkyrie/audit.sh'

# Check quick summary
cat ~/contabo_audit/summary_latest.txt
```

Notes:
- Scripts are written for Debian/Ubuntu (systemd, apt). Many commands are POSIX/Bash standard and will work across variants, but some checks (UFW, apt, apachectl) are distro-specific.
- Running as root gives more complete results; the script warns if run as non-root.

---

## Cron job (automated daily audit)

Add the job as root (example runs daily at 03:00 and logs stdout/stderr to syslog):

```bash
sudo crontab -e
# Add the following line:
0 3 * * * /opt/phoenix/audit.sh 2>&1 | logger -t phoenix-audit
```

If you prefer file logging instead of syslog:

```bash
0 3 * * * /opt/phoenix/audit.sh >> /var/log/phoenix-audit.log 2>&1
```

Retention note: the scripts themselves keep the 4 newest audit files and purge older ones automatically.

---

## Output & Alerts

By default results are written to `~/contabo_audit/`:

- `summary_YYYYMMDD_HHMMSS.txt` — brief text summary
- `summary_YYYYMMDD_HHMMSS.md` — markdown summary
- `server_audit_YYYYMMDD_HHMMSS.txt` — full report
- `files_YYYYMMDD_HHMMSS.txt` — file inventory
- `alerts_YYYYMMDD_HHMMSS.txt` — alerts (warnings and criticals)
- `server_audit_*.tgz` / `*.zip` — bundled archives
- `summary_latest.txt` / `summary_latest.md` — symlinks to most recent summaries

Exit codes (for automation):
- `0` = Clean run (or warnings only)
- `1` = Critical alerts detected (immediate attention required)

---

## Security & Privacy

- The audit collects potentially sensitive system information (packages, service status, logs). Keep archives and summaries protected and only share with trusted admins.
- Where applicable, use secure transport (scp/rsync over SSH) to transfer archives.

---

## Contribution & Roadmap

See `CHANGELOG.md` for release notes and roadmap. If you want enhancements, open an issue or PR documenting the expected behavior and any required third-party API credentials (do not include secrets in PRs).

---

## License

This repository is distributed under an internal use policy (see `LICENSE`).

---

If you want, I can also initialize a git repository here and provide a suggested commit history (local only). Do you want me to run `git init` and create initial commits for you?