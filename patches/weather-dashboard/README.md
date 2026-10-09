# Weather Dashboard cho LilyGo T5S3

Bản vá cho firmware thời tiết LilyGo, dùng trên **T5-4.7-S3 V2.4, ESP32-S3 N16R8,
màn hình 960 × 540, RTC PCF8563**. Không dùng bản này cho T5 Pro hoặc ESP32 đời cũ.

**Trạng thái 04/10/2026:** lưu lại bản đã nạp để dùng thiết bị làm lịch, đồng hồ
và thời tiết. Phần app Android và trình đọc BizReader đã dừng phát triển; không
cần app để dùng firmware này. Xem [kết quả kiểm tra](VERIFICATION.md) trước khi
nạp lại hoặc đánh giá mức độ hoàn thiện.

- Repo gốc: <https://github.com/Xinyuan-LilyGO/LilyGo-EPD-4-7-OWM-Weather-Display>
- Nhánh: `web`
- Commit nền: `3aea8d0a8c8a024291bba38e6da805f02acbb188`
- Bản vá: `weather-dashboard.patch` trong cùng thư mục.

Bản tuỳ chỉnh từ **09/10/2026** dùng giao diện dọc **540 × 960**: nửa trên là
giờ lớn, ngày dương và âm lịch; giữa là thời tiết hiện tại với nhiệt độ, mây,
độ ẩm, gió và biểu tượng; dưới là bốn mốc dự báo theo giờ. Đã bỏ lịch tháng.
Dữ liệu dự báo hiện có các mốc cách nhau ba giờ, hiển thị theo giờ Việt Nam.
Đồng hồ đổi mỗi phút, có nhãn tiếng Việt, lề 28 px và trang cài đặt nhúng.
RTC lưu UTC; giao diện hiển thị UTC+7. Các kiểm thử trên máy tính không thay thế
việc kiểm tra lưu bóng, chất lượng làm mới và thời lượng pin trên thiết bị thật.
Thiết bị không cần máy tính đang đọc USB để khởi động hoặc đi ngủ. Không có
luồng ngủ phụ thuộc `Serial.flush()`. Dữ liệu đệm và cấu hình chỉ được đổi tên
sau khi đóng tệp ghi, mở lại và xác minh toàn bộ nội dung đã lưu.

![Giao diện dọc với dữ liệu mẫu](portrait-preview.png)

Ảnh trên được dựng từ mã firmware và dữ liệu mẫu. Xem
[kiểm tra bản dọc ngày 09/10/2026](PORTRAIT_2026-10-09.md) để phân biệt kết quả
build/kiểm thử trên máy tính với kết quả chạy trên thiết bị thật.

**Không có SSID, mật khẩu Wi-Fi hay API key trong bản vá.** Cấu hình riêng trên
thiết bị được giữ nguyên khi chỉ nạp vùng ứng dụng. Không đưa bản sao flash,
tệp SPIFFS, log riêng hoặc cấu hình đang dùng lên Git.

## Áp dụng và build

Chạy từ một thư mục làm việc riêng. Thay `/duong-dan/BizReader` bằng đường dẫn
checkout chứa bản vá này.

```sh
git clone --branch web https://github.com/Xinyuan-LilyGO/LilyGo-EPD-4-7-OWM-Weather-Display.git weather-dashboard
cd weather-dashboard
git checkout --detach 3aea8d0a8c8a024291bba38e6da805f02acbb188
git apply --check /duong-dan/BizReader/patches/weather-dashboard/weather-dashboard.patch
git apply /duong-dan/BizReader/patches/weather-dashboard/weather-dashboard.patch
pio run -e hcm_weather
```

Kết quả: `.pio/build/hcm_weather/firmware.bin`. Font tiếng Việt đã có sẵn trong
bản vá, không cần cài công cụ tạo font để build firmware. PlatformIO dùng
`espressif32@6.4.0`; phụ thuộc `LilyGo-EPD47#esp32s3` vẫn theo nhánh upstream,
vì vậy một lần build trong tương lai không được bảo đảm giống từng byte.

## Nạp riêng ứng dụng

Chỉ áp dụng cho thiết bị đã có bootloader và bảng phân vùng BizReader 16 MB
tương ứng `partitions-bizreader.csv`: `app0` tại `0x10000`, kích thước `0x640000`;
SPIFFS tại `0xc90000`. Nếu chưa xác minh bảng phân vùng thực tế thì dừng trước
khi nạp. Bảng CSV trong bản vá chỉ phục vụ build, không phải chỉ dẫn ghi lại
bảng phân vùng trên máy đang dùng.

Ví dụ dưới đây dùng esptool 5; thay cổng USB theo thiết bị thực tế:

```sh
python -m esptool --chip esp32s3 --port /dev/cu.usbmodem2101 --baud 921600 read-flash 0 0x1000000 weather-before-update-private.bin
python -m esptool --chip esp32s3 --port /dev/cu.usbmodem2101 --baud 921600 write-flash 0x10000 .pio/build/hcm_weather/firmware.bin
python -m esptool --chip esp32s3 --port /dev/cu.usbmodem2101 --baud 921600 verify-flash 0x10000 .pio/build/hcm_weather/firmware.bin
```

Không chạy `buildfs`, `uploadfs`, xoá toàn bộ flash hoặc nạp gói gộp. Các thao tác
đó có thể thay cấu hình Wi-Fi/API key hiện đang lưu trong SPIFFS. Nạp ứng dụng
không ghi lên thẻ nhớ ngoài. Giữ bản sao flash ở nơi riêng tư vì có thể chứa
thông tin kết nối.

Trang cài đặt được phục vụ từ `settings_page.h`, không còn phụ thuộc
`data/config.html` trong SPIFFS. Điểm truy cập cài đặt dùng mật khẩu WPA2 ngẫu
nhiên hiện trên màn hình; địa chỉ là `http://192.168.4.1/settings`. Mật khẩu Wi-Fi
và API key để trống khi lưu sẽ giữ giá trị cũ; chỉ chọn Wi-Fi mở nếu thực sự
muốn xoá mật khẩu Wi-Fi đã lưu.

## Kiểm thử

Chạy trong checkout đã áp dụng bản vá, cần Clang và Python 3:

```sh
clang++ -std=c++17 -Wall -Wextra -Werror -fsanitize=address,undefined tests/lunar_calendar_test.cpp -o /tmp/weather-lunar-test
/tmp/weather-lunar-test
clang++ -std=c++17 -Wall -Wextra -Werror -fsanitize=address,undefined tests/weather_state_test.cpp -o /tmp/weather-state-test
/tmp/weather-state-test
clang++ -std=c++11 -Wall -Wextra -Werror -fsanitize=address,undefined -I tests/rtc_stubs tests/weather_rtc_test.cpp -o /tmp/weather-rtc-test
/tmp/weather-rtc-test
clang++ -std=c++11 -Wall -Wextra -Werror -fsanitize=address,undefined tests/weather_portrait_test.cpp -o /tmp/weather-portrait-test
/tmp/weather-portrait-test
python3 tests/preview/render_dashboard.py
python3 tests/preview/check_dashboard_cases.py
python3 tests/preview/render.py
python3 tests/preview/check_cases.py
python3 tests/test_monitor_cycles.py
python3 -B tests/check_cache_persistence.py
```

Kiểm thử monitor cần `pyserial` và hệ điều hành POSIX (macOS/Linux). Monitor
`tests/monitor_cycles.py` chỉ đọc, không đổi DTR/RTS, bỏ cờ `HUPCL` và giữ log
khởi động đang chờ. Ba kiểm thử kiểm tra cả PTY thật trên máy tính; không mở
cổng USB của thiết bị trong lúc chạy kiểm thử.
Kiểm thử lưu dữ liệu đệm lấy trực tiếp hàm hiện tại từ `weather_runtime.h`,
giả lập kích thước cũ trên handle ghi và lỗi đọc lại; dữ liệu cũ phải được giữ
nguyên nếu bước xác minh không đạt.

Xem thêm `tests/preview/README.md`. Trình xem trước tạo ảnh PGM, mã trung gian
và executable cục bộ; những tệp này không nằm trong bản vá. Script tạo font
`scripts/generate_vi_font.py` cần `freetype-py`, font Noto Sans Bold và tham số
`--font /duong-dan/NotoSans-Bold.ttf` khi chạy ngoài checkout BizReader.
Giấy phép font được giữ trong `NOTO_FONT_LICENSE.txt`.

Font đồng hồ chỉ chứa chữ số và dấu phân cách. Khi tạo lại font:

```sh
python3 scripts/generate_vi_font.py --font /duong-dan/NotoSans-Bold.ttf --size 80 --name NotoClock80B --characters='-0123456789:' > noto_clock_80b.h
python3 scripts/generate_vi_font.py --font /duong-dan/NotoSans-Bold.ttf --size 16 --name NotoSansVi16B > noto_sans_vi_16b.h
```

## Manifest Nguồn

Danh sách này là đầu vào cho bước tạo lại bản vá, không tự quét các tệp build.

<!-- BEGIN SOURCE MANIFEST -->
```text
LilyGo-EPD-4-7-OWM-Weather-Display.ino
data/config.html
data/config.json
forecast_record.h
owm_credentials.h
platformio.ini
web.cpp
web.h
NOTO_FONT_LICENSE.txt
lunar_calendar.h
noto_sans_vi_8b.h
noto_sans_vi_10b.h
noto_sans_vi_12b.h
noto_sans_vi_16b.h
noto_clock_80b.h
partitions-bizreader.csv
settings_page.h
weather_dashboard.h
weather_rtc.h
weather_runtime.h
weather_state.h
weather_portrait.h
scripts/generate_vi_font.py
tests/lunar_calendar_test.cpp
tests/weather_rtc_test.cpp
tests/weather_state_test.cpp
tests/weather_portrait_test.cpp
tests/monitor_cycles.py
tests/test_monitor_cycles.py
tests/check_cache_persistence.py
tests/weather_cache_persistence_fixture.cpp
tests/rtc_stubs/Wire.h
tests/preview/Arduino.h
tests/preview/epd_driver.h
tests/preview/host.hpp
tests/preview/fixture.hpp
tests/preview/dashboard_fixture.hpp
tests/preview/render.py
tests/preview/render_dashboard.py
tests/preview/check_cases.py
tests/preview/check_dashboard_cases.py
tests/preview/README.md
```
<!-- END SOURCE MANIFEST -->

## Tạo Lại Bản Vá

Chạy từ checkout BizReader sau khi đã dừng chỉnh sửa nguồn. Script chỉ ghi bản
vá và clone tạm; không sửa nguồn đang dùng hoặc index của hai checkout. Các
trường bí mật được xoá trong **bản sao tạm**, kể cả khi cấu hình nguồn đã đổi.

```sh
node <<'NODE'
const fs = require('fs'), path = require('path'), os = require('os');
const {execFileSync} = require('child_process');
const root = process.cwd();
const source = path.join(root, 'build/weather-display-web');
const output = path.join(root, 'patches/weather-dashboard');
const base = '3aea8d0a8c8a024291bba38e6da805f02acbb188';
const readme = fs.readFileSync(path.join(output, 'README.md'), 'utf8');
const manifest = readme.match(/<!-- BEGIN SOURCE MANIFEST -->\s*```text\n([\s\S]*?)\n```/)[1].split('\n');
const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'weather-dashboard-patch-'));
const git = (...args) => execFileSync('git', ['-C', temp, ...args], {maxBuffer: 16 * 1024 * 1024});
try {
  execFileSync('git', ['clone', '--quiet', '--no-checkout', '--no-hardlinks', source, temp]);
  git('checkout', '--quiet', '--detach', base);
  for (const name of manifest) {
    const target = path.join(temp, name);
    fs.mkdirSync(path.dirname(target), {recursive: true});
    fs.copyFileSync(path.join(source, name), target);
    if (name === 'NOTO_FONT_LICENSE.txt')
      fs.writeFileSync(target, fs.readFileSync(target, 'utf8').replace(/\r\n/g, '\n').replace(/[ \t]+$/gm, ''));
  }
  const jsonPath = path.join(temp, 'data/config.json');
  const config = JSON.parse(fs.readFileSync(jsonPath, 'utf8'));
  config.WLAN.ssid = ''; config.WLAN.password = ''; config.OpenWeather.apikey = '';
  fs.writeFileSync(jsonPath, JSON.stringify(config, null, 2) + '\n');
  const headerPath = path.join(temp, 'owm_credentials.h');
  let header = fs.readFileSync(headerPath, 'utf8');
  for (const key of ['ssid', 'password', 'apikey']) {
    const expression = new RegExp('(String\\s+' + key + '\\s*=\\s*)"(?:[^"\\\\]|\\\\.)*"');
    if (!expression.test(header)) throw new Error('Missing credential declaration: ' + key);
    header = header.replace(expression, '$1""');
  }
  fs.writeFileSync(headerPath, header);
  git('add', '-N', '--', ...manifest);
  const patch = git('diff', '--binary', '--no-ext-diff', base, '--', ...manifest);
  fs.writeFileSync(path.join(output, 'weather-dashboard.patch'), patch);
  console.log('Generated sanitized source patch: ' + manifest.length + ' files, ' + patch.length + ' bytes.');
} finally {
  fs.rmSync(temp, {recursive: true, force: true});
}
NODE
```

Sau khi tạo lại, áp dụng bản vá vào một checkout sạch của commit nền bằng
`git apply --check`, rồi chạy lại build và các kiểm thử cần thiết. Không xem
việc tạo bản vá thành công là bằng chứng firmware đã chạy trên thiết bị.
