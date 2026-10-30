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
