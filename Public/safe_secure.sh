#!/usr/bin/env bash

# This is a safe(has break logic if something fails) hardenind script to configure a vps
# Does:
# SSH
# Password auth - no
# UFW
# Fail2ban


set -e

NEW_USER="secureuser"
SSH_PORT="2222"

echo "=== SAFE VPS HARDENING START ==="

if [ "$EUID" -ne 0 ]; then
  echo "Ошибка: запускать только от root"
  exit 1
fi

echo "[1/8] Обновление системы..."
apt update && apt upgrade -y

echo "[2/8] Установка пакетов..."
apt install -y sudo ufw fail2ban logrotate unattended-upgrades

echo "[3/8] Создание пользователя..."
if ! id "$NEW_USER" &>/dev/null; then
    adduser --disabled-password --gecos "" $NEW_USER
    usermod -aG sudo $NEW_USER
fi

echo "[4/8] Копирование SSH ключей..."
mkdir -p /home/$NEW_USER/.ssh

if [ -f /root/.ssh/authorized_keys ]; then
    cp /root/.ssh/authorized_keys /home/$NEW_USER/.ssh/
    chown -R $NEW_USER:$NEW_USER /home/$NEW_USER/.ssh
    chmod 700 /home/$NEW_USER/.ssh
    chmod 600 /home/$NEW_USER/.ssh/authorized_keys
else
    echo "ОШИБКА: нет /root/.ssh/authorized_keys"
    exit 1
fi

echo ""
echo "=== ВАЖНО ==="
echo "Открой НОВЫЙ терминал и проверь вход:"
echo "ssh $NEW_USER@$(hostname -I | awk '{print $1}')"
echo ""
read -p "Если вход работает — нажми Enter..."

echo "[5/8] Настройка UFW..."
ufw allow 22/tcp
ufw allow $SSH_PORT/tcp
ufw default deny incoming
ufw default allow outgoing
ufw --force enable

echo "[6/8] Backup SSH config..."
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak

echo "[7/8] Настройка SSH (безопасный режим)..."

SSHD_CONFIG="/etc/ssh/sshd_config"

sed -i '/^Port /d' $SSHD_CONFIG
sed -i '/^PasswordAuthentication /d' $SSHD_CONFIG
sed -i '/^PermitRootLogin /d' $SSHD_CONFIG

cat >> $SSHD_CONFIG <<EOF

# --- custom hardening ---
Port 22
Port $SSH_PORT
PubkeyAuthentication yes
PasswordAuthentication no
PermitRootLogin prohibit-password
MaxAuthTries 3
EOF

sshd -t

systemctl restart ssh

echo ""
echo "=== ПРОВЕРКА №2 ==="
echo "Теперь подключись через НОВЫЙ порт:"
echo "ssh -p $SSH_PORT $NEW_USER@IP"
echo ""
read -p "Если всё работает — нажми Enter..."

echo "[8/8] Финальный hardening..."

sed -i '/^PermitRootLogin /d' $SSHD_CONFIG
sed -i '/^AllowUsers /d' $SSHD_CONFIG

cat >> $SSHD_CONFIG <<EOF
PermitRootLogin no
AllowUsers $NEW_USER
EOF

sshd -t
systemctl restart ssh

echo "Настройка Fail2Ban..."
cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
bantime = 24h
findtime = 15m
maxretry = 3
banaction = ufw

[sshd]
enabled = true
port = $SSH_PORT
EOF

systemctl enable fail2ban
systemctl restart fail2ban

echo ""
echo "======================================"
echo " ГОТОВО (SAFE MODE)"
echo " SSH порт: $SSH_PORT"
echo " Пользователь: $NEW_USER"
echo " Root вход: отключён"
echo "======================================"
