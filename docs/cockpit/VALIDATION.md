# Local integration validation

## Taller session history (0.6.2)

On 2026-10-31, 25 existing tests in `SpendDashboardSessionRowTests` and `SessionUsagePresentationTests`
passed, together with the opt-in `SpendDashboardScreenshotRenderTests.test_renderUsageSpendRangeScreenshots`
render. The synthetic wide Sessions preview was visually inspected. `make check` passed with 3,224 Swift
files and all 22 locale catalogs. Both session entry points share a 760-point height; compact lists use
up to 320 points and retain the existing separate list, detail, and outer-page scrolling.

## User-owned Cloudflare setup (0.6.1)

On 2026-10-30, 28 tests across `CockpitTeamClientTests`, `CockpitTeamStoreTests`, and
`CockpitTeamScreenshotTests` passed. New health-check fixtures verify anonymous GET requests, supported
service identity/version, and malformed/unrecognized response handling. Existing enrollment and account
isolation regressions remained green. `make check` passed with 3,224 Swift files and all 22 locale catalogs.
The synthetic Chinese self-hosted setup form was visually inspected; no real server or credentials were used.

## Members and devices (0.6.0)

On 2026-10-30, 63 tests in seven suites passed: five `CockpitTeam*` suites,
`CockpitProjectionUITests`, and `PreferencesSelectionTests`. The vendored Worker also passed its
14 Node tests using in-memory SQLite. Native coverage includes consent boundaries, UTC+8 day handling,
unknown/partial cost, account changes with unavailable quota, A→B→A isolation, one-person/multiple-device
budgeting, stale draft/reset-cycle conflicts, offline caches, monotonic replacement uploads, no-secret
JSON, paused/disconnected operations, and recovery of received enrollment credentials after local save failures.

Synthetic Chinese team renders at 600×760 and 420×760 and the 880×760 connection settings were visually
inspected. `make check` passed, including all 22 locale catalogs and strict lint of 3,223 Swift files.
The content scrolls at both menu widths; full-height companion captures cover the remaining
devices. Images remain private. The 0.6.0/build 14 bundle passed signature verification and isolated
startup/resource checks with network access blocked. Real cloud deployment and two-device acceptance
remain pending; no personal usage or provider credentials were uploaded. Desktop interaction remains
blocked while the Mac is locked.

## Calendar feeling faces (0.5.1)

On 2026-10-30, 17 existing tests across `CockpitCalendarPeriodScreenshotTests`,
`CockpitCalendarCaptureTests`, and `CockpitProjectionUITests` passed. The synthetic quarterly calendar
render was visually inspected: month cells use feeling faces, and the selected status button retains
its face alongside a checkmark. `make check` passed with 3,204 Swift files. Preview images remain private.
The 0.5.1/build 13 bundle passed strict signature verification and the isolated startup/resource check.

## Restored quota comfort curve (0.5.0)

On 2026-10-30, 81 focused tests in ten suites passed: `CockpitQuotaComfortTests`,
`CockpitQuotaComfortUITests`, `CockpitComfortCoreTests`, `CockpitPlanCoreTests`, `CockpitPlanStoreTests`,
`CockpitCalendarCaptureTests`, `CockpitPersonalUsageModelTests`, `CockpitProjectionUITests`,
`CockpitNavigationIsolationTests`, and `CockpitCalendarPeriodTests`.

Coverage includes independent formula values, grid-fit optimality, recency and partial-coverage
weights, default/one-sample behavior, cumulative use above 100%, the upstream 90-feedback window,
legacy JSON decoding, historical/archived observations, unknown-versus-zero data, and account/date/
provider/time-zone isolation. Changing a feeling preserves its measurement and leaves plans and
manual caps intact. Store tests use temporary paths and synthetic account snapshots.

`make check` passed with 3,204 Swift files. A subsequent test-only macro compatibility adjustment
passed focused formatting/lint before the final successful test run. Eight private synthetic renders
cover default/fitted curves, Chinese/English, and 600/420-point widths; four complementary renders
were visually inspected. No real-account data or new preview images are published with this change.
The 0.5.0/build 12 development bundle passed strict signature verification and the isolated six-second
startup/resource smoke check, including direct and symlinked CLI loading with the checkout unreadable.

## Pro allowance labels (0.4.2)

