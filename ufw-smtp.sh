#!/bin/bash

set -e

echo "[1/2] Configuring UFW for Mail Services..."

ufw allow 25/tcp

ufw allow 587/tcp
ufw allow 465/tcp # SSL/TLS

ufw allow 993/tcp # IMAPS
ufw allow 995/tcp # POP3S

# INSECURE PROTOCOLS
# ufw allow 143/tcp # IMAP
# ufw allow 110/tcp # POP3

echo "[2/2] Reloading Firewall..."
ufw reload

echo "-----------------------------------"
echo "Mail ports are now OPEN in UFW:"
echo "25 (SMTP), 465/587 (Submission), 993 (IMAPS), 995 (POP3S)"
echo "-----------------------------------"
ufw status