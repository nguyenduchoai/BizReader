# BizTransfer và BizSync v2

Firmware LilyGo dùng hai đường truyền có mục đích riêng:

- **BLE Sync v2**: tiến độ đọc, ghi chú, việc cần làm, lịch, thời tiết và cấu hình nền nghỉ.
- **Wi-Fi/HTTP**: sách và ảnh BMP lớn; WebDAV vẫn là đường dự phòng.

BLE chỉ bật khi người dùng mở **Truyền tệp > Kết nối App**, không bonding và
không yêu cầu passkey. Thoát màn hình hoặc hết thời gian chờ sẽ tắt radio.

## BLE GATT

| Thành phần | UUID | Thuộc tính |
| --- | --- | --- |
| Service | `7d2f1000-8d4f-4f5b-a8d0-53b495a9b001` | Advertise |
| Command | `7d2f1001-8d4f-4f5b-a8d0-53b495a9b001` | Write |
| Status | `7d2f1002-8d4f-4f5b-a8d0-53b495a9b001` | Read/notify |
| Info | `7d2f1003-8d4f-4f5b-a8d0-53b495a9b001` | Read |
| Sync RX | `7d2f1004-8d4f-4f5b-a8d0-53b495a9b001` | Write |
| Sync TX | `7d2f1005-8d4f-4f5b-a8d0-53b495a9b001` | Read |

Info trả `protocol: 2`. Command và Status tiếp tục tương thích với BizTransfer
v1. Mọi lệnh có `request`; firmware phản hồi cùng mã để App không nhận nhầm
trạng thái cũ.

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
48 KiB; riêng content tối đa 32 KiB, 40 ghi chú, 60 task và 100 tiến độ đọc.

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
  "progress": [{"filename":"book.epub","percentage":0.42,"spineIndex":2,"updatedAt":1786400000200,"pending":false}]
}
```

Tiến độ từ App mới hơn được đặt `pending: true`; firmware áp dụng khi EPUB tương
ứng được mở. Khi thiết bị lưu trang mới, `updatedAt` tăng và lần sync sau sẽ đưa
vị trí đó về App.

Firmware validate toàn bộ snapshot trước khi ghi và thay thế từng file qua
`.part/.bak`. Việc ghi `content.json` cùng nhiều file tiến độ chưa là một
transaction xuyên file; lỗi SD giữa vòng commit có thể cần chạy đồng bộ lại.

## Truyền sách và ảnh qua Wi-Fi

Lệnh `start` không nhận SSID/mật khẩu; firmware chỉ dùng Wi-Fi đã lưu trên máy.
Sau khi kết nối, Status trả IP và token ngắn hạn. App dùng:

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

## Ranh giới tin cậy

Thiết kế coi khoảng cách gần và thao tác bật **Kết nối App** trên máy là ranh
giới tin cậy. Một BLE client ở gần trong cửa sổ này có thể đọc/ghi snapshot hoặc
kích hoạt phiên Wi-Fi. Mật khẩu Wi-Fi không đi qua BLE. Đây chưa phải cơ chế xác
thực phù hợp cho môi trường công cộng có yêu cầu bảo mật cao.
