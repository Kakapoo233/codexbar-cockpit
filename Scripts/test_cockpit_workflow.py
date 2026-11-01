#!/usr/bin/env python3
"""Check the active fork's build/test gates independently of archived upstream CI examples."""
from pathlib import Path
import re
import shlex
import unittest

ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = ROOT / '.github/workflows/cockpit-ci.yml'


def check_workflow(workflow):
    required_triggers = ['  push:', '    branches: [main]', '  pull_request:', '  workflow_dispatch:']
    if not all(line in workflow.splitlines() for line in required_triggers):
        raise ValueError('Fork CI must run on main pushes, pull requests, and manual dispatches')
    if not re.search(r'(?m)^  contents: read$', workflow) or re.search(r'(?m)^\s+contents: write$', workflow):
        raise ValueError('Fork CI requires read-only contents permission')
    if not re.search(r'actions/checkout@[0-9a-f]{40}\b', workflow):
        raise ValueError('Fork CI checkout must be pinned to a commit')
    job = re.search(r'(?ms)^  macos:\n(?P<body>.*?)(?=^  [a-zA-Z0-9_-]+:|\Z)', workflow)
    if not job:
        raise ValueError('Fork CI must contain the macos job')
    body = job.group('body')
    if not re.search(r'(?m)^    runs-on: macos-[a-zA-Z0-9.-]+$', body):
        raise ValueError('Fork CI must build on a macOS runner')
    timeout = re.search(r'(?m)^    timeout-minutes: (\d+)$', body)
    if not timeout or int(timeout.group(1)) < 30:
        raise ValueError('Fork CI needs at least 30 minutes for the pinned build and focused tests')
    if re.search(r'(?m)^\s+(if:|continue-on-error:)', body) or '|| true' in body:
        raise ValueError('Fork build, integration tests and checks must all gate success')
    runs = re.findall(r'(?m)^        run: (.+)$', body)
    required = ['swift build --product CodexBar', 'make check']
    if any(command not in runs for command in required):
        raise ValueError('Fork CI must build the app and run make check')
    focused = [shlex.split(command) for command in runs if command.startswith('make test-fast ')]
    if len(focused) != 1 or len(focused[0]) != 3 or not focused[0][2].startswith('FILTER='):
        raise ValueError('Fork CI must run one explicit focused integration test selection')
    selected = focused[0][2].removeprefix('FILTER=').split('|')
    if not {'Cockpit', 'ForkIdentityTests', 'ForkSettingsImportTests'} <= set(selected):
        raise ValueError('Fork CI must cover cockpit features, identity isolation and settings imports')
    test_command = next(command for command in runs if command.startswith('make test-fast '))
    if not runs.index(required[0]) < runs.index(test_command) < runs.index(required[1]):
        raise ValueError('Fork CI must build, test and check in that order')


def check_windows_workflow(workflow):
    if '    runs-on: windows-latest' not in workflow:
        raise ValueError('Windows client must build on Windows')
    if '  contents: read' not in workflow or 'contents: write' in workflow:
        raise ValueError('Windows CI must have read-only repository permission')
    if not re.search(r'actions/checkout@[0-9a-f]{40}\b', workflow):
        raise ValueError('Windows CI checkout must be pinned')
    if 'continue-on-error:' in workflow or '|| true' in workflow:
        raise ValueError('Windows verification must gate success')
    required = [
        'run: npm ci', 'run: npm test', 'run: npm run build',
        'run: cargo test --locked --manifest-path src-tauri/Cargo.toml',
        'run: npm run tauri build -- --bundles nsis',
        "-ArgumentList '--smoke-test'", "@('--smoke-test', '--smoke-floating')",
        "$result.presentation.surface -ne 'compact'", 'if-no-files-found: error',
    ]
    if any(command not in workflow for command in required):
        raise ValueError('Windows CI must test, package, check startup and retain its installer')


class CockpitWorkflowTests(unittest.TestCase):
    def test_current_workflow_builds_and_tests_fork_without_upstream_release_jobs(self):
        check_workflow(WORKFLOW.read_text())
        active = sorted(path.name for path in WORKFLOW.parent.iterdir() if path.suffix in {'.yml', '.yaml'})
        self.assertEqual(active, ['cockpit-ci.yml', 'windows-ci.yml'])
        check_windows_workflow((WORKFLOW.parent / 'windows-ci.yml').read_text())
        cache = (ROOT / 'Scripts/ci_swiftpm_cache.py').read_text()
        self.assertIn('".github/workflows/cockpit-ci.yml"', cache)
        self.assertNotIn('".github/workflows/ci.yml"', cache)

    def test_missing_or_non_gating_verification_is_rejected(self):
        workflow = WORKFLOW.read_text()
        weakened = [
            workflow.replace('swift build --product CodexBar', 'echo build-skipped'),
            workflow.replace('make check', 'echo check-skipped'),
            workflow.replace('|ForkIdentityTests', ''),
            workflow.replace('|ForkSettingsImportTests', ''),
            workflow.replace('run: make check', 'continue-on-error: true\n        run: make check'),
            workflow.replace('run: make check', 'run: make check || true'),
            workflow.replace('contents: read', 'contents: write'),
        ]
        for candidate in weakened:
            with self.subTest(candidate=candidate):
                with self.assertRaises(ValueError):
                    check_workflow(candidate)


    def test_windows_checks_cannot_be_silently_skipped(self):
        workflow = (WORKFLOW.parent / 'windows-ci.yml').read_text()
        for original in ['run: npm test', 'run: npm run build',
                         'run: cargo test --locked --manifest-path src-tauri/Cargo.toml',
                         "-ArgumentList '--smoke-test'", "@('--smoke-test', '--smoke-floating')",
                         "$result.presentation.surface -ne 'compact'", 'contents: read']:
            with self.subTest(original=original):
                with self.assertRaises(ValueError):
                    check_windows_workflow(workflow.replace(original, 'skipped'))


if __name__ == '__main__':
    unittest.main()
