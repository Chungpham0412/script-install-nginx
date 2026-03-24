#!/bin/bash

B='\033[0;34m' G='\033[0;32m' R='\033[0;31m' C='\033[0;36m' W='\033[1;37m' NC='\033[0m'

divider() { echo -e "${B}────────────────────────────────────────────────────${NC}"; }

divider
printf "${W}  %-38s %-8s %-8s${NC}\n" "DOMAIN" "PORT" "SSL"
divider

count=0
for f in /etc/nginx/sites-enabled/*; do
    [ -f "$f" ] || [ -L "$f" ] || continue
    domain=$(basename "$f")
    [ "$domain" = "default" ] && continue

    # Detect port or PHP version
    port=$(grep -m1 'proxy_pass' "$f" 2>/dev/null | grep -oE '[0-9]+' | tail -1 || true)
    if [ -z "$port" ]; then
        php_ver=$(grep -m1 'fastcgi_pass' "$f" 2>/dev/null | grep -oE 'php[0-9]+\.[0-9]+' | head -1 || true)
        port="${php_ver:+PHP ${php_ver#php}}"
        port="${port:-PHP}"
    fi
    # SSL status
    if [ -f "/etc/letsencrypt/live/$domain/fullchain.pem" ]; then
        ssl="${G}✓ HTTPS${NC}"
    else
        ssl="${R}✗ HTTP ${NC}"
    fi

    printf "  %-38s %-8s " "$domain" "$port"
    echo -e "$ssl"
    (( count++ )) || true
done

divider
echo -e "  ${C}Total: $count website(s)${NC}"
divider
