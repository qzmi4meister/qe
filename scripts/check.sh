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
import shutil

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

    # Exercise real Launch Services events without changing the user's folder default.
    (root / 'Папка с пробелами').mkdir()
    check_app = root / 'FolderOpenCheck.app'
    executable = check_app / 'Contents' / 'MacOS' / 'QE'
    executable.parent.mkdir(parents=True)
    shutil.copy2('.build/debug/QE', executable)
    build_script = Path('scripts/build.sh').read_text()
    app_plist = build_script.split('<<PLIST\n', 1)[1].split('\nPLIST', 1)[0]
    info = plistlib.loads(app_plist.replace('$version', Path('VERSION').read_text().strip()).encode())
    info['CFBundleIdentifier'] = 'local.qe.folder-check.' + uuid.uuid4().hex
    (check_app / 'Contents' / 'Info.plist').write_bytes(plistlib.dumps(info))
    subprocess.run(['codesign', '--force', '--sign', '-', str(check_app)], check=True)
    output = Path('.build/folder-integration-check').absolute()
    report = output / 'ui-check.json'
    report.unlink(missing_ok=True)
    subprocess.run(['open', '-n', '-W', '-a', str(check_app), str(root / 'Projects'),
                    '--args', '--directory', str(root), '--ui-check', str(output),
                    '--folder-integration-check'], check=True, timeout=45)
    if not report.is_file() or json.loads(report.read_text())['failures']:
        raise RuntimeError('Folder integration check failed')
PY
