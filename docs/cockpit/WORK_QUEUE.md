# Active delivery queue

Updated 2026-10-31. These items are one ongoing local developer-app iteration; source changes alone do not count as installed acceptance.

| Request | Status | Acceptance |
| --- | --- | --- |
| Correct full-day advice and show available allowance separately | Implemented and installed in 0.8.1 | 90% remaining / 6 days gives a 15% base allocation at 08:00, before reset-risk boost and comfort cap; observed use is deducted once and allowance is bounded by actual balance. |
| Use the original Cockpit comfort curve in daily estimates | Implemented and installed in 0.8.1 | Same-account quota feedback fits the curve; baseline/fitted cap and risk sources are explained. Manual caps retain priority. Token feedback never becomes quota percentage. |
| Unify day/week/month calendar styling, inspired by Apple Calendar | Implemented and installed in 0.8.0 | Shared date/selection/grid styling; all status/reset markers remain reachable at wide and narrow widths. |
| Keep Codex reset announcements above calendar period selection | Implemented and installed in 0.8.0 | Compact pinned announcement first, period selector immediately below; details expand without hiding the calendar. |
| Show a short confirmed reset date and countdown at the top of Usage | Implemented and installed in 0.8.0 | Only fresh dated pending announcements; no banner for estimates, absent dates, cancellation or expired deadlines. |
| Move Plan Usage into Statistics | Implemented and installed in 0.8.0 | Existing account-scoped history and burndown charts embedded directly; remove extra unified-homepage submenu. |
| Increase Usage & Spend session height | Implemented and installed in 0.8.0 | More visible list/detail rows; scrolling remains available on smaller displays. |
| Integrate usage receipts into Usage & Spend | Implemented and installed in 0.8.0 | One action on the selected historical session, preview/export in context, no separate receipt navigation page. |
| Diagnose Usage & Spend not working | Closed by user | User reports the problem is no longer present and requested skipping it; no speculative fix. |
| Update Settings About | Delivered; live-verified | Correct fork identity, version, project/support/changelog links and upstream attribution. |

0.8.1 validation: 81 focused tests across 12 suites passed. `make check` passed (3,236 Swift files; 23 locale catalogs); final test-fixture type fixes passed targeted format/lint. The original 08:00 regression now returns 15.75% with the default risk model, instead of 10%. Wide and narrow synthetic panel renders were inspected, and a local-data calculation retained partial coverage. Packaging, signatures and isolated startup passed. Developer app 0.8.1 build 21 is installed and running with a 0.8.0 backup. Live panel interaction remains unverified because the UI connection times out.

0.8.0 validation: 122 focused tests across 18 suites passed, plus 2 follow-up plan-history refresh tests. Packaging and isolated startup passed. About was live-verified; final interactive acceptance of the updated Statistics/session controls is pending opening Settings. Synthetic screenshots remain local. Original CodexBar is not replaced.
