#!/bin/bash
set -euo pipefail

[ "$#" -ne 1 ] && { echo "Usage: sudo $0 <domain>"; exit 1; }

DOMAIN=$1
DOC_ROOT="/var/www/public_html/$DOMAIN"
CONF="/etc/nginx/sites-available/$DOMAIN"
ENABLED="/etc/nginx/sites-enabled/$DOMAIN"
NGINX_LOG_DIR="/var/log/nginx"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 0. Backup trước khi xóa
bash "$SCRIPT_DIR/backup-website.sh" "$DOMAIN"

# 1. Xóa symlink và config nginx
rm -f "$ENABLED"  && echo "Đã xóa sites-enabled/$DOMAIN"
rm -f "$CONF"     && echo "Đã xóa sites-available/$DOMAIN"

# 2. Xóa DocumentRoot
if [ -d "$DOC_ROOT" ]; then
    rm -rf "$DOC_ROOT" && echo "Đã xóa $DOC_ROOT"
fi

# 3. Xóa SSL (nếu có)
certbot delete --cert-name "$DOMAIN" --non-interactive 2>/dev/null || true
rm -rf "/etc/letsencrypt/live/$DOMAIN" \
       "/etc/letsencrypt/archive/$DOMAIN" \
       "/etc/letsencrypt/renewal/$DOMAIN.conf" 2>/dev/null || true

# 4. Xóa log
rm -f "$NGINX_LOG_DIR/$DOMAIN-access.log" \
      "$NGINX_LOG_DIR/$DOMAIN-error.log" \
      "$NGINX_LOG_DIR/$DOMAIN-ssl-access.log" \
      "$NGINX_LOG_DIR/$DOMAIN-ssl-error.log" 2>/dev/null || true

# 5. Reload nginx
if nginx -t; then
    systemctl restart nginx
    echo "Nginx reload thành công."
else
    echo "Nginx test failed. Kiểm tra: sudo nginx -t" >&2
    exit 1
fi

echo "Xong: đã xóa website $DOMAIN."
