# BizTransfer và BizSync v2

Firmware LilyGo dùng hai đường truyền có mục đích riêng:

- **BLE Sync v2**: tiến độ đọc, ghi chú, việc cần làm, lịch, thời tiết, cấu hình
  nền nghỉ và cấu hình thiết bị (settings + mạng Wi-Fi).
- **Wi-Fi/HTTP**: sách và ảnh BMP lớn; WebDAV vẫn là đường dự phòng.

BLE chỉ bật khi người dùng mở **Truyền tệp > Kết nối App**. Liên kết phải được
mã hóa: firmware dùng pairing "Just Works" (bonding + LE Secure Connections,
không passkey); Android tự khởi tạo ghép đôi khi gặp lỗi thiếu mã hóa. Thoát
màn hình hoặc hết thời gian chờ sẽ tắt radio.

## BLE GATT

| Thành phần | UUID | Thuộc tính |
| --- | --- | --- |
| Service | `7d2f1000-8d4f-4f5b-a8d0-53b495a9b001` | Advertise |
| Command | `7d2f1001-8d4f-4f5b-a8d0-53b495a9b001` | Write (mã hóa) |
| Status | `7d2f1002-8d4f-4f5b-a8d0-53b495a9b001` | Read/notify (mã hóa) |
| Info | `7d2f1003-8d4f-4f5b-a8d0-53b495a9b001` | Read (thuần văn bản) |
| Sync RX | `7d2f1004-8d4f-4f5b-a8d0-53b495a9b001` | Write (mã hóa) |
| Sync TX | `7d2f1005-8d4f-4f5b-a8d0-53b495a9b001` | Read (mã hóa) |

Info trả `protocol: 2`. Info cố ý không mã hóa: giá trị là chuỗi mô tả giao
thức tĩnh, không chứa bí mật, nên đọc được trước khi ghép đôi phục vụ dò tìm
và chẩn đoán. Notify của Status chỉ được gửi tới các liên kết đã mã hóa
(CCCD của NimBLE không bị READ_ENC chặn). Command và Status tiếp tục tương
thích với BizTransfer v1. Mọi lệnh có `request`; firmware phản hồi cùng mã để
App không nhận nhầm trạng thái cũ.

Mọi lệnh có thể kèm trường tùy chọn `now` (uint64, mili-giây epoch — đồng hồ
của App). Nếu đồng hồ thiết bị chưa được đặt, firmware nhận giá trị này làm giờ
hệ thống để `updatedAt` là thời gian thật; đồng hồ đã hợp lệ thì bỏ qua. Khi
nhận đồng hồ, firmware chạy một lần di trú: các bản ghi tiến độ mang dấu thời
gian bộ đếm (thời kỳ đồng hồ chết) được đóng dấu lại theo giờ thật, giữ nguyên
thứ tự tương đối; bản ghi `updatedAt == 0` giữ nguyên.

Khi phiên Wi-Fi đang mở (ready/complete), gửi lại `start` không khởi động lại
Wi-Fi: firmware nhận `request` mới và phát lại Status hiện tại (kèm
ip/port/token). `sync_pull` được phục vụ từ `idle` và `error`; khi còn phiên đồng bộ cũ
(`sync_receiving`/`sync_ready`) firmware hủy phiên đó và phục vụ lần kéo mới.
Ở các trạng thái bận `connecting`/`ready`/`uploading`/`complete` lệnh bị từ
chối (firmware vẫn cập nhật `request` và phát lại Status hiện tại).

## Đồng bộ BLE

App thực hiện một giao dịch hai pha:

1. Gửi `sync_pull`, đọc snapshot hiện tại của thiết bị qua Sync TX.
2. Hợp nhất từng mục theo `id` và `updatedAt`; tombstone mới hơn thắng dữ liệu cũ.
3. Gửi `sync_begin`, ghi các chunk theo thứ tự vào Sync RX, rồi gửi `sync_commit`.
4. Firmware chỉ ghi snapshot sau khi nhận đủ byte/chunk và trả snapshot đã lưu.

