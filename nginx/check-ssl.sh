#!/bin/bash
set -euo pipefail

R='\033[0;31m' G='\033[0;32m' Y='\033[1;33m' C='\033[0;36m' W='\033[1;37m' NC='\033[0m'
BOLD='\033[1m'

divider() { echo -e "${C}  $(printf '─%.0s' {1..50})${NC}"; }

# ── Parse ngày hết hạn từ cert ────────────────────────────────────────────────
cert_expiry_days() {
    local domain="$1"
    local cert="/etc/letsencrypt/live/$domain/fullchain.pem"
    [ -f "$cert" ] || { echo "-1"; return; }

    local expiry_str
    expiry_str=$(openssl x509 -enddate -noout -in "$cert" 2>/dev/null | cut -d= -f2)
    [ -z "$expiry_str" ] && { echo "-1"; return; }

    local expiry_epoch now_epoch
    expiry_epoch=$(date -d "$expiry_str" +%s 2>/dev/null || date -j -f "%b %d %T %Y %Z" "$expiry_str" +%s 2>/dev/null || echo "0")
    now_epoch=$(date +%s)
    echo $(( (expiry_epoch - now_epoch) / 86400 ))
}

# ── Header ────────────────────────────────────────────────────────────────────
echo
divider
printf "${W}${BOLD}  %-36s %-12s %s${NC}\n" "DOMAIN" "HẾT HẠN" "TRẠNG THÁI"
divider

found=0
for f in /etc/nginx/sites-enabled/*; do
    [ -f "$f" ] || [ -L "$f" ] || continue
    domain=$(basename "$f")
    [ "$domain" = "default" ] && continue

    cert="/etc/letsencrypt/live/$domain/fullchain.pem"
    [ -f "$cert" ] || continue   # bỏ qua site không có SSL

    days=$(cert_expiry_days "$domain")
    expiry_date=$(openssl x509 -enddate -noout -in "$cert" 2>/dev/null | cut -d= -f2 | awk '{print $1,$2,$4}' || echo "N/A")

    if [ "$days" -lt 0 ]; then
        status="${R}${BOLD}  ĐÃ HẾT HẠN${NC}"
        label="${R}${BOLD}$expiry_date${NC}"
    elif [ "$days" -le 14 ]; then
        status="${R}  Còn ${days} ngày ← CẦN GIA HẠN NGAY${NC}"
        label="${R}$expiry_date${NC}"
    elif [ "$days" -le 30 ]; then
        status="${Y}  Còn ${days} ngày ← Sắp hết hạn${NC}"
        label="${Y}$expiry_date${NC}"
    else
        status="${G}  Còn ${days} ngày${NC}"
        label="${G}$expiry_date${NC}"
    fi

    printf "  %-36s %-12b %b\n" "$domain" "$label" "$status"
    (( found++ )) || true
done

divider

if [ "$found" -eq 0 ]; then
    echo -e "  ${Y}Không có domain nào đang dùng SSL.${NC}"
else
    echo -e "  ${C}Tổng: $found domain có SSL${NC}"

    # Cảnh báo nếu cần gia hạn
    urgent=0
    for f in /etc/nginx/sites-enabled/*; do
        [ -f "$f" ] || [ -L "$f" ] || continue
        domain=$(basename "$f")
        [ "$domain" = "default" ] && continue
        cert="/etc/letsencrypt/live/$domain/fullchain.pem"
        [ -f "$cert" ] || continue
        days=$(cert_expiry_days "$domain")
        [ "$days" -le 30 ] && (( urgent++ )) || true
    done

    if [ "$urgent" -gt 0 ]; then
        echo
        echo -e "  ${Y}Gợi ý gia hạn: ${NC}certbot renew --dry-run"
        echo -e "  ${Y}Gia hạn thật:  ${NC}certbot renew"
    fi
fi

divider
echo
