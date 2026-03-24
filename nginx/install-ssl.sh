#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[ "$#" -ne 1 ] && { echo "Usage: sudo $0 <domain>"; exit 1; }

DOMAIN=$1
DOC_ROOT="/var/www/public_html/$DOMAIN"
CONF="/etc/nginx/sites-available/$DOMAIN"
CERT="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
EMAIL="webmaster@$DOMAIN"

[ ! -f "$CONF" ] && { echo "Chưa tạo website cho $DOMAIN. Chạy create-website trước."; exit 1; }

# Cài certbot nếu chưa có hoặc thiếu options-ssl-nginx.conf
if ! command -v certbot &>/dev/null || [ ! -f /etc/letsencrypt/options-ssl-nginx.conf ]; then
    echo "Cài đặt Certbot + nginx plugin..."
    apt update -qq
    apt install -y certbot python3-certbot-nginx
fi

# Lấy cert nếu chưa có
if [ -f "$CERT" ]; then
    echo "SSL đã tồn tại cho $DOMAIN."
else
    echo "Lấy chứng chỉ SSL cho $DOMAIN..."
    mkdir -p "$DOC_ROOT"
    # Thử với cả www, nếu lỗi thì chỉ dùng domain chính
    certbot certonly --webroot -w "$DOC_ROOT" \
        -d "$DOMAIN" -d "www.$DOMAIN" \
        -m "$EMAIL" --agree-tos --non-interactive 2>/dev/null || \
    certbot certonly --webroot -w "$DOC_ROOT" \
        -d "$DOMAIN" \
        -m "$EMAIL" --agree-tos --non-interactive
fi

# Tái tạo nginx config với HTTPS block (cert đã tồn tại)
PORT=$(grep -m1 'proxy_pass' "$CONF" 2>/dev/null | grep -oE '[0-9]+' | tail -1 || true)
if [ -n "$PORT" ]; then
    bash "$SCRIPT_DIR/create-website-localhost.sh" "$DOMAIN" "$PORT"
else
    PHP_VER=$(grep -m1 'fastcgi_pass' "$CONF" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1 || true)
    bash "$SCRIPT_DIR/create-website.sh" "$DOMAIN" "$PHP_VER"
fi

echo "SSL đã cài đặt xong cho $DOMAIN."
