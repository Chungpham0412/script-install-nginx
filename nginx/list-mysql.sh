#!/bin/bash
set -euo pipefail

R='\033[0;31m' G='\033[0;32m' Y='\033[1;33m'
C='\033[0;36m' W='\033[1;37m' NC='\033[0m' BOLD='\033[1m'

success() { echo -e "${G}  ✓ $1${NC}"; }
error()   { echo -e "${R}  ✗ $1${NC}" >&2; }
info()    { echo -e "${C}  → $1${NC}"; }
divider() { echo -e "${C}  $(printf '─%.0s' {1..60})${NC}"; }

# ── Kết nối MySQL ─────────────────────────────────────────────────────────────
MYSQL_PASS=""
MYSQL_CMD=""

_try_connect() {
    mysql "$@" -e "SELECT 1" &>/dev/null
}

if _try_connect -u root --skip-password 2>/dev/null; then
    MYSQL_CMD="mysql -u root --skip-password"
elif _try_connect -u root -p"" 2>/dev/null; then
    MYSQL_CMD="mysql -u root -p"
else
    printf "${Y}  Mật khẩu root MySQL:${NC} "
    read -rs MYSQL_PASS; echo
    if ! mysql -u root -p"${MYSQL_PASS}" -e "SELECT 1" &>/dev/null; then
        error "Sai mật khẩu hoặc MySQL chưa cài."
        exit 1
    fi
    MYSQL_CMD="mysql -u root -p${MYSQL_PASS}"
fi

# Wrapper để chạy query
_sql() { $MYSQL_CMD --batch --skip-column-names -e "$1" 2>/dev/null; }

# ── Kiểm tra MySQL có chạy không ──────────────────────────────────────────────
if ! command -v mysql &>/dev/null; then
    error "MySQL chưa được cài."
    exit 1
fi

# ── Hiển thị ──────────────────────────────────────────────────────────────────
echo
echo -e "  ${W}${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "  ${W}${BOLD}║              MYSQL — DATABASE & USER MANAGER            ║${NC}"
echo -e "  ${W}${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"

# ══ 1. DANH SÁCH DATABASE ══════════════════════════════════════════════════════
echo
echo -e "  ${W}${BOLD}▌ DATABASES${NC}"
divider
printf "  ${W}${BOLD}%-30s %10s %8s  %s${NC}\n" "DATABASE" "SIZE" "TABLES" "CHARSET"
divider

SYSTEM_DBS="'information_schema','performance_schema','mysql','sys'"

_sql "
SELECT
    s.SCHEMA_NAME,
    COALESCE(CONCAT(ROUND(SUM(t.data_length + t.index_length) / 1024 / 1024, 2), ' MB'), '0 MB') AS size,
    COUNT(t.TABLE_NAME) AS table_count,
    s.DEFAULT_CHARACTER_SET_NAME
FROM information_schema.SCHEMATA s
LEFT JOIN information_schema.TABLES t ON t.TABLE_SCHEMA = s.SCHEMA_NAME
WHERE s.SCHEMA_NAME NOT IN ($SYSTEM_DBS)
GROUP BY s.SCHEMA_NAME, s.DEFAULT_CHARACTER_SET_NAME
ORDER BY s.SCHEMA_NAME;
" | while IFS=$'\t' read -r db size tables charset; do
    printf "  %-30s %10s %8s  %s\n" "$db" "$size" "$tables" "$charset"
done

DB_COUNT=$(_sql "SELECT COUNT(*) FROM information_schema.SCHEMATA WHERE SCHEMA_NAME NOT IN ($SYSTEM_DBS);")
divider
echo -e "  ${C}Tổng: ${DB_COUNT} database(s)${NC}"

# ══ 2. DANH SÁCH USER ══════════════════════════════════════════════════════════
echo
echo -e "  ${W}${BOLD}▌ USERS${NC}"
divider
printf "  ${W}${BOLD}%-25s %-16s  %s${NC}\n" "USER" "HOST" "CÓ QUYỀN TRÊN"
divider

_sql "SELECT DISTINCT User, Host FROM mysql.user WHERE User != '' ORDER BY User, Host;" \
| while IFS=$'\t' read -r user host; do
    # Lấy danh sách DB mà user này có quyền
    dbs=$(_sql "
        SELECT GROUP_CONCAT(DISTINCT Db ORDER BY Db SEPARATOR ', ')
        FROM mysql.db
        WHERE User = '$user' AND Host = '$host' AND Db NOT IN ($SYSTEM_DBS);
    ")

    # Nếu user có ALL PRIVILEGES (global), thêm thông tin
    global=$(_sql "
        SELECT Super_priv FROM mysql.user
        WHERE User = '$user' AND Host = '$host';
    ")

    if [ "$global" = "Y" ]; then
        dbs="${dbs:+$dbs, }${Y}[ALL DATABASES]${NC}"
    fi

    dbs="${dbs:-${R}(không có quyền DB nào)${NC}}"

    printf "  %-25s %-16s  " "$user" "$host"
    echo -e "$dbs"
done

USER_COUNT=$(_sql "SELECT COUNT(DISTINCT User) FROM mysql.user WHERE User != '';")
divider
echo -e "  ${C}Tổng: ${USER_COUNT} user(s)${NC}"

# ══ 3. CHI TIẾT QUYỀN THEO DB ═════════════════════════════════════════════════
echo
echo -e "  ${W}${BOLD}▌ QUYỀN CHI TIẾT THEO DATABASE${NC}"
divider
printf "  ${W}${BOLD}%-25s %-20s  %s${NC}\n" "DATABASE" "USER@HOST" "PRIVILEGES"
divider

_sql "
SELECT
    Db,
    CONCAT(User, '@', Host) AS user_host,
    CONCAT_WS(', ',
        IF(Select_priv='Y','SELECT',NULL),
        IF(Insert_priv='Y','INSERT',NULL),
        IF(Update_priv='Y','UPDATE',NULL),
        IF(Delete_priv='Y','DELETE',NULL),
        IF(Create_priv='Y','CREATE',NULL),
        IF(Drop_priv='Y','DROP',NULL),
        IF(Index_priv='Y','INDEX',NULL),
        IF(Alter_priv='Y','ALTER',NULL)
    ) AS privs
FROM mysql.db
WHERE Db NOT IN ($SYSTEM_DBS) AND User != ''
ORDER BY Db, User;
" | while IFS=$'\t' read -r db user_host privs; do
    printf "  %-25s %-20s  %s\n" "$db" "$user_host" "$privs"
done

divider
echo
