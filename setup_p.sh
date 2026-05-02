#!/bin/bash
# SAVE SSH KEYS BEFORE RUNNING

set -e

NEW_USER="secureuser"
SSH_PORT="2222"
LOG_RETENTION_DAYS=7

if [ "$EUID" -ne 0 ]; then
  echo "Run as root"
  exit 1
fi

echo "[1/8] Updating system..."
apt update && apt upgrade -y

echo "[2/8] Installing base packages..."
apt install -y sudo ufw fail2ban logrotate postfix git curl gnupg lsb-release

echo "[3/8] Creating user..."
adduser --disabled-password --gecos "" $NEW_USER
usermod -aG sudo $NEW_USER

mkdir -p /home/$NEW_USER/.ssh
cp /root/.ssh/authorized_keys /home/$NEW_USER/.ssh/ 2>/dev/null || true
chown -R $NEW_USER:$NEW_USER /home/$NEW_USER/.ssh
chmod 700 /home/$NEW_USER/.ssh
chmod 600 /home/$NEW_USER/.ssh/authorized_keys

echo "[4/8] Configuring SSH..."

SSHD_CONFIG="/etc/ssh/sshd_config"

sed -i "s/#Port 22/Port $SSH_PORT/" $SSHD_CONFIG
sed -i "s/#PasswordAuthentication yes/PasswordAuthentication no/" $SSHD_CONFIG
sed -i "s/#PermitRootLogin prohibit-password/PermitRootLogin no/" $SSHD_CONFIG

grep -q "^PasswordAuthentication" $SSHD_CONFIG || echo "PasswordAuthentication no" >> $SSHD_CONFIG
grep -q "^PermitRootLogin" $SSHD_CONFIG || echo "PermitRootLogin no" >> $SSHD_CONFIG
grep -q "^Port" $SSHD_CONFIG || echo "Port $SSH_PORT" >> $SSHD_CONFIG

systemctl restart ssh

echo "[5/8] Configuring firewall..."

ufw default deny incoming
ufw default allow outgoing

ufw allow $SSH_PORT/tcp

ufw --force enable

echo "[6/8] Configuring Fail2Ban..."

cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 5
destemail = root@localhost
sender = fail2ban@localhost

[sshd]
enabled = true
port = $SSH_PORT
logpath = /var/log/auth.log
backend = systemd
EOF

systemctl enable fail2ban
systemctl restart fail2ban

echo "[7/8] Configuring log rotation..."

cat > /etc/logrotate.d/custom <<EOF
/var/log/*.log {
    daily
    rotate $LOG_RETENTION_DAYS
    missingok
    notifempty
    compress
    delaycompress
    copytruncate
}
EOF

echo "[8/8] Installing Postfix..."

debconf-set-selections <<< "postfix postfix/mailname string localhost"
debconf-set-selections <<< "postfix postfix/main_mailer_type string 'Internet Site'"

apt install -y postfix

systemctl enable postfix
systemctl restart postfix

echo "===================================="
echo "SETUP COMPLETE"
echo "===================================="
echo "User: $NEW_USER"
echo "SSH Port: $SSH_PORT"
echo "IMPORTANT: reconnect using:"
echo "ssh -p $SSH_PORT $NEW_USER@your_server_ip"
echo "===================================="