On 2026-10-30, 164 focused tests in eight suites passed: `CodexPlanFormattingTests`,
`OpenAIDashboardScrapeScriptTests`, `OpenAIDashboardParserTests`, `ProviderQuotaFixtureContractTests`,
`CodexPresentationCharacterizationTests`, `CLISnapshotTests`, `ShareStatsTests`, and
`OpenAIDashboardFetcherCreditsWaitTests`. These cover current price-bearing plan names,
Pro Lite's 10x label, unchanged Pro 200 20x, explicit Pro 500 50x, repeated formatting,
unknown-name preservation, closed share labels, and unchanged server usage percentages.
The WebKit cases use synthetic local HTML. `make check` passed, including strict lint over 3,200 Swift files.
The 0.4.2/build 11 development bundle passed strict signature verification and the isolated six-second
startup/resource smoke check, including direct and symlinked CLI loading with the checkout unreadable.

Price-specific labels require an explicit plan name. The existing generic `pro` mapping remains
20x; the app does not infer undocumented account SKUs or rescale measured quota data.
Older explicitly formatted labels are preserved until a fresh provider snapshot arrives.

Validated on Apple Silicon, macOS 27.0.1, Xcode 27 and Swift 6.4 (2026-10-29).
This is a development build, not a notarized public release.

## Automated coverage

The initial integration focused Swift run covered 176 tests in 16 suites: planning and reset precision, local comfort
attribution, receipt totals and partial data, task lineage and inherited-history deduplication,
account isolation and persistence, explicit settings import, fork identity, and menu labels.
Tests use synthetic inputs and the repository's isolated test environment.

```sh
source Scripts/test_environment.sh
export CODEXBAR_COCKPIT_PROOF_DIR=/tmp/cockpit-proof
swift test -j 6 --filter 'Cockpit|ForkIdentityTests|ForkSettingsImportTests|AppGroupSupportTests|CodexSubagentAccountingIntegrationTests|CodexSubagentForkBaselineTests|ConfigValidationTests|KeychainStringStoreTests|ClaudeOAuthApplicationDefaultsTests|StatusItemBalanceDisplayTests'
make check
./Scripts/package_cockpit.sh debug
./Scripts/verify_packaged_app_launch.sh 'CodexBar Cockpit.app'
```

The package passed strict signature/resource verification and a six-second isolated startup with
network access blocked, synthetic settings, test credential isolation, and the build checkout
unreadable. This also checks both directly invoked and symlinked CLI resource loading.

Native overview, month-grid, and Chinese multi-currency receipt renders were visually inspected.
The committed preview images contain only synthetic data. The full upstream Swift test suite was
not run; focused coverage and the repository checks are the handoff gates.

## Manual acceptance still required

- Save a PNG and copy/paste it into another application.
- Confirm the display-setting import and selected providers match the user's preferences.
- Verify real-account quota and local-log coverage with the user's explicit authorization.
- Accept the development build before replacing the existing CodexBar installation.

There is no configured fork update feed, Developer ID signature, or notarized downloadable release.
The original CodexBar remains installed and its settings are not automatically migrated.

## Calendar personal-state regression

Version 0.1.1 passed 51 focused Cockpit tests across 7 suites and `make check`. Its separate opt-in
native-data acceptance test also passed with private artifacts kept outside the repository.
Direct editing for the selected calendar date has regression coverage for date, provider,
time-zone and local-machine isolation; persistence after editing and clearing; future-day availability;
and retaining the original measurement when changing only a feeling.

`CockpitRealDataAcceptanceTests` is skipped by default. It requires explicit authorization,
`CODEXBAR_COCKPIT_LIVE_ACCEPTANCE=1`, and the existing private directory
`/private/tmp/codex-cockpit-live-validation/rendered`. Run it alone with a 90-second external process
watchdog, after building the test bundle. It retains credential isolation, reads only native Codex logs,
uses a separate temporary cache with bounded scanning, disables pricing refresh, and never initializes
the application settings or writes the clipboard. It can validate partial coverage; it does not claim a
complete historical scan. Generated images and data must not be committed or uploaded.

## Unified menu-bar panel (0.2.0)

Validated on 2026-10-30. The final build passed 211 focused Swift tests, run in eight isolated processes. One combined run hit a timing-sensitive row-identity assertion
in an upstream native-menu test; the same suite passed alone and in the final isolated groups.
The exact source of that timing interference was not established.

Coverage includes original action sender identity, provider context on first open, provider switching,
settings-driven refresh, expandable card height, submenu hydration and return navigation, shutdown,
page-local reporting filters, persistence, and immediate budget observation. Real SwiftUI/AppKit renders
of the unified usage and compact calendar pages use synthetic state and are committed as previews.
The calendar keeps date/state controls above the month grid and follows the selected UI language.

