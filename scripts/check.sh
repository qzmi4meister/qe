#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
sh -n scripts/build.sh
sh -n scripts/release.sh
swift build
.build/debug/QEChecks "$@"
python3 - <<'PY'
from pathlib import Path
import json
import os
import subprocess
import tempfile
import plistlib
import uuid

release_env = {key: value for key, value in os.environ.items()
               if key not in ('QE_SIGN_IDENTITY', 'QE_NOTARY_PROFILE')}
for extra, missing in [({}, 'QE_SIGN_IDENTITY'),
                       ({'QE_SIGN_IDENTITY': 'unused-test-identity'}, 'QE_NOTARY_PROFILE')]:
    result = subprocess.run(['./scripts/release.sh'], env=release_env | extra,
                            capture_output=True, text=True)
    if result.returncode == 0 or missing not in result.stderr:
        raise RuntimeError(f'Release must reject missing {missing}')
print('PASS release requires signing identity and notarization profile', flush=True)

with tempfile.TemporaryDirectory(prefix='qe-ui-') as temporary:
    root = Path(temporary)
    for name in ['Projects', 'Documents', 'Photos']:
        (root / name).mkdir()
    (root / 'Projects' / 'needle.txt').write_text('Search fixture\n')
    for name in ['Notes.md', 'Shopping List.txt', '.hidden']:
        (root / name).write_text('UI fixture\n')
    receiver = root / 'OpenReceiver.app'
    executable = receiver / 'Contents' / 'MacOS' / 'OpenReceiver'
    executable.parent.mkdir(parents=True)
    (receiver / 'Contents' / 'Info.plist').write_bytes(plistlib.dumps({
        'CFBundleIdentifier': 'local.qe.receiver.' + uuid.uuid4().hex,
        'CFBundleExecutable': 'OpenReceiver', 'CFBundlePackageType': 'APPL', 'LSUIElement': True,
    }))
    subprocess.run(['swiftc', 'Tests/OpenReceiver/main.swift', '-o', str(executable)], check=True)
    output = Path('.build/ui-check').absolute()
    report = output / 'ui-check.json'
    report.unlink(missing_ok=True)
    subprocess.run(['.build/debug/QE', '--directory', str(root), '--ui-check',
                    str(output), '--open-check-app', str(receiver)], check=True, timeout=45)
    if not report.is_file():
        raise RuntimeError('UI check exited without writing its report')
    if json.loads(report.read_text())['failures']:
        raise RuntimeError('UI check reported failures')
PY
