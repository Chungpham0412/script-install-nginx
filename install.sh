#!/bin/bash
set -euo pipefail

GITHUB_USER="Chungpham0412"
GITHUB_REPO="script-install-nginx"
INSTALL_DIR="/opt/server-manager"

R='\033[0;31m' G='\033[0;32m' Y='\033[1;33m' C='\033[0;36m' NC='\033[0m'

[ "$EUID" -ne 0 ] && { echo -e "${R}Chạy với quyền root: sudo bash install.sh${NC}"; exit 1; }

echo -e "${C}→ Cài đặt Server Manager...${NC}"

# Cài git nếu chưa có
if ! command -v git &>/dev/null; then
    echo -e "${Y}→ Cài git...${NC}"
    apt-get update -qq && apt-get install -y -qq git
fi

# Nhập token
printf "${Y}  Nhập GitHub Token (Enter để bỏ qua nếu repo public):${NC} "
read -rs GH_TOKEN </dev/tty
echo

# Xác định URL clone
if [ -n "$GH_TOKEN" ]; then
    CLONE_URL="https://${GH_TOKEN}@github.com/${GITHUB_USER}/${GITHUB_REPO}.git"
else
    CLONE_URL="https://github.com/${GITHUB_USER}/${GITHUB_REPO}.git"
fi

# Clone hoặc update repo
if [ -d "$INSTALL_DIR/.git" ]; then
    echo -e "${Y}→ Cập nhật repo...${NC}"
    git -C "$INSTALL_DIR" remote set-url origin "$CLONE_URL"
    git -C "$INSTALL_DIR" pull --ff-only
else
    echo -e "${Y}→ Clone repo...${NC}"
    git clone "$CLONE_URL" "$INSTALL_DIR"
fi

# Cấp quyền thực thi
chmod +x "$INSTALL_DIR"/nginx/*.sh

# Tạo lệnh toàn cục
ln -sf "$INSTALL_DIR/nginx/nginx-full-script.sh" /usr/local/bin/server-manager

echo -e "${G}✓ Xong! Chạy lệnh: sudo server-manager${NC}"