Khung nhị phân có header little-endian 4 byte:

```text
uint16 sequence | uint16 totalChunks | payload
```

Kích thước frame được điều chỉnh theo ATT MTU, tối đa 240 byte. Snapshot tối đa
48 KiB; riêng content tối đa 32 KiB, 40 ghi chú, 60 task, 60 sự kiện lịch,
80 tombstone ghi chú (`deleted.notes`), 120 tombstone task (`deleted.todos`)
và 100 tiến độ đọc.

Các lệnh:

```json
{"op":"sync_pull","request":"a1","frameSize":240}
{"op":"sync_begin","request":"a2","size":12345,"chunks":53}
{"op":"sync_commit","request":"a3"}
```

Status dùng thêm `sync_receiving` và `sync_ready`; ở trạng thái sẵn sàng có
`syncChunks` và `syncSize`.

Snapshot:

```json
{
  "protocol": 2,
  "content": {
    "version": 2,
    "updatedAt": 1786400000000,
    "notes": [{"id":"n1","title":"Ý tưởng","body":"...","updatedAt":1786400000000}],
    "todos": [{"id":"t1","title":"Đọc sách","done":true,"due":"Hôm nay","updatedAt":1786400000100}],
    "deleted": {"notes":[],"todos":[]},
    "events": [],
    "weather": {},
    "sleep": {"mode":"calendar"}
  },
  "progress": [{"filename":"book.epub","percentage":0.42,"spineIndex":2,"updatedAt":1786400000200,"pending":false}],
  "device": {
    "settings": {"uiTheme":1,"fontSize":1,"language":"VI"},
    "wifiSsids": ["NhaRieng","VanPhong"]
  }
}
```

Tiến độ từ App mới hơn được đặt `pending: true`; firmware áp dụng khi EPUB tương
ứng được mở. Khi thiết bị lưu trang mới, `updatedAt` tăng và lần sync sau sẽ đưa
vị trí đó về App.

### Cấu hình thiết bị (`device`)

`device` là object cấp cao nhất, ngang hàng `content` và `progress` (không tính
vào giới hạn 32 KiB của content).

**Chiều máy → App (pull)**: luôn có mặt (trừ `wifiScan` — tùy chọn).

- `settings`: đúng object JSON mà firmware lưu trong `settings.json`
  (`uiTheme`, `fontSize`, `orientation`, `language`, ...). Không chứa bí mật.
- `wifiSsids`: mảng SSID đã lưu — **chỉ tên mạng; mật khẩu chỉ đi chiều
  app→máy, không bao giờ trả về**.
- `wifiScan` (tùy chọn): kết quả lần quét Wi-Fi gần nhất trong phiên, chỉ có
  mặt khi đã có kết quả (xem mục Quét Wi-Fi bên dưới):

  ```json
  {"wifiScan": [{"ssid": "NhaRieng", "rssi": -55, "sec": true}]}
  ```

  Tối đa 15 mục (~1 KiB, nằm trong giới hạn 48 KiB của snapshot), sắp xếp theo
  sóng mạnh nhất trước; `sec` là `true` khi mạng có mật khẩu (authmode khác
  open). Kết quả bị xóa khi dịch vụ BLE tắt (thoát màn hình Kết nối App).

**Chiều App → máy (push)**: mọi khóa đều tùy chọn; thiếu `device` thì cấu hình
thiết bị giữ nguyên (App cũ không bị ảnh hưởng); khóa lạ bị bỏ qua.

```json
{
  "device": {
    "settings": {"fontSize":2},
    "wifiAdd": [{"ssid":"NhaRieng","password":"matkhau123"}],
    "wifiRemove": ["VanPhong"]
  }
}
```

- `settings`: object đầy đủ hoặc một phần; khóa vắng mặt giữ giá trị hiện tại.
  Giá trị ngoài khoảng bị kẹp/chuẩn hóa đúng như khi đọc `settings.json` (một
  đường code chung). Đổi `uiTheme` có hiệu lực ngay; các setting khác có hiệu
  lực từ màn hình kế tiếp (thiết bị không khởi động lại, không đụng phiên
  Wi-Fi đang chạy).
