# DCPRO IntentShield™ — 1.0 Final

**YOUR INTENT. YOUR CONTROL.**

Phát triển bởi **Dochoithuvi** · Giải pháp hỗ trợ đọc sách trên Kindle Basic 2022 gặp tình trạng ghost touch (loạn cảm ứng).

[![Release](https://img.shields.io/badge/release-1.0%20Final%20r3-238636)](https://github.com/dochoithuvi/ghostguard-kindle/releases/tag/intentshield-v1.0.0-r3)
![Device](https://img.shields.io/badge/Kindle-Basic%202022-333333)
![ZenOS](https://img.shields.io/badge/ZenOS-4.3%2B-blue)

**[Tải OneClick Installer (.SH)](https://github.com/dochoithuvi/ghostguard-kindle/releases/download/intentshield-v1.0.0-r3/DCPRO_IntentShield_OneClick_Install.sh)** · [Bản ZIP dự phòng và thông tin phát hành](https://github.com/dochoithuvi/ghostguard-kindle/releases/tag/intentshield-v1.0.0-r3)

## Tính năng

- Hạn chế thao tác ngoài ý muốn trong ZenOS, thư viện, trang sách và các menu được hỗ trợ.
- Vuốt để chọn mục, cuộn hoặc lật trang.
- Global Shield, Auto Resume và Auto Boot (thử nghiệm).
- OneClick tự cài KOReader, ZenOS và IntentShield khi cần; hiển thị tiến trình, tự mở KOReader sau khi hoàn tất.
- Tự đồng bộ và kích hoạt bản quyền hợp lệ khi có Wi-Fi.

## Yêu cầu

- Kindle Basic 2022 đã jailbreak.
- KPM (`;kpm`) nếu chưa có KOReader; SH Integration có quyền root.
- Wi-Fi để tải các thành phần cần thiết và kích hoạt online.
- KOReader 2026.03+ và ZenOS 4.3+ có cấu trúc tương thích. Bộ cài kiểm tra trước khi áp dụng; không đảm bảo mọi bản tương lai đều tương thích.

## Cài đặt OneClick

1. Sao lưu dữ liệu, dừng GhostGuard cũ (nếu có) và thoát hoàn toàn KOReader về giao diện Kindle.
2. Tải file `DCPRO_IntentShield_OneClick_Install.sh` ở phần Release (nếu tải ZIP, giải nén lấy file SH).
3. Chép file SH vào thư mục `documents` của Kindle. Ngắt kết nối USB, kết nối Wi-Fi.
4. Mở file bằng SH Integration có quyền root và đợi đủ 9 bước.
5. Khi cài thành công, OneClick tự mở KOReader / ZenOS và tự xóa file cài khỏi thư viện nếu có thể.
6. Mở **DCPRO IntentShield™** trong Navbar hoặc menu plugin. Nếu đã có bản quyền hợp lệ, Global Shield và Auto Resume tự bật khi đủ điều kiện. Không bật đồng thời GhostGuard cũ.

Nếu chưa kích hoạt, chọn **License → Đồng bộ license online → Kiểm tra license** khi có Wi-Fi. License GhostGuard RSA v4 hợp lệ vẫn được hỗ trợ. Nếu đã dùng ZenOS trước đó, có thể cần thêm shortcut vào Navbar và chọn Readerly R cỡ 18 trong Zen Settings.

## Cách sử dụng

| Thao tác | Cách thực hiện khi Global Shield bật |
| --- | --- |
| Chọn sách hoặc mục menu | Vuốt ngang, nhấc tay tại mục cần chọn |
| Cuộn danh sách | Vuốt dọc ở giữa màn hình |
| Lật trang sách | Vuốt trái / phải |
| Mở menu khi đọc | Vuốt dọc dài (từ 300 px) ở giữa màn hình |
| Thoát Shield | Hai nét vuốt dọc dài (từ 350 px) ngược chiều trong 8 giây, cả hai ở 1/4 màn hình bên trái |

Chạm đơn không hoạt động như bình thường khi Shield bật. Auto Boot là tính năng thử nghiệm, chỉ bật sau khi kiểm tra Global Shield và phương án cứu hộ. Nếu kiểm tra tương thích không đạt, không ép bật Auto Boot.

## Cứu hộ và lưu ý

Nếu khó thao tác, dùng nút nguồn để dừng phiên bảo vệ. Khi có thể truy cập USB, tạo hai file rỗng tại gốc Kindle:

```text
DISABLE_INTENTGATE
DISABLE_INTENTSHIELD_BOOT
```

Xóa `ENABLE_INTENTSHIELD_GLOBAL` và `ENABLE_INTENTSHIELD_BOOT`, khởi động lại nếu cần. USB có thể không khả dụng khi máy treo. Chỉ xóa marker cứu hộ khi sẵn sàng bật lại.

IntentShield hỗ trợ giảm thao tác ngoài ý muốn, không sửa chữa phần cứng cảm ứng và không bảo vệ giao diện Kindle gốc. Auto Boot chưa được xác nhận trên mọi thiết bị. Log hỗ trợ nằm trong `GhostGuard_Reports/IntentGate/`; không đăng công khai thông tin nhận dạng thiết bị.

---

**Dochoithuvi** · [Các bản phát hành](https://github.com/dochoithuvi/ghostguard-kindle/releases) · [Báo lỗi](https://github.com/dochoithuvi/ghostguard-kindle/issues)

KindleForge: [KPM manifest](manifest.v2.json). Các bản GhostGuard cũ được lưu trong lịch sử dự án.
