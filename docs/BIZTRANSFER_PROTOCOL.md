# BizTransfer v1

BizTransfer dùng BLE làm kênh điều khiển và Wi-Fi làm kênh dữ liệu. Giao thức
chỉ được build cho profile `lilygo`; WebDAV thủ công của CrossPoint vẫn giữ
nguyên cho các profile khác và làm đường dự phòng.

## BLE GATT

| Thành phần | UUID | Thuộc tính |
| --- | --- | --- |
| Service | `7d2f1000-8d4f-4f5b-a8d0-53b495a9b001` | Advertise |
| Command | `7d2f1001-8d4f-4f5b-a8d0-53b495a9b001` | Write, encrypted, authenticated |
| Status | `7d2f1002-8d4f-4f5b-a8d0-53b495a9b001` | Read/notify, encrypted |
| Info | `7d2f1003-8d4f-4f5b-a8d0-53b495a9b001` | Read |

Thiết bị dùng LE Secure Connections, bonding và passkey 6 số hiển thị trên
e-paper. Mật khẩu Wi-Fi chỉ được ghi qua characteristic đã mã hóa.

Lệnh JSON:

```json
{"op":"start"}
{"op":"provision","ssid":"WiFi 2.4G","password":"secret"}
{"op":"stop"}
{"op":"ping"}
```

App có thể thêm `request` vào lệnh; firmware phản hồi lại cùng mã để App không
nhận nhầm trạng thái của lệnh trước. Trạng thái JSON có `state`, `message`,
`request`, `ip`, `port`, `token` và tiến độ `received/total`. Các state v1 là
`idle`, `connecting`, `ready`, `uploading`, `complete`, `error`.

## HTTP upload

Khi Wi-Fi kết nối, firmware mở server trong tối đa 5 phút không hoạt động:

```http
GET /api/bizreader/status
X-BizReader-Token: <token>

PUT /Ebook/<filename>.epub
Content-Length: <bytes>
X-Content-SHA256: <64 hex chars>
X-BizReader-Token: <token>
```

Giới hạn file là 128 MiB. Chỉ nhận `.epub`, `.txt`, `.xtc`, `.xtch`, `.bmp`.
Firmware ghi vào `<filename>.part`, xác minh kích thước và SHA-256, rồi mới đổi
tên sang file đích. File dở bị xóa khi lỗi, hủy hoặc server dừng.

## Trình tự

1. App quét service BLE và kết nối.
2. Android ghép đôi bằng passkey trên màn hình BizReader.
3. App gửi `start`; nếu chưa có mạng đã lưu thì gửi `provision`.
4. Firmware trả IP và token phiên qua notification đã mã hóa.
5. App tính SHA-256 và stream file bằng HTTP `PUT`.
6. Firmware xác minh, hoàn tất file và thông báo `complete`.
7. Sau 5 phút không hoạt động, firmware tắt HTTP và Wi-Fi; BLE tồn tại đến khi
   thiết bị ngủ để lần truyền sau có thể bắt đầu mà không vào menu WebDAV.
