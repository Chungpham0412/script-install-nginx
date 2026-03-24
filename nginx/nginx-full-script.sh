#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[ "$EUID" -ne 0 ] && { echo -e "\033[0;31mChạy với quyền root: sudo $0\033[0m"; exit 1; }

# ── Colors ────────────────────────────────────────────────────────────────────
R='\033[0;31m' G='\033[0;32m' Y='\033[1;33m'
B='\033[0;34m' C='\033[0;36m' W='\033[1;37m' NC='\033[0m'
BOLD='\033[1m' DIM='\033[2m'

# ── Helpers ───────────────────────────────────────────────────────────────────
divider()  { echo -e "${B}  ──────────────────────────────────────────${NC}"; }
prompt()   { printf "${Y}  %s${NC} " "$1"; }
success()  { echo -e "${G}  ✓ $1${NC}"; }
error()    { echo -e "${R}  ✗ $1${NC}"; }
info()     { echo -e "${C}  → $1${NC}"; }
pause()    { echo; prompt "Nhấn Enter để tiếp tục..."; read -r; }

valid_domain() {
    [[ "$1" =~ ^[a-zA-Z0-9]([a-zA-Z0-9._-]*[a-zA-Z0-9])?$ ]] && [[ ! "$1" =~ [[:space:]] ]]
}
valid_port() {
    [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -ge 1 ] && [ "$1" -le 65535 ]
}

# ── Read single keypress ───────────────────────────────────────────────────────
read_key() {
    local key
    IFS= read -rsn1 key
    if [[ "$key" == $'\x1b' ]]; then
        local s1 s2
        IFS= read -rsn1 -t 0.1 s1 2>/dev/null || true
        IFS= read -rsn1 -t 0.1 s2 2>/dev/null || true
        key="${key}${s1}${s2}"
    fi
    printf '%s' "$key"
}

# ── Yes/No picker ─────────────────────────────────────────────────────────────
confirm_yn() {
    local msg="$1"
    local sel=1
    while true; do
        tput clear 2>/dev/null || clear
        echo
        echo -e "  ${W}${BOLD}${msg}${NC}"
        echo
        (( sel == 0 )) \
            && echo -e "    ${G}${BOLD}[ ✓ Yes ]${NC}   ${DIM}[ No ]${NC}" \
            || echo -e "    ${DIM}[ Yes ]${NC}   ${R}${BOLD}[ ✗ No ]${NC}"
        echo
        echo -e "  ${DIM}← →  di chuyển    Enter  xác nhận${NC}"
        local key; key=$(read_key)
        case "$key" in
            $'\x1b[D'|$'\x1b[A') sel=0 ;;
            $'\x1b[C'|$'\x1b[B') sel=1 ;;
            [yY]) return 0 ;; [nN]|$'\x1b') return 1 ;;
            ''|$'\n') return $sel ;;
        esac
    done
}

