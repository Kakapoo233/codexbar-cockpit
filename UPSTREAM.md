# Upstream sources

| Project | Base | Commit | License |
| --- | --- | --- | --- |
| steipete/CodexBar | v0.82.0 | 7749f7b94ae8f1b84b9ffb2046643cec810f4078 | MIT, Peter Steinberger |
| HouSiyuan2001/codex-cockpit | v0.3.4 | cefcbc9efe03071150431645b4ebb51e7faac574 | MIT, Quota Float contributors |

CodexBar is the source base. Cockpit contributes design and algorithmic reference for daily plans,
subjective usage feedback, task grouping, and receipts. The native implementation preserves these
sources' notices. System fonts and SF Symbols are used; the Cockpit web fonts and Tauri runtime are
not bundled.

Keep upstream changes separate from integration changes. Merge a reviewed stable release, rerun
provider and Cockpit regression tests, and verify app identity and storage paths before packaging.
The historical upstream workflows are retained as inactive text in docs/cockpit/upstream-workflows.
