# BizReader Connect

Ứng dụng Android đồng hành với firmware BizReader.

## Chức năng hiện có

- Tìm BizReader bằng BLE và chạm để lưu, không cần mã ghép đôi.
- Yêu cầu firmware dùng Wi-Fi đã lưu; App không hỏi SSID hoặc mật khẩu.
- Tự nhận IP/token sau khi người dùng mở **Truyền tệp > Kết nối App** trên máy.
- Nhập EPUB vào thư viện ứng dụng và đọc trực tiếp trên Android.
- Lưu vị trí đọc trên điện thoại và đồng bộ thủ công hai chiều theo từng sách.
- Mở tệp trực tiếp trong App hoặc từ menu **Mở bằng BizReader** của Android.
- Đọc ngoại tuyến PDF, DOCX, XLSX/XLS/XLSM/XLSB/CSV/ODS, PPTX,
  Markdown, văn bản/mã nguồn, ảnh, âm thanh và video.
- Chế độ demo có thư viện mẫu và nội dung đọc để chụp ảnh Play Store.
- Chọn và gửi nhiều tệp EPUB, TXT, XTC, XTCH hoặc BMP vào `/Ebook`.
- Tính SHA-256 trước khi gửi và hiển thị phần trăm truyền.
- Giữ kết nối WebDAV thủ công làm phương án dự phòng.
- Hiển thị khung quản lý mini-app và màn hình nghỉ có lịch.
- Tạo/sửa/xóa ghi chú, việc cần làm và sự kiện lịch trên App.
- Cập nhật thời tiết tự động theo tên thành phố hoặc nhập tay.
- Chọn ảnh điện thoại, đổi sang BMP 960 x 540 và dùng làm nền nghỉ.
- Đồng bộ toàn bộ tiện ích một chiều xuống **Tiện ích BizReader** trên thiết bị.

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

Trình xem đa định dạng được tích hợp từ dự án Gander (MIT) và đóng gói toàn bộ
bộ dựng tài liệu trong APK; nội dung không được tải lên máy chủ. EPUB vẫn dùng
trình đọc BizReader để giữ thư viện và đồng bộ tiến độ. Các định dạng Office cũ
`.doc` và `.ppt` chưa được hỗ trợ; hãy lưu lại thành `.docx` hoặc `.pptx`. PDF
cần Android System WebView phiên bản 125 trở lên.

Nội dung tiện ích được sửa trên App và chỉ đọc trên thiết bị. Đồng bộ vị trí EPUB
vẫn là luồng riêng theo từng sách. Hợp đồng dữ liệu được mô tả tại
`../../docs/BIZTRANSFER_PROTOCOL.md`.
