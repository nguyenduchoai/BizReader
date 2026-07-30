# BizReader Connect

Ứng dụng Android đồng hành với firmware BizReader.

## Chức năng hiện có

- Lưu tên và địa chỉ thiết bị trong mạng nội bộ.
- Kiểm tra WebDAV khi máy đọc đang mở **Truyền tệp**.
- Chọn và gửi nhiều tệp EPUB, TXT, XTC, XTCH hoặc BMP vào `/Ebook`.
- Hiển thị khung quản lý mini-app và màn hình nghỉ có lịch.

## Chạy và build

```bash
flutter pub get
flutter test
flutter build apk --debug
```

APK debug nằm tại:

```text
build/app/outputs/flutter-apk/app-debug.apk
```

Điện thoại và BizReader phải ở cùng mạng. Trên máy đọc, mở **Truyền tệp**,
chọn **Kết nối Wi-Fi** hoặc **Tạo điểm phát**, sau đó nhập URL đang hiển thị
vào ứng dụng.

## Phạm vi tiếp theo

Notes, Todo, Calendar, Weather, Photos, BLE provisioning và đồng bộ hai chiều
cần API BizSync trong firmware. Hợp đồng dữ liệu được mô tả tại
`docs/BIZREADER_PLATFORM.md`.
