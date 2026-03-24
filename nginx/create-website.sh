#!/bin/bash
set -euo pipefail

[ "$#" -lt 1 ] && { echo "Usage: sudo $0 <domain> [php_version]"; exit 1; }

DOMAIN=$1
PHP_VERSION_ARG=${2:-}
DOC_ROOT="/var/www/public_html/$DOMAIN"
CONF="/etc/nginx/sites-available/$DOMAIN"
CERT="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"

_arrow_menu() {
    local result_var=$1; shift
    local items=("$@")
    local n=${#items[@]}
    local cur=1  # mặc định chọn item thứ 2 (8.1)
    local i

    tput civis 2>/dev/null || true

    for i in "${!items[@]}"; do
        if [ "$i" -eq "$cur" ]; then
            printf "  \033[1;32m>\033[0m %s\n" "${items[$i]}"
        else
            printf "    %s\n" "${items[$i]}"
        fi
    done

    while true; do
        local key escape_seq=""
        IFS= read -rsn1 key 2>/dev/null || true
        if [[ "$key" == $'\x1b' ]]; then
            IFS= read -rsn2 -t 0.1 escape_seq 2>/dev/null || true
            key+="$escape_seq"
        fi
        case "$key" in
            $'\x1b[A') [ "$cur" -gt 0 ] && cur=$(( cur - 1 )) ;;
            $'\x1b[B') [ "$cur" -lt $(( n - 1 )) ] && cur=$(( cur + 1 )) ;;
            ''|$'\n') break ;;
            *) continue ;;
        esac
        tput cuu "$n" 2>/dev/null || true
        for i in "${!items[@]}"; do
            if [ "$i" -eq "$cur" ]; then
                printf "  \033[1;32m>\033[0m %s\n" "${items[$i]}"
            else
                printf "    %s\n" "${items[$i]}"
            fi
        done
    done

    tput cnorm 2>/dev/null || true
    printf '\n'
    printf -v "$result_var" '%d' "$cur"
}

choose_php_version() {
    local installed
    installed=()

    if [ -d "/etc/php" ]; then
        mapfile -t installed < <(ls -1 /etc/php 2>/dev/null | sort -V)
    fi

    if [ -n "$PHP_VERSION_ARG" ]; then
        PHP_VERSION="$PHP_VERSION_ARG"
        return
    fi

    local choices=(7.4 8.1 8.2 8.3 8.4)

    if command -v dialog >/dev/null 2>&1; then
        local menu_items=()
        for i in "${!choices[@]}"; do
            local v="${choices[$i]}"
            local mark=""
            if printf '%s\n' "${installed[@]}" | grep -qx "$v"; then
                mark="(đã cài)"
            fi
            menu_items+=("$((i+1))" "$v $mark")
        done
        local tmpfile
        tmpfile=$(mktemp)
        dialog --clear --title "Chọn phiên bản PHP" --menu "Di chuyển bằng mũi tên lên/xuống, Enter chọn" 15 50 5 "${menu_items[@]}" 2>"$tmpfile"
        local sel
        sel=$(<"$tmpfile")
        rm -f "$tmpfile"
        if [ -z "$sel" ]; then
            echo "Không chọn phiên bản nào. Hủy."; exit 1
        fi
        if ! [[ "$sel" =~ ^[0-9]+$ ]] || [ "$sel" -lt 1 ] || [ "$sel" -gt "${#choices[@]}" ]; then
            echo "Lựa chọn không hợp lệ. Hủy."; exit 1
        fi
        PHP_VERSION="${choices[$((sel-1))]}"
    else
        local display_items=()
        for i in "${!choices[@]}"; do
            local v="${choices[$i]}"
            local mark=""
            if printf '%s\n' "${installed[@]}" | grep -qx "$v"; then
                mark=" (đã cài)"
            fi
            display_items+=("${v}${mark}")
        done

        echo "Chọn phiên bản PHP (↑↓ di chuyển, Enter chọn):"
        local idx=1
        _arrow_menu idx "${display_items[@]}"
        PHP_VERSION="${choices[$idx]}"
    fi

}

