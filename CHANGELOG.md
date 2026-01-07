# PHOENIX AUDIT SYSTEM — CHANGELOG

## Version 2.1 (Production / v3) (2026-01-07)

### Highlights
- **Production-grade preflight checks:** v3 aborts safely when the root filesystem is critically low (default requires ~2GB free) to avoid failing mid-audit and corrupting reports.
- **Improved robustness:** Use of `safe()` and `safe_out()` wrappers for non-fatal command failure handling, more robust Docker and Nginx discovery logic.
- **Deployment helpers:** `deploy/check-requirements.sh` added to detect missing commands and suggest apt packages; wrapper `deploy/run-phoenix-audit.sh` updated to prefer v3 and to run optional preflight checks.
- **Minor fixes:** hostname classification logic refined, improved outputs and consistent `summary_latest` linking.

---

## Version 2.0 Enhanced (2025-01-06)

### Major Changes
- **Dual-Target Architecture:** Single script adapts to Phoenix targets (legacy and AI) servers

**Maintained by:** Travis — Phoenix CommandOps  
**License:** Internal Use — Phoenix Framework  
**Last Updated:** 2025-01-06
- **Hostname-Based Classification:** Auto-detects server identity via hostname
- **Service Fingerprinting:** Dynamic detection of n8n, Home Assistant, Nextcloud, OpenWebUI, Ollama
- **Alert System:** Critical/Warning classification with exit codes for automation
- **Drift Detection:** Config hash comparison across audits

### New Audit Sections
- **Nginx Full Audit:** Config validation, VHost mapping, SSL cert expiry, upstream backends
- **Docker Deep Inspection:** Health status, restart counts, volume mounts, resource limits
- **Log Intelligence:** OOM kills, segfaults, failed SSH logins (aggregated by IP)
- **Security Audit:** Port/firewall cross-check, world-writable files, SUID binaries, recent /etc modifications
- **Service-Specific Checks:** n8n, Home Assistant, Nextcloud, OpenWebUI/Ollama status and logs
- **Database Validation:** MySQL connection test, database sizes, table counts

### Enhanced Features
- **Resource Trending:** Load averages, I/O wait analysis, historical sar data
- **Threshold Monitoring:** Disk >85%, swap active, high load, container restarts >10
- **SSL Certificate Expiry:** Per-domain cert validation with expiration warnings
- **Apache/Nginx Coexistence:** Handles servers running both web servers
- **Automated Retention:** Keeps 4 most recent audits, purges older

### Output Improvements
- **Quick Summary:** Standalone lightweight report for rapid status check
- **Alert Log:** Dedicated file for all critical alerts and warnings
- **Symlinked Latest:** `summary_latest.txt` always points to most recent
- **Markdown Support:** Dual-format output (TXT + MD) for documentation integration
- **Bundled Archives:** Auto-generated .tgz and .zip for easy transfer

### Exit Code Logic
```
0 = Clean run, no critical alerts (warnings acceptable)
1 = Critical alerts detected, immediate action required
```

### Automation Hooks
- Compatible with cron scheduling
- Syslog integration via logger
- n8n webhook-ready output format
- Conditional alerting based on exit codes

---

## Version 1.0 Original (2024-12-XX)

### Initial Features
- Basic system information collection
- Service status checks (systemd, Docker, Apache)
- Network configuration mapping
- Firewall rule extraction
- Package inventory
- Log file sampling
- Manual execution only

### Limitations
- No service-specific intelligence
- No alerting mechanism
- No drift detection
- Point-in-time resource data only
- Single generic report format
- Manual retention management

---

## Future Roadmap (Phase 2)

### Planned for v2.1
- [ ] Service API integration (n8n workflow status, HA entity count)
- [ ] Comparative trend analysis (week-over-week metrics)
- [ ] Container performance profiling (JSON output for graphing)
- [ ] VRAM tracking for Ollama (nvidia-smi integration)
- [ ] Predictive disk space warnings

### Planned for v2.2
- [ ] Web dashboard integration (Phoenix CommandOps)
- [ ] Real-time audit streaming
- [ ] Anomaly detection via ML baseline
- [ ] Multi-server orchestration (audit fleet management)
- [ ] Automated remediation suggestions

---

**Maintained by:** Travis — Phoenix CommandOps  
**License:** Internal Use — Phoenix Framework  
**Last Updated:** 2025-01-06