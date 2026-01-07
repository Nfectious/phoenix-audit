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

# Run audit (append output)
/opt/phoenix/audit_enhanced.sh >> "$OUTLOG" 2>&1

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
