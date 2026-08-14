# BizReader Connect

Ứng dụng Android đồng hành với firmware BizReader.

## Chức năng hiện có

- Tìm BizReader bằng BLE và chạm để lưu, không cần mã ghép đôi.
- Yêu cầu firmware dùng Wi-Fi đã lưu; App không hỏi SSID hoặc mật khẩu.
- Tự nhận IP/token sau khi người dùng mở **Truyền tệp > Kết nối App** trên máy.
- Nhập EPUB vào thư viện ứng dụng và đọc từng trang bằng thao tác vuốt ngang
  hoặc chạm mép màn hình.
- Có mục lục, dấu trang, thanh đọc tự ẩn và bảng chỉnh cỡ chữ, giãn dòng, lề,
  kiểu chữ, căn chữ cùng 6 nền đọc.
- Lưu CFI và vị trí chương/trang; đồng bộ tiến độ BLE hai chiều với thiết bị.
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
- Đồng bộ BLE hai chiều cho tiến độ đọc, ghi chú và việc cần làm.
- Dùng tombstone để thao tác xóa không làm mục cũ xuất hiện lại.
- Gửi riêng ảnh nền qua Wi-Fi; sách lớn vẫn dùng Wi-Fi có kiểm tra SHA-256.

## Chạy và build

```bash
flutter pub get
flutter test
flutter build apk --debug
```

Bản phát hành bắt buộc có upload key trong `android/key.properties`; Gradle sẽ
dừng rõ ràng thay vì âm thầm ký bằng debug key. Sau khi cấu hình key, build bằng
`flutter build apk --release --split-per-abi` hoặc
`flutter build appbundle --release`.

APK release ARM64 nằm tại:

```text
build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

Trên BizReader, mở **Truyền tệp > Kết nối App** để bật BLE, sau đó chọn **Tìm
BizReader** trong App và chạm thiết bị để lưu. Khi gửi sách, mở lại màn hình
**Kết nối App**; App yêu cầu thiết bị dùng Wi-Fi đã lưu và mở phiên truyền.
Android cần quyền quét/kết nối Bluetooth.

Thời tiết dùng Open-Meteo và hiển thị attribution trong App. Endpoint miễn phí
chỉ phù hợp đánh giá, thử nghiệm và mục đích phi thương mại. Bản thương mại cần
gói Open-Meteo có API key và build bằng
`--dart-define=OPEN_METEO_API_KEY=<key>`; khi có key, App tự chuyển geocoding và
forecast sang customer endpoint. Dart define được nhúng vào APK, vì vậy sản
phẩm quy mô lớn nên đặt khóa sau backend/proxy có kiểm soát hạn mức.

Trình xem đa định dạng được tích hợp từ dự án Gander (MIT) và đóng gói toàn bộ
bộ dựng tài liệu trong APK; nội dung không được tải lên máy chủ. EPUB dùng fork
`flutter_epub_viewer`/`epub.js` cục bộ đã tắt script, quyền WebView, tải mạng và
điều hướng ngoài để giữ thư viện cùng tiến độ trong BizReader. Các định dạng Office cũ
`.doc` và `.ppt` chưa được hỗ trợ; hãy lưu lại thành `.docx` hoặc `.pptx`. PDF
cần Android System WebView phiên bản 125 trở lên.

Trong **Tiện ích BizReader > Việc cần làm**, nút giữa hoặc chạm vào dòng sẽ đổi
trạng thái hoàn thành và lưu trên thẻ nhớ. Lần đồng bộ BLE tiếp theo sẽ hợp nhất
thay đổi đó về App. Hợp đồng dữ liệu được mô tả tại
`../../docs/BIZTRANSFER_PROTOCOL.md`.
