#!/usr/bin/env bash

# Used to configure UFW for mail services
# Implies that you already have basic ufw configuration

set -euo pipefail

echo "[Mail UFW] Script to set ufw smtp rules"


# SMTP / Mail submission
ufw allow 25/tcp comment "SMTP - server to server mail"

ufw allow 587/tcp comment "SMTP Submission (authenticated clients)"

ufw allow 465/tcp comment "SMTPS (legacy SSL SMTP)"

ufw allow 993/tcp comment "IMAPS (secure IMAP)"

# Uncomment if POP3 needed
# ufw allow 995/tcp comment "POP3S (secure POP3)"

# Optional hardening
# SMTp abuse prevention
ufw limit 25/tcp comment "SMTP rate-limited"

# Reload only if needed
echo "[Mail UFW] Reloading firewall"
ufw reload

echo "[Mail UFW] Current status:"
ufw status verbose | sed -n '1,120p'

echo "[Mail UFW] Mail ports configured successfully."