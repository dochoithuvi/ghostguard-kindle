# DCPRO IntentShield™ 1.1 Beta — Basic 2024

Nhánh thử nghiệm riêng cho Kindle Basic 2024; vẫn hỗ trợ Basic 2022. Bản Beta 1 đã được chủ thiết bị xác nhận hoạt động trên Basic 2024. Beta 2 bổ sung thao tác khi đang đọc sách và cần kiểm thử trên máy thật.

## Cài đặt
Tải bộ cài Beta 2 trong artifact của GitHub Actions trên nhánh này. Chép SH vào documents, thoát KOReader, kết nối Wi-Fi, chạy SH Integration (root). Basic 2024 tự bảo vệ thử 60 giây; nếu ổn, chọn Global Shield liên tục + Auto Resume.

## Cử chỉ
- Vuốt ngang: lật trang; khi mở menu, vuốt ngang và nhấc tại mục cần chọn.
- Vuốt từ mép dưới (ngoài 1/4 bên trái) lên khoảng 300 px: mở ZenOS Page Browser tab Aa, nơi có chỉnh font, bố cục, mục lục, bookmark, highlight và các tab được bật.
- Vuốt chéo lên-phải, nhấc tay tại từ cần tra: từ điển KOReader. Beta 2 hỗ trợ sách văn bản reflowable và yêu cầu đã cài từ điển.
- Vuốt dọc dài ở vùng đọc: mở menu như trước.
- Hai nét vuốt dọc dài ngược chiều ở 1/4 bên trái: thoát Shield.

Tab Annotations riêng cần bật trong thiết lập Page Browser của ZenOS nếu đang ẩn. Không thay đổi cấu hình của ZenOS đã cài. Không cho phép tap/hold tự do khi Shield bật. Auto Boot Basic 2024 chưa hỗ trợ. Nếu khó thao tác, tạo DISABLE_INTENTGATE và DISABLE_INTENTSHIELD_BOOT tại gốc Kindle qua USB.

Không thay đổi registry, private key hay bản phát hành r3.
