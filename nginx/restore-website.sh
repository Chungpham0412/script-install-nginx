#!/bin/bash
set -euo pipefail

BACKUP_DIR="/var/backups/nginx-websites"
DOC_BASE="/var/www/public_html"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
R='\033[0;31m' G='\033[0;32m' Y='\033[1;33m'
C='\033[0;36m' W='\033[1;37m' NC='\033[0m' BOLD='\033[1m'

success() { echo -e "${G}  ✓ $1${NC}"; }
error()   { echo -e "${R}  ✗ $1${NC}" >&2; }
info()    { echo -e "${C}  → $1${NC}"; }
divider() { echo -e "${C}  $(printf '─%.0s' {1..50})${NC}"; }

# ── Arrow key picker ───────────────────────────────────────────────────────────
_pick_backup() {
    local result_var=$1; shift
    local items=("$@")
    local n=${#items[@]}
    local cur=0

    tput civis 2>/dev/null || true

    _redraw() {
        local i
        for i in "${!items[@]}"; do
            if [ "$i" -eq "$cur" ]; then
                printf "  \033[1;32m>\033[0m %s\n" "${items[$i]}"
            else
                printf "    %s\n" "${items[$i]}"
            fi
        done
    }

    _redraw
    while true; do
        local key esc=""
        IFS= read -rsn1 key 2>/dev/null || true
        if [[ "$key" == $'\x1b' ]]; then
            IFS= read -rsn2 -t 0.1 esc 2>/dev/null || true
            key+="$esc"
        fi
        case "$key" in
            $'\x1b[A') [ "$cur" -gt 0 ] && cur=$(( cur - 1 )) ;;
            $'\x1b[B') [ "$cur" -lt $(( n - 1 )) ] && cur=$(( cur + 1 )) ;;
            ''|$'\n') break ;;
        esac
        tput cuu "$n" 2>/dev/null || true
        _redraw
    done

    tput cnorm 2>/dev/null || true
    printf -v "$result_var" '%s' "${items[$cur]}"
}

# ── Kiểm tra backup dir ────────────────────────────────────────────────────────
if [ ! -d "$BACKUP_DIR" ] || [ -z "$(ls "$BACKUP_DIR"/*.tar.gz 2>/dev/null)" ]; then
    error "Không có backup nào trong $BACKUP_DIR"
    exit 1
fi

# ── Liệt kê backup (mới nhất trước) ───────────────────────────────────────────
echo
divider
echo -e "  ${W}${BOLD}  CHỌN BACKUP ĐỂ RESTORE${NC}"
divider
echo

mapfile -t backup_files < <(ls -t "$BACKUP_DIR"/*.tar.gz 2>/dev/null)

# Tạo display labels: "domain  2026-03-24 10:13:25  (4.0K)"
display_items=()
for f in "${backup_files[@]}"; do
    fname=$(basename "$f")
    # Extract domain: bỏ _YYYYMMDD_HHMMSS.tar.gz ở cuối
    orig_domain=$(echo "$fname" | sed 's/_[0-9]\{8\}_[0-9]\{6\}\.tar\.gz$//')
    # Extract timestamp: YYYYMMDD_HHMMSS → YYYY-MM-DD HH:MM:SS
    ts_raw=$(echo "$fname" | grep -oE '[0-9]{8}_[0-9]{6}')
    ts_fmt=$(echo "$ts_raw" | sed 's/\([0-9]\{4\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)_\([0-9]\{2\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)/\1-\2-\3 \4:\5:\6/')
    size=$(du -sh "$f" 2>/dev/null | cut -f1)
    display_items+=("$(printf '%-38s  %s  (%s)' "$orig_domain" "$ts_fmt" "$size")")
done

selected_label=""
_pick_backup selected_label "${display_items[@]}"

# Map label về file path
selected_idx=0
for i in "${!display_items[@]}"; do
    [ "${display_items[$i]}" = "$selected_label" ] && selected_idx=$i && break
done
BACKUP_FILE="${backup_files[$selected_idx]}"
fname=$(basename "$BACKUP_FILE")
ORIG_DOMAIN=$(echo "$fname" | sed 's/_[0-9]\{8\}_[0-9]\{6\}\.tar\.gz$//')

# ── Nhập target domain ─────────────────────────────────────────────────────────
echo
echo -e "${Y}  Domain muốn restore về${NC} ${C}(Enter = ${ORIG_DOMAIN})${NC}: "
read -r TARGET_DOMAIN
TARGET_DOMAIN="${TARGET_DOMAIN:-$ORIG_DOMAIN}"

# ── Tiến hành restore ──────────────────────────────────────────────────────────
CONF="/etc/nginx/sites-available/$TARGET_DOMAIN"
DOC_ROOT="$DOC_BASE/$TARGET_DOMAIN"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

echo
divider
info "Đang restore ${W}$BACKUP_FILE${NC}"
info "→ Domain: ${W}$TARGET_DOMAIN${NC}"
divider

# Giải nén
tar -xzf "$BACKUP_FILE" -C "$TMPDIR"
EXTRACT_DIR="$TMPDIR/$ORIG_DOMAIN"

# 1. DocumentRoot
if [ -d "$EXTRACT_DIR/public_html" ]; then
    if [ -d "$DOC_ROOT" ]; then
        info "DocRoot đã tồn tại, overwrite..."
        rm -rf "$DOC_ROOT"
    fi
    mkdir -p "$(dirname "$DOC_ROOT")"
    cp -a "$EXTRACT_DIR/public_html" "$DOC_ROOT"
    chown -R www-data:www-data "$DOC_ROOT"
    success "DocumentRoot → $DOC_ROOT"
fi

# 2. Nginx config
SKIP_RELOAD=false
if [ -f "$EXTRACT_DIR/nginx.conf" ]; then
    if [ "$TARGET_DOMAIN" = "$ORIG_DOMAIN" ]; then
        # Cùng domain: dùng config gốc (cert đã được restore ở bước 3)
        cp "$EXTRACT_DIR/nginx.conf" "$CONF"
        ln -sf "$CONF" "/etc/nginx/sites-enabled/$TARGET_DOMAIN"
        success "Nginx config → $CONF"
    else
        # Domain mới: gọi create script để gen config HTTP-only sạch
        port=$(grep -m1 'proxy_pass' "$EXTRACT_DIR/nginx.conf" 2>/dev/null | grep -oE '[0-9]+' | tail -1 || true)
        php_ver=$(grep -m1 'fastcgi_pass' "$EXTRACT_DIR/nginx.conf" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1 || true)
        if [ -n "$port" ]; then
            info "Tạo config reverse proxy (port $port)..."
            bash "$SCRIPT_DIR/create-website-localhost.sh" "$TARGET_DOMAIN" "$port"
        else
            info "Tạo config PHP ${php_ver:-(static)}..."
            bash "$SCRIPT_DIR/create-website.sh" "$TARGET_DOMAIN" "$php_ver"
        fi
        SKIP_RELOAD=true  # create scripts đã reload nginx
    fi
fi

# 3. SSL cert (chỉ restore nếu cùng domain)
if [ "$TARGET_DOMAIN" = "$ORIG_DOMAIN" ] && [ -d "$EXTRACT_DIR/ssl" ]; then
    CERT_DIR="/etc/letsencrypt/live/$TARGET_DOMAIN"
    mkdir -p "$CERT_DIR"
    cp "$EXTRACT_DIR/ssl/fullchain.pem" "$CERT_DIR/" 2>/dev/null || true
    cp "$EXTRACT_DIR/ssl/privkey.pem"   "$CERT_DIR/" 2>/dev/null || true
    success "SSL cert → $CERT_DIR"
elif [ "$TARGET_DOMAIN" != "$ORIG_DOMAIN" ] && [ -d "$EXTRACT_DIR/ssl" ]; then
    info "SSL cert bỏ qua (domain khác — chạy Cài SSL sau nếu cần)"
fi

# 4. Reload nginx (chỉ khi không dùng create script)
echo
if [ "$SKIP_RELOAD" = false ]; then
    if nginx -t; then
        systemctl restart nginx
        success "Nginx reload thành công"
    else
        error "Nginx config lỗi — kiểm tra: nginx -t"
        exit 1
    fi
fi

echo
divider
success "Restore hoàn tất: ${W}$TARGET_DOMAIN${NC}"
divider
echo
