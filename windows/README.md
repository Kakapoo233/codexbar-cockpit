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

## Calendar and settings alignment (alpha.2)

Calendar buttons keep their component padding and use the tray theme's text colors.
Settings share a label/control grid; at narrow widths non-toggle fields stack vertically.
The font slider and its percentage stay in the same control group.

`windows/scripts/check-layout.js` is a read-only rendered-DOM probe for the synthetic preview.
Evaluate it in the current preview page to check calendar arrow centers, settings control columns,
row overflow and navigation clipping. It throws on failure; it does not edit preferences or page DOM.
The original calendar arrow offset measured 5 CSS pixels. The corrected offset is 0; at 920px width
all six primary settings controls share one start coordinate. At 520px width and 200% UI text scale,
the calendar day/week/month views and settings remain horizontally contained. These are browser
geometry checks; physical Windows scaling and native interaction require Workstation acceptance.

For genuine Windows WebView2 inspection, run the built executable with `--ui-preview`.
It opens a visible resizable window titled `CodexBar Cockpit - Synthetic UI Preview`, using the
same frontend with synthetic data in a new temporary profile. It has no plugins, application command
handlers, provider collectors or cloud clients, and blocks external navigation. Closing the window exits.
Normal startup and `--smoke-test` remain separate paths.
