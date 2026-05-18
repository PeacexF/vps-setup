#!/usr/bin/env bash

set -Eeuo pipefail

# HOSTNAME CONFIGURATION
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

LOG_DIR="$ROOT_DIR/logs"
STATE_DIR="$ROOT_DIR/state"
BACKUP_DIR="$ROOT_DIR/state/backups"

mkdir -p "$LOG_DIR" "$STATE_DIR" "$BACKUP_DIR"

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

# CONFIG LOADING
CONFIG_FILE="$ROOT_DIR/config.env"

if [[ ! -f "$CONFIG_FILE" ]]; then
  fatal "Missing config file: $CONFIG_FILE"
fi

# shellcheck disable=SC1090
source "$CONFIG_FILE"

# REQUIRED VARIABLES
: "${DOMAIN:?DOMAIN is not set}"
: "${HOSTNAME:?HOSTNAME is not set}"

# VALIDATION
validate_fqdn() {
  local fqdn="$1"

  if [[ "$fqdn" != *.* ]]; then
    return 1
  fi

  if [[ "$fqdn" =~ [[:space:]] ]]; then
    return 1
  fi

  if [[ "$fqdn" =~ [A-Z] ]]; then
    return 1
  fi

  return 0
}

if ! validate_fqdn "$HOSTNAME"; then
  fatal "Invalid FQDN hostname: $HOSTNAME"
fi

if [[ "$HOSTNAME" != *".$DOMAIN" ]]; then
  fatal "HOSTNAME does not belong to DOMAIN"
fi

log "Hostname validation passed"

# BACKUP FILES
backup_file() {
  local file="$1"

  if [[ -f "$file" ]]; then
    local backup_name
    backup_name="$(basename "$file").$(date +%s).bak"

    cp "$file" "$BACKUP_DIR/$backup_name"

    log "Backup created: $backup_name"
  fi
}

backup_file /etc/hostname
backup_file /etc/hosts

# APPLY HOSTNAME
CURRENT_HOSTNAME="$(hostnamectl --static status 2>/dev/null || true)"

if [[ "$CURRENT_HOSTNAME" == "$HOSTNAME" ]]; then
  log "Hostname already configured"
else
  log "Setting hostname to: $HOSTNAME"

  hostnamectl set-hostname "$HOSTNAME"
fi

# /etc/hostname
echo "$HOSTNAME" > /etc/hostname

log "/etc/hostname updated"

# /etc/hosts MANAGEMENT
SHORT_HOSTNAME="${HOSTNAME%%.*}"

LOCALHOST_LINE="127.0.1.1 $HOSTNAME $SHORT_HOSTNAME"

if grep -q "^127\.0\.1\.1" /etc/hosts; then
  sed -i \
    "s/^127\.0\.1\.1.*/$LOCALHOST_LINE/" \
    /etc/hosts

  log "Updated existing 127.0.1.1 entry"
else
  echo "$LOCALHOST_LINE" >> /etc/hosts

  log "Added new 127.0.1.1 entry"
fi

# VALIDATION
FINAL_HOSTNAME="$(hostname -f 2>/dev/null || true)"

if [[ "$FINAL_HOSTNAME" != "$HOSTNAME" ]]; then
  fatal "Final hostname validation failed"
fi

log "Hostname successfully configured"

# DNS CHECK
if getent ahostsv4 "$HOSTNAME" >/dev/null 2>&1; then
  log "Hostname resolves via DNS"
else
  warn "Hostname does not currently resolve via DNS"
fi

# POSTFIX PRE-CHECK
if command -v postconf >/dev/null 2>&1; then
  POSTFIX_HOSTNAME="$(postconf -h myhostname 2>/dev/null || true)"

  if [[ -n "$POSTFIX_HOSTNAME" ]]; then
    log "Existing Postfix hostname detected: $POSTFIX_HOSTNAME"
  fi
fi

# STATE FILE
touch "$STATE_DIR/02-hostname.done"

log "Hostname configuration completed successfully"