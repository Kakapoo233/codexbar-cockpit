#!/usr/bin/env python3
"""Offline regressions for notice coverage and packaging."""
import copy
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('acknowledgements', Path(__file__).with_name('acknowledgements.py'))
notices = importlib.util.module_from_spec(spec)
spec.loader.exec_module(notices)


class AcknowledgementsTests(unittest.TestCase):
    def setUp(self):
        self.entries = json.loads((notices.ROOT / notices.RESOURCE).read_text())

    def test_resolved_packages_and_vendored_notices_are_covered(self):
        notices.check(notices.ROOT, self.entries)
        rendered = notices.render(self.entries)
        for expected in ['Commander', 'KeyboardShortcuts', 'Sparkle', 'SweetCookieKit', 'swift-log',
                         'swift-crypto', 'swift-asn1', 'Vortex', 'QuickJS', 'UNICODE LICENSE V3',
                         'BoringSSL', 'XKCP', 'Brian Gladman', 'Sucrase', '@jridgewell/gen-mapping',
                         '@jridgewell/resolve-uri', '@jridgewell/sourcemap-codec',
                         '@jridgewell/trace-mapping', 'lines-and-columns', 'ts-interface-checker']:
            self.assertIn(expected, rendered)

    def test_dependency_addition_or_pin_change_requires_refresh(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for lock in notices.LOCKS:
                path = root / lock
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes((notices.ROOT / lock).read_bytes())
            pin_file = root / notices.LOCKS[0]
            data = json.loads(pin_file.read_text())
            data['pins'].append({'identity': 'new-dependency', 'location': 'https://example.com/new',
                                 'state': {'revision': 'a' * 40}})
            pin_file.write_text(json.dumps(data))
            with self.assertRaisesRegex(ValueError, 'Update PACKAGES'):
                notices.check(root, self.entries)
            data['pins'].pop()
            data['pins'][0]['state']['revision'] = 'b' * 40
            pin_file.write_text(json.dumps(data))
            with self.assertRaisesRegex(ValueError, 'pins disagree'):
                notices.check(root, self.entries)

    def test_missing_or_modified_notice_is_rejected(self):
        entries = copy.deepcopy(self.entries)
        entries[0]['sources'][0]['text'] += 'edited'
        with self.assertRaisesRegex(ValueError, 'notice changed'):
            notices.check(notices.ROOT, entries)
        entries = [item for item in self.entries if item['name'] != 'XKCP']
        with self.assertRaisesRegex(ValueError, 'missing'):
            notices.check(notices.ROOT, entries)

    def test_fork_app_distribution_exports_the_common_resource_and_readable_notices(self):
        package = (notices.ROOT / 'Scripts/package_app.sh').read_text()
        self.assertIn('cp -R "$bundle" "$APP/Contents/Resources/"', package)
        self.assertIn('CORE_RESOURCE_BUNDLE="${PREFERRED_BUILD_DIR}/CodexBar_CodexBarCore.bundle"', package)
        self.assertIn('cp -R "$CORE_RESOURCE_BUNDLE" "$APP/Contents/Helpers/"', package)
        export = 'python3 "$ROOT/Scripts/acknowledgements.py" --text-output "$APP/Contents/Resources/THIRD_PARTY_NOTICES"'
        license_copy = 'cp "$ROOT/LICENSE" "$APP/Contents/Resources/LICENSE"'
        self.assertEqual(package.count(export), 1)
        self.assertEqual(package.count(license_copy), 1)
        self.assertLess(package.index(export), package.index('# Finally sign the app bundle itself'))
        # Execute the actual packaging commands without compiling, signing, or launching an app.
        with tempfile.TemporaryDirectory() as temporary:
            app = Path(temporary) / 'CodexBar Cockpit.app'
            (app / 'Contents/Resources').mkdir(parents=True)
            subprocess.run(['/bin/bash', '-eu', '-c', export + '\n' + license_copy],
                           env=dict(os.environ, ROOT=str(notices.ROOT), APP=str(app)),
                           check=True, capture_output=True, text=True)
            self.assertEqual((app / 'Contents/Resources/THIRD_PARTY_NOTICES').read_text(), notices.render(self.entries))
            self.assertEqual((app / 'Contents/Resources/LICENSE').read_bytes(), (notices.ROOT / 'LICENSE').read_bytes())


if __name__ == '__main__':
    unittest.main()
