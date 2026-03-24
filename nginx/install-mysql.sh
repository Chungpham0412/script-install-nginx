#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
R='\033[0;31m' G='\033[0;32m' Y='\033[1;33m'
C='\033[0;36m' W='\033[1;37m' NC='\033[0m' BOLD='\033[1m'

success() { echo -e "${G}  ✓ $1${NC}"; }
error()   { echo -e "${R}  ✗ $1${NC}" >&2; }
info()    { echo -e "${C}  → $1${NC}"; }
divider() { echo -e "${C}  $(printf '─%.0s' {1..50})${NC}"; }
prompt()  { printf "${Y}  %s${NC} " "$1"; }

# ── Arrow key menu ─────────────────────────────────────────────────────────────
_arrow_menu() {
    local result_var=$1; shift
    local items=("$@")
    local n=${#items[@]}
    local cur=0 i

    tput civis 2>/dev/null || true
    for i in "${!items[@]}"; do
        [ "$i" -eq "$cur" ] && printf "  \033[1;32m>\033[0m %s\n" "${items[$i]}" \
                            || printf "    %s\n" "${items[$i]}"
    done

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
        for i in "${!items[@]}"; do
            [ "$i" -eq "$cur" ] && printf "  \033[1;32m>\033[0m %s\n" "${items[$i]}" \
                                || printf "    %s\n" "${items[$i]}"
        done
    done

    tput cnorm 2>/dev/null || true
    printf '\n'
    printf -v "$result_var" '%d' "$cur"
}

# ── Kiểm tra root ──────────────────────────────────────────────────────────────
[ "$EUID" -ne 0 ] && { error "Cần chạy với quyền root: sudo $0"; exit 1; }

# ── Kiểm tra MySQL đã cài chưa ────────────────────────────────────────────────
if command -v mysql &>/dev/null; then
    VER=$(mysql --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    echo
    error "MySQL đã được cài (v${VER}). Gỡ cài trước nếu muốn đổi version."
    echo -e "  ${Y}Gỡ cài:${NC} apt purge -y mysql-server mysql-client mysql-common && apt autoremove -y"
    exit 1
fi

# ── Chọn version ──────────────────────────────────────────────────────────────
echo
divider
echo -e "  ${W}${BOLD}  CHỌN PHIÊN BẢN MYSQL${NC}"
divider
echo

UBUNTU_VER=$(lsb_release -rs 2>/dev/null || echo "22.04")
choices=("5.7  (Legacy — chỉ hỗ trợ Ubuntu 20.04)"
         "8.0  (Stable — phổ biến nhất)"
         "8.4  (LTS mới nhất)")
idx=1
_arrow_menu idx "${choices[@]}"

case $idx in
    0) MYSQL_VERSION="5.7" ;;
    1) MYSQL_VERSION="8.0" ;;
    2) MYSQL_VERSION="8.4" ;;
esac

# ── Nhập root password ────────────────────────────────────────────────────────
echo
prompt "Nhập mật khẩu root MySQL:"
read -rs ROOT_PASS; echo
prompt "Xác nhận mật khẩu:"
read -rs ROOT_PASS2; echo

if [ "$ROOT_PASS" != "$ROOT_PASS2" ]; then
    error "Mật khẩu không khớp."
    exit 1
fi
if [ ${#ROOT_PASS} -lt 6 ]; then
    error "Mật khẩu tối thiểu 6 ký tự."
    exit 1
fi

# ── Cài đặt ───────────────────────────────────────────────────────────────────
echo
divider
info "Cài MySQL $MYSQL_VERSION..."
divider

_add_mysql_repo() {
    local version="$1"
    info "Thêm MySQL APT repository..."
    apt install -y gnupg lsb-release curl 2>/dev/null || true

    local key_url="https://repo.mysql.com/RPM-GPG-KEY-mysql-2023"
    curl -fsSL "$key_url" | gpg --dearmor -o /etc/apt/trusted.gpg.d/mysql.gpg

    local codename; codename=$(lsb_release -cs)
    echo "deb http://repo.mysql.com/apt/ubuntu/ $codename mysql-${version}" \
        > /etc/apt/sources.list.d/mysql.list

    apt update -qq
    success "MySQL APT repo đã thêm (mysql-${version})"
}

case "$MYSQL_VERSION" in
    5.7)
        # Ubuntu 20.04: có trong mặc định. 22.04+: cần repo
        candidate=$(apt-cache policy mysql-server-5.7 2>/dev/null | awk '/Candidate:/{print $2}')
        if [ -z "$candidate" ] || [ "$candidate" = "(none)" ]; then
            _add_mysql_repo "5.7"
        fi
        DEBIAN_FRONTEND=noninteractive apt install -y mysql-server-5.7
        ;;
    8.0)
        candidate=$(apt-cache policy mysql-server 2>/dev/null | awk '/Candidate:/{print $2}')
        # Nếu repo mặc định có 8.0 thì dùng thẳng, ngược lại thêm repo
        if echo "$candidate" | grep -q "^8\.0"; then
            DEBIAN_FRONTEND=noninteractive apt install -y mysql-server
        else
            _add_mysql_repo "8.0"
            DEBIAN_FRONTEND=noninteractive apt install -y mysql-server
        fi
        ;;
    8.4)
        _add_mysql_repo "8.4"
        DEBIAN_FRONTEND=noninteractive apt install -y mysql-server
        ;;
esac

success "MySQL $MYSQL_VERSION đã cài"

# ── Khởi động MySQL ────────────────────────────────────────────────────────────
systemctl enable --now mysql 2>/dev/null || systemctl enable --now mysqld 2>/dev/null || true
sleep 1

# ── Đặt root password & bảo mật ───────────────────────────────────────────────
info "Cấu hình bảo mật..."

mysql -u root 2>/dev/null <<SQL || mysql -u root --skip-password 2>/dev/null <<SQL2
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${ROOT_PASS}';
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost','127.0.0.1','::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test_%';
FLUSH PRIVILEGES;
SQL

ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${ROOT_PASS}';
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost','127.0.0.1','::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test_%';
FLUSH PRIVILEGES;
SQL2

success "Root password đặt xong, anonymous users đã xóa, test DB đã xóa"

# ── Tạo database mới (tùy chọn) ───────────────────────────────────────────────
echo
prompt "Tạo database mới? (y/N):"
read -r CREATE_DB
if [[ "$CREATE_DB" =~ ^[Yy]$ ]]; then
    prompt "Tên database:"
    read -r DB_NAME
    prompt "Tên user:"
    read -r DB_USER
    prompt "Mật khẩu user:"
    read -rs DB_PASS; echo

    mysql -u root -p"${ROOT_PASS}" <<SQL
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
SQL
    echo
    success "Database: ${W}${DB_NAME}${NC}"
    success "User:     ${W}${DB_USER}@localhost${NC}"
fi

# ── Tóm tắt ───────────────────────────────────────────────────────────────────
echo
divider
echo -e "  ${W}${BOLD}  MYSQL $MYSQL_VERSION ĐÃ SẴN SÀNG${NC}"
divider
echo -e "  ${C}Version:  ${NC}$(mysql --version 2>/dev/null | grep -oE 'Distrib [0-9.]+' | head -1)"
echo -e "  ${C}Kết nối:  ${NC}mysql -u root -p"
echo -e "  ${C}Service:  ${NC}systemctl status mysql"
divider
echo
