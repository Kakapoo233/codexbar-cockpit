# Windows tray client

Current candidate: Windows 0.1.0-alpha.5, adding recommendation-linked pace to the tray/floating client.
Local source validation and genuine Windows installer/native acceptance are recorded separately in
WORK_QUEUE.md and the corresponding pull request.

## Product contract

Keep the existing native macOS app. Add a Windows client in this repository with its own
application identity, AppData storage, build pipeline and installer. Initial verification targets
Windows 11 x64; other Windows versions and architectures are not supported claims until tested.

The proposed default is a notification-area tray icon opening one panel with Usage, Statistics,
Calendar, and Members & Devices. Settings belongs to that panel's settings entry. The user can instead
select the compact floating summary; both surfaces share one App owner. Closing or deactivating the panel returns to the tray;
an explicit Quit action terminates the app. Window placement must respect monitor work areas and DPI.

Windows tray icons have bounded image space rather than the Mac menu bar's variable-width text.
Represent numeric, bar and bottom-up filled-circle allowance modes with dynamic tray images and
an accessible tooltip containing the full daily percentage and weekly equivalent. Validate legibility
at supported DPI scales; never compress several selected modes into unreadable text.

## Proposed implementation

Reuse the MIT Codex Cockpit v0.3.4 Tauri 2 / React / Rust foundation at commit
`cefcbc9efe03071150431645b4ebb51e7faac574`, already pinned in UPSTREAM.md. Its source includes Windows
credential integration, Codex collectors, local usage, team synchronization and Windows installer CI.
The user approved reusing this Tauri toolchain. Dependencies remain isolated to windows/.

Place the client under `windows/`. Preserve upstream MIT attribution and document every imported
subtree. Use reviewed dependency locks and a separate Windows CI job. Remove upstream update feeds,
updater keys, repository links, application identifiers, floating-window restoration and automatic
cloud mutation behavior. Do not reuse upstream signing credentials or publish unsigned builds as
trusted releases. Initially produce reviewable CI artifacts; release publication is separate.

Do not compile the existing Swift UI as a Windows application. AppKit and SwiftUI implement the Mac
shell, while the Core's process/PTY/file-lock code still contains POSIX dependencies. Reuse typed
contracts and synthetic behavioral fixtures across implementations rather than pretending the
entire Core is portable.

## Parity work

| Area | Required implementation and acceptance |
| --- | --- |
| Desktop shell | Single instance, tray show/hide, bounded positioning, settings persistence, explicit quit, optional user-controlled login startup. |
| Daily planning | Port the current fork's full-local-day comfort-curve calculation, reset horizon, manual caps and actual-balance limit. Today remaining uses daily allocation as denominator; retain weekly equivalent and partial-data upper bounds. Do not revert to upstream's older intraday allocation. |
| Codex collection | Native Windows `CODEX_HOME` and home paths, account-scoped official quota observations, safe unavailable/stale states. Tokens must never be converted into official quota percentage. |
| Local history | Codex and Claude JSONL parsing, archived sessions, fork deduplication, timestamp/currency/coverage rules, selectable ranges and session receipt action. WSL roots require explicit selection and source deduplication. |
| Calendar | Day/week/month views with common typography, personal feedback, comfort curve and pinned reset announcements. Unknown days remain unknown. |
| Reset notices | Current verified reset source, dated confirmed banner and countdown, separately labeled estimates, notification opt-in and durable deduplication. |
| Team and devices | Existing self-hosted Cloudflare Worker v2 protocol, independent-source declaration, account binding, revision conflicts and Asia/Shanghai team day. Store credentials through Windows current-user protection; never in settings JSON. |
| Other providers | Inventory each provider and port authentication and collection separately. Expose only supported integrations; describe missing ones explicitly. Mac browser-cookie/Keychain/PTY collectors are not automatically portable. |
| Languages | Preserve the established app languages as translated features land. Keep any English-only tray preference scoped to the tray. |
| Personal sync | The existing Mac CloudKit permission problem remains separate. Windows does not inherit that integration. Choose and verify a cross-platform personal-sync protocol before exposing a working-sync claim. |

## Delivery gates

1. Shared synthetic fixtures verify advice, remaining allowance, reset windows, partial observations,
   calendar dates and history deduplication against the current Mac behavior.
2. Frontend and Rust tests run without real credentials or cloud writes. Permission failures and
   missing logs have explicit states; no mock data appears as live account data.
3. Windows CI compiles the actual native target and produces an installable package with fork-owned
   identity. Building the web frontend alone is not a Windows build.
4. A Windows machine verifies installation, launch, tray click/close/quit, 100/150/200 percent DPI,
   scrolling, date-range changes, persistence and real-data collection with user authorization.
5. Two devices verify team synchronization and concurrent-update handling before claiming cross-device
   operation. Neither a health response nor simulated transport proves this.
6. Track provider parity and incomplete features in this document and the work queue. Do not mark
   Windows adaptation complete after scaffolding or a first installer build.

## Sources

- [Pinned upstream Windows build](https://github.com/HouSiyuan2001/codex-cockpit/blob/cefcbc9efe03071150431645b4ebb51e7faac574/.github/workflows/release.yml)
- [Pinned upstream dependencies](https://github.com/HouSiyuan2001/codex-cockpit/blob/cefcbc9efe03071150431645b4ebb51e7faac574/src-tauri/Cargo.toml)
- [Tauri prerequisites](https://v2.tauri.app/start/prerequisites/)
- [Tauri Windows packaging](https://v2.tauri.app/distribute/windows-installer/)
- [Windows notification-area behavior](https://learn.microsoft.com/en-us/windows/win32/shell/notification-area)
