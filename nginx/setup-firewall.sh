#!/bin/bash
set -euo pipefail

R='\033[0;31m' G='\033[0;32m' Y='\033[1;33m' C='\033[0;36m' NC='\033[0m'
success() { echo -e "${G}  ✓ $1${NC}"; }
error()   { echo -e "${R}  ✗ $1${NC}" >&2; }
info()    { echo -e "${C}  → $1${NC}"; }

# ── Kiểm tra UFW có sẵn không ────────────────────────────────────────────────
if ! command -v ufw &>/dev/null; then
    info "UFW chưa cài, đang cài..."
    apt install -y ufw
fi

info "Cấu hình firewall UFW..."

# Cho phép SSH trước để không bị khóa khỏi server
ufw allow 22/tcp   comment 'SSH'    &>/dev/null
ufw allow 80/tcp   comment 'HTTP'   &>/dev/null
ufw allow 443/tcp  comment 'HTTPS'  &>/dev/null
ufw allow 3306/tcp comment 'MySQL'  &>/dev/null

# Enable UFW (--force để không hỏi confirm)
if ufw status | grep -q "Status: inactive"; then
    ufw --force enable &>/dev/null
    success "UFW đã bật"
else
    ufw reload &>/dev/null
    success "UFW đã reload"
fi

success "Firewall: SSH(22), HTTP(80), HTTPS(443), MySQL(3306) đã mở"
