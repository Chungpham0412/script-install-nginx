#!/bin/bash

# install-nginx.sh
# Script cài đặt Nginx (Ubuntu/Debian)

set -euo pipefail

# Kiểm tra quyền root
if [ "$EUID" -ne 0 ]; then
  echo "Vui lòng chạy script này với quyền root: sudo ./install-nginx.sh"
  exit 1
fi

# Hỗ trợ hệ điều hành
if [ -f /etc/os-release ]; then
  . /etc/os-release
  OS_NAME="$ID"
else
  echo "Không xác định được hệ điều hành. Script này dành cho Debian/Ubuntu."
  exit 1
fi

if [[ "$OS_NAME" != "ubuntu" && "$OS_NAME" != "debian" ]]; then
  echo "Hệ điều hành hiện tại: $OS_NAME. Script này chỉ hỗ trợ Ubuntu/Debian." 
  exit 1
fi

echo "Cài đặt repo nginx mới nhất (ondrej/nginx)..."
apt install -y software-properties-common
add-apt-repository -y ppa:ondrej/nginx
apt update -y

echo "Cài đặt Nginx và tiện ích cần thiết..."
apt install -y nginx curl certbot python3-certbot-nginx

echo "Kích hoạt và khởi động Nginx..."
systemctl enable nginx
systemctl start nginx

# Kiểm tra trạng thái
if systemctl is-active --quiet nginx; then
  echo "Nginx đã được cài đặt và đang chạy."
  echo "Truy cập http://localhost để kiểm tra."
else
  echo "Có lỗi khi khởi động Nginx. Vui lòng kiểm tra trạng thái với: sudo systemctl status nginx" >&2
  exit 1
fi

# Đảm bảo certbot config files tồn tại (cần cho các site đã có SSL)
mkdir -p /etc/letsencrypt
if [ ! -f /etc/letsencrypt/options-ssl-nginx.conf ]; then
  echo "Khôi phục options-ssl-nginx.conf..."
  apt install --reinstall -y python3-certbot-nginx -qq 2>/dev/null || true
fi
if [ ! -f /etc/letsencrypt/options-ssl-nginx.conf ]; then
  echo "Tạo options-ssl-nginx.conf thủ công..."
  cat > /etc/letsencrypt/options-ssl-nginx.conf <<'SSL_CONF'
ssl_session_cache shared:le_nginx_SSL:10m;
ssl_session_timeout 1440m;
ssl_session_tickets off;
ssl_protocols TLSv1.2 TLSv1.3;
ssl_prefer_server_ciphers off;
ssl_ciphers "ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384";
SSL_CONF
  echo "Đã tạo /etc/letsencrypt/options-ssl-nginx.conf"
fi
if [ ! -f /etc/letsencrypt/ssl-dhparams.pem ]; then
  echo "Tạo ssl-dhparams.pem (mất ~30 giây)..."
  openssl dhparam -out /etc/letsencrypt/ssl-dhparams.pem 2048 2>/dev/null
  echo "Đã tạo /etc/letsencrypt/ssl-dhparams.pem"
fi

# Deploy default page
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_PAGE="$SCRIPT_DIR/default-page.html"
if [ -f "$DEFAULT_PAGE" ]; then
  cp "$DEFAULT_PAGE" /var/www/html/index.html
  echo "Đã deploy default page -> /var/www/html/index.html"
fi

# Tạo self-signed SSL cert cho default server
echo "Tạo self-signed SSL cert cho default server..."
mkdir -p /etc/nginx/ssl
if [ ! -f /etc/nginx/ssl/default.crt ]; then
  openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
    -keyout /etc/nginx/ssl/default.key \
    -out    /etc/nginx/ssl/default.crt \
    -subj   "/CN=default" 2>/dev/null
  echo "Đã tạo /etc/nginx/ssl/default.crt"
fi

# Ghi config default
cat > /etc/nginx/sites-available/default <<'NGINX_DEFAULT'
server {
    listen 80 default_server;
    server_name _;
    root /var/www/html;
    index index.html index.htm;

    location / {
        try_files $uri $uri/ =404;
    }
}

server {
    listen 443 ssl default_server;
    server_name _;

    ssl_certificate     /etc/nginx/ssl/default.crt;
    ssl_certificate_key /etc/nginx/ssl/default.key;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;

    root /var/www/html;
    index index.html index.htm;

    location / {
        try_files $uri $uri/ =404;
    }

    error_page 500 502 503 504 /50x.html;
    location = /50x.html {
        root /var/www/html;
    }
}
NGINX_DEFAULT

ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default
nginx -t && systemctl restart nginx
echo "Đã cấu hình default server (HTTP + HTTPS self-signed)."

# Cấu hình firewall
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "$SCRIPT_DIR/setup-firewall.sh"

echo "install-nginx hoàn tất."
