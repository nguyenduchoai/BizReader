# BizTransfer v1

BizTransfer dùng BLE làm kênh điều khiển và Wi-Fi làm kênh dữ liệu. Giao thức
chỉ được build cho profile `lilygo`; WebDAV thủ công của CrossPoint vẫn giữ
nguyên cho các profile khác và làm đường dự phòng.

## BLE GATT

| Thành phần | UUID | Thuộc tính |
| --- | --- | --- |
| Service | `7d2f1000-8d4f-4f5b-a8d0-53b495a9b001` | Advertise |
| Command | `7d2f1001-8d4f-4f5b-a8d0-53b495a9b001` | Write |
| Status | `7d2f1002-8d4f-4f5b-a8d0-53b495a9b001` | Read/notify |
| Info | `7d2f1003-8d4f-4f5b-a8d0-53b495a9b001` | Read |

BLE không bonding và không yêu cầu passkey. Firmware không nhận SSID hoặc mật
khẩu qua BLE; lệnh `start` chỉ sử dụng mạng Wi-Fi đã lưu sẵn trên BizReader.

Lệnh JSON:

```json
{"op":"start"}
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
2. Người dùng chạm thiết bị để App lưu BLE ID, không cần ghép đôi.
3. Khi gửi sách, App kết nối BLE và gửi `start`.
4. Firmware dùng Wi-Fi đã lưu rồi trả IP và token phiên qua BLE.
5. App tính SHA-256 và stream file bằng HTTP `PUT`.
6. Firmware xác minh, hoàn tất file và thông báo `complete`.
7. Sau 5 phút không hoạt động, firmware tắt HTTP và Wi-Fi; BLE tồn tại đến khi
   thiết bị ngủ để lần truyền sau có thể bắt đầu mà không vào menu WebDAV.

BLE mở coi khoảng cách gần là ranh giới tin cậy. Một BLE client ở gần có thể
kích hoạt phiên và đọc token ngắn hạn; mật khẩu Wi-Fi không được truyền qua
kênh này.
