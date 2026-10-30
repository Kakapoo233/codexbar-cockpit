# Cockpit v0.3.4 feature comparison

Reference: HouSiyuan2001/codex-cockpit tag `v0.3.4`, commit
`cefcbc9efe03071150431645b4ebb51e7faac574`. The integration uses native SwiftUI/AppKit
and the existing CodexBar collectors; it does not embed a second Tauri application.

| Upstream capability | Native integration | Remaining distinction |
| --- | --- | --- |
| Quota status and daily advice | Usage page alongside the original provider cards; frozen daily suggestion, manual cap, cross-reset observations | Upstream reset-risk/fatigue-knee optimization is not used to rewrite frozen plans |
| Local statistics | Existing Usage & Spend dashboard, provider/project/session breakdown and reporting periods | Retained history depends on the selected data sources and scan settings |
| Personal weekday calibration | Optional local reference with history readiness, separate seven-day validation, stale/drift/no-gain fallbacks | Adapted to observed native quota history; not a new official quota |
| Subjective Token experience | Calendar feelings, correctable history, recent-experience weighted trend | Descriptive native trend; not the upstream fitted comfort-curve parameter or a productivity forecast |
| Quota comfort curve | Original smooth-knee function, 0.1–100% knee fit, fixed subjective scores, 14-day decay, partial-data weighting, default/fitted chart and hover details | Direct current-account observations; no team cost-share allocation or reset-risk heatmap |
| Usage calendar | Day/week/month/quarter/year browsing, Token/cost selection, daily details | Uses loaded local history; unscanned days remain unknown |
| Reset history | Public history, scheduled previews, local estimates, and early notices | Public reset events never change account quotas or personal plans |
| Task receipt | Searchable task selection, parent/subagent union, PNG preview/save/copy | Totals cover scanned task sessions and disclose partial cost |
| Display/settings | CodexBar preferences, existing 23 languages, top-menu English override, layout hover help | Explicit CodexBar settings import; no silent import of unrelated Cockpit state |
| Floating/always-on-top shell | Replaced by one anchored menu-bar panel with peer pages | Intentional product choice; no floating window |
| Team/member/device allocation and Cloudflare sync | Not implemented | Separate extension requiring a server/account/data-sharing design |
| Tokei/local source configuration | Existing CodexBar source settings and parsers | No import of Cockpit-specific team/source settings |

The comparison records functionality, not a claim of identical algorithms. Current local additions
preserve provider/account/time-zone isolation, unknown versus measured-zero data, currency separation,
and the user's frozen recommendation and manually chosen cap.
