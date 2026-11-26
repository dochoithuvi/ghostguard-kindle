DCPRO IntentShield™ 1.0 Final — Global Protection (Auto Boot EXPERIMENTAL)
By Dochoithuvi | Kindle Basic 2022 (KindleBasic4), portrait 1072×1448
Auto Boot: CHỈ FW 5.18.6 đã xác minh, root SH Integration/SSH.
Cần KOReader đã cài (ưu tiên 2026.07), ZenOS 4.3.2 đang chạy được.
Không tải mạng; không thay ZenOS/KOReader, license/profile. Có script thay thế plugin GhostGuard cũ riêng, phục hồi được.

CÀI ĐẶT VÀ THỬ THỦ CÔNG TRƯỚC
1. Sao lưu Kindle. Thoát hoàn toàn KOReader về Kindle gốc. Tắt Protect của GhostGuard cũ.
2. Giải nén, chép NỘI DUNG COPY_TO_KINDLE_ROOT vào gốc Kindle.
3. Chạy documents/GhostGuard_IntentGate_INSTALL.sh qua SH Integration.
   Tự sao lưu plugin cũ vào GhostGuardIntentTrial/backup-before-1.0-<timestamp>-<pid>.
   Nếu backup đã tồn tại, bộ cài từ chối ghi đè; không xóa backup.
4. Vào ZenOS, chọn DCPRO IntentShield 1.0 trong Launcher/Plugin Menu.
   Kiểm tra License; nếu cần, đồng bộ online qua Wi-Fi hoặc dùng license.key RSA v4.
   Bật Global Shield — liên tục + Auto Resume. Dùng thao tác thoát hoặc nút nguồn để dừng.
   Menu chỉ còn Global Shield, Dừng, Trạng thái, License và Báo cáo & hướng dẫn.

CÁCH DÙNG GLOBAL SHIELD (khác cảm ứng thông thường)
- Home, Library, các menu/hộp thoại: vuốt NGANG có chủ đích, nhấc tay tại
  mục muốn chọn. Bộ lọc gửi tap nội bộ tại điểm cuối, không tiêm evdev.
  Vuốt DỌC giữa màn hình để gửi swipe cuộn; widget có thể không hỗ trợ swipe.
- Trong trang sách: vuốt ngang trái/phải để lật trang; vuốt dọc dài >=300 px
  ở giữa màn hình mở menu Reader. Chạm đơn/hold/pan gốc bị chặn.
- THOÁT: vuốt dọc dài >=350 px lên rồi xuống (hoặc ngược lại) trong 8 giây,
  CẢ HAI nét bắt đầu/kết thúc ở 1/4 bên trái màn hình. Không cuộn từ vùng này.
- Nút nguồn: dừng khi ngủ; chế độ continuous+resume thử bật lại sau 5 giây.
  Nhấn nguồn lần nữa trong 5 giây để hủy; có khoảng trống không được bảo vệ.
- Nếu khó điều khiển: nhấn nút nguồn để ngủ và hủy tự resume bằng lần nhấn tiếp theo trong 5 giây chờ. Hoặc kết nối USB
  và tạo file rỗng DISABLE_INTENTGATE ở gốc Kindle. Sau đó reboot nếu cần.
  Marker được kiểm tra mỗi ~2 giây khi KOReader chạy; không bảo đảm USB xuất hiện
  nếu hệ thống treo. Có thể phải khởi động lại bằng nút nguồn.

AUTO BOOT — CHỈ BẬT SAU KHI GLOBAL THỦ CÔNG ỔN ĐỊNH
1. Thoát KOReader. Chạy IntentShield_ENABLE_AUTOBOOT.sh (cần quyền root).
   Script kiểm tra model/firmware, Upstart framework running, checksum, ZenOS
   và plugin đã cài. Không tự reboot, không dừng Amazon framework.
   Cài một job /etc/upstart/dcpro-intentshield-boot.conf, không respawn.
   Tạo ENABLE_INTENTSHIELD_BOOT + ENABLE_INTENTSHIELD_GLOBAL.
2. Xem GhostGuard_Reports/IntentGate/boot-install.log có SUCCESS; nếu FAIL
   thì xem boot.log, không ép bỏ qua kiểm tra firmware.
