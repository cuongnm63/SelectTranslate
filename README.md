# Select Translate

App macOS chỉ chạy trên menu bar. Bôi đen text ở bất kỳ app nào sẽ hiện một nút nhỏ. Bấm nút đó, Claude sẽ dịch sang tiếng Việt và gợi ý 3 câu trả lời (thân mật, trung tính, trang trọng) viết bằng ngôn ngữ gốc.

## Yêu cầu

- macOS 13 trở lên
- Xcode hoặc Command Line Tools (`xcode-select --install`)
- Anthropic API key

## Chạy

```bash
cd SelectTranslate
make run        # build + đóng gói build/SelectTranslate.app + mở app
# hoặc
make install    # copy vào /Applications rồi mở
```

Lần đầu mở app:

1. macOS sẽ hỏi quyền **Accessibility**. Vào System Settings → Privacy & Security → Accessibility, bật **SelectTranslate**, rồi **thoát và mở lại app**.
2. Bấm icon 💬 trên menu bar, chọn **Nguồn**:
   - **Claude Code**: dùng gói Pro/Max đã đăng nhập trong `claude` CLI, không tốn tiền API, chậm hơn 2–4s mỗi lần. App tự tìm lệnh `claude`; bấm **Kiểm tra** để xác nhận. Nếu không tìm thấy, nhập đường dẫn (xem bằng `which claude`).
   - **API key**: dán key từ console.anthropic.com, bấm **Lưu** (lưu trong Keychain). Nhanh hơn, trả tiền theo token.
3. Bôi đen text, nút tròn sẽ hiện cạnh con trỏ. Bấm nút để xem bản dịch và gợi ý trả lời, mỗi mục có nút copy.

Phím tắt **⌥D**: dịch ngay vùng đang bôi đen, không cần bấm nút. **Esc** hoặc click ra ngoài để đóng popup.

## Chia sẻ cho người khác

```bash
make dmg      # → build/SelectTranslate-0.1.0.dmg (chạy được trên cả Apple Silicon và Intel)
```

Máy không có Xcode? Đẩy code lên GitHub rồi chạy workflow **Build DMG** (Actions → Run workflow), tải DMG ở mục Artifacts. Push tag `v0.1.0` thì DMG tự gắn vào Release.

**Không có Apple Developer ID (bản miễn phí):** người nhận sẽ thấy cảnh báo "cannot be opened". Cách mở:
- Kéo app vào Applications, mở 1 lần, sau đó vào System Settings → Privacy & Security → bấm **Open Anyway**; hoặc
- `xattr -dr com.apple.quarantine /Applications/SelectTranslate.app`

**Có Developer ID ($99/năm, mở được ngay không cảnh báo):**
```bash
xcrun notarytool store-credentials selecttranslate --apple-id you@x.com --team-id TEAMID
SIGN_IDENTITY="Developer ID Application: Cuong Nguyen (TEAMID)" NOTARY_PROFILE=selecttranslate make dmg
```
Trên GitHub Actions, thêm các secrets: `DEVELOPER_ID_P12` (file .p12 dạng base64), `DEVELOPER_ID_P12_PASSWORD`, `SIGN_IDENTITY`, `NOTARY_APPLE_ID`, `NOTARY_TEAM_ID`, `NOTARY_PASSWORD` (app-specific password).

Mỗi người dùng cần tự nhập **API key của họ** và tự cấp quyền Accessibility. Không nhúng key của bạn vào app vì ai cũng trích ra được.

Muốn có icon riêng: đặt file `Resources/AppIcon.icns`.

## Lưu ý khi rebuild

Nếu ký ad-hoc (mặc định), mỗi lần rebuild chữ ký sẽ đổi, nên macOS coi đó là app mới. Hậu quả: mất quyền Accessibility, và Keychain có thể hỏi lại quyền truy cập. Có 2 cách xử lý:

```bash
make reset-ax && make run                                  # cấp lại quyền mỗi lần

# hoặc ký bằng cert cố định (khuyên dùng khi dev lâu dài)
security find-identity -v -p codesigning                   # xem cert có sẵn
SIGN_IDENTITY="Apple Development: you@example.com (XXXX)" make run
```

Khi debug nhanh không cần file .app, có thể dùng `ANTHROPIC_API_KEY=sk-ant-... swift run`. Terminal cần được cấp quyền Accessibility thì cách này mới chạy.

## Cấu trúc

```
Sources/SelectTranslate/
├── SelectTranslateApp.swift      # MenuBarExtra + AppDelegate (wiring, phím tắt ⌥D)
├── Selection/
│   ├── SelectionMonitor.swift    # global mouse monitor: kéo / double-click → đọc selection
│   ├── SelectionReader.swift     # AX API, fallback ⌘C + khôi phục clipboard
│   └── HotKey.swift              # Carbon global hotkey
├── UI/
│   ├── FloatingPanel.swift       # NSPanel nonactivating (không cướp focus)
│   ├── PopupController.swift     # nút trigger + popup kết quả, vị trí trên màn hình
│   ├── TriggerButton.swift
│   ├── ResultView.swift          # bản dịch + gợi ý trả lời
│   └── SettingsView.swift        # UI trên menu bar
├── Claude/
│   ├── ClaudeClient.swift        # Messages API streaming (SSE)
│   ├── Prompt.swift              # system prompt + parser output dạng tag
│   └── TranslationSession.swift  # state của một lần dịch
└── Support/
    ├── AppSettings.swift         # UserDefaults + lịch sử
    └── Keychain.swift
```

## Giới hạn đã biết

- Không phát hành qua Mac App Store được, vì App Sandbox chặn Accessibility và việc giả lập phím. Nên phát hành bằng DMG đã sign và notarize.
- Ô password (Secure Input) không đọc được.
- Với app Electron, app sẽ dùng fallback ⌘C. Riêng VS Code, nhấn ⌘C khi không bôi đen gì sẽ copy cả dòng. Nếu thấy phiền, thêm `com.microsoft.VSCode` vào danh sách chặn.
