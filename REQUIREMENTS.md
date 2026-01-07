# Phoenix Audit — Requirements

This file lists the commands and packages the audit scripts use. The repository contains three releases (`v1`, `v2`, `v3`). **v3** (Production, VERSION=2.1) adds a safe preflight storage check and additional runtime helpers. Install the *required* packages on target Ubuntu/Debian hosts before running the audit for complete results.

## Required (core)
- bash (script runner)
- coreutils (md5sum/sha256sum, awk, sed, sort, uniq, df, ln, date, nproc)
- iproute2 (ip, ss)
- util-linux (lsblk)
- procps (uptime, free)
- curl
- timeout (part of coreutils or moreutils on some systems)
- openssl
- gzip
- tar
- zip (optional — script falls back to a Python zip method)
- python3
- systemd tools (systemctl, journalctl)
- find (find command)

## v3 notes
- v3 performs a storage preflight on `/` and will abort the audit if the system is critically low on space (default requires ~2GB free) or if usage/inode thresholds are exceeded (defaults: >=90% usage, >=95% inode usage). Ensure the target has sufficient free space before running large audits or bundle creation.
- The `deploy/check-requirements.sh` helper attempts to map missing commands to likely `apt` packages and prints suggested install lines.

## Optional (service-specific, improves audit detail)
- docker.io or docker-ce — Docker inspection and container checks
- nginx — Nginx configuration checks and SSL expiry probes
- apache2 (apachectl) — Apache virtualhost checks
- mysql-client (mysql CLI) — Database checks
- ufw — firewall status checks
- iptables / nft — firewall inspection
- fail2ban-client — fail2ban checks
- apparmor-utils (aa-status) — AppArmor status
- sysstat (sar,iostat) — historical resource metrics
- bc — numeric comparisons
- md5sum / sha256sum — hashing for drift detection (md5sum preferred)

## Installation hints (Ubuntu/Debian)
To install the most common requirements:

```bash
sudo apt update
sudo apt install -y curl python3 tar zip gzip iproute2 util-linux procps findutils systemd openssl coreutils
# Optional (select per your environment)
sudo apt install -y docker.io nginx apache2 mysql-client ufw iptables nftables fail2ban apparmor-utils sysstat bc
```

## Notes
- The script will run without the optional packages, but sections that depend on those services will be skipped or limited. The script warns if tools are missing.
- Running as `root` yields more complete information (service status, logs, permissions).

## Quick check
Use the `deploy/check-requirements.sh` script included in this repo to discover missing commands and get suggested install commands:

```bash
# Local dry-run (no changes):
bash deploy/check-requirements.sh

# Optional interactive install (asks before installing):
sudo bash deploy/check-requirements.sh --install
```
