# CodexBar Cockpit for Windows

Development client, based on MIT Codex Cockpit v0.3.4, commit
`cefcbc9efe03071150431645b4ebb51e7faac574`. See LICENSE.upstream.

The Windows client is being adapted to a system tray panel. It is separate from the Swift Mac client.
This directory is not yet a claim of full provider, language, calendar or synchronization parity.
Activity export remains blocked until the fork's account binding, source declaration and day boundary
are implemented. Local history stays local. Cloudflare connection/member reads are separate.

Requires Node 24, Rust stable, Microsoft C++ Build Tools and WebView2 to build on Windows.

```
npm ci
npm test
npm run build
cargo test --manifest-path src-tauri/Cargo.toml
npm run tauri build -- --bundles nsis
```

The Windows CI produces review artifacts, not a signed public release. Installation, tray interaction,
DPI and live provider collection require Windows verification before this is called supported.
Existing Mac iCloud Drive synchronization remains in the native Mac app; Windows personal sync is pending.

Bundled upstream fonts were omitted in favor of installed system fonts. Upstream icon assets retain
the upstream MIT attribution. Upstream signing keys, updater feeds and application identities must not
be used by this fork.