3. Khởi động lại Kindle. Job thử khởi chạy KOReader --asap một lần mỗi boot,
   chờ user store, kiểm tra marker, chờ 20 giây sau preflight. ZenOS phải đang
   được bật trong KOReader; plugin Global tự bật ~1 giây sau init. Không bảo vệ
   stock UI, giai đoạn boot/loading, trước plugin init hoặc trong wake delay.
   Event 'started framework' là giả thuyết cần xác nhận trên Kindle thật;
   không đảm bảo job chạy hoặc ZenOS hiện đúng màn hình Home (KOReader có thể
   mở cuốn sách gần nhất theo thiết lập). Không đổi cấu hình khởi động KOReader.
4. Cứu hộ USB: xóa ENABLE_INTENTSHIELD_BOOT và ENABLE_INTENTSHIELD_GLOBAL;
   tạo DISABLE_INTENTSHIELD_BOOT và DISABLE_INTENTGATE. Reboot nếu cần.
   Script IntentShield_DISABLE_AUTOBOOT.sh làm điều này và gỡ đúng job nếu root.
   Không tự dừng KOReader đang chạy. Không xóa dữ liệu GhostGuard.
5. Muốn chỉ auto Global không auto boot: tự tạo ENABLE_INTENTSHIELD_GLOBAL
   ở gốc Kindle khi đã kiểm chứng, không tạo ENABLE_INTENTSHIELD_BOOT.

ROLLBACK: chạy IntentShield_DISABLE_AUTOBOOT.sh trước, thoát KOReader,
GhostGuard_IntentGate_ROLLBACK.sh. Khôi phục bản trước nếu có backup 1.0,
marker DISABLE_INTENTGATE vẫn còn để tránh tự chạy. Xóa thủ công khi muốn bật.

LOG: GhostGuard_Reports/IntentGate/ (install.log, *_GLOBAL.log, boot.log,
boot-install.log). ACTION là lệnh được cấp phép, không chứng minh widget xử lý.
Report không phân biệt tuyệt đối chạm thật/giả. Giới hạn 5000 dòng contact/phiên.

GIỚI HẠN: Global 0.5 đã được chủ máy Basic 2022 xác nhận hoạt động tốt; 1.0 giữ nguyên ngưỡng và hành động Global, chưa test lại trên Kindle thật. Auto Boot 0.5 bị từ chối trước khi cài, không phải boot thành công. Global sử dụng
UIManager và raw MT Type-B sau điều chỉnh driver. Tương thích ZenOS từng widget
chưa xác nhận; hộp thoại, bàn phím và widget đặc biệt có thể cần thao tác riêng.
Chỉ ngăn hành động từ gesture, không chữa phần cứng hay chặn mọi nguồn input.
Strict giữ nguyên ngưỡng 0.3; bổ sung tọa độ đầu/cuối vào kết quả. Không Fast
trong Global. Auto Boot có chỉnh một file Upstart hệ thống khi người dùng bật
riêng. Không chạy lại liên tục, không thay firmware, không vô hiệu framework.
Kiểm thử: Lua 5.4 local + mock KOReader; không phải LuaJIT/Kindle thật.

MIGRATION: Sau khi cài và test Global, thoát KOReader, chạy IntentShield_REPLACE_LEGACY.sh để chuyển plugin cũ vào backup ngoài plugins. Không xóa license, profile hay service chẩn đoán native read-only. IntentShield_RESTORE_LEGACY.sh khôi phục plugin cũ và vô hiệu IntentShield; không tự bật lại legacy autoboot.
AUTO BOOT FIX: Chạy IntentShield_BOOT_PROBE.sh và xem boot.log. Nguồn hệ thống ưu tiên; nếu chỉ có /mnt/us/system/version.txt chứa Kindle 5.18.6, kiểm tra Device Info trên Kindle rồi tạo file CONFIRM_INTENTSHIELD_FW_5.18.6 ở gốc USB chứa đúng 5.18.6 (một dòng). Không tạo nếu không đúng. Nếu nguồn hệ thống báo phiên bản khác, vẫn từ chối. Chưa xác thực Upstart trên máy thật.

1.0 Final — licensed revision: xác thực license GhostGuard RSA v4 và signed registry giữ nguyên. Bộ cài tự sao chép license.key hiện có từ plugin IntentShield, GhostGuard hoặc backup legacy đã ghi nhận; không gửi khóa cá nhân lên mạng. Sau khi kiểm tra license và Global Shield, chạy IntentShield_REPLACE_LEGACY.sh để ẩn plugin cũ bằng sao lưu. Không cần profile. Không có SimpleUI. Chưa kiểm thử bản tích hợp license trên Kindle thật.
