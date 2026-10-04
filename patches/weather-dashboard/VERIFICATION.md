# Kiểm tra bản thời tiết và lịch ngày 04/10/2026

## Thiết bị và bản nạp

- LilyGo T5-4.7-S3 V2.4, ESP32-S3 N16R8, màn hình 960 × 540, RTC PCF8563.
- Môi trường build: `hcm_weather`, Arduino 2.0.11, PlatformIO `espressif32@6.4.0`.
- Chỉ ghi ứng dụng tại `0x10000`; không nạp lại bảng phân vùng hoặc SPIFFS.
- Firmware: 1.132.944 byte.
- SHA256 firmware: `cb59d2ccbc29e439a00bcd9df9376dd4489211bf252b2cb49706544fabbce29a`.
- SHA256 bản vá nguồn: `9b88796ea5f9798e9329b53f1ea07fe75ce1619245ec526d8b95ac045b6309e9`.

## Kết quả đã xác nhận

- Build thành công; esptool xác minh toàn bộ ứng dụng khớp bản nạp.
- Kết nối bằng cấu hình Wi-Fi/API hiện có và nhận đủ thời tiết, 24 mốc dự báo.
- Đọc PCF8563, đồng bộ NTP vào RTC theo UTC; giao diện dùng UTC+7.
- Đọc lại `/weather.bin` hợp lệ sau khởi động lại; bản thời tiết mới ghi thành công và được đọc lại để kiểm tra trước khi thay bản cũ.
- Vòng đổi phút trước bản đóng gói cuối: cập nhật riêng đồng hồ, không bật Wi-Fi, thức khoảng 1.225 ms, stack còn tối thiểu 5.904 byte.
- Bản đóng gói cuối đã đổi từ 15:19 sang 15:20: mỗi vòng thức 1.225 ms, cập nhật riêng vùng đồng hồ, không dùng Wi-Fi và còn tối thiểu 5.904 byte stack. Monitor thụ động kết thúc bình thường, không có reset hoặc lỗi runtime trong hai vòng này.
- Logic cập nhật mỗi giờ và thử lại sau 15 phút khi lỗi mạng đã qua kiểm thử; giữ bản gần nhất và đánh dấu dữ liệu cũ. Chưa chạy thử mất mạng kéo dài trên thiết bị thật.
- Không có mục ghi chú hoặc việc cần làm, theo yêu cầu.

## Kiểm thử tự động

- Âm lịch: 26 ngày đối chiếu, 10 ngày không hợp lệ, 73.049 ngày liên tiếp.
- Cache: giá trị, checksum, vị trí, thời gian lùi, chu kỳ một giờ và thử lại.
- RTC: giả lập I2C, BCD, ngày nhuận, lỗi bus, cờ mất nguồn và phạm vi thanh ghi.
- Lưu cache: metadata cũ của file đang ghi và năm trường hợp lỗi đọc lại; bản cũ và cấu hình không bị thay khi kiểm tra thất bại.
- Giao diện: 36 trường hợp dashboard và 18 trường hợp biểu tượng cũ; kiểm tra lề 28 px và cô lập vùng đổi phút.
- Monitor USB: 3 kiểm thử, không điều khiển DTR/RTS khi kết nối lại.
- Các kiểm thử C++ trên máy tính chạy với ASan/UBSan.
- Trang cài đặt: kiểm tra trình duyệt ở 320, 390 và 1280 px bằng API giả lập; bản C++ đã build.

## Giới hạn

- Chưa đo thời lượng pin hoặc độ lưu bóng dài hạn; phần trăm pin là ước lượng ADC.
- Cần người dùng xác nhận lề màn hình và chất lượng làm mới bằng mắt trên máy thật.
- Chưa nghiệm thu thao tác nút mở trang cài đặt và lưu cấu hình qua Wi-Fi trên phần cứng với bản cuối.
- Toolchain hiện tại dùng `time_t` 32-bit; kiểm thử âm lịch đến 2099 không bảo đảm đồng hồ hệ thống hoạt động qua năm 2038.
- Bản này được giữ lại để dùng thiết bị làm lịch và thời tiết sau khi dừng phát triển trình đọc; không phải bản nghiệm thu toàn bộ BizReader hoặc cảm ứng.

Log và binary nằm trong checkout cục bộ `build/weather-display-web`, không đưa vào bản vá nguồn. Bản sao firmware trước nâng cấp được giữ cục bộ; cấu hình riêng không nằm trong gói nguồn.
