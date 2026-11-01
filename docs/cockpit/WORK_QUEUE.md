# Active delivery queue

Updated 2026-10-31. These items are one ongoing local developer-app iteration; source changes alone do not count as installed acceptance.

| Request | Status | Acceptance |
| --- | --- | --- |
| Unify day/week/month calendar styling, inspired by Apple Calendar | Implemented and installed in 0.8.0 | Shared date/selection/grid styling; all status/reset markers remain reachable at wide and narrow widths. |
| Keep Codex reset announcements above calendar period selection | Implemented and installed in 0.8.0 | Compact pinned announcement first, period selector immediately below; details expand without hiding the calendar. |
| Show a short confirmed reset date and countdown at the top of Usage | Implemented and installed in 0.8.0 | Only fresh dated pending announcements; no banner for estimates, absent dates, cancellation or expired deadlines. |
| Move Plan Usage into Statistics | Implemented and installed in 0.8.0 | Existing account-scoped history and burndown charts embedded directly; remove extra unified-homepage submenu. |
| Increase Usage & Spend session height | Implemented and installed in 0.8.0 | More visible list/detail rows; scrolling remains available on smaller displays. |
| Integrate usage receipts into Usage & Spend | Implemented and installed in 0.8.0 | One action on the selected historical session, preview/export in context, no separate receipt navigation page. |
| Diagnose Usage & Spend not working | Closed by user | User reports the problem is no longer present and requested skipping it; no speculative fix. |
| Update Settings About | Delivered; live-verified | Correct fork identity, version, project/support/changelog links and upstream attribution. |

Validation: 122 focused tests across 18 suites passed, plus 2 follow-up plan-history refresh tests. `make check` passed; packaging, signatures and isolated startup passed. Developer app 0.8.0 build 20 is installed with a 0.7.1 backup. Synthetic screenshots remain local. About was live-verified; final interactive acceptance of the updated Statistics/session controls is pending opening Settings. Original CodexBar is not replaced.
