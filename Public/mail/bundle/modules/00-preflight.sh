#!/usr/bin/env bash

# "PRE-FLIGHT" CHECKS
# THIS SCRIPT IS RAN BEFORE THE REST TO DETERMINE WHETHER YOU CAN OR CAN NOT CONTINUE
# EDIT AT YOUR OWN RISK

set -Eeuo pipefail

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
  echo "[$(timestamp)] [WARN] $*" | tee -a "$LOG_FILE" >&2
}

fatal() {
  echo "[$(timestamp)] [ERROR] $*" | tee -a "$LOG_FILE" >&2
  exit 1
}

# HELPERS
require_command() {
  command -v "$1" >/dev/null 2>&1 || \
    fatal "Required command not found: $1"
}

check_port() {
  local port="$1"

  if ss -tulpn | grep -q ":$port "; then
    fatal "Port $port is already in use"
  fi
}

check_service_absent() {
  local svc="$1"

  if systemctl list-unit-files | grep -q "^${svc}\.service"; then
    if systemctl is-active --quiet "$svc"; then
      fatal "Conflicting service is active: $svc"
    fi
  fi
}

# ROOT CHECK
log "Running pre-flight checks..."

if [[ "$EUID" -ne 0 ]]; then
  fatal "This script must be run as root"
fi

# OS CHECK

if [[ ! -f /etc/os-release ]]; then
  fatal "Cannot determine operating system"
fi

source /etc/os-release

case "${ID:-}" in
  debian|ubuntu)
    ;;
  *)
    fatal "Unsupported operating system: ${ID:-unknown}"
    ;;
esac

log "Detected OS: ${PRETTY_NAME:-unknown}"

# SYSTEMD CHECK

if ! pidof systemd >/dev/null 2>&1; then
  fatal "Systemd is required"
fi

log "Systemd detected"

# REQUIRED COMMANDS
REQUIRED_COMMANDS=(
  ss
  systemctl
  hostnamectl
  awk
  grep
  sed
  tee
  apt
)

for cmd in "${REQUIRED_COMMANDS[@]}"; do
  require_command "$cmd"
done

log "Required commands verified"

# NETWORK PORT CHECKS
log "Checking required ports..."

PORTS=(
  25
  587
  993
)

for port in "${PORTS[@]}"; do
  check_port "$port"
done

log "Ports are available"

# CONFLICTING MTAS
log "Checking conflicting mail services..."

CONFLICTING_SERVICES=(
  exim4
  sendmail
)

for svc in "${CONFLICTING_SERVICES[@]}"; do
  check_service_absent "$svc"
done

log "No conflicting MTAs detected"

# HOSTNAME VALIDATION
CURRENT_HOSTNAME="$(hostname -f 2>/dev/null || true)"

if [[ -z "$CURRENT_HOSTNAME" ]]; then
  fatal "FQDN hostname is not configured"
fi

if [[ "$CURRENT_HOSTNAME" != *.* ]]; then
  fatal "Hostname is not a valid FQDN: $CURRENT_HOSTNAME"
fi

log "FQDN hostname: $CURRENT_HOSTNAME"

# DNS RESOLUTION CHECK
if ! getent ahostsv4 "$CURRENT_HOSTNAME" >/dev/null 2>&1; then
  warn "Hostname does not resolve via DNS: $CURRENT_HOSTNAME"
else
  log "Hostname resolves correctly"
fi

# MEMORY CHECK
TOTAL_MEM_MB="$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)"

if (( TOTAL_MEM_MB < 512 )); then
  warn "Low memory detected: ${TOTAL_MEM_MB}MB"
else
  log "Memory check passed: ${TOTAL_MEM_MB}MB"
fi

# DISK CHECK
FREE_DISK_MB="$(df / --output=avail -m | tail -n1 | tr -d ' ')"

if (( FREE_DISK_MB < 1024 )); then
  fatal "Not enough disk space available"
fi

log "Disk space available: ${FREE_DISK_MB}MB"

# TIME SYNC CHECK
if systemctl is-active --quiet systemd-timesyncd; then
  log "Time synchronization service active"
else
  warn "systemd-timesyncd is not active"
fi

# APT LOCK CHECK
if fuser /var/lib/dpkg/lock >/dev/null 2>&1; then
  fatal "APT/dpkg lock detected"
fi

if fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; then
  fatal "APT frontend lock detected"
fi

log "APT locks not detected"

# STATE FILE
touch "$STATE_DIR/00-preflight.done"

log "Pre-flight checks completed successfully"