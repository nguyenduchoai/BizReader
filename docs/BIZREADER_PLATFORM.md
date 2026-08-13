# Kiến trúc BizReader

## Phạm vi sản phẩm

BizReader gồm firmware LilyGo T5 EPD47 và App Android. Trình đọc sách và thư
viện là chức năng chính; App không bắt người dùng kết nối thiết bị trước khi đọc.

Phạm vi đang có trong mã nguồn:

- đọc sách trên thiết bị và EPUB trên Android;
- cảm ứng trên firmware EPD47 và nút vật lý theo board profile;
- BLE Sync v2 cho snapshot nhỏ;
- BLE kích hoạt máy đọc tự nối Wi-Fi đã lưu;
- HTTP có token cho sách, ảnh và dữ liệu tương thích cũ;
- WebDAV, web file manager, Calibre và OPDS độc lập với App;
- ghi chú, việc cần làm, lịch, thời tiết và nền nghỉ;
- trình xem nhiều định dạng ngoại tuyến trên Android.

Chưa có: tài khoản/cloud relay, đồng bộ từ xa, nhiều người dùng, push notification,
giọng nói, cập nhật firmware từ App hoặc iOS. Những mục này không phải điều kiện
để đọc sách và không được coi là chức năng đã vận hành.

## Phần cứng đích

| Thành phần | LilyGo T5 EPD47 v2.4 |
| --- | --- |
| MCU | ESP32-S3-WROOM-1 N16R8 |
| Màn hình | ED047TC1, 960 x 540, 4.7 inch |
| Cảm ứng | GT911 |
| Lưu trữ | microSD qua SPI |
| Kết nối | Wi-Fi 2.4 GHz và BLE |
| Thời gian | PCF8563 nếu có trên revision; NTP khi kết nối mạng |

Profile firmware hiện coi GPIO21 là nút người dùng/nguồn. Quay lại, chọn, cuộn
và chuyển trang được tổng hợp từ GT911. Các nút nhìn thấy trên vỏ nhưng nối vào
reset/boot hoặc đường điều khiển màn hình không được mặc định coi là nút ứng
dụng. Cần UAT đúng revision phần cứng trước khi thay đổi pin map.

## Thành phần

### Firmware

- Lõi thư viện/EPUB kế thừa CrossPoint Reader.
- `BizHubActivity` hiển thị ghi chú, task, lịch, thời tiết và trạng thái nền nghỉ.
- `BizContentStore` lưu snapshot JSON trong `/.crosspoint/bizsync/content.json`.
- `BizReadingProgressStore` lưu tiến độ theo tên tệp trong cùng thư mục.
- `BizTransferService` quảng bá GATT, xử lý BLE Sync v2 và mở HTTP theo yêu cầu.
- `BizBookUploadHandler` nhận tệp vào `.part`, kiểm tra SHA-256 rồi mới hoàn tất.
- `OtaUpdater` chỉ nhận `firmware.bin` từ GitHub Release của BizReader; release
  tag `vX.Y.Z` được đóng gói cho profile LilyGo cùng checksum và mã nguồn tương
  ứng.

### Android

- Flutter quản lý Tổng quan, Thư viện, Tiện ích và Thiết bị.
- EPUB được nhập vào vùng dữ liệu riêng của App và đọc bằng `epub_view`.
- `BizTransferBleClient` kéo snapshot, hợp nhất theo `updatedAt`, đẩy snapshot
  kết quả về máy và đọc lại để xác nhận.
- `WebDavDeviceClient` dùng token BizTransfer hoặc cấu hình WebDAV thủ công để
  truyền tệp lớn.
- Viewer Android native kế thừa Gander, xử lý tài liệu cục bộ trong WebView bị
  giới hạn về host asset nội bộ.

## Luồng BLE Sync v2

