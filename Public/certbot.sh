#!/usr/bin/env bash

set -euo pipefail

# Configuration
DOMAIN="yourdomain.com"
EMAIL="admin@yourdomain.com"

echo "[*] Updating system packages..."
apt update && apt upgrade -y

echo "[*] Installing Nginx (web server)..."
apt install -y nginx

echo "[*] Installing snapd..."
apt install -y snapd

apt-get remove -y certbot || true

echo "[*] Installing Certbot via Snap..."
snap install core
snap refresh core
snap install --classic certbot

ln -sf /snap/bin/certbot /usr/bin/certbot

echo "[*] Installing Certbot Nginx plugin..."
snap set certbot trust-plugin-with-root=ok

echo "[*] Requesting SSL certificate..."
systemctl start nginx

# Start of certbot
certbot --nginx \
  -d "$DOMAIN" \
  -d "www.$DOMAIN" \
  --non-interactive \
  --agree-tos \
  -m "$EMAIL" \
  --redirect

echo "[*] Checking renewal timer..."
systemctl list-timers | grep certbot

echo "[+] SSL Configuration completed successfully!"