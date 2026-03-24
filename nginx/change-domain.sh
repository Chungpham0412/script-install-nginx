#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ "$#" -ne 2 ]; then
    echo "Usage: sudo $0 <old-domain> <new-domain>"
    exit 1
fi

OLD_DOMAIN=$1
NEW_DOMAIN=$2
OLD_CONF="/etc/nginx/sites-available/$OLD_DOMAIN"
NEW_CONF="/etc/nginx/sites-available/$NEW_DOMAIN"
OLD_DOC_ROOT="/var/www/public_html/$OLD_DOMAIN"
NEW_DOC_ROOT="/var/www/public_html/$NEW_DOMAIN"

[ ! -f "$OLD_CONF" ] && { echo "Không tìm thấy config cho $OLD_DOMAIN."; exit 1; }
[ -f "$NEW_CONF" ]   && { echo "Config cho $NEW_DOMAIN đã tồn tại."; exit 1; }

# Backup tạm thời (xóa sau khi migration thành công)
BACKUP="$OLD_CONF.bak.$(date +%Y%m%d%H%M%S)"
cp -p "$OLD_CONF" "$BACKUP"

# Tạo config mới bằng cách thay thế tất cả occurrences của old domain
cp -p "$OLD_CONF" "$NEW_CONF"
sed -i "s|$OLD_DOMAIN|$NEW_DOMAIN|g" "$NEW_CONF"

# Di chuyển DocumentRoot
if [ -d "$OLD_DOC_ROOT" ]; then
    mv "$OLD_DOC_ROOT" "$NEW_DOC_ROOT"
    echo "Đổi DocumentRoot: $OLD_DOMAIN -> $NEW_DOMAIN"
fi

# Enable site mới, disable site cũ
ln -sf "$NEW_CONF" "/etc/nginx/sites-enabled/$NEW_DOMAIN"
rm -f "/etc/nginx/sites-enabled/$OLD_DOMAIN"

# Nếu chưa có SSL cho domain mới → xóa toàn bộ 443 server block
if [ ! -f "/etc/letsencrypt/live/$NEW_DOMAIN/fullchain.pem" ]; then
    echo "Chưa có SSL cho $NEW_DOMAIN — xóa HTTPS block khỏi config."
    PORT=$(grep -m1 'proxy_pass' "$NEW_CONF" 2>/dev/null | grep -oE '[0-9]+' | tail -1 || true)
    if [ -n "$PORT" ]; then
        bash "$SCRIPT_DIR/create-website-localhost.sh" "$NEW_DOMAIN" "$PORT"
    else
        PHP_VER=$(grep -m1 'fastcgi_pass' "$NEW_CONF" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1 || true)
        bash "$SCRIPT_DIR/create-website.sh" "$NEW_DOMAIN" "$PHP_VER"
    fi
else
    # Kiểm tra và reload nginx
    if nginx -t; then
        systemctl restart nginx
    else
        echo "Nginx test failed. Rollback..." >&2
        rm -f "/etc/nginx/sites-enabled/$NEW_DOMAIN" "$NEW_CONF"
        ln -sf "$OLD_CONF" "/etc/nginx/sites-enabled/$OLD_DOMAIN"
        [ -d "$NEW_DOC_ROOT" ] && mv "$NEW_DOC_ROOT" "$OLD_DOC_ROOT"
        nginx -t || true
        exit 1
    fi
fi

# Migration thành công → xóa config cũ (backup giữ lại tại $BACKUP)
rm -f "$OLD_CONF"
echo "Domain đổi thành công: $OLD_DOMAIN → $NEW_DOMAIN"
echo "Backup config cũ: $BACKUP"
