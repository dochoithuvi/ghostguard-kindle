# DCPRO IntentShield™ — 1.1 Final

**YOUR INTENT. YOUR CONTROL.**

Phát triển bởi **Dochoithuvi**. Giải pháp hỗ trợ đọc sách trên Kindle gặp tình trạng ghost touch (loạn cảm ứng) khi dùng KOReader và ZenOS.

**[Tải OneClick (.SH)](https://github.com/dochoithuvi/ghostguard-kindle/releases/download/intentshield-v1.1.0/DCPRO_IntentShield_OneClick_Install.sh)** · [Bản ZIP](https://github.com/dochoithuvi/ghostguard-kindle/releases/download/intentshield-v1.1.0/DCPRO_IntentShield_1.1_Final_OneClick.zip) · [Release](https://github.com/dochoithuvi/ghostguard-kindle/releases/tag/intentshield-v1.1.0)

## Thiết bị
| Model | Tình trạng |
| --- | --- |
| Kindle Basic 2022 | Đã thử trên máy thật |
| Kindle Basic 2024 | Đã thử trên máy thật |
| Kindle Paperwhite 4 (10th gen, 2018) | Hỗ trợ thử nghiệm, chưa xác nhận trên máy thật |
| Kindle Basic 2019 (10th gen) | Hỗ trợ thử nghiệm, chưa xác nhận trên máy thật |

## Tính năng
- OneClick tự nhận diện model, cài KOReader và ZenOS khi cần, tự mở KOReader khi hoàn tất.
- Global Shield và Auto Resume, hạn chế thao tác cảm ứng ngoài ý muốn.
- Tra từ điển bằng bốn hướng vuốt chéo theo vùng hỗ trợ; mở Aa, mục lục, bookmark và ghi chú qua Page Browser.
- Gesture Guide minh họa 5 trang; tắt bảo vệ bằng xác nhận trong plugin, không còn gesture thoát.
- Đồng bộ bản quyền tự động khi có Wi-Fi; tự lưu báo cáo cục bộ.

## Cài đặt
Yêu cầu Kindle đã jailbreak, SH Integration có quyền root, Wi-Fi, KPM (`;kpm`) nếu chưa cài KOReader. KOReader 2026.03+ và ZenOS 4.3+ có cấu trúc tương thích; bộ cài kiểm tra trước khi áp dụng, không đảm bảo mọi phiên bản tương lai.

1. Sao lưu dữ liệu, tắt GhostGuard cũ (nếu có), thoát KOReader.
2. Tải file SH (nếu tải ZIP, giải nén lấy SH), chép vào `documents`, ngắt USB và kết nối Wi-Fi.
3. Chạy bằng SH Integration root, chờ hoàn tất 9 bước.
4. OneClick tự mở KOReader và tự xóa file cài nếu có thể. Mở DCPRO IntentShield™ từ Navbar hoặc menu plugin.
5. License hợp lệ được tự đồng bộ khi có Wi-Fi. Nếu cần, vào License → Đồng bộ license online → Kiểm tra license. License RSA v4 hiện có được giữ nguyên.
6. Trên các model thử nghiệm, lần tự kích hoạt chạy thử 60 giây; kiểm tra thao tác rồi chọn Global Shield để bật liên tục.

## Cách sử dụng
| Cử chỉ | Chức năng |
| --- | --- |
| Vuốt ngang trong sách | Lật trang |
| Vuốt ngang và nhấc tại mục | Chọn mục trong menu/thư viện |
| Vuốt dọc | Cuộn danh sách |
| Vuốt dọc dài trong sách | Mở menu |
| Vuốt từ mép dưới lên (ngoài 1/4 trái) | Mở Page Browser, tab Aa |
| Vuốt chéo và nhấc tại từ | Tra từ điển theo vùng hỗ trợ |

Xem Gesture Guide trong plugin. Tra từ điển ưu tiên sách văn bản reflowable có từ điển đã cài. Tab Annotations cần bật trong cấu hình Page Browser nếu đang ẩn. Không dùng chạm đơn thông thường khi Shield hoạt động.

## Lưu ý và cứu hộ
- Auto Boot vẫn thử nghiệm, chỉ chuẩn bị trên Basic 2022 firmware chính xác 5.18.6 khi preflight thành công; không tự bật. Firmware khác và model khác chưa hỗ trợ.
- Dừng bảo vệ bằng menu plugin và xác nhận; khi mở lại KOReader, Auto Shield có thể bật lại theo cấu hình.
- Cứu hộ qua USB: tạo file rỗng `DISABLE_INTENTGATE` và `DISABLE_INTENTSHIELD_BOOT` ở gốc Kindle, xóa `ENABLE_INTENTSHIELD_GLOBAL` và `ENABLE_INTENTSHIELD_BOOT`; reboot nếu cần. Nút nguồn dừng phiên nhưng Auto Resume có thể bật lại. USB có thể không hoạt động khi máy treo.
- Báo cáo nằm ở `GhostGuard_Reports/IntentGate/`, tự ghi cục bộ, không gửi online. Không đăng công khai thông tin định danh.
- Đây không phải sửa phần cứng và không bảo vệ giao diện Kindle gốc. Không bật đồng thời GhostGuard cũ.

[Releases](https://github.com/dochoithuvi/ghostguard-kindle/releases) · [Issues](https://github.com/dochoithuvi/ghostguard-kindle/issues)