1. Người dùng mở **Truyền tệp > Kết nối App** trên máy đọc.
2. Firmware bật BLE với service UUID BizReader; không bonding/passkey.
3. App gửi `sync_pull` và đọc snapshot theo các frame có sequence/total.
4. App hợp nhất ghi chú, task, tombstone và tiến độ theo stable ID/tên tệp cùng
   `updatedAt`. Lịch, thời tiết và chế độ nền nghỉ do App quản lý.
5. App gửi `sync_begin`, lần lượt ghi frame và kết thúc bằng `sync_commit`.
6. Firmware chỉ commit khi đủ frame đúng thứ tự, validate toàn bộ JSON rồi trả
   snapshot đã lưu để App xác nhận.
7. Disconnect, Back hoặc timeout hủy phiên và giải phóng buffer.

Giới hạn snapshot là 48 KiB, tối đa 40 ghi chú, 60 task, 60 sự kiện, 80/120
tombstone và 100 bản ghi tiến độ. Danh sách bị giới hạn phải giữ các mục mới
nhất. Sách, ảnh và firmware không đi trong snapshot BLE.

## Luồng truyền sách/ảnh

1. App gửi lệnh BLE `start`.
2. Firmware chỉ dùng SSID/mật khẩu đã lưu trên máy đọc để nối Wi-Fi.
3. Firmware tạo token ngẫu nhiên theo phiên, trả IP, port và token qua BLE.
4. App gửi tệp bằng HTTP kèm token, `Content-Length` và SHA-256.
5. Firmware stream vào `.part`; chỉ đổi tên sau khi kích thước và hash khớp.
6. App gửi `stop`; firmware tắt HTTP/Wi-Fi. Phiên bỏ quên cũng tự hết hạn.

WebDAV vẫn là luồng riêng, dùng được không cần App. App không đọc hoặc vận chuyển
mật khẩu Wi-Fi đã lưu trên máy đọc.

## Dữ liệu trên thiết bị

```text
/Ebook/                         # sách của người dùng
/sleep.bmp                      # ảnh nền nghỉ tùy chọn
/.crosspoint/bizsync/
  content.json                  # notes/tasks/events/weather/sleep + tombstones
  <fnv1a>.json                  # tiến độ theo filename
```

Mỗi file store dùng ghi tạm/backup để giảm nguy cơ mất điện giữa lúc thay thế.
Tuy nhiên, `content.json` và nhiều file tiến độ chưa tạo thành một transaction
xuyên file: nếu thẻ SD lỗi giữa vòng commit, snapshot có thể chỉ được áp dụng một
phần và App phải đồng bộ lại. Sách cá nhân trong `Ebook/` không thuộc mã nguồn và
phải nằm ngoài Git.

## Bảo mật và riêng tư

- BLE mở không ghép đôi là quyết định sản phẩm; ranh giới tin cậy là thao tác
  người dùng mở màn hình kết nối và khoảng cách gần.
- Token HTTP ngẫu nhiên chỉ tồn tại trong phiên và được so sánh constant-time.
- Upload từ xa không được ghi trực tiếp vào tên đích trước khi xác minh.
- Không có tài khoản, analytics hay máy chủ BizReader trung gian.
- Tên thành phố/tọa độ dự báo chỉ được gửi tới Open-Meteo khi người dùng bấm cập
  nhật tự động; xem [chính sách quyền riêng tư](../PRIVACY_POLICY.md).

## Giới hạn kiểm chứng

Unit test và build chứng minh mã biên dịch và logic host đã chạy, nhưng không
chứng minh màn hình, cảm ứng, nút, thẻ nhớ, BLE radio hoặc Wi-Fi trên máy thật.
Release chỉ đạt khi đã UAT đúng board với các tình huống ngắt BLE giữa frame,
SD đầy/mất điện, sách lớn, tiếng Việt, sleep/wake và quay lại từ mọi màn hình.

Chi tiết wire contract nằm tại [BIZTRANSFER_PROTOCOL.md](BIZTRANSFER_PROTOCOL.md).
