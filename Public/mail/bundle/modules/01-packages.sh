#!/usr/bin/env bash

# INSTALLS PACKAGES NEEDED FOR POSTFIX AND DOVECOT SETUP
# PACKAGE LIST AT LINE 63

set -Eeuo pipefail

# PACKAGE INSTALLATION
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

LOG_DIR="$ROOT_DIR/logs"
STATE_DIR="$ROOT_DIR/state"

mkdir -p "$LOG_DIR" "$STATE_DIR"

LOG_FILE="$LOG_DIR/setup.log"

# LOGGING
timestamp() {
  date +"%Y-%m-%d %H:%M:%S"
}

log() {
  echo "[$(timestamp)] [INFO] $*" | tee -a "$LOG_FILE"
}

warn() {
  echo "[$(timestamp)] [WARN] $*" | tee -a "$LOG_FILE"
}

fatal() {
  echo "[$(timestamp)] [ERROR] $*" | tee -a "$LOG_FILE" >&2
  exit 1
}

# ROOT CHECK
if [[ "$EUID" -ne 0 ]]; then
  fatal "This script must be run as root"
fi

# APT RETRY WRAPPER
apt_retry() {
  local retries=5
  local delay=5
  local count=0

  until "$@"; do
    exit_code=$?

    count=$((count + 1))

    if (( count >= retries )); then
      fatal "Command failed after ${retries} attempts: $*"
    fi

    warn "Command failed. Retry ${count}/${retries} in ${delay}s..."
    sleep "$delay"
  done
}

# PACKAGE LIST
PACKAGES=(
  postfix
  postfix-pcre
  dovecot-core
  dovecot-imapd
  openssl
  mailutils
  rsyslog
)

# APT UPDATE
log "Updating package index..."

export DEBIAN_FRONTEND=noninteractive

apt_retry apt-get update -y

# PACKAGE INSTALLATION
log "Installing required packages..."

apt_retry apt-get install -y \
  "${PACKAGES[@]}"

# PACKAGE VALIDATION
log "Validating installed packages..."

for pkg in "${PACKAGES[@]}"; do
  if ! dpkg -s "$pkg" >/dev/null 2>&1; then
    fatal "Package validation failed: $pkg"
  fi
done

log "All packages installed successfully"

# SERVICE VALIDATION
SERVICES=(
  postfix
  dovecot
  rsyslog
)

for svc in "${SERVICES[@]}"; do
  if ! systemctl list-unit-files | grep -q "^${svc}\.service"; then
    fatal "Service unit missing: $svc"
  fi
done

log "Systemd services verified"

# VERSION LOGGING
log "Installed versions:"

postconf mail_version | tee -a "$LOG_FILE"
dovecot --version | tee -a "$LOG_FILE"
openssl version | tee -a "$LOG_FILE"

# STATE FILE
touch "$STATE_DIR/01-packages.done"

log "Package installation completed successfully"