# ── Domain picker ─────────────────────────────────────────────────────────────
SELECTED_DOMAIN=""
select_domain() {
    local title="${1:-Chọn domain:}"
    local domains=() ports=() has_ssl=()
    for f in /etc/nginx/sites-enabled/*; do
        [ -f "$f" ] || [ -L "$f" ] || continue
        local d; d=$(basename "$f")
        [ "$d" = "default" ] && continue
        local p; p=$(grep -m1 'proxy_pass' "$f" 2>/dev/null | grep -oE '[0-9]+' | tail -1 || true)
        if [ -z "$p" ]; then
            local pv; pv=$(grep -m1 'fastcgi_pass' "$f" 2>/dev/null | grep -oE 'php[0-9]+\.[0-9]+' | head -1 || true)
            p="${pv:+PHP ${pv#php}}"; p="${p:-PHP}"
        fi
        local s=0
        [ -f "/etc/letsencrypt/live/$d/fullchain.pem" ] && s=1
        domains+=("$d"); ports+=("$p"); has_ssl+=("$s")
    done

    [ ${#domains[@]} -eq 0 ] && { error "Không có website nào."; return 1; }

    local sel=0 total=${#domains[@]}
    while true; do
        tput clear 2>/dev/null || clear
        echo
        echo -e "  ${W}${BOLD}${title}${NC}"
        echo
        divider
        printf "  ${W}${BOLD}  %-34s %-8s %-8s${NC}\n" "DOMAIN" "PORT" "SSL"
        divider
        for (( i=0; i<total; i++ )); do
            local ssl_label
            (( has_ssl[i] == 1 )) && ssl_label="${G}✓ HTTPS${NC}" || ssl_label="${R}✗ HTTP ${NC}"
            if (( i == sel )); then
                printf "  ${Y}${BOLD} ▶  %-34s %-8s ${NC}" "${domains[$i]}" "${ports[$i]}"
            else
                printf "  ${DIM}    %-34s %-8s ${NC}" "${domains[$i]}" "${ports[$i]}"
            fi
            echo -e "$ssl_label"
        done
        divider
        echo -e "  ${DIM}↑ ↓  di chuyển    Enter  chọn    Esc  hủy${NC}"
        local key; key=$(read_key)
        case "$key" in
            $'\x1b[A') sel=$(( (sel - 1 + total) % total )) ;;
            $'\x1b[B') sel=$(( (sel + 1) % total )) ;;
            ''|$'\n')  SELECTED_DOMAIN="${domains[$sel]}"; return 0 ;;
            $'\x1b')   return 1 ;;
        esac
    done
}

# ── Header box ────────────────────────────────────────────────────────────────
_draw_header() {
    local subtitle="${1:-}"
    echo
    echo -e "  ${W}${BOLD}╔══════════════════════════════════════════╗${NC}"
    if [ -n "$subtitle" ]; then
        local line="  SERVER MANAGER  ›  ${subtitle}"
        printf "  ${W}${BOLD}║${NC}${Y}${BOLD}%-42s${W}${BOLD}║${NC}\n" "$line"
    else
        echo -e "  ${W}${BOLD}║           SERVER MANAGER                ║${NC}"
    fi
    echo -e "  ${W}${BOLD}╠══════════════════════════════════════════╣${NC}"
    if systemctl is-active --quiet nginx 2>/dev/null; then
        local ver; ver=$(nginx -v 2>&1 | grep -o 'nginx/[0-9.]*')
        echo -e "  ${W}${BOLD}║${NC}  ${G}●${NC} nginx  ${C}${ver}${NC}"
    else
        echo -e "  ${W}${BOLD}║${NC}  ${R}●${NC} nginx stopped"
    fi
    echo -e "  ${W}${BOLD}╠══════════════════════════════════════════╣${NC}"
    echo
}

# ── Main menu ─────────────────────────────────────────────────────────────────
MAIN_LABELS=(
    "  Website"
    "  SSL"
    "  MySQL"
    "  Hệ thống"
    "  Thoát"
)
MAIN_TOTAL=${#MAIN_LABELS[@]}

draw_main_menu() {
    local sel=$1
    tput clear 2>/dev/null || clear
    _draw_header ""
    for (( i=0; i<MAIN_TOTAL; i++ )); do
        if (( i == sel )); then
            (( i == MAIN_TOTAL-1 )) \
                && echo -e "  ${R}${BOLD} ▶ ${MAIN_LABELS[$i]}${NC}" \
                || echo -e "  ${Y}${BOLD} ▶ ${MAIN_LABELS[$i]}${NC}"
        elif (( i == MAIN_TOTAL-1 )); then
            echo -e "  ${R}   ${MAIN_LABELS[$i]}${NC}"
        else
            echo -e "  ${DIM}   ${MAIN_LABELS[$i]}${NC}"
        fi
    done
    echo
    echo -e "  ${W}${BOLD}╚══════════════════════════════════════════╝${NC}"
    echo -e "  ${DIM}↑ ↓  di chuyển    Enter  chọn    Q  thoát${NC}"
}

# ── Sub-menu draw ─────────────────────────────────────────────────────────────
draw_submenu() {
    local subtitle="$1" sel="$2"; shift 2
    local items=("$@") total=${#items[@]}
    tput clear 2>/dev/null || clear
    _draw_header "$subtitle"
    for (( i=0; i<total; i++ )); do
        if (( i == total-1 )); then
            # Quay lại — luôn màu cyan
            (( i == sel )) \
                && echo -e "  ${C}${BOLD} ▶  ${items[$i]}${NC}" \
                || echo -e "  ${C}    ${items[$i]}${NC}"
        elif (( i == sel )); then
            echo -e "  ${Y}${BOLD} ▶  ${items[$i]}${NC}"
        else
            echo -e "  ${DIM}    ${items[$i]}${NC}"
        fi
    done
    echo
    echo -e "  ${W}${BOLD}╚══════════════════════════════════════════╝${NC}"
    echo -e "  ${DIM}↑ ↓  di chuyển    Enter  chọn    Esc  quay lại${NC}"
}

# ── list_sites ────────────────────────────────────────────────────────────────
list_sites() {
    echo
    divider
    printf "  ${W}${BOLD}  %-36s %-8s %-8s${NC}\n" "DOMAIN" "PORT" "SSL"
    divider
    local count=0
    for f in /etc/nginx/sites-enabled/*; do
        [ -f "$f" ] || [ -L "$f" ] || continue
        local domain; domain=$(basename "$f")
        [ "$domain" = "default" ] && continue
        local port; port=$(grep -m1 'proxy_pass' "$f" 2>/dev/null | grep -oE '[0-9]+' | tail -1 || true)
        if [ -z "$port" ]; then
            local pv; pv=$(grep -m1 'fastcgi_pass' "$f" 2>/dev/null | grep -oE 'php[0-9]+\.[0-9]+' | head -1 || true)
            port="${pv:+PHP ${pv#php}}"; port="${port:-PHP}"
        fi
        local ssl
        [ -f "/etc/letsencrypt/live/$domain/fullchain.pem" ] \
            && ssl="${G}✓ HTTPS${NC}" || ssl="${R}✗ HTTP ${NC}"
        printf "    %-36s %-8s " "$domain" "$port"
        echo -e "$ssl"
        (( count++ )) || true
    done
    divider
    echo -e "${C}    Total: ${count} website(s)${NC}"
    divider
    echo
}

# ═══════════════════════════════════════════════════════════════════════════════
# Actions
# ═══════════════════════════════════════════════════════════════════════════════
do_install_nginx() {
    info "Cài đặt Nginx + Certbot..."
    bash "$SCRIPT_DIR/install-nginx.sh"
    success "Nginx + Certbot đã cài xong."
}

do_setup_firewall() {
    bash "$SCRIPT_DIR/setup-firewall.sh"
}

do_create_php() {
    local domain
    while true; do
        prompt "Domain (vd: example.com):" ; read -r domain
        [ -z "$domain" ] && { info "Hủy."; return; }
        valid_domain "$domain" && break
        error "Domain không hợp lệ: '$domain'"; sleep 1
    done
    bash "$SCRIPT_DIR/create-website.sh" "$domain"
}

do_create_port() {
    local domain port
    while true; do
        prompt "Domain (vd: example.com):" ; read -r domain
        [ -z "$domain" ] && { info "Hủy."; return; }
        valid_domain "$domain" && break
        error "Domain không hợp lệ: '$domain'"; sleep 1
    done
    while true; do
        prompt "Port (vd: 3000):" ; read -r port
        [ -z "$port" ] && { info "Hủy."; return; }
        valid_port "$port" && break
        error "Port không hợp lệ: '$port'"; sleep 1
    done
    bash "$SCRIPT_DIR/create-website-localhost.sh" "$domain" "$port"
}

do_install_ssl() {
    select_domain "Chọn domain để cài SSL:" || { info "Hủy."; return; }
    local domain="$SELECTED_DOMAIN"
    tput clear 2>/dev/null || clear
    bash "$SCRIPT_DIR/install-ssl.sh" "$domain"
}

do_remove_ssl() {
    select_domain "Chọn domain để xóa SSL:" || { info "Hủy."; return; }
    local domain="$SELECTED_DOMAIN"
    tput clear 2>/dev/null || clear
    bash "$SCRIPT_DIR/remove-ssl.sh" "$domain"
}

do_remove() {
    select_domain "Chọn domain để xóa:" || { info "Hủy."; return; }
    local domain="$SELECTED_DOMAIN"
    confirm_yn "Xóa ${domain} và toàn bộ dữ liệu?" || { info "Hủy."; return; }
    tput clear 2>/dev/null || clear
    bash "$SCRIPT_DIR/delete-website.sh" "$domain"
}

do_change_domain() {
    select_domain "Chọn domain cũ:" || { info "Hủy."; return; }
    local old="$SELECTED_DOMAIN"
    local new
    while true; do
        tput clear 2>/dev/null || clear
        echo -e "  ${C}Domain cũ: ${W}${old}${NC}"
        echo -e "  ${DIM}(Để trống + Enter để hủy)${NC}"
        prompt "Domain mới:" ; read -r new
        [ -z "$new" ] && { info "Hủy."; return; }
        valid_domain "$new" || { error "Domain không hợp lệ: '$new'"; sleep 1; continue; }
        if [ -f "/etc/nginx/sites-available/$new" ]; then
            if [ -L "/etc/nginx/sites-enabled/$new" ]; then
                error "'$new' đang active. Dùng Xóa website trước."
                sleep 2; continue
            else
                rm -f "/etc/nginx/sites-available/$new"
            fi
        fi
        break
    done
    bash "$SCRIPT_DIR/change-domain.sh" "$old" "$new" || { error "Đổi domain thất bại."; return; }
}

do_backup() {
    select_domain "Chọn domain để backup:" || { info "Hủy."; return; }
    local domain="$SELECTED_DOMAIN"
    tput clear 2>/dev/null || clear
    bash "$SCRIPT_DIR/backup-website.sh" "$domain"
}

do_restore() {
    tput clear 2>/dev/null || clear
    bash "$SCRIPT_DIR/restore-website.sh"
}

do_check_ssl() {
    tput clear 2>/dev/null || clear
    bash "$SCRIPT_DIR/check-ssl.sh"
}

do_install_mysql() {
    tput clear 2>/dev/null || clear
    bash "$SCRIPT_DIR/install-mysql.sh"
}

do_list_mysql() {
    tput clear 2>/dev/null || clear
    bash "$SCRIPT_DIR/list-mysql.sh"
}

# ═══════════════════════════════════════════════════════════════════════════════
# Sub-menus
# ═══════════════════════════════════════════════════════════════════════════════
menu_website() {
    local labels=(
        "Tạo website PHP"
        "Tạo website theo Port  (reverse proxy)"
        "Danh sách website"
        "Đổi domain"
        "Backup website"
        "Restore website"
        "Xóa website"
        "← Quay lại"
    )
    local total=${#labels[@]} sel=0
    while true; do
        draw_submenu "WEBSITE" "$sel" "${labels[@]}"
        local key; key=$(read_key)
        case "$key" in
            $'\x1b[A') sel=$(( (sel - 1 + total) % total )) ;;
            $'\x1b[B') sel=$(( (sel + 1) % total )) ;;
            $'\x1b')   return ;;
            [qQ])      echo -e "\n  ${G}Bye!${NC}\n"; exit 0 ;;
            ''|$'\n')
                (( sel == total-1 )) && return
                tput clear 2>/dev/null || clear
                case $sel in
                    0) do_create_php    ;;
                    1) do_create_port   ;;
                    2) list_sites       ;;
                    3) do_change_domain ;;
                    4) do_backup        ;;
                    5) do_restore       ;;
                    6) do_remove        ;;
                esac
                pause
                ;;
        esac
    done
}

menu_ssl() {
    local labels=(
        "Cài SSL"
        "Xóa SSL"
        "Kiểm tra SSL"
        "← Quay lại"
    )
    local total=${#labels[@]} sel=0
    while true; do
        draw_submenu "SSL" "$sel" "${labels[@]}"
        local key; key=$(read_key)
        case "$key" in
            $'\x1b[A') sel=$(( (sel - 1 + total) % total )) ;;
            $'\x1b[B') sel=$(( (sel + 1) % total )) ;;
            $'\x1b')   return ;;
            [qQ])      echo -e "\n  ${G}Bye!${NC}\n"; exit 0 ;;
            ''|$'\n')
                (( sel == total-1 )) && return
                tput clear 2>/dev/null || clear
                case $sel in
                    0) do_install_ssl ;;
                    1) do_remove_ssl  ;;
                    2) do_check_ssl   ;;
                esac
                pause
                ;;
        esac
    done
}

menu_mysql() {
    local labels=(
        "Install MySQL"
        "Quản lý DB & User"
        "← Quay lại"
    )
    local total=${#labels[@]} sel=0
    while true; do
        draw_submenu "MYSQL" "$sel" "${labels[@]}"
        local key; key=$(read_key)
        case "$key" in
            $'\x1b[A') sel=$(( (sel - 1 + total) % total )) ;;
            $'\x1b[B') sel=$(( (sel + 1) % total )) ;;
            $'\x1b')   return ;;
            [qQ])      echo -e "\n  ${G}Bye!${NC}\n"; exit 0 ;;
            ''|$'\n')
                (( sel == total-1 )) && return
                tput clear 2>/dev/null || clear
                case $sel in
                    0) do_install_mysql ;;
                    1) do_list_mysql    ;;
                esac
                pause
                ;;
        esac
    done
}

menu_system() {
    local labels=(
        "Install Nginx  (+ Certbot)"
        "Cấu hình Firewall"
        "← Quay lại"
    )
    local total=${#labels[@]} sel=0
    while true; do
        draw_submenu "HỆ THỐNG" "$sel" "${labels[@]}"
        local key; key=$(read_key)
        case "$key" in
            $'\x1b[A') sel=$(( (sel - 1 + total) % total )) ;;
            $'\x1b[B') sel=$(( (sel + 1) % total )) ;;
            $'\x1b')   return ;;
            [qQ])      echo -e "\n  ${G}Bye!${NC}\n"; exit 0 ;;
            ''|$'\n')
                (( sel == total-1 )) && return
                tput clear 2>/dev/null || clear
                case $sel in
                    0) do_install_nginx  ;;
                    1) do_setup_firewall ;;
                esac
                pause
                ;;
        esac
    done
}

# ═══════════════════════════════════════════════════════════════════════════════
# Main loop
# ═══════════════════════════════════════════════════════════════════════════════
selected=0
while true; do
    draw_main_menu "$selected"
    key=$(read_key)
    case "$key" in
        $'\x1b[A') selected=$(( (selected - 1 + MAIN_TOTAL) % MAIN_TOTAL )) ;;
        $'\x1b[B') selected=$(( (selected + 1) % MAIN_TOTAL )) ;;
        [qQ])      echo -e "\n  ${G}Bye!${NC}\n"; exit 0 ;;
        ''|$'\n')
            case $selected in
                0) menu_website ;;
                1) menu_ssl     ;;
                2) menu_mysql   ;;
                3) menu_system  ;;
                4) echo -e "\n  ${G}Bye!${NC}\n"; exit 0 ;;
            esac
            ;;
    esac
done
