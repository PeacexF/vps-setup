#!/bin/bash

set -e

echo "[1/3] Creating Fail2Ban jail for Mail services..."

cat > /etc/fail2ban/jail.d/mail-security.local <<EOF
[postfix]
enabled  = true
port     = smtp,465,587
filter   = postfix
logpath  = /var/log/mail.log
maxretry = 3
bantime  = 24h

[postfix-sasl]
enabled  = true
port     = smtp,465,587,submission,imap,imaps,pop3,pop3s
filter   = postfix[mode=auth]
logpath  = /var/log/mail.log
maxretry = 3
bantime  = 48h

[dovecot]
enabled = true
port    = pop3,pop3s,imap,imaps,submission
filter  = dovecot
logpath = /var/log/mail.log
maxretry = 5
bantime  = 24h
EOF

echo "[2/3] Customizing filters if needed..."
# DEFAULT FILTERS AT /etc/fail2ban/filter.d/

echo "[3/3] Restarting Fail2Ban..."
systemctl restart fail2ban

echo "Fail2Ban mail protection enabled."
echo "Check status: fail2ban-client status postfix"