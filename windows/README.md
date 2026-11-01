# CodexBar Cockpit for Windows

Development client, based on MIT Codex Cockpit v0.3.4, commit
`cefcbc9efe03071150431645b4ebb51e7faac574`. See LICENSE.upstream.

The Windows client supports a system tray panel and an optional compact floating summary. It is separate from the Swift Mac client.
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

## Compact floating window (alpha.4)

In Settings → Display mode, select **Compact floating window**. The 340×170 logical-pixel card
shows Codex short-term and weekly quota, today's remaining daily allocation, and the full-day
recommendation. Percentage, bar and bottom-up filled circle use the same daily values as the full
panel. Unknown values remain unknown. English daily labels use T; detailed hover/accessibility text
retains the weekly equivalent and incomplete-data qualification.

Drag the header to move it. Settings controls always-on-top behavior. The detail button opens the
complete panel in the same WebView; closing that panel returns to the summary. Clicking elsewhere
keeps the compact card visible. Hiding it is recoverable from the tray. The display mode and position
are stored locally; older preferences retain tray mode. Collection and planning stay in the same App
instance while surfaces change.

For an isolated native preview use `--ui-preview --floating-preview`; for credential-free startup
verification use `--smoke-test --smoke-floating`. CI verifies both tray and floating startup.
The browser equivalent is `/?synthetic-preview=1&surface=compact&sample=usage`; its account and
quota ledger are fictional and no native handlers are invoked. Browser geometry checks do not
establish Windows drag, focus, tray or physical-DPI acceptance.


## Daily recommendation pace (alpha.5)

The compact footer, Usage panel and tray tooltip share the same local Codex plan. Expected use is
`full-day automatic recommendation × elapsed local-day fraction`; deviation is observed use today
minus that reference, in **weekly quota percentage points**. The daily target itself does not shrink
as the day passes, and personal caps remain independent. Comfort-curve and valid reset-horizon changes
recompute both recommendation and pace through the same App owner and minute timer.

Incomplete observations yield a lower bound (`≥`), not a confirmed reserve. Missing/stale data, unknown
accounts, non-main pools and snapshots awaiting matching account/cycle ingestion remain unavailable.
Daily comparison is never an official-quota exhaustion ETA or a cumulative weekly progress stripe.
The existing percentage/bar/circle allowance forms keep their original daily-allocation denominator.
