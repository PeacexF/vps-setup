#!/usr/bin/env bash

set -Eeuo pipefail

# =========================================================
# TLS / CERTIFICATE SETUP
# =========================================================
#
# Supported modes:
# - selfsigned
#
# Planned future modes:
# - letsencrypt
#
# Responsibilities:
# - certificate generation
# - certificate validation
# - permissions management
#
# This module DOES NOT:
# - configure Postfix TLS
# - configure Dovecot TLS
# - reload services
#
# =========================================================

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
: "${TLS_MODE:?TLS_MODE is not set}"
: "${TLS_CERT_DIR:?TLS_CERT_DIR is not set}"

: "${HOSTNAME:?HOSTNAME is not set}"

: "${TLS_COUNTRY:?TLS_COUNTRY is not set}"
: "${TLS_STATE:?TLS_STATE is not set}"
: "${TLS_CITY:?TLS_CITY is not set}"
: "${TLS_ORG:?TLS_ORG is not set}"
: "${TLS_UNIT:?TLS_UNIT is not set}"

# PATHS
CERT_FILE="$TLS_CERT_DIR/mail.crt"
KEY_FILE="$TLS_CERT_DIR/mail.key"

# HELPERS
require_command() {
  command -v "$1" >/dev/null 2>&1 || \
    fatal "Required command not found: $1"
}

backup_file() {
  local file="$1"

  if [[ -f "$file" ]]; then
    local backup_name
    backup_name="$(basename "$file").$(date +%s).bak"

    cp "$file" "$BACKUP_DIR/$backup_name"

    log "Backup created: $backup_name"
  fi
}

# VALIDATION
require_command openssl

# PREPARE TLS DIRECTORY
mkdir -p "$TLS_CERT_DIR"

chmod 755 "$TLS_CERT_DIR"
chown root:root "$TLS_CERT_DIR"

log "TLS directory prepared: $TLS_CERT_DIR"

# BACKUP EXISTING FILES

backup_file "$CERT_FILE"
backup_file "$KEY_FILE"

# TLS MODE
case "$TLS_MODE" in

  selfsigned)

    log "Using self-signed TLS mode"

    if [[ -f "$CERT_FILE" && -f "$KEY_FILE" ]]; then
      warn "TLS certificate already exists"

    else
      log "Generating self-signed certificate"

      openssl req \
        -new \
        -newkey rsa:4096 \
        -x509 \
        -sha256 \
        -nodes \
        -days 3650 \
        -subj "/C=$TLS_COUNTRY/ST=$TLS_STATE/L=$TLS_CITY/O=$TLS_ORG/OU=$TLS_UNIT/CN=$HOSTNAME" \
        -keyout "$KEY_FILE" \
        -out "$CERT_FILE"

      log "Self-signed certificate generated"
    fi

    ;;

  letsencrypt)

    fatal "Let's Encrypt mode is not implemented yet"

    ;;

  *)

    fatal "Unsupported TLS_MODE: $TLS_MODE"

    ;;

esac

# APPLY PERMISSIONS
chmod 600 "$KEY_FILE"
chmod 644 "$CERT_FILE"

chown root:root "$KEY_FILE"
chown root:root "$CERT_FILE"

log "TLS file permissions applied"

# FILE EXISTENCE CHECK
[[ -f "$CERT_FILE" ]] || \
  fatal "Certificate file missing"

[[ -f "$KEY_FILE" ]] || \
  fatal "Private key file missing"

# CERTIFICATE VALIDATION
if ! openssl x509 \
  -in "$CERT_FILE" \
  -noout \
  >/dev/null 2>&1; then

  fatal "Invalid certificate format"
fi

log "Certificate format validation passed"

# PRIVATE KEY VALIDATION
if ! openssl rsa \
  -in "$KEY_FILE" \
  -check \
  -noout \
  -passin pass: \
  >/dev/null 2>&1; then

  fatal "Invalid or encrypted private key"
fi

log "Private key validation passed"

# CERT/KEY MATCH VALIDATION
CERT_MODULUS="$(
  openssl x509 \
    -noout \
    -modulus \
    -in "$CERT_FILE" \
    | openssl sha256
)"

KEY_MODULUS="$(
  openssl rsa \
    -noout \
    -modulus \
    -in "$KEY_FILE" \
    -passin pass: \
    | openssl sha256
)"

if [[ "$CERT_MODULUS" != "$KEY_MODULUS" ]]; then
  fatal "Certificate and private key do not match"
fi

log "Certificate/private key pair validation passed"

# CERTIFICATE INFO
CERT_SUBJECT="$(
  openssl x509 \
    -in "$CERT_FILE" \
    -noout \
    -subject
)"

CERT_EXPIRE="$(
  openssl x509 \
    -in "$CERT_FILE" \
    -noout \
    -enddate
)"

log "Certificate subject: $CERT_SUBJECT"
log "Certificate expiration: $CERT_EXPIRE"

# STATE FILE
touch "$STATE_DIR/03-tls.done"

log "TLS setup completed successfully"