# Local integration validation

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

- Open the menu-bar entry and navigate all four tabs with real local data.
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
