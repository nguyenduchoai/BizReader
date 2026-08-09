# BizReader Connect

Ứng dụng Android đồng hành với firmware BizReader.

## Chức năng hiện có

- Tìm và ghép đôi BizReader bằng BLE với mã 6 số trên màn hình e-paper.
- Dùng Wi-Fi đã lưu hoặc cấu hình Wi-Fi 2.4 GHz lần đầu qua BLE mã hóa.
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

Để BizReader đang thức, chọn **Tìm BizReader** trong App và xác nhận mã ghép
đôi. Lần đầu nhập Wi-Fi 2.4 GHz; các lần sau App tự yêu cầu thiết bị mở phiên
Wi-Fi trước khi gửi sách. Android cần quyền quét/kết nối Bluetooth.

## Phạm vi tiếp theo

Notes, Todo, Calendar, Weather, Photos và đồng bộ hai chiều cần API BizSync
trong firmware. Hợp đồng dữ liệu được mô tả tại
`../../docs/BIZREADER_PLATFORM.md`.
