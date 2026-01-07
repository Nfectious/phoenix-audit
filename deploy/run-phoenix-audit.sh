#!/usr/bin/env bash
# Wrapper to run the Phoenix audit and perform simple file rotation when needed
# Install: copy to /usr/local/bin/run-phoenix-audit.sh and chmod +x

OUTLOG=/var/log/phoenix-audit.log
MAX_BYTES=$((50*1024*1024))   # rotate when > 50MB
RETENTION=7                   # keep last 7 rotated files

# Ensure log file exists with safe perms
if [ ! -f "$OUTLOG" ]; then
  touch "$OUTLOG" && chown root:adm "$OUTLOG" && chmod 0640 "$OUTLOG" || true
fi

# Optional preflight check (if included in /opt/phoenix/deploy)
if [ -x /opt/phoenix/deploy/check-requirements.sh ]; then
  /opt/phoenix/deploy/check-requirements.sh >> "$OUTLOG" 2>&1 || true
fi

# Run audit (append output)
# Prefer the installed v3 script (recommended). Fallback to other known names if present.
AUDIT_CANDIDATES=(/opt/phoenix/audit.sh /opt/phoenix/audit_v3.sh /opt/phoenix/audit_enhanced.sh /usr/local/bin/phoenix-audit.sh)
RAN=0
for candidate in "${AUDIT_CANDIDATES[@]}"; do
  if [ -x "$candidate" ]; then
    "$candidate" >> "$OUTLOG" 2>&1 || true
    RAN=1
    break
  fi
done

if [ "$RAN" -eq 0 ]; then
  echo "[ERROR] No audit script found in known locations; please install v3 to /opt/phoenix/audit.sh" >> "$OUTLOG"
fi

# Rotate if file exceeds size
if [ -f "$OUTLOG" ] && [ "$(stat -c%s "$OUTLOG")" -gt $MAX_BYTES ]; then
  TIMESTAMP=$(date -u +%Y%m%d_%H%M%S)
  mv "$OUTLOG" "${OUTLOG}.${TIMESTAMP}"
  gzip -9 "${OUTLOG}.${TIMESTAMP}" || true
  # Recreate empty log with proper perms
  touch "$OUTLOG" && chown root:adm "$OUTLOG" && chmod 0640 "$OUTLOG" || true
  # Remove older archives beyond retention
  ls -1t /var/log/phoenix-audit.log.*.gz 2>/dev/null | tail -n +$((RETENTION+1)) | xargs -r rm --
fi
