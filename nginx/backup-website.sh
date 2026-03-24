#!/bin/bash
set -euo pipefail

DOMAIN="${1:?Usage: backup-website.sh <domain>}"
DOC_ROOT="/var/www/public_html/$DOMAIN"
CONF="/etc/nginx/sites-available/$DOMAIN"
BACKUP_DIR="/var/backups/nginx-websites"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/${DOMAIN}_${TIMESTAMP}.tar.gz"
TMPDIR=$(mktemp -d)

R='\033[0;31m' G='\033[0;32m' Y='\033[1;33m' C='\033[0;36m' NC='\033[0m'
success() { echo -e "${G}  ✓ $1${NC}"; }
error()   { echo -e "${R}  ✗ $1${NC}" >&2; }
info()    { echo -e "${C}  → $1${NC}"; }

trap 'rm -rf "$TMPDIR"' EXIT

# ── Kiểm tra domain tồn tại ───────────────────────────────────────────────────
if [ ! -f "$CONF" ]; then
    error "Không tìm thấy config: $CONF"
    exit 1
fi

mkdir -p "$BACKUP_DIR"
mkdir -p "$TMPDIR/$DOMAIN"

info "Đang backup $DOMAIN..."

# ── 1. Nginx config ────────────────────────────────────────────────────────────
cp "$CONF" "$TMPDIR/$DOMAIN/nginx.conf"
success "Nginx config"

# ── 2. DocumentRoot ────────────────────────────────────────────────────────────
if [ -d "$DOC_ROOT" ]; then
    cp -a "$DOC_ROOT" "$TMPDIR/$DOMAIN/public_html"
    success "DocumentRoot ($(du -sh "$DOC_ROOT" 2>/dev/null | cut -f1))"
else
    info "DocumentRoot không tồn tại, bỏ qua."
fi

# ── 3. SSL cert (nếu có) ───────────────────────────────────────────────────────
CERT_DIR="/etc/letsencrypt/live/$DOMAIN"
if [ -d "$CERT_DIR" ]; then
    mkdir -p "$TMPDIR/$DOMAIN/ssl"
    cp -L "$CERT_DIR/fullchain.pem" "$TMPDIR/$DOMAIN/ssl/" 2>/dev/null || true
    cp -L "$CERT_DIR/privkey.pem"  "$TMPDIR/$DOMAIN/ssl/" 2>/dev/null || true
    success "SSL cert"
fi

# ── 4. Nén tất cả ─────────────────────────────────────────────────────────────
tar -czf "$BACKUP_FILE" -C "$TMPDIR" "$DOMAIN"
success "Backup lưu tại: ${Y}$BACKUP_FILE${NC}${G} ($(du -sh "$BACKUP_FILE" | cut -f1))"
