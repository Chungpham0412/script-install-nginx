#!/bin/bash
set -euo pipefail

[ "$#" -ne 2 ] && { echo "Usage: sudo $0 <domain> <port>"; exit 1; }

DOMAIN=$1
PORT=$2
DOC_ROOT="/var/www/public_html/$DOMAIN"
CONF="/etc/nginx/sites-available/$DOMAIN"
CERT="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"

mkdir -p "$DOC_ROOT"
chown -R www-data:www-data "$DOC_ROOT"

[ ! -f "$DOC_ROOT/index.html" ] && cat > "$DOC_ROOT/index.html" <<HTML
<!DOCTYPE html>
<html lang="vi">
<head><meta charset="UTF-8"><title>$DOMAIN</title></head>
<body><h1>Welcome $DOMAIN</h1></body>
</html>
HTML

write_proxy_block() {
    cat <<EOF
    location /.well-known/acme-challenge/ { root $DOC_ROOT; }
    location / {
        proxy_pass              http://127.0.0.1:$PORT;
        proxy_http_version      1.1;
        proxy_set_header        Upgrade     \$http_upgrade;
        proxy_set_header        Connection  'upgrade';
        proxy_set_header        Host        \$host;
        proxy_set_header        X-Real-IP   \$remote_addr;
        proxy_set_header        X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header        X-Forwarded-Proto \$scheme;
        proxy_buffer_size       128k;
        proxy_buffers           4 256k;
        proxy_busy_buffers_size 256k;
        proxy_redirect          off;
        proxy_read_timeout      120;
        proxy_intercept_errors  on;
        error_page 502 503 504  @fallback;
    }
    location @fallback {
        root  $DOC_ROOT;
        try_files /index.html =503;
    }
EOF
}

{
    cat <<EOF
server {
    listen 80;
    server_name $DOMAIN www.$DOMAIN;
    access_log /var/log/nginx/$DOMAIN-access.log;
    error_log  /var/log/nginx/$DOMAIN-error.log;

EOF
    if [ -f "$CERT" ]; then
        cat <<EOF
    location /.well-known/acme-challenge/ { root $DOC_ROOT; }

    location / {
        return 301 https://\$host\$request_uri;
    }
}
EOF
    else
        write_proxy_block
        echo "}"
    fi

    if [ -f "$CERT" ]; then
        cat <<EOF

server {
    listen 443 ssl;
    http2 on;
    server_name $DOMAIN www.$DOMAIN;
    ssl_certificate     /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;
    access_log /var/log/nginx/$DOMAIN-ssl-access.log;
    error_log  /var/log/nginx/$DOMAIN-ssl-error.log;

EOF
        write_proxy_block
        echo "}"
    fi
} > "$CONF"

ln -sf "$CONF" "/etc/nginx/sites-enabled/$DOMAIN"
nginx -t && systemctl restart nginx

if [ -f "$CERT" ]; then
    echo "Done: $DOMAIN -> localhost:$PORT (HTTP + HTTPS)"
else
    echo "Done: $DOMAIN -> localhost:$PORT (HTTP only — chưa có SSL)"
fi
