# Delivery and acceptance

User-approved scope: all CodexBar providers; complete local statistics, calendar, planning, subjective
feedback, and task receipts; one menu-bar panel with peer pages; eventual replacement
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
- [x] Add an independent English text option for the top menu bar while preserving the expanded panel language (0.3.2).
- [x] Select, correct, and clear personal state directly on a calendar date (0.1.1).
- [x] Implement daily frozen recommendation, personal cap, and cross-reset observation accounting.
- [x] Implement subjective feedback records and Token experience chart.
- [x] Implement parent/subagent task grouping and deduplicated selected-task receipt.
- [x] Implement PNG preview, save, and clipboard export; render Chinese and missing-cost fixtures.
- [x] Confirm same-panel navigation and visible calendar state controls with the user (0.2.0).
- [ ] Complete settings, PNG save/clipboard, migration, and updated-layout desktop acceptance.

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
