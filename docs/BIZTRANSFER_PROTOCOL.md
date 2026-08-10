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

## Đồng bộ vị trí đọc

Hai endpoint sau dùng cùng token ngắn hạn của phiên BizTransfer:

```http
GET /api/bizreader/progress?filename=<filename.epub>
X-BizReader-Token: <token>

POST /api/bizreader/progress
Content-Type: application/json
X-BizReader-Token: <token>

{"filename":"book.epub","percentage":0.42}
```

Firmware lưu tiến độ theo tên tệp trong `/.crosspoint/bizsync/`. Vị trí App gửi
được đánh dấu chờ và áp dụng khi EPUB tương ứng được mở lần sau. Khi đọc và lưu
trang trên BizReader, bản ghi được cập nhật lại để App có thể kéo về. Hai trình
đọc có cách phân trang khác nhau nên phần trăm toàn sách là khóa chuyển đổi; App
luôn hỏi người dùng chọn vị trí điện thoại hoặc BizReader khi hai bên khác nhau.

## Đồng bộ tiện ích một chiều

App gửi một bản JSON giới hạn kích thước bằng `POST /api/bizreader/content`, dùng
cùng `X-BizReader-Token` của phiên BizTransfer. Firmware kiểm tra cấu trúc rồi
ghi nguyên tử vào `/.crosspoint/bizsync/content.json`. Ghi chú, việc cần làm,
lịch và thời tiết là dữ liệu chỉ đọc trên thiết bị.

Chế độ nền nghỉ nằm tại `sleep.mode` (`calendar` hoặc `photo`). Với chế độ ảnh,
App đổi ảnh sang BMP 960 x 540 và tải lên `PUT /sleep.bmp` kèm kích thước,
SHA-256 và token trước khi chốt bản JSON. Chế độ lịch dùng RTC, thời tiết và tối
đa ba sự kiện trong bản đồng bộ.

## Trình tự

1. Người dùng mở **Truyền tệp > Kết nối App** để bật BLE.
2. Người dùng chạm thiết bị để App lưu BLE ID, không cần ghép đôi.
3. Khi gửi sách, App kết nối BLE và gửi `start`.
4. Firmware dùng Wi-Fi đã lưu rồi trả IP và token phiên qua BLE.
5. App tính SHA-256 và stream file bằng HTTP `PUT`, hoặc gọi API tiến độ khi
   người dùng bấm đồng bộ.
6. Firmware xác minh, hoàn tất file và thông báo `complete`; tiến độ App gửi
   được áp dụng ở lần mở EPUB kế tiếp.
7. Thoát màn hình hoặc sau 5 phút không có phiên truyền, firmware tắt BLE,
   HTTP và Wi-Fi.

BLE mở coi khoảng cách gần là ranh giới tin cậy. Một BLE client ở gần có thể
kích hoạt phiên và đọc token ngắn hạn; mật khẩu Wi-Fi không được truyền qua
kênh này.
