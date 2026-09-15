#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
swift build
.build/debug/QEChecks "$@"
python3 - <<'PY'
from pathlib import Path
import subprocess
import tempfile
import plistlib
import uuid

with tempfile.TemporaryDirectory(prefix='qe-ui-') as temporary:
    root = Path(temporary)
    for name in ['Проекты', 'Документы', 'Фото']:
        (root / name).mkdir()
    (root / 'Проекты' / 'needle.txt').write_text('Search fixture\n')
    for name in ['Заметки.md', 'Список покупок.txt', '.hidden']:
        (root / name).write_text('UI fixture\n')
    receiver = root / 'OpenReceiver.app'
    executable = receiver / 'Contents' / 'MacOS' / 'OpenReceiver'
    executable.parent.mkdir(parents=True)
    (receiver / 'Contents' / 'Info.plist').write_bytes(plistlib.dumps({
        'CFBundleIdentifier': 'local.qe.receiver.' + uuid.uuid4().hex,
        'CFBundleExecutable': 'OpenReceiver', 'CFBundlePackageType': 'APPL', 'LSUIElement': True,
    }))
    subprocess.run(['swiftc', 'Tests/OpenReceiver/main.swift', '-o', str(executable)], check=True)
    subprocess.run(['.build/debug/QE', '--directory', str(root), '--ui-check',
                    str(Path('.build/ui-check').absolute()), '--open-check-app', str(receiver)], check=True, timeout=45)
PY
