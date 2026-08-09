# BizReader Platform

## Mục tiêu

BizReader giữ trải nghiệm đọc EPUB của CrossPoint và bổ sung mô hình điều
khiển tương tự reTerminal Sticky dưới thương hiệu, giao diện và giao thức riêng:

- Lưu thiết bị BLE và kích hoạt Wi-Fi đã cấu hình trên máy đọc.
- Gửi sách, ghi chú, việc cần làm, lịch, thời tiết và ảnh.
- Hiển thị màn hình nghỉ có lịch hoặc ảnh cá nhân.
- Đồng bộ hai chiều, hoạt động ngoại tuyến và tự đồng bộ lại.
- Cập nhật OTA và quản lý nhiều thiết bị.
- Giữ WebDAV, web file manager và Calibre hiện có.

Không sao chép mã đóng, APK, tài nguyên nhận diện hoặc API riêng của Seeed.
Mã nguồn mở được tái sử dụng theo đúng giấy phép và có ghi công.

## Đối chiếu phần cứng

| Thành phần | reTerminal Sticky | LilyGo T5 EPD47 v2.4 | Hướng xử lý |
| --- | --- | --- | --- |
| MCU | ESP32-S3R8 | ESP32-S3 N16R8 | Tương thích kiến trúc |
| Màn hình | 800 x 480, 3.97 inch | 960 x 540, 4.7 inch | Layout theo kích thước động |
| Cảm ứng | GT911 | GT911 | Dùng FreeInk InputManager |
| Thẻ nhớ | microSD | microSD | Nguồn dữ liệu cục bộ |
| Wi-Fi/BLE | Có | Có | LAN, discovery và đồng bộ |
| Nút dùng được | 3 | 1 nút ứng dụng | Cảm ứng là điều khiển chính |
| Micro | PDM | Không | Nhận giọng nói trên điện thoại |
| RTC | PCF8563 | Không | NTP + thời gian hệ thống |
| Buzzer | Có | Không | Nhắc việc trên điện thoại |
| Cảm biến/IMU | Có | Không | Dữ liệu thời tiết qua mạng |

## Trạng thái triển khai

BizTransfer v1 đã có trong firmware LilyGo và App Android:

- BLE discovery mở, chạm để lưu thiết bị, không bonding hoặc passkey.
- Chỉ dùng Wi-Fi đã lưu trên BizReader; App không nhận mật khẩu mạng.
- Token HTTP ngắn hạn được trả qua BLE khi thiết bị ở gần.
- HTTP stream vào `/Ebook`, file `.part`, kiểm tra kích thước và SHA-256.
- Tự tắt Wi-Fi/server sau 5 phút; WebDAV thủ công vẫn hoạt động độc lập.

Chi tiết byte-level và endpoint: [BizTransfer v1](./BIZTRANSFER_PROTOCOL.md).

## Thành phần hệ thống

### Firmware

CrossPoint/BizReader tiếp tục là lõi đọc sách. `BizHubActivity` sẽ là điểm vào
cho các mini-app, còn `BizSyncService` chịu trách nhiệm:

- REST API trong LAN.
- Kho dữ liệu JSON trên thẻ nhớ.
- Hàng đợi thay đổi khi ngoại tuyến.
- BLE discovery và kích hoạt phiên BizTransfer bằng Wi-Fi đã lưu.
- Kích hoạt làm mới màn hình khi có nội dung mới.

### Ứng dụng Android

Flutter dùng một codebase cho Android trước, sau đó có thể mở rộng iOS:

- Thiết bị và trạng thái kết nối.
- Thư viện và WebDAV.
- Trình soạn Notes/Todo/Calendar.
- Chuẩn hóa ảnh về 960 x 540 và dithering.
- Cấu hình Clock/Weather/wallpaper.
- Giọng nói trên điện thoại.
- OTA và chẩn đoán.

### Đồng bộ

LAN là đường mặc định và không cần tài khoản. Cloud relay là thành phần tùy
chọn cho điều khiển từ xa và nhiều người dùng; firmware không phụ thuộc cloud
để đọc sách hoặc xem nội dung đã đồng bộ.

## Lưu trữ trên thẻ nhớ

