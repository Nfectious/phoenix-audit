#!/usr/bin/env bash
set -euo pipefail

# Enhanced dependency checker for Phoenix Audit (supports v3 preflight)
# Usage: check-requirements.sh [--install]

INSTALL=0
if [[ ${1-} == "--install" ]]; then
  INSTALL=1
fi

# Core commands v3 expects (including preflight helpers)
REQUIRED=(bash md5sum sha256sum ip ss lsblk uptime df awk ln nproc curl timeout openssl tar gzip zip python3 systemctl journalctl find stat)
OPTIONAL=(docker nginx apache2 mysql ufw iptables nft fail2ban aa-status sar iostat bc apachectl)

missing_req=()
for cmd in "${REQUIRED[@]}"; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    missing_req+=("$cmd")
  fi
done

missing_opt=()
for cmd in "${OPTIONAL[@]}"; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    missing_opt+=("$cmd")
  fi
done

if [ ${#missing_req[@]} -eq 0 ]; then
  echo "All required commands are present."
else
  echo "Missing REQUIRED commands: ${missing_req[*]}"
  # Suggest apt packages using a small mapping
  declare -A pkgmap=(
    [df]=coreutils [awk]=gawk [ln]=coreutils [nproc]=coreutils [stat]=coreutils
    [ss]=iproute2 [ip]=iproute2 [lsblk]=util-linux [uptime]=procps [sar]=sysstat
    [iostat]=sysstat [apachectl]=apache2-utils [docker]=docker.io [mysql]=default-mysql-client
    [find]=findutils [tar]=tar [gzip]=gzip [zip]=zip [curl]=curl [python3]=python3
  )

  pkgs=()
  for cmd in "${missing_req[@]}"; do
    p="${pkgmap[$cmd]:-}"
    if [[ -n "$p" ]]; then pkgs+=("$p"); fi
done

  # Deduplicate
  if [ ${#pkgs[@]} -gt 0 ]; then
    IFS=$' ' read -r -a uniqpkgs <<< "$(printf "%s\n" "${pkgs[@]}" | awk '!x[$0]++')"
    echo "Suggested install (Debian/Ubuntu - common packages):"
    echo "  sudo apt update && sudo apt install -y ${uniqpkgs[*]}"
  else
    echo "Suggested install (Debian/Ubuntu):"
    echo "  sudo apt update && sudo apt install -y ${missing_req[*]}"
  fi

  echo
  echo "Note: v3 performs a storage preflight (requires ~2GB free on / by default) and will abort the audit if the system is critically low on space."
fi

if [ ${#missing_opt[@]} -eq 0 ]; then
  echo "All optional commands detected or none missing."
else
  echo "Missing OPTIONAL commands (service-specific): ${missing_opt[*]}"
  echo "Install optional packages as needed, for example:"
  echo "  sudo apt install -y ${missing_opt[*]}"
fi

if [ "$INSTALL" -eq 1 ]; then
  if ! command -v apt >/dev/null 2>&1; then
    echo "--install requested but no apt/dpkg found on this system. Aborting." >&2
    exit 2
  fi

  read -p "Proceed to apt install MISSING SUGGESTED packages? [y/N] " answer
  if [[ "$answer" =~ ^[Yy]$ ]]; then
    sudo apt update
    # If we have a suggested package list from the mapping, prefer that
    if [ ${#uniqpkgs[@]:-0} -gt 0 ]; then
      sudo apt install -y "${uniqpkgs[@]}" || { echo "apt install failed" >&2; exit 3; }
    else
      sudo apt install -y ${missing_req[*]} || { echo "apt install failed" >&2; exit 3; }
    fi
  else
    echo "Install aborted by user.";
  fi
fi

exit 0
