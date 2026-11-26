# r3 candidate — chưa phát hành

Yêu cầu: Kindle Basic 2022 đã jailbreak. OneClick cần Wi-Fi, KPM và SH Integration quyền root.

- Build: `python3 packages/intentshield/build_oneclick.py` (tạo ZIP và file SH OneClick chứa payload).
- Chạy file OneClick qua SH Integration; script dùng KPM CLI cài KOReader nếu thiếu, tải ZenOS 4.3.2 từ upstream và xác minh SHA-256, cài IntentShield từ payload nhúng.
- Chưa xác minh ZenOS có package riêng trong KPM; do đó không tuyên bố ZenOS được cài bởi KPM. Không ghi đè KOReader/ZenOS hiện có. Nếu có Zen UI/Project: Title/SimpleUI, xử lý xung đột theo hướng dẫn upstream.
- ZenOS mới: mặc định Library, Home, DCPRO IntentShield™ (tia sét); font giao diện Library/Home Readerly R cỡ 18. ZenOS hiện có giữ nguyên cấu hình; thêm shortcut qua Zen Settings > Interface > Navbar > Tabs > Add > Plugin Menu; chọn DCPRO IntentShield™, icon tia sét. Font Library chọn Readerly R 18.
- Auto Boot mặc định tắt; menu IntentShield gọi script preflight cũ. Tắt từ menu chỉ tắt lần boot sau, không tắt Shield đang chạy. Script DISABLE_AUTOBOOT vẫn là cứu hộ toàn bộ. Giữ kiểm tra firmware 5.18.6 trong code và điều kiện kỹ thuật; không vượt preflight.
- Cần kiểm thử mock, CI, kiểm thử installer KPM, quyền root, menu ZenOS, font hiển thị, license và reboot trên Kindle thật trước khi phát hành. Không ghi đè release r2.
