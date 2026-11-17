"""Fetch the approved official templates and extract only this project's Web zips."""
from pathlib import Path
import hashlib
import json
import shutil
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
TARGET = ROOT / '.tools' / 'godot-4.7.2'
ARCHIVE_NAME = 'Godot_v4.7.2-stable_export_templates.tpz'
ARCHIVE_URL = ('https://godot-releases.nbg1.your-objectstorage.com/'
               '4.7.2-stable/' + ARCHIVE_NAME)
SUMS_URL = ('https://github.com/godotengine/godot-builds/releases/download/'
            '4.7.2-stable/SHA512-SUMS.txt')


def main():
    TARGET.mkdir(parents=True, exist_ok=True)
    request = urllib.request.Request(SUMS_URL, headers={'User-Agent': 'SigilRPG-LocalBuild/0.1'})
    with urllib.request.urlopen(request, timeout=60) as response:
        sums = response.read().decode('utf-8-sig')
    lines = [line for line in sums.splitlines() if line.split() and
             line.split()[-1].lstrip('*') == ARCHIVE_NAME]
    if len(lines) != 1:
        raise RuntimeError('Official checksum entry missing or ambiguous; no extraction performed')
    expected = lines[0].split()[0].lower()
    if len(expected) != 128:
        raise RuntimeError('Unexpected SHA-512 format')
    (TARGET / 'SHA512-SUMS.txt').write_text(sums, encoding='utf-8')
    archive = TARGET / ARCHIVE_NAME
    partial = archive.with_suffix('.tpz.part')
    if not archive.exists():
        print('Downloading official archive to project-local .tools', flush=True)
        request = urllib.request.Request(ARCHIVE_URL, headers={'User-Agent': 'SigilRPG-LocalBuild/0.1'})
        with urllib.request.urlopen(request, timeout=120) as response, partial.open('wb') as output:
            total = int(response.headers.get('Content-Length', 0))
            received, next_report = 0, 64 * 1024 * 1024
            while chunk := response.read(1024 * 1024):
                output.write(chunk)
                received += len(chunk)
                if received >= next_report:
                    print(f'{received:,} / {total:,} bytes', flush=True)
                    next_report += 64 * 1024 * 1024
        if total and received != total:
            raise RuntimeError('Download incomplete; partial file retained')
        partial.replace(archive)
    actual = hashlib.file_digest(archive.open('rb'), 'sha512').hexdigest()
    if actual != expected:
        raise RuntimeError('Official SHA-512 mismatch; archive retained, not extracted')
    extracted = []
    with zipfile.ZipFile(archive) as package:
        for item in package.infolist():
            name = Path(item.filename).name
            if name.startswith('web_') and name.endswith('.zip'):
                # Flatten a fixed file-name allowlist, never extract arbitrary archive paths.
                if '/' in name or '\\' in name or name.startswith('.'):
                    raise RuntimeError('Unexpected template name')
                dest = TARGET / name
                with package.open(item) as source, dest.open('wb') as output:
                    shutil.copyfileobj(source, output)
                with zipfile.ZipFile(dest) as template:
                    if bad := template.testzip():
                        raise RuntimeError(f'Corrupt nested template entry: {bad}')
                extracted.append({'name': name, 'bytes': dest.stat().st_size,
                                  'sha256': hashlib.file_digest(dest.open('rb'), 'sha256').hexdigest()})
    if not extracted:
        raise RuntimeError('No Web templates found')
    receipt = {'version': '4.7.2.stable', 'archive_url': ARCHIVE_URL,
               'official_checksums_url': SUMS_URL, 'sha512': actual,
               'official_sha512_matched': True, 'archive_bytes': archive.stat().st_size,
               'web_templates': extracted, 'global_install_modified': False}
    (TARGET / 'receipt.json').write_text(json.dumps(receipt, indent=2), encoding='utf-8')
    print(json.dumps(receipt, indent=2), flush=True)


if __name__ == '__main__':
    main()
