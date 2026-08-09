# BizReader Connect

Ứng dụng Android đồng hành với firmware BizReader.

## Chức năng hiện có

- Tìm BizReader bằng BLE và chạm để lưu, không cần mã ghép đôi.
- Yêu cầu firmware dùng Wi-Fi đã lưu; App không hỏi SSID hoặc mật khẩu.
- Tự nhận IP/token và mở phiên truyền sách, không cần vào menu **Truyền tệp**.
- Chọn và gửi nhiều tệp EPUB, TXT, XTC, XTCH hoặc BMP vào `/Ebook`.
- Tính SHA-256 trước khi gửi và hiển thị phần trăm truyền.
- Giữ kết nối WebDAV thủ công làm phương án dự phòng.
- Hiển thị khung quản lý mini-app và màn hình nghỉ có lịch.

## Chạy và build

```bash
flutter pub get
flutter test
flutter build apk --release --split-per-abi
```

APK release ARM64 nằm tại:

```text
build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

Trên BizReader, mở **Truyền tệp > Kết nối App** để bật BLE, sau đó chọn **Tìm
BizReader** trong App và chạm thiết bị để lưu. Khi gửi sách, mở lại màn hình
**Kết nối App**; App yêu cầu thiết bị dùng Wi-Fi đã lưu và mở phiên truyền.
Android cần quyền quét/kết nối Bluetooth.

## Phạm vi tiếp theo

Notes, Todo, Calendar, Weather, Photos và đồng bộ hai chiều cần API BizSync
trong firmware. Hợp đồng dữ liệu được mô tả tại
`../../docs/BIZREADER_PLATFORM.md`.
