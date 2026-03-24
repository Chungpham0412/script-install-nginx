#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[ "$#" -ne 1 ] && { echo "Usage: sudo $0 <domain>"; exit 1; }

DOMAIN=$1
CONF="/etc/nginx/sites-available/$DOMAIN"

[ ! -f "$CONF" ] && { echo "Không tìm thấy config cho $DOMAIN."; exit 1; }

# Xóa cert qua certbot
if certbot certificates 2>/dev/null | grep -q "Certificate Name: $DOMAIN$"; then
    echo "Xóa chứng chỉ SSL cho $DOMAIN..."
    certbot delete --cert-name "$DOMAIN" --non-interactive || true
fi

# Xóa file cert còn sót nếu có
rm -rf "/etc/letsencrypt/live/$DOMAIN" \
       "/etc/letsencrypt/archive/$DOMAIN" \
       "/etc/letsencrypt/renewal/$DOMAIN.conf" 2>/dev/null || true

# Tái tạo config HTTP only (cert đã xóa → create scripts sẽ bỏ HTTPS block)
PORT=$(grep -m1 'proxy_pass' "$CONF" 2>/dev/null | grep -oE '[0-9]+' | tail -1 || true)
if [ -n "$PORT" ]; then
    bash "$SCRIPT_DIR/create-website-localhost.sh" "$DOMAIN" "$PORT"
else
    PHP_VER=$(grep -m1 'fastcgi_pass' "$CONF" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1 || true)
    bash "$SCRIPT_DIR/create-website.sh" "$DOMAIN" "$PHP_VER"
fi

echo "Đã xóa SSL và chuyển $DOMAIN về HTTP only."
