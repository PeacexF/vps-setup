#!/usr/bin/env bash

# This script sets up POSTFIX and DOVECOT (System users local delivery)
# it implies that you already have ufw and fail2ban set up
# i tried making it as a "single run" script, but i will separate it for security and clarity reasons, do not recommend to run it now

# Not configured:
# SPF / DKIM / DMARC
# Anti-spam (Rspamd or SpamAssassin)
# Real CA TLS cert (Let’s Encrypt via certbot)
# SMTP AUTH 

set -euo pipefail

# CONFIGURATION (change this)
DOMAIN="example.com"
HOSTNAME="mail.$DOMAIN"

TLS_COUNTRY="RU"
TLS_STATE="Saratov Oblast"
TLS_CITY="Saratov"
TLS_ORG="MailServer"
TLS_UNIT="IT"

# SAFETY BACKUP
backup_file() {
  if [ -f "$1" ]; then
    cp "$1" "$1.backup.$(date +%s)"
  fi
}

echo "[*] Updating system..."
apt update && apt upgrade -y

echo "[*] Installing Postfix and Dovecot..."
DEBIAN_FRONTEND=noninteractive apt install -y \
  postfix dovecot-core dovecot-imapd mailutils openssl

# TLS CERTIFICATE
CERT_DIR="/etc/ssl/mail"
mkdir -p "$CERT_DIR"

if [ ! -f "$CERT_DIR/mail.crt" ]; then
  echo "[*] Generating self-signed TLS certificate..."
  openssl req -new -x509 -days 3650 -nodes \
    -out "$CERT_DIR/mail.crt" \
    -keyout "$CERT_DIR/mail.key" \
    -subj "/C=$TLS_COUNTRY/ST=$TLS_STATE/L=$TLS_CITY/O=$TLS_ORG/OU=$TLS_UNIT/CN=$HOSTNAME"

  chmod 600 "$CERT_DIR/mail.key"
fi


# POSTFIX CONFIG
echo "[*] Configuring Postfix..."

postconf -e "myhostname = $HOSTNAME"
postconf -e "mydomain = $DOMAIN"
postconf -e "myorigin = \$mydomain"
postconf -e "inet_interfaces = all"
postconf -e "inet_protocols = ipv4"
# Разрешаем локальную доставку для нашего домена
postconf -e "mydestination = \$myhostname, localhost.\$mydomain, localhost, \$mydomain"
postconf -e "home_mailbox = Maildir/"

# TLS для Postfix
postconf -e "smtpd_tls_cert_file = $CERT_DIR/mail.crt"
postconf -e "smtpd_tls_key_file = $CERT_DIR/mail.key"
postconf -e "smtpd_use_tls = yes"
postconf -e "smtpd_tls_security_level = may"
postconf -e "smtp_tls_security_level = may"

# Включение submission (587) с жестким контролем отступов (табуляция)
backup_file /etc/postfix/master.cf

if ! grep -q "^submission" /etc/postfix/master.cf; then
# Важно: Строки после submission НАЧИНАЮТСЯ С ТАБУЛЯЦИИ (\t)
cat >> /etc/postfix/master.cf << 'EOF'

submission inet n       -       y       -       -       smtpd
	-o syslog_name=postfix/submission
	-o smtpd_tls_security_level=encrypt
	-o smtpd_sasl_auth_enable=yes
	-o smtpd_recipient_restrictions=permit_sasl_authenticated,reject
EOF
fi


# DOVECOT CONFIG
echo "[*] Configuring Dovecot..."

backup_file /etc/dovecot/dovecot.conf
backup_file /etc/dovecot/conf.d/10-mail.conf
backup_file /etc/dovecot/conf.d/10-auth.conf
backup_file /etc/dovecot/conf.d/10-ssl.conf

# Настройка путей к почте (синхронно с Postfix)
sed -i 's|#mail_location =.*|mail_location = maildir:~/Maildir|' /etc/dovecot/conf.d/10-mail.conf

# Настройка аутентификации
sed -i 's/#disable_plaintext_auth = yes/disable_plaintext_auth = yes/' /etc/dovecot/conf.d/10-auth.conf
sed -i 's/auth_mechanisms =.*/auth_mechanisms = plain login/' /etc/dovecot/conf.d/10-auth.conf

# Безопасное изменение SSL (заменяем только нужные строки, не ломая остальной файл)
sed -i 's/^ssl =.*/ssl = required/' /etc/dovecot/conf.d/10-ssl.conf
sed -i "s|^ssl_cert =.*|ssl_cert = <$CERT_DIR/mail.crt|" /etc/dovecot/conf.d/10-ssl.conf
sed -i "s|^ssl_key =.*|ssl_key = <$CERT_DIR/mail.key|" /etc/dovecot/conf.d/10-ssl.conf


# MAILDIR SETUP (Безопасный проход по существующим пользователям)
echo "[*] Setting Maildir skeleton..."
# Включаем nullglob, чтобы если /home пуст, цикл просто не начался
shopt -s nullglob
for user_home in /home/*; do
  if [ -d "$user_home" ]; then
    USERNAME=$(basename "$user_home")
    # Проверяем, что это реальный пользователь, а не просто забытая папка
    if id "$USERNAME" &>/dev/null; then
      mkdir -p "$user_home/Maildir"/{cur,new,tmp}
      chmod 700 "$user_home/Maildir"
      chown -R "$USERNAME":"$USERNAME" "$user_home/Maildir"
    fi
  fi
done
shopt -u nullglob


# RESTART SERVICES
echo "[*] Restarting services..."
systemctl restart postfix
systemctl restart dovecot

systemctl enable postfix
systemctl enable dovecot

# DONE
echo "[+] Mail server setup complete!"
echo "    Host: $HOSTNAME"
echo "    Domain: $DOMAIN"
echo "    Ports: 25 (SMTP), 587 (Submission), 993 (IMAPS)"