- `wifiAdd`: mỗi mục cần `ssid` 1..32 byte và `password` tối đa 63 byte (chuỗi
  rỗng = mạng mở). SSID đã có thì cập nhật mật khẩu; tối đa 8 mạng — vượt giới
  hạn thì mục mới bị từ chối (không xóa mạng cũ). Mục sai bị bỏ qua từng mục,
  không làm hỏng cả lần commit (giống chính sách của `progress`).
- `wifiRemove`: xóa theo SSID; SSID không tồn tại được bỏ qua.

Snapshot trả về sau `sync_commit` được dựng lại sau khi áp dụng, nên
`wifiSsids`/`settings` trong phản hồi phản ánh trạng thái mới.

Firmware validate toàn bộ snapshot trước khi ghi và thay thế từng file qua
`.part/.bak`. Lỗi cấu trúc (protocol/phiên bản sai, JSON hỏng, content sai
dạng) làm hỏng cả lần commit; riêng mục tiến độ không hợp lệ (tên quá dài,
trùng lặp, phần trăm sai) chỉ bị bỏ qua từng mục, phần còn lại vẫn được ghi.
Việc ghi `content.json` cùng nhiều file tiến độ chưa là một transaction xuyên
file; lỗi SD giữa vòng commit có thể cần chạy đồng bộ lại.

## Quét Wi-Fi qua BLE

Lệnh `wifi_scan` yêu cầu thiết bị quét mạng Wi-Fi xung quanh (để App hiển thị
danh sách mạng khi cấu hình `wifiAdd`):

```json
{"op":"wifi_scan","request":"a5","now":1786400000000}
```

- Chỉ được phép ở trạng thái `idle`. Mọi trạng thái khác — kể cả `ready`, vì
  ở đó `sync_pull` cũng bị từ chối nên App sẽ không lấy được kết quả quét —
  firmware không quét nhưng vẫn nhận `request` mới và phát lại Status hiện
  tại (cùng kiểu tái kết nối như `start`/`sync_pull`). Gửi lại khi đang quét
  chỉ phát lại Status.
- Quét chạy **bất đồng bộ** ở chế độ STA, không kết nối vào mạng nào. Nếu
  radio Wi-Fi đang tắt, firmware bật tạm để quét rồi **tắt lại** khi quét xong
  (trừ khi một phiên HTTP đang mở hoặc đang kết nối Wi-Fi).
- Kết quả: tối đa 15 mạng, khử trùng lặp theo SSID (giữ RSSI mạnh nhất), bỏ
  SSID ẩn/rỗng, sắp theo sóng mạnh nhất trước. SSID tối đa 32 byte.
- **Best-effort**: quét lỗi thì Status được phát lại **không có** trường
  `scan`; App không nên chờ vô hạn.

Khi quét xong, Status có thêm trường tùy chọn `"scan": <số mạng>` — chỉ xuất
hiện sau khi một lần quét đã hoàn tất trong phiên **và chỉ khi Status ở trạng
thái `idle`**: các Status phát lại trong trạng thái bận không mang trường này,
để kết quả của phiên trước không đánh lừa App gửi một `sync_pull` sẽ bị từ
chối. Trường bị xóa khi dịch vụ khởi động và khi một lần quét mới bắt đầu.
Danh sách chi tiết lấy qua `sync_pull`:
mục `device.wifiScan` của snapshot (xem trên). Kết quả chỉ là ảnh chụp tại
thời điểm quét — muốn dữ liệu mới, App gửi `wifi_scan` lại.

## Trạng thái trên màn hình thiết bị

Màn hình **Kết nối App** hiển thị trạng thái trực tiếp trong lúc App thao tác:
chờ App kết nối / App đã kết nối (dòng tiêu đề), và một dòng trạng thái theo
máy trạng thái của dịch vụ — đang kết nối Wi-Fi, sẵn sàng nhận sách, đang
nhận dữ liệu đồng bộ, đang đồng bộ, đang quét Wi-Fi, đã nhận sách. Khi đang
nhận sách qua HTTP, màn hình hiển thị tên tệp, thanh tiến độ và số byte
đã nhận/tổng. Lỗi hiển thị đúng chuỗi `message` của Status.

Vì màn hình e-ink, thiết bị chỉ vẽ lại khi trạng thái đổi; tiến độ tải được
giới hạn tối đa một lần vẽ mỗi ~2 giây hoặc mỗi bước 10%.

## Truyền sách và ảnh qua Wi-Fi

Lệnh `start` không nhận SSID/mật khẩu; firmware chỉ dùng Wi-Fi đã lưu trên máy.
Firmware ưu tiên mạng đã kết nối thành công gần nhất; nếu chưa từng kết nối
hoặc mạng đó không còn trong danh sách (ví dụ mạng chỉ được thêm qua
`wifiAdd`, hoặc mạng cũ đã bị xóa), firmware dùng mạng đầu tiên trong danh
sách đã lưu (thứ tự thêm vào). Chỉ khi máy chưa lưu mạng nào, `start` mới trả
lỗi "Hãy lưu Wi-Fi trên BizReader trước". Sau khi kết nối, Status trả IP và
token ngắn hạn. App dùng:

```http
PUT /Ebook/<filename>.epub
PUT /sleep.bmp
Content-Length: <bytes>
X-Content-SHA256: <64 hex chars>
X-BizReader-Token: <token>
```

Sách được ghi vào `.part`, kiểm tra kích thước và SHA-256 rồi mới đổi tên. File
tối đa 128 MiB và nhận `.epub`, `.txt`, `.xtc`, `.xtch`, `.bmp`. Các endpoint
HTTP content/progress v1 vẫn được giữ để tương thích, nhưng App 0.7 dùng BLE cho
dữ liệu nhỏ.

Khi mở Kết nối App lần đầu sau khởi động, firmware quét `/Ebook` (và
`/sleep.bmp`): xóa `.part` mồ côi do mất điện; `.bak` được đổi tên về file gốc
nếu file gốc đã mất, ngược lại bị xóa.

Status không còn trường `sha256`: App xác minh sách qua header
`X-Content-SHA256` và body phản hồi của lệnh PUT. Trường `filename` trong
Status được cắt còn tối đa ~96 byte UTF-8 (ký tự đặc biệt thay bằng `_`) để
JSON trạng thái luôn nằm trong giới hạn 512 byte của giá trị ATT. Lệnh `stop`
(hoặc hết thời gian chờ) đóng phiên và xóa `filename` của lần truyền trước
khỏi Status; App không nên dựa vào trường này sau khi phiên đã đóng.

## Ranh giới tin cậy

Thiết kế coi khoảng cách gần và thao tác bật **Kết nối App** trên máy là ranh
giới tin cậy. Mọi characteristic trừ Info yêu cầu liên kết BLE đã mã hóa
(pairing "Just Works"), và notify chỉ gửi tới liên kết đã mã hóa, nên token
HTTP và snapshot không còn đọc được qua BLE thuần văn bản. Tuy vậy Just Works không chống MITM chủ động: một client ở gần trong cửa
sổ Kết nối App vẫn có thể ghép đôi, đọc/ghi snapshot hoặc kích hoạt phiên
Wi-Fi.

Mật khẩu Wi-Fi nay đi qua BLE **một chiều app→máy** (mục `device.wifiAdd`) và
**bắt buộc** liên kết đã mã hóa nêu trên — Sync RX từ chối ghi khi chưa mã
hóa. Chiều máy→app chỉ trả SSID, không bao giờ trả mật khẩu. Vì Just Works
không chống MITM chủ động, chỉ nên đẩy mật khẩu trong môi trường riêng tư;
firmware vẫn giữ màn hình nhập Wi-Fi trên máy làm đường dự phòng khi không có
App. Đây chưa phải cơ chế xác thực phù hợp cho môi trường công cộng có yêu cầu
bảo mật cao.
