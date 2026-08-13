# Thông báo phần mềm bên thứ ba

## Firmware LilyGo T5 EPD47

Các môi trường `lilygo`, `lilygo_release` và `lilygo_release_rc` liên kết thư
viện [Xinyuan-LilyGO/LilyGo-EPD47](https://github.com/Xinyuan-LilyGO/LilyGo-EPD47)
tại commit `77387e337483be92186dee1e5ac6ad1d193ae16a`. Thư viện này được phân
phối theo GNU General Public License version 3; bản giấy phép đầy đủ nằm tại
`licenses/LilyGo-EPD47-GPL-3.0.txt`.

Giấy phép MIT ở `LICENSE` tiếp tục áp dụng cho mã nguồn thuộc phạm vi giấy phép
đó. Tuy nhiên, firmware binary dành cho LilyGo là combined work có liên kết thư
viện GPL-3.0. Khi phát hành binary này, nhà phát hành phải tuân thủ GPL-3.0, kèm
thông báo giấy phép và cung cấp Corresponding Source hoàn chỉnh của đúng phiên
bản binary theo các điều khoản của GPL-3.0. Không được phân phối firmware LilyGo
như một binary chỉ theo giấy phép MIT.

Workflow release và release candidate đính kèm gói `*-source.tar.gz`, gồm mã
nguồn BizReader và các submodule; toàn bộ thư viện PlatformIO đã resolve sau khi
áp dụng patch; mã nguồn platform/framework; cùng các nguồn, lock file và cấu
hình dùng để tạo thư viện ESP-IDF được liên kết vào firmware. Gói nguồn này phải
được phân phối cùng quyền truy cập tương đương với binary tương ứng.

Một số thư viện ESP32 do Espressif cung cấp chỉ ở dạng binary (ví dụ các blob
Wi-Fi/Bluetooth/PHY). Trước khi tạo tag hoặc phát hành Public cần rà soát pháp lý
để xác nhận ngoại lệ System Libraries hay điều khoản phân phối tương thích; gói
nguồn tự động không thay thế bước xác nhận này.

## Gander

Trình xem đa định dạng trong `apps/bizreader_connect` được điều chỉnh từ
[mokshablr/gander](https://github.com/mokshablr/gander), commit
`7527ad6f12f05fd3971e04de46184b729143727b`.

Copyright (c) 2026 Arjun Maniyani. Phân phối theo giấy phép MIT. Bản giấy phép
đầy đủ được đóng gói tại
`android/app/src/main/assets/viewer/GANDER_LICENSE.txt`.

Các thư viện JavaScript đóng gói trong viewer:

| Thư viện | Phiên bản | Giấy phép |
| --- | --- | --- |
| pdf.js | 5.7.284 | Apache-2.0 |
| JSZip | 3.10.1 và 2.x | MIT (lựa chọn từ giấy phép kép) |
| docx-preview | 0.3.x | Apache-2.0 |
| SheetJS Community Edition | 0.20.3 | Apache-2.0 |
| marked | 15.0.12 | MIT |
| DOMPurify | 3.4.12 | Apache-2.0 (lựa chọn từ giấy phép kép) |
| PPTXjs / divs2slides / FileReader.js | 1.21.1 / 1.3.2 / 0.99 | MIT |
| jQuery | 1.11.3 | MIT |
| D3 | 3.5.10 | BSD-3-Clause |
| NVD3 | 1.8.1 | Apache-2.0 |

Các tệp thư viện là bản phân phối thu gọn, không chỉnh sửa, được Gander đóng
gói để hiển thị tài liệu hoàn toàn ngoại tuyến.

## Open-Meteo

Chức năng cập nhật thời tiết theo tên thành phố sử dụng API và dữ liệu từ
[Open-Meteo](https://open-meteo.com/). Dữ liệu thời tiết được cung cấp theo
CC BY 4.0 và cần ghi công Open-Meteo. Endpoint miễn phí chỉ dành cho mục đích
phi thương mại theo điều khoản của nhà cung cấp; bản phân phối thương mại phải
dùng gói/endpoint có giấy phép phù hợp hoặc thay dịch vụ trước khi phát hành.
