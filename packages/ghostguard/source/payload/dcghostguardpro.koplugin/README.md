# DCPRO GhostGuard v0.5.0 Final Hotfix 1

## Activation

GhostGuard only starts observation, calibration or protection when this file exists and validates:

```text
/mnt/us/koreader/plugins/dcghostguardpro.koplugin/license.key
```

The verifier is compatible with **DCPRO License Manager v3 Offline JSON**. It checks format, serial, issue date, expiry, feature grant (`ultimate` or `ghostguard`), SHA-256 signature and persistent clock rollback state. A legacy key may be copied once into the plugin folder for migration, but the final canonical location is the plugin folder above.

STOP, status, SAFE_MODE and Cloud diagnostics remain reachable even when activation fails.

## Customer workflow

1. Install the bundle and put the per-device `license.key` in the plugin folder.
2. Open KOReader. If no approved profile exists, GhostGuard automatically starts background learning.
3. The customer reads and uses the device normally. Learning progress accumulates across KOReader sessions.
4. When enough abnormal contacts are collected, GhostGuard shows **Hoàn tất thiết lập bảo vệ**.
5. One confirmation approves the profile, enables Auto Protect and starts two conservative probation sessions.

## Safe Input

KOReader consumes every complete raw touch frame before GhostGuard may suppress the resulting gesture. Hook/observer faults fail open, restore the original handler and write `RUNTIME_FAULT.txt`. Quarantine remains disabled. Probation uses a lower circuit-breaker threshold.

## SimpleUI

GhostGuard registers a `Tools` tab after Home through SimpleUI's external Quick Action API. It does not patch SimpleUI source files. The plugin key is `dcghostguardpro`.

## Cloud

Closed sessions are queued under `/mnt/us/.dcpro_ghostguard/cloud_outbox/`. Empty packages are refused. Reports collect session logs, active profile, KOReader crash/runtime logs and license status. The private RootInstall contains the configured Apps Script URL/token and must not be redistributed publicly.


CHÍNH SÁCH LICENSE CUỐI
- Chỉ kích hoạt khi file tồn tại đúng tại /mnt/us/koreader/plugins/dcghostguardpro.koplugin/license.key
- Không tự động nhập license từ tool cũ.
- Bản phát hành không đóng sẵn license.key; mỗi máy dùng key riêng theo serial.
- Khi cập nhật, không xóa thư mục plugin nếu chưa sao lưu license.key.


## Hotfix 3 — ExitTrace / Wrapper / Engine isolation

- Làm sạch NUL/control byte trong `/proc/usid`.
- Bật PROTECT_WRAPPER PASS_THROUGH trong Observe/Calibration.
- Đóng widget không còn dừng engine bằng lý do giả `koreader-exit`.
- Ghi `EXIT_REASON_DETAIL.txt`, `KOReader_EXIT_TRACEBACK.txt`, `EXIT_HISTORY.log`.
- Bắt `UIManager.quit/restart/reboot/powerOff`, `os.exit` và runtime fault.
- Giữ nguyên Hotfix 2: tháo wrapper trước suspend, bật lại sau resume theo fail-open.
