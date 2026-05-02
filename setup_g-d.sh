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

echo "[1/7] Updating system..."
apt update && apt upgrade -y

echo "[2/7] Installing base packages..."
apt install -y sudo ufw fail2ban logrotate git curl gnupg lsb-release

echo "[3/7] Creating user..."
if id "$NEW_USER" &>/dev/null; then
    echo "User $NEW_USER already exists"
else
    adduser --disabled-password --gecos "" $NEW_USER
    usermod -aG sudo $NEW_USER
fi

mkdir -p /home/$NEW_USER/.ssh
if [ -f /root/.ssh/authorized_keys ]; then
    cp /root/.ssh/authorized_keys /home/$NEW_USER/.ssh/
    chown -R $NEW_USER:$NEW_USER /home/$NEW_USER/.ssh
    chmod 700 /home/$NEW_USER/.ssh
    chmod 600 /home/$NEW_USER/.ssh/authorized_keys
else
    echo "WARNING: /root/.ssh/authorized_keys not found. Password login will be disabled, you might lose access!"
fi

echo "[4/7] Configuring SSH..."
SSHD_CONFIG="/etc/ssh/sshd_config"

sed -i '/^Port /d' $SSHD_CONFIG
sed -i '/^PasswordAuthentication /d' $SSHD_CONFIG
sed -i '/^PermitRootLogin /d' $SSHD_CONFIG

echo "Port $SSH_PORT" >> $SSHD_CONFIG
echo "PasswordAuthentication no" >> $SSHD_CONFIG
echo "PermitRootLogin no" >> $SSHD_CONFIG

systemctl restart ssh

echo "[5/7] Installing Docker..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg --yes
chmod a+r /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt update
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

usermod -aG docker $NEW_USER

echo "[6/7] Configuring firewall..."
ufw default deny incoming
ufw default allow outgoing
ufw allow $SSH_PORT/tcp
ufw --force enable

echo "[7/7] Configuring Fail2Ban..."
cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 5

[sshd]
enabled = true
port = $SSH_PORT
EOF
systemctl enable fail2ban
systemctl restart fail2ban

echo "===================================="
echo "SETUP COMPLETE"
echo "Docker, Git, and Security baselines installed."
echo "IMPORTANT: Open a NEW terminal and try to login before closing this one:"
echo "ssh -p $SSH_PORT $NEW_USER@your_server_ip"
echo "===================================="