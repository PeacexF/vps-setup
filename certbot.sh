echo "Installing Certbot and configuring SSL..."

apt update
apt install -y snapd
snap install core; snap refresh core

apt-get remove -y certbot

snap install --classic certbot

ln -s /snap/bin/certbot /usr/bin/certbot || true

# Получение сертификата: ЗАМЕНИ ДОМЕН И ПОЧТУ
# ВАЖНО: Веб-сервер (Nginx/Apache) должен быть запущен, 
# а домен должен быть направлен на IP этого сервера.
# Если хочешь просто установить, но не выпускать пока сертификат — закомментируй строку ниже.
# certbot --nginx -d yourdomain.com -d www.yourdomain.com --non-interactive --agree-tos -m admin@yourdomain.com

# Проверка таймера авто-обновления
systemctl list-timers | grep certbot