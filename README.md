# BizReader

BizReader là nền tảng đọc sách cho **LilyGo T5 ePaper S3 / T5S3 4.7 inch
(EPD47 v2.4, ESP32-S3 N16R8)**, gồm firmware trên máy đọc và ứng dụng Android
đồng hành. Dự án kế thừa lõi đọc EPUB của
[CrossPoint Reader](https://github.com/crosspoint-reader/crosspoint-reader), sau
đó bổ sung giao diện tiếng Việt, cảm ứng GT911, phím người dùng/nguồn, màn hình
nghỉ và đồng bộ BizReader.

Tên hiển thị trên thiết bị là **BizReader**; phần thông tin và màn hình nghỉ ghi
**Hoài Nguyễn**.

## Chức năng

### Trên máy đọc

- Đọc EPUB 2/3, TXT, XTC, XTCH và BMP từ thẻ nhớ.
- Thư viện, sách gần đây, dấu trang, mục lục, tìm kiếm và tùy chỉnh kiểu đọc.
- Cảm ứng trực tiếp cho quay lại, chọn, cuộn và chuyển trang. Profile EPD47 v2.4
  chỉ dùng KEY GPIO21 làm nguồn/đánh thức; BOOT và RESET không phải nút điều
  hướng của ứng dụng.
- Giao diện và font tiếng Việt.
- Tiện ích ghi chú, việc cần làm, lịch, thời tiết và nền nghỉ.
- Nền nghỉ dạng lịch hoặc ảnh `sleep.bmp`.
- Web, WebDAV, Calibre và OPDS của lõi đọc vẫn được giữ làm phương án dự phòng.

### Trên Android

- Mở thẳng vào Tổng quan; kết nối thiết bị là một chức năng trong tab Thiết bị,
  không phải bước bắt buộc để dùng App.
- Nhập và đọc EPUB theo từng trang lật ngang, có mục lục, dấu trang, tùy chỉnh
  chữ/nền; lưu tiến độ cục bộ và đồng bộ với máy đọc.
- Quản lý ghi chú, việc cần làm, lịch, thời tiết và nền nghỉ.
- Mở ngoại tuyến PDF, DOCX, XLSX/XLS/XLSM/XLSB/CSV/ODS, PPTX, Markdown,
  văn bản/mã nguồn, ảnh, âm thanh và video.
- Có chế độ demo để kiểm tra giao diện mà không cần máy đọc.

## Cơ chế đồng bộ

BizReader tách dữ liệu nhỏ và tệp lớn để giữ BLE nhanh, ổn định và tiết kiệm pin:

1. Trên máy đọc, mở **Truyền tệp > Kết nối App**. BLE chỉ bật trong màn hình
   này và tắt khi bấm Back hoặc hết thời gian.
2. App tìm thiết bị ở gần và kết nối BLE, không yêu cầu ghép đôi hay mã PIN.
3. Tiến độ đọc, ghi chú, việc cần làm, lịch, thời tiết và cấu hình nền nghỉ được
   hợp nhất hai chiều bằng BLE Sync v2.
4. Sách và ảnh nền được gửi bằng HTTP qua Wi-Fi. App chỉ yêu cầu máy đọc dùng
   mạng đã lưu; App không nhận hoặc lưu mật khẩu Wi-Fi của máy đọc.
5. Firmware ghi tệp `.part`, kiểm tra kích thước và SHA-256 rồi mới đổi tên vào
   `/Ebook`. WebDAV tiếp tục hoạt động độc lập khi không dùng App.

BLE không ghép đôi là chủ ý sản phẩm. Trong thời gian màn hình **Kết nối App**
đang mở, một ứng dụng tương thích ở gần có thể đọc/ghi dữ liệu đồng bộ; không
nên để màn hình này mở lâu ở nơi công cộng.

Chi tiết kỹ thuật:

- [Kiến trúc nền tảng](docs/BIZREADER_PLATFORM.md)
- [Giao thức BLE Sync v2 và BizTransfer](docs/BIZTRANSFER_PROTOCOL.md)
- [Ứng dụng Android](apps/bizreader_connect/README.md)
- [Quyền riêng tư](PRIVACY_POLICY.md)

## Chuẩn bị thẻ nhớ

Tạo thư mục sau trên thẻ microSD:

```text
/Ebook
```

Sách cá nhân trong `Ebook/` là dữ liệu cục bộ và không được đưa lên Git. Dữ liệu
vận hành của firmware được lưu dưới `/.crosspoint/` trên thẻ.

## Build firmware LilyGo

Yêu cầu PlatformIO Core tương thích với `platformio.ini` và submodule đã được
lấy đầy đủ:

```bash
git submodule update --init --recursive
pio run -e lilygo
```

Build bản phát hành:

```bash
pio run -e lilygo_release
```

Flash bằng PlatformIO để tool tự dùng đúng bootloader, partition và địa chỉ cho
ESP32-S3:

```bash
pio run -e lilygo -t upload --upload-port /dev/cu.usbmodemXXXX
pio device monitor --baud 115200 --port /dev/cu.usbmodemXXXX
```

Không dùng lệnh flash ESP32-C3 hoặc địa chỉ cố định từ tài liệu CrossPoint/Xteink
cho LilyGo. Nếu máy không hiện cổng serial, giữ nút BOOT, bấm RESET rồi thả BOOT
để vào chế độ tải firmware.

Artifact của bản release nằm trong:

```text
.pio/build/lilygo_release/
```

Tag phiên bản dạng `vX.Y.Z` trên commit mới nhất của `main`, khớp với trường
`version` trong `platformio.ini`, sẽ build đúng profile LilyGo và tạo GitHub
Release có `firmware.bin`, checksum, giấy phép cùng gói mã nguồn tương ứng. Menu
cập nhật trên thiết bị chỉ kiểm tra release của repo BizReader này.

Gói `*-source.tar.gz` chứa đúng source snapshot của bản build, gồm các patch đã
áp dụng cho dependency, platform/framework và nguồn để tạo các thư viện ESP-IDF
được link vào firmware. Asset của một tag đã phát hành là bất biến; muốn phát
hành lại phải tăng phiên bản và tạo tag mới.

## Build ứng dụng Android

```bash
cd apps/bizreader_connect
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

APK debug dùng để cài thử cục bộ. Bản đưa lên Google Play phải có
`android/key.properties` và upload keystore hợp lệ, sau đó build:

```bash
flutter build appbundle --release
```

Keystore, `key.properties`, APK/AAB và thông tin đăng nhập không được commit.
Quy trình release phải dừng nếu thiếu khóa; không dùng bản ký debug để phát hành
Public.

## Kiểm tra trước phát hành

```bash
cmake -S test -B build/test -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build/test
ctest --test-dir build/test --output-on-failure

cd apps/bizreader_connect
flutter analyze
flutter test
cd android
./gradlew :app:lintRelease
```

Build và unit test không thay thế kiểm tra trên thiết bị thật. Trước khi phát
hành cần xác nhận ít nhất: khởi động, cảm ứng, các nút vật lý có thể dùng ở
revision phần cứng thực tế, mở EPUB tiếng
Việt, lưu/khôi phục tiến độ, BLE ngắt giữa chừng, đồng bộ hai chiều, gửi sách
lớn qua Wi-Fi, nền nghỉ và quay lại từ mọi màn hình.

## Nguồn và giấy phép

- Mã nguồn thuộc phạm vi [LICENSE](LICENSE) của repository được phát hành theo
  MIT. Binary firmware LilyGo có liên kết driver GPL-3.0, vì vậy phải kèm giấy
  phép và mã nguồn tương ứng như mô tả trong
  [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
- Driver màn hình dùng
  [LilyGo-EPD47](https://github.com/Xinyuan-LilyGO/LilyGo-EPD47).
- Trình xem đa định dạng Android có thành phần kế thừa Gander theo giấy phép MIT;
  thông tin bên thứ ba nằm trong thư mục ứng dụng.
- BizReader không phải sản phẩm chính thức của LilyGo hay CrossPoint Reader.