```text
/Ebook/
/.bizreader/
  device.json
  notes.json
  todos.json
  calendar.json
  weather.json
  dashboard.json
  sync-journal.jsonl
  media/
  wallpapers/
```

Mỗi bản ghi đồng bộ có:

```json
{
  "id": "uuid",
  "revision": 12,
  "updatedAt": "2026-07-30T10:30:00Z",
  "actorId": "phone-or-device-id",
  "deleted": false
}
```

Notes dùng last-write-wins theo từng bản ghi. Todo và Calendar giữ tombstone
cho thao tác xóa để thiết bị ngoại tuyến không làm sống lại dữ liệu cũ.

## BizSync API v1

Các endpoint chạy cùng web server hiện có:

| Method | Endpoint | Mục đích |
| --- | --- | --- |
| `GET` | `/api/v1/device` | Tên, MAC, phiên bản, pin, SD, khả năng |
| `GET` | `/api/v1/sync?since=<rev>` | Lấy thay đổi sau revision |
| `POST` | `/api/v1/sync` | Đẩy một lô thay đổi |
| `POST` | `/api/v1/display/activate` | Mở mini-app hoặc wallpaper |
| `POST` | `/api/v1/wifi` | Cấu hình Wi-Fi qua phiên LAN đã xác thực |
| `POST` | `/api/v1/ota/check` | Kiểm tra bản firmware |
| `POST` | `/api/v1/ota/install` | Cài bản đã xác thực |

BizTransfer HTTP hoặc WebDAV tiếp tục đảm nhiệm tệp lớn. JSON sync không mang
dữ liệu EPUB hoặc ảnh nhị phân trong body.

## BLE

BLE quảng bá trong thời gian thiết bị đang thức và tự dừng trước deep sleep.
GATT cung cấp:

- Device identity và trạng thái phiên.
- Lệnh mở Wi-Fi đã lưu, không truyền SSID hoặc mật khẩu.
- URL LAN và token ngắn hạn sau khi kết nối thành công.

Truyền ảnh/sách lớn qua Wi-Fi hoặc WebDAV, không đẩy qua BLE. Có thể dùng các
phần tương thích của OpenDisplay service `0x2446` cho ảnh cục bộ, nhưng không
được làm thay đổi giao thức BizSync hay buộc firmware vào OpenDisplay.

## Bảo mật

- BLE không bonding; khoảng cách gần là ranh giới tin cậy của BizTransfer v1.
- Token LAN được tạo mới cho từng phiên và hết hiệu lực khi phiên dừng.
- Không đưa mật khẩu Wi-Fi, token cloud hoặc thông tin đăng nhập vào log.
- OTA phải kiểm tra manifest, kích thước và SHA-256 trước khi đổi partition.
- Không truyền access token Codex/OpenAI xuống thiết bị.
- Cloud relay, nếu bật, dùng TLS và token riêng cho từng thiết bị.

## Trình tự triển khai

1. **BizTransfer v1 (đã có):** BLE mở Wi-Fi, token phiên, gửi sách có SHA-256.
2. **BizSync local:** API thiết bị, Notes, Todo và calendar wallpaper.
3. **Media:** ảnh, dithering, theme Clock/Weather và wallpaper.
4. **BLE mở rộng:** đổi tên thiết bị, quyền truy cập tùy chọn và chẩn đoán mạng.
5. **Remote sync:** relay tùy chọn, nhiều thiết bị và thông báo.
6. **Voice/OTA:** giọng nói trên Android, OTA từ ứng dụng và theo dõi lỗi.

## Nguồn tham khảo

- [reTerminal Sticky docs](https://www.seeedstudio.com/sticky/docs/en/quick-start/)
- [Sticky hardware overview](https://www.seeedstudio.com/sticky/docs/en/device-guide/hardware-overview/)
- [CrossPoint Reader](https://github.com/crosspoint-reader/crosspoint-reader)
- [FreeInk SDK](https://github.com/Free-Ink/freeink-sdk)
- [Sticky Reminders](https://github.com/Free-Ink/sticky-reminders) (MIT)
- [OpenDisplay protocol](https://opendisplay.org/protocol/index.html)
