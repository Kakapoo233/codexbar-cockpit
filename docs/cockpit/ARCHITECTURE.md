# Integration architecture

## Product contract

CodexBar remains the native menu-bar shell and provider collector. A persistent, ordinary macOS
window hosts the Cockpit detail views. There is no floating widget or second Tauri process.

## Modules and interfaces

- `UsageStore` and `SpendDashboardController` remain the authoritative provider and cost interfaces.
  Cockpit consumes their published snapshots rather than starting a second collector.
- `CockpitPlanState` is a serializable Foundation module. It receives official quota observations and
  produces frozen daily recommendations, manual caps, observed use, and completeness.
- `CockpitPlanStore` adapts existing snapshots to the planning module and atomically persists local
  state. Provider/account identifiers scope each plan. Unknown accounts are not merged.
- `CockpitComfortModel` represents subjective experience against recorded Token use. Its output is
  descriptive and never converted into an official quota percentage. Local Token history belongs to
  the explicit `local-machine` scope, independently of whichever quota account is currently selected.
- `CockpitTaskLineage` groups already-accounted sessions using bounded session metadata reads. Fork
  baseline deduplication remains owned by CodexBar's scanner. Subagents belong to their root task;
  independent forks remain independent work.
- `CockpitWindowController` and SwiftUI views compose statistics, monthly calendar, plans, and receipts.
- `CockpitAppIdentity` centralizes fork-owned configuration, cache, defaults, and Keychain namespaces.
  `CockpitSettingsImport` exposes only a whitelist of presentation and provider selection settings.

## Accounting invariants

Use the configured local natural day consistently, including DST. Do not re-label legacy Shanghai
aggregates as local-day data; derive new daily totals from source events. Distinguish missing/partial
coverage from measured zero, and keep currencies separate. Official percentage changes are observations,
not a complete bill; gaps and resets retain uncertainty. The first daily recommendation is frozen;
manual changes affect the personal cap only. Account changes must not reuse another account's plan.

Receipts use stable session identifiers and union selected membership before summing. Parent and
child selection must not double count; unknown cost remains unknown or explicitly partial.
The selected period filters active tasks; totals cover their complete scanned sessions and can include
usage outside that period. Both the selection UI and exported receipt disclose this distinction.

## Delivery

Development bundles are isolated and ad-hoc signed. No upstream automatic update feed is accepted.
Replacing an installed CodexBar happens after user acceptance; local integration testing does not
replace or migrate an existing installation automatically. The public repository is
Kakapoo233/codexbar-cockpit; integration/native-cockpit records the initial integration.
Feature-sized commits and pull requests record each iteration.
