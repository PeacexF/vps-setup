#!/usr/bin/env bash

# !!! СОХРАНИТЬ И ДОБАВИТЬ SSH КЛЮЧИ ИЗ /root/.ssh/authorized_keys В НОВОГО ПОЛЬЗОВАТЕЛЯ, А ТАКЖЕ СОХРАНИТЬ ИХ ЛОКАЛЬНО У СЕБЯ
# Unsafe script - run with caution
# does basic hardening


set -e

NEW_USER="secureuser"
SSH_PORT="2222"

if [ "$EUID" -ne 0 ]; then
  echo "Ошибка: Запустите скрипт от имени root"
  exit 1
fi

echo "[1/5] Обновление системы и установка инструментов безопасности..."
apt update && apt upgrade -y
apt install -y sudo ufw fail2ban logrotate libpam-tmpdir unattended-upgrades git docker

echo "[2/5] Настройка пользователя и прав..."
if ! id "$NEW_USER" &>/dev/null; then
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
    echo "ВНИМАНИЕ: /root/.ssh/authorized_keys не найден. Убедитесь, что у вас есть доступ!"
fi

echo "[3/5] Укрепление SSH (Hardening)..."
SSHD_CONFIG="/etc/ssh/sshd_config"

sed -i '/^Port /d' $SSHD_CONFIG
sed -i '/^PasswordAuthentication /d' $SSHD_CONFIG
sed -i '/^PermitRootLogin /d' $SSHD_CONFIG
sed -i '/^PubkeyAuthentication /d' $SSHD_CONFIG
sed -i '/^X11Forwarding /d' $SSHD_CONFIG
sed -i '/^MaxAuthTries /d' $SSHD_CONFIG

cat >> $SSHD_CONFIG <<EOF
Port $SSH_PORT
PubkeyAuthentication yes
PasswordAuthentication no
PermitRootLogin no
MaxAuthTries 3
X11Forwarding no
AllowUsers $NEW_USER
EOF

systemctl restart ssh

echo "[4/5] Настройка Firewall (UFW)..."
ufw default deny incoming
ufw default allow outgoing
ufw allow $SSH_PORT/tcp
ufw limit $SSH_PORT/tcp
ufw --force enable

echo "[5/5] Настройка Fail2Ban (Расширенная)..."
cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
# Бан на 24 часа для рецидивистов
bantime = 24h
findtime = 15m
maxretry = 3
banaction = ufw

[sshd]
enabled = true
port = $SSH_PORT
logpath = %(sshd_log)s
backend = %(sshd_backend)s
EOF

systemctl enable fail2ban
systemctl restart fail2ban

echo "=========================================================="
echo "БЕЗОПАСНОСТЬ НАСТРОЕНА"
echo "1. SSH порт: $SSH_PORT"
echo "2. Вход под root: ЗАПРЕЩЕН"
echo "3. Вход по паролю: ЗАПРЕЩЕН"
echo "4. Пользователь с sudo: $NEW_USER"
echo "=========================================================="