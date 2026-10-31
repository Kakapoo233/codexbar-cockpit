# Delivery and acceptance

User-approved scope: all CodexBar providers; complete local statistics, calendar, planning, subjective
feedback, and session receipts; one menu-bar panel with peer pages; eventual replacement
of the installed CodexBar after acceptance. Project: CodexBar Cockpit, MIT, intended public repository
`Kakapoo233/codexbar-cockpit`.

## Foundation

- [x] Inspect both upstream repositories and licenses.
- [x] Pin latest stable CodexBar v0.82.0 and Cockpit v0.3.4.
- [x] Compile the unmodified CodexBar baseline on Apple Silicon.
- [x] Verify isolated application identity, settings, caches, and credential namespaces.
- [x] Validate explicit import of original display settings using synthetic fixtures.

## Integrated behavior

- [x] Implement the initial menu-bar entry and native detail views (0.1.x).
- [x] Replace the intermediate Cockpit window with one menu-bar panel (0.2.0).
- [x] Adapt the expanded Usage page to wide columns and compact single-column layouts (0.2.2).
- [x] Retain existing provider and Usage & Spend capabilities.
- [x] Implement monthly calendar driven by the same daily ledger.
- [x] Add public reset history, source previews, local estimates, and early reminders (0.3.0).
- [x] Complete Cockpit translations in the existing 23 languages, including localized formats and RTL receipt export (0.3.1).
- [x] Add localized hover help throughout the menu-bar layout editor (0.4.0).
- [x] Add multi-scale calendar and Token/cost browsing over the loaded ledger (0.4.0).
- [x] Add validated local weekday reference and recency-weighted experience trends (0.4.0).
- [x] Add an independent English text option for the top menu bar while preserving the expanded panel language (0.3.2).
- [x] Select, correct, and clear personal state directly on a calendar date (0.1.1).
- [x] Implement live daily recommendation from observed balance and valid reset windows, personal cap, and cross-reset observation accounting (0.7.0).
- [x] Implement subjective feedback records and Token experience chart.
- [x] Restore the upstream quota comfort curve with account-scoped feedback and native chart (0.5.0).
- [x] Implement parent/subagent task grouping and deduplicated selected-task receipt.
- [x] Move receipt creation into a single action on the selected historical session, removing its separate page (0.6.3).
- [x] Implement PNG preview, save, and clipboard export; render Chinese and missing-cost fixtures.
- [x] Confirm same-panel navigation and visible calendar state controls with the user (0.2.0).
- [ ] Complete settings, PNG save/clipboard, migration, and updated-layout desktop acceptance.

## Team extension (0.6.0)

- [x] Add native member/device navigation and connection settings.
- [x] Restore upstream v2 member assignment, invitations, revocation and daily allocation.
- [x] Separate team data from personal iCloud settings and provider credentials.
- [x] Include the self-hosted Worker, migrations and synthetic protocol tests.
- [ ] Select and deploy the owner's cloud service; connect a second device and verify real synchronization.
- [ ] Complete desktop acceptance of the new team page and settings.

## Verification and release

- [x] Focused accounting, persistence, identity, and receipt tests pass (176 tests, 16 suites).
- [x] `make check` passes, including strict formatting/lint, generated files, locales, and scripts.
- [x] Integrated app compiles and packages with independent identity.
- [x] Packaged startup and resources verified with network blocked and synthetic settings.
- [x] Synthetic native overview, calendar, and receipt renders visually inspected on this Mac.
- [ ] Real-account and menu-bar UI acceptance on this Mac; original app remains installed.
- [ ] User acceptance and final settings migration.
- [x] Create public GitHub repository and publish the project foundation on the development branch.
- [ ] Release automation/signing/update feed configured for this fork.

## Upstream feature follow-up

The v0.3.4 comparison is tracked in [PARITY.md](PARITY.md). Local behavior is adapted to
the native menu-bar app; no floating Tauri shell is planned. Team/device allocation and
Cloudflare synchronization remain separate extensions outside the current local integration.
