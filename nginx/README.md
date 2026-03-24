# nginx/

Tập hợp các script quản lý Nginx, SSL và MySQL trên Ubuntu/Debian. Có thể chạy từng script trực tiếp hoặc qua menu TUI của `nginx-full-script.sh`.

## Yêu cầu

- Ubuntu / Debian
- Quyền root (`sudo`)

---

## Script chính

### `nginx-full-script.sh`

Menu TUI tương tác — đây là entrypoint của toàn bộ bộ công cụ (được link thành lệnh `server-manager`).

```bash
sudo bash nginx-full-script.sh
```

Điều hướng bằng **↑ ↓**, chọn bằng **Enter**, thoát/quay lại bằng **Esc** hoặc **Q**.

---

## Hệ thống

### `install-nginx.sh`

Cài Nginx (từ PPA `ondrej/nginx`), Certbot, tạo self-signed SSL cho default server và cấu hình firewall.

```bash
sudo bash install-nginx.sh
```

Sau khi chạy:
- Nginx đang chạy và tự khởi động cùng hệ thống
- Default server phục vụ cả HTTP (80) và HTTPS (443, self-signed)
- Default page được deploy vào `/var/www/html/index.html`

### `setup-firewall.sh`

Bật UFW và mở các port cần thiết.

```bash
sudo bash setup-firewall.sh
```

| Port | Dịch vụ |
|------|---------|
| 22   | SSH     |
| 80   | HTTP    |
| 443  | HTTPS   |
| 3306 | MySQL   |

---

## Website

### `create-website.sh`

Tạo website PHP với PHP-FPM.

```bash
sudo bash create-website.sh <domain> [php_version]
```

- Hỗ trợ PHP: `7.4`, `8.1`, `8.2`, `8.3`, `8.4`
- Nếu bỏ qua `php_version`, hiện menu chọn tương tác
- PHP chưa cài sẽ được tự động cài từ PPA `ondrej/php`
- DocumentRoot: `/var/www/public_html/<domain>`
- Log: `/var/log/nginx/<domain>-access.log` và `<domain>-error.log`

### `create-website-localhost.sh`

Tạo website dạng reverse proxy, chuyển tiếp request đến ứng dụng đang chạy trên localhost.

```bash
sudo bash create-website-localhost.sh <domain> <port>
```

- Hỗ trợ WebSocket (`Upgrade`, `Connection`)
- Fallback về trang tĩnh (`/var/www/public_html/<domain>/index.html`) khi upstream lỗi 502/503/504
- DocumentRoot: `/var/www/public_html/<domain>`

### `list-website.sh`

Liệt kê tất cả website đang active, kèm port/PHP version và trạng thái SSL.

```bash
sudo bash list-website.sh
```

### `change-domain.sh`

Đổi tên domain cho một website đang chạy.

```bash
sudo bash change-domain.sh <domain_cũ> <domain_mới>
```

### `delete-website.sh`

Xóa website (nginx config, symlink, DocumentRoot).

```bash
sudo bash delete-website.sh <domain>
```

### `backup-website.sh`

Backup nginx config, DocumentRoot và SSL cert (nếu có) thành file `.tar.gz`.

```bash
sudo bash backup-website.sh <domain>
```

File backup lưu tại: `/var/backups/nginx-websites/<domain>_YYYYMMDD_HHMMSS.tar.gz`

Nội dung backup:
```
<domain>/
├── nginx.conf      # /etc/nginx/sites-available/<domain>
├── public_html/    # /var/www/public_html/<domain>
└── ssl/            # fullchain.pem + privkey.pem (nếu có)
```

### `restore-website.sh`

Restore website từ file backup.

```bash
sudo bash restore-website.sh
```

---

## SSL

### `install-ssl.sh`

Lấy chứng chỉ Let's Encrypt (miễn phí) và cập nhật nginx config với HTTPS block.

```bash
sudo bash install-ssl.sh <domain>
```

- Yêu cầu: domain đã trỏ DNS về IP server, website đã tạo trước
- Thử lấy cert cho cả `domain` và `www.domain`, tự động fallback nếu `www` không trỏ đúng
- Tự động tái tạo nginx config với HTTPS (443) sau khi lấy cert thành công

### `remove-ssl.sh`

Xóa chứng chỉ SSL và chuyển website về HTTP.

```bash
sudo bash remove-ssl.sh <domain>
```

### `check-ssl.sh`

Kiểm tra trạng thái và ngày hết hạn của các chứng chỉ SSL.

```bash
sudo bash check-ssl.sh
```

---

## MySQL

### `install-mysql.sh`

Cài đặt MySQL với menu chọn version tương tác.

```bash
sudo bash install-mysql.sh
```

Các version hỗ trợ:
- `5.7` — Legacy (Ubuntu 20.04)
- `8.0` — Stable, phổ biến nhất
- `8.4` — LTS mới nhất

Sau khi cài:
- Đặt root password
- Xóa anonymous user và test database
- Tùy chọn tạo thêm database + user mới

### `list-mysql.sh`

Quản lý database và user: liệt kê, tạo, xóa.

```bash
sudo bash list-mysql.sh
```

---

## Đường dẫn quan trọng

| Mục đích | Đường dẫn |
|---------|-----------|
| DocumentRoot | `/var/www/public_html/<domain>` |
| Nginx config | `/etc/nginx/sites-available/<domain>` |
| Nginx symlink | `/etc/nginx/sites-enabled/<domain>` |
| SSL cert | `/etc/letsencrypt/live/<domain>/` |
| Nginx log | `/var/log/nginx/<domain>-access.log` |
| Backup | `/var/backups/nginx-websites/` |