The strict project checks pass. The ad-hoc development package passed signature/resource checks
and the six-second isolated startup test with network access blocked. It is isolated from the original CodexBar.
A user report of other settings failing still needs specific control names and reproduction steps;
passing persistence tests does not establish that every reported UI problem has been resolved.
Live popover keyboard input, outside-click dismissal, and PNG save/clipboard remain manual acceptance
items when the computer-use accessibility connection is unavailable.

### Live desktop follow-up

On 2026-10-30, the user confirmed that all four pages work in the same panel and that Calendar shows
the personal-state controls. Desktop screenshots and accessibility state also confirmed daily advice
on Usage, real local statistics, the compact Calendar, task selection, and a rendered receipt preview.
Changing the usage-bar fill setting from remaining to used appeared on the provider card; the setting
was subsequently verified back at its original remaining mode. The automated acceptance actions did
not create subjective experience records, and the original CodexBar was not replaced.

The receipt Save PNG dialog opened, but the desktop tool raised Settings above it. A process sample
confirmed that the application was still waiting inside `NSSavePanel.runModal`; this was an active
application-modal dialog, not evidence of a deadlock or lost preference writes. The user cancelled it.
PNG file creation and clipboard round-trip were not verified. Private screenshots, account data,
usage values, and the process sample remain outside the repository.

## Receipt save ownership (0.2.1)

The application-modal receipt save was replaced by an asynchronous sheet attached to the preview's
own window. Nine new synthetic tests passed for owner routing, pending-save lifetime, duplicate saves,
cancellation, late callbacks, window removal, rendering failures, write errors, and a decodable PNG.
The existing receipt-core and projection/UI suites also passed (17 tests), for 26 focused tests in
three suites. `make check` passed with zero SwiftLint violations across 3,175 Swift files.
Independent source review found no remaining blocking issues in the save lifecycle.
The 0.2.1 development package passed strict signature/resource verification and the six-second
isolated startup check with network access blocked and the build checkout unreadable.

These tests use fake save panels and temporary files. They do not claim that the native nested save
sheet, a real PNG save, or a clipboard round-trip has passed desktop acceptance.

## Responsive wide panel (0.2.2)

The default panel is 960 by 700 points, bounded by the current screen's visible area. Usage splits
into independently scrolling provider and daily-advice columns at widths of 800 points or more;
smaller widths keep a single scrolling column. A shared layout value sizes both SwiftUI columns
and the original AppKit-hosted cards, with space reserved for their submenu indicators.

The final focused run passed 22 tests across five suites. Native synthetic screenshots were checked
at 960 by 700 and 676 by 460 in Chinese and English; the additional English render run also passed.
The screenshots exercise the actual native card bridge and verify card bounds after submenu return.
No real accounts or usage logs are used in these fixtures.

A long native menu title exposed a separate details-width path: the regression failed eight width
assertions before the fix. Panel-owned root and descendant menus now use the same card width for
hosted detail hydration and refresh. Synthetic status-component cards pass both paths, and menus
outside the panel retain native width calculation.

The final `make check` passed with zero SwiftLint violations across 3,176 Swift files. Independent
review checked the six Chinese/English renders and the detail-width regression. The 0.2.2 package
passed signature/resource verification and the six-second isolated startup check.

After the Mac was unlocked, 0.2.2 (build 5) was installed and its running executable path verified.
The previous development bundle was backed up, and the original CodexBar remained running.
Live pointer/scroll acceptance of the updated panel remains pending; the desktop accessibility
connection still timed out after startup.

## Public reset calendar and previews (0.3.0)

On 2026-10-30, 85 focused tests in 13 suites passed, including the public API opt-in proof and
synthetic native panel rendering. The API proof used anonymous requests and decoded all 69 current
history entries; both scheduled reset and active watch were null at the time of verification.
Non-null scheduled/watch behavior is covered with fixtures based on the published OpenAPI schema.

Coverage includes complete pagination, invalid responses, UTC/DST grouping, unknown or missing
source metadata, local-estimate sample rules, pending/expired forecasts, offline caches, independent
status/history failures, settings persistence, portable preference import/export, and rate-limit
backoff. Gated tests exercise a manual refresh joining a status-only request and stale notification
submission completing after a newer delivery. A source review found no remaining blocking issues.

Chinese and English synthetic calendar/usage renders were inspected at 960×700 and 676×460.
Longer calendar content remains vertically scrollable. The new renders stay outside the public
repository; committed preview images describe the earlier layout. An additional English render run
passed. `make check` passed with zero SwiftLint violations across 3,187 Swift files.

