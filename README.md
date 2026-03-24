# Server Manager

Công cụ quản lý server Linux với giao diện menu tương tác (TUI) trên terminal. Hỗ trợ quản lý Nginx, SSL và MySQL chỉ bằng vài phím bấm.

## Tính năng

- **Website** — Tạo website PHP, reverse proxy theo port, đổi domain, backup/restore, xóa
- **SSL** — Cài/xóa chứng chỉ Let's Encrypt, kiểm tra trạng thái SSL
- **MySQL** — Cài đặt MySQL, quản lý database & user
- **Hệ thống** — Cài Nginx + Certbot, cấu hình Firewall (UFW)

## Yêu cầu

- Ubuntu / Debian
- Quyền root (`sudo`)
- Kết nối internet

## Cài đặt

```bash
curl -fsSL https://raw.githubusercontent.com/Chungpham0412/script-install-nginx/master/install.sh | sudo bash
```

Hoặc tải về rồi chạy:

```bash
sudo bash install.sh
```

> Script sẽ clone repo về `/opt/server-manager` và tạo lệnh toàn cục `server-manager`.

Trong quá trình cài đặt, script sẽ hỏi **GitHub Token**. Nếu repo là **public** thì nhấn Enter bỏ qua. Nếu repo là **private**, cần cung cấp token:

1. Vào [https://github.com/settings/tokens/new](https://github.com/settings/tokens/new)
2. Đặt tên token (vd: `server-manager`)
3. Chọn thời hạn (Expiration)
4. Tích vào quyền **`repo`** (Full control of private repositories)
5. Nhấn **Generate token** và copy token
6. Dán token vào lúc script hỏi

## Sử dụng

```bash
sudo server-manager
```

Dùng phím **↑ ↓** để di chuyển, **Enter** để chọn, **Esc** hoặc **Q** để thoát/quay lại.

## Cấu trúc

```
.
├── install.sh                  # Script cài đặt một lệnh
└── nginx/
    ├── nginx-full-script.sh    # Menu chính (lệnh server-manager)
    ├── install-nginx.sh        # Cài Nginx + Certbot
    ├── setup-firewall.sh       # Cấu hình UFW
    ├── create-website.sh       # Tạo website PHP
    ├── create-website-localhost.sh  # Tạo reverse proxy theo port
    ├── list-website.sh         # Danh sách website
    ├── change-domain.sh        # Đổi domain
    ├── delete-website.sh       # Xóa website
    ├── backup-website.sh       # Backup website
    ├── restore-website.sh      # Restore website
    ├── install-ssl.sh          # Cài SSL (Let's Encrypt)
    ├── remove-ssl.sh           # Xóa SSL
    ├── check-ssl.sh            # Kiểm tra SSL
    ├── install-mysql.sh        # Cài MySQL
    └── list-mysql.sh           # Quản lý DB & User
```

## Cập nhật

Chạy lại lệnh cài đặt — script sẽ tự `git pull` về phiên bản mới nhất.

```bash
sudo bash install.sh
```