ensure_php_fpm() {
    local php_service="php${PHP_VERSION}-fpm"
    local sock="/run/php/${php_service}.sock"
    PHP_SOCK=""

    if [ ! -d "/etc/php/$PHP_VERSION" ]; then
        local candidate
        candidate=$(apt-cache policy "php${PHP_VERSION}-fpm" 2>/dev/null | awk '/Candidate:/{print $2}')

        # Nếu không có trong repo, thử thêm ondrej/php PPA
        if [ -z "$candidate" ] || [ "$candidate" = "(none)" ]; then
            echo "Thêm PPA ondrej/php để cài PHP $PHP_VERSION..."
            apt install -y software-properties-common 2>/dev/null || true
            add-apt-repository -y ppa:ondrej/php 2>/dev/null || true
            apt update -qq
            candidate=$(apt-cache policy "php${PHP_VERSION}-fpm" 2>/dev/null | awk '/Candidate:/{print $2}')
        fi

        if [ -n "$candidate" ] && [ "$candidate" != "(none)" ]; then
            echo "Phiên bản PHP $PHP_VERSION chưa cài. Sẽ cài tự động."
            apt install -y "php${PHP_VERSION}-fpm"
            systemctl enable --now "$php_service" || true
            sleep 1
        else
            echo "PHP-FPM cho phiên bản $PHP_VERSION không có sẵn, site sẽ không dùng FPM."
            return
        fi
    fi

    if [ ! -S "$sock" ]; then
        systemctl restart "$php_service" 2>/dev/null || true
        sleep 1
    fi

    if [ -S "$sock" ]; then
        PHP_SOCK="$sock"
    else
        echo "Không tìm được socket FPM cho PHP $PHP_VERSION, site sẽ không dùng FPM."
    fi
}

choose_php_version
ensure_php_fpm

mkdir -p "$DOC_ROOT"
chown -R www-data:www-data "$DOC_ROOT"

if [ -n "$PHP_SOCK" ]; then
    [ ! -f "$DOC_ROOT/index.php" ] && cat > "$DOC_ROOT/index.php" <<HTML
<!DOCTYPE html>
<html lang="vi">
<head><meta charset="UTF-8"><title>$DOMAIN</title></head>
<body><h1>Welcome $DOMAIN</h1></body>
</html>
HTML
    [ ! -f "$DOC_ROOT/info.php" ] && echo '<?php phpinfo();' > "$DOC_ROOT/info.php"
else
    [ ! -f "$DOC_ROOT/index.html" ] && cat > "$DOC_ROOT/index.html" <<HTML
<!DOCTYPE html>
<html lang="vi">
<head><meta charset="UTF-8"><title>$DOMAIN</title></head>
<body><h1>Welcome $DOMAIN</h1></body>
</html>
HTML
fi
write_php_block() {
    cat <<EOF
    location /.well-known/acme-challenge/ { root $DOC_ROOT; }
    root  $DOC_ROOT;
EOF
    if [ -n "$PHP_SOCK" ]; then
        cat <<EOF
    index index.html index.htm index.php;

    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location ~ \.php$ {
        fastcgi_pass         unix:$PHP_SOCK;
        fastcgi_index        index.php;
        fastcgi_read_timeout 3600;
        fastcgi_param        SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include              fastcgi_params;
        client_max_body_size 100M;
    }
EOF
    else
        cat <<EOF
    index index.html index.htm;

    location / {
        try_files \$uri \$uri/ =404;
    }
EOF
    fi
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
        write_php_block
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
        write_php_block
        echo "}"
    fi
} > "$CONF"

ln -sf "$CONF" "/etc/nginx/sites-enabled/$DOMAIN"
nginx -t && systemctl restart nginx

if [ -f "$CERT" ]; then
    echo "Done: $DOMAIN (PHP $PHP_VERSION, HTTP + HTTPS)"
else
    echo "Done: $DOMAIN (PHP $PHP_VERSION, HTTP only — chưa có SSL)"
fi