The 0.3.0 build 6 package passed signature/resource checks and the six-second isolated startup test.
It was installed over the developer app with the previous bundle backed up; the original CodexBar
remained running. The installed developer process and its public cache containing all 69 reset
records were verified. Desktop accessibility timed out again after relaunch, so actual notification
appearance/click-through and live calendar pointer interaction are not claimed as verified.

## Existing language completion (0.3.1)

On 2026-10-30, all 154 Cockpit keys were checked in the existing 23 language catalogs. Non-Cockpit
translations were preserved. Placeholder signatures, protected literals, duplicate-key checks,
and nonempty translation coverage passed. The language list was not expanded.

The focused Cockpit and localization run passed 231 tests in 31 suites. An additional Arabic
native-panel render passed after making the column-bounds assertion aware of right-to-left layout.
Coverage includes retained error text and retry dates after a language change, selected-language
percentages and receipt dates, existing reset synchronization behavior, and offline receipt exports.
`make check` passed with zero violations in 3,189 Swift files; later test-only adjustments passed
targeted formatting and strict lint checks.

Synthetic German and Arabic Usage/Calendar panels were rendered at 960×700 and 676×460. German,
Arabic, Persian, Japanese, and Traditional Chinese receipt exports were inspected for wrapping,
footer visibility, and direction. The images stay outside the repository. These checks do not
constitute native-speaker linguistic review of every translation or live language-picker acceptance.

The 0.3.1 build 7 package passed signing/resource checks and isolated six-second startup, then replaced
the independent developer bundle after backing up 0.3.0. Desktop accessibility still timed out when
attaching to the accessory app; real panel clicks and language-picker operation remain unverified.

## Independent English status text (0.3.2)

On 2026-10-30, 204 focused tests in six suites passed. Coverage includes default-off persistence,
app/CLI preference transfer, observation invalidation, language-scope restoration after errors,
cache separation, and actual independent/merged AppKit status-item redraws in both directions.
The expanded panel's language is checked after each English render. Existing renderer, portable
preferences, icon-signature, and language-catalog regressions also passed.

All 23 language catalogs include the option's title and scope description. `make check` passed
with zero violations across 3,191 Swift files; later test-only fixes passed targeted format/lint.
An independent source review found no remaining scope, refresh, or persistence issue. Test fixtures
remain synthetic; desktop clicking of the installed settings toggle is not claimed as verified.

The 0.3.2 build 8 package passed signing/resource checks and isolated startup. It was installed over
the independent developer app with a backup; the original CodexBar remains separate. Accessibility
attachment still times out after launch, so on-device toggle clicks require manual acceptance.

## Editor help and local insights (0.4.0)

- `make test-fast FILTER='Cockpit|MenuBarLayout|StatusItemConditionalSignatureTests'`:
  416 tests in 36 suites passed, including calendar periods, cross-currency partial totals,
  normal weekly resets, non-midnight polling, observation corrections, old-state migration,
  and unchanged frozen-plan/manual-cap behavior.
- `make check`: passed; strict SwiftLint reported zero violations across 3,200 Swift files.
  Follow-up edits also passed targeted formatting and strict lint.
- Verified 85 new keys across all 23 existing locales, including matching format placeholders.
- Synthetic quarterly/yearly cost calendars and the wide Usage sidebar rendered and were inspected.
  New screenshots remain local; no private usage records or new images were published.
- The 0.4.0 build 9 package passed signing/resource checks and isolated startup with network blocked
  and the build checkout unreadable. The installed developer bundle was updated with a previous-version
  backup; the original CodexBar installation was preserved.
- Interactive desktop hover acceptance remains pending: the interface connection could not attach
  during development, and the desktop was locked at the final launch attempt.

The personal reference is limited to qualifying recorded periods, not a full-day quota forecast.
It requires sufficient historical coverage and a separate successful validation week; collection,
stale, drift, and no-gain states intentionally show no reference value. See [PARITY.md](PARITY.md)
for remaining upstream algorithm and team/cloud differences.

## Statistics time-zone settings placement (0.4.1)

- The menu-bar Statistics page hides time-zone configuration; Settings → Usage & Spend retains
  the existing picker and current-Mac-zone action against the same persisted setting.
- 20 tests in SpendTimeZoneControlsTests, CockpitNavigationIsolationTests, and CockpitProjectionUITests
  passed, including persistence, immediate reporting-day changes, and calendar navigation isolation.
- `make check` passed with zero SwiftLint violations. Debug packaging and signing checks passed.
- Packaged offline startup passed. Version 0.4.1 build 10 was installed with the previous developer
  bundle backed up; desktop acceptance remains pending while the Mac is locked.
