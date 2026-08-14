# Chính sách quyền riêng tư BizReader

Cập nhật lần cuối: 14/08/2026

BizReader là ứng dụng đọc sách và hỗ trợ kết nối điện thoại Android với máy đọc
sách BizReader. Ứng dụng có thể đọc tệp trên điện thoại, quản lý nội dung cá
nhân và truyền dữ liệu trực tiếp tới thiết bị do người dùng chọn.

## Dữ liệu chúng tôi thu thập

BizReader không yêu cầu tài khoản, không hiển thị quảng cáo và không tích hợp
công cụ phân tích hoặc theo dõi hành vi. Nhà phát triển không nhận bản sao sách,
ghi chú, việc cần làm, lịch, ảnh nền hoặc tiến độ đọc của người dùng.

Ứng dụng lưu cục bộ trên điện thoại:

- tên thiết bị, địa chỉ mạng nội bộ và mã định danh Bluetooth của máy đọc đã chọn;
- sách đã nhập, tiến độ, vị trí EPUB, dấu trang và tùy chọn trình bày khi đọc;
- ghi chú, việc cần làm, sự kiện lịch, lựa chọn nền nghỉ và ảnh nền;
- địa điểm cùng kết quả thời tiết gần nhất.

Người dùng có thể xoá cấu hình thiết bị trong ứng dụng. Có thể xoá toàn bộ dữ
liệu bằng phần Cài đặt Android hoặc gỡ ứng dụng.

## Quyền ứng dụng

- Bluetooth và thiết bị ở gần: dùng để tìm và kết nối với máy đọc sách BizReader.
- Vị trí trên Android 11 trở xuống: Android yêu cầu quyền này để quét Bluetooth Low Energy. BizReader không đọc, lưu hoặc truyền vị trí của người dùng.
- Mạng: dùng để truyền dữ liệu trực tiếp tới máy đọc BizReader trong mạng Wi-Fi
  nội bộ và tải dữ liệu thời tiết khi người dùng yêu cầu.

## Tệp sách

BizReader chỉ truy cập tệp mà người dùng chủ động chọn bằng trình chọn tệp của
Android hoặc gửi tới BizReader bằng chức năng Mở/Chia sẻ của Android. Tệp được
xử lý trên điện thoại và, khi người dùng chọn truyền, được gửi trực tiếp tới máy
đọc trong mạng nội bộ. Tệp không được tải lên máy chủ của nhà phát triển hay
dịch vụ lưu trữ bên thứ ba.

Trình đọc EPUB tắt script nhúng trong sách và chặn tài nguyên mạng, yêu cầu
quyền WebView cùng điều hướng ra ngoài. Ảnh, phông và biểu định kiểu trong sách
được đọc từ chính tệp EPUB trên điện thoại.

## Dữ liệu thời tiết

Khi người dùng chủ động cập nhật thời tiết, App gửi tên thành phố tới dịch vụ
định vị của Open-Meteo, sau đó gửi tọa độ kết quả tới dịch vụ dự báo Open-Meteo.
Open-Meteo cũng nhận địa chỉ IP theo cơ chế thông thường của kết nối Internet.
BizReader không gửi sách, ghi chú, việc cần làm, sự kiện lịch, mã Bluetooth hoặc
thông tin máy đọc tới Open-Meteo. Có thể dùng App mà không sử dụng chức năng
thời tiết.

Chính sách của Open-Meteo: https://open-meteo.com/en/terms

## Truyền dữ liệu tới máy đọc

Đồng bộ BLE và truyền Wi-Fi chỉ diễn ra khi người dùng yêu cầu. Dữ liệu được gửi
thẳng giữa điện thoại và máy đọc ở gần; không đi qua máy chủ của nhà phát triển.
BLE không yêu cầu ghép đôi, vì vậy người dùng chỉ nên mở màn hình **Kết nối App**
trên máy đọc trong lúc thực hiện đồng bộ.

## Trẻ em

BizReader không hướng tới trẻ em và không chủ động thu thập dữ liệu của trẻ em.

## Thay đổi chính sách

Khi chính sách này thay đổi, ngày cập nhật ở đầu trang sẽ được điều chỉnh. Phiên bản mới có hiệu lực kể từ khi được đăng công khai.

## Liên hệ

Mọi câu hỏi về quyền riêng tư có thể gửi tới: nguyenduchoai@gmail.com
