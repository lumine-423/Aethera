"""Read-only structure and contact diagnostics, not natural-motion acceptance."""
from pathlib import Path
from PIL import Image
import json

ROOT = Path(__file__).resolve().parents[1]
image = Image.open(ROOT / 'assets/characters/rin-motion-v2/motion.png').convert('RGBA')
meta = json.loads((ROOT / 'assets/characters/rin-motion-v2/motion.json').read_text('utf-8'))
assert image.size == (640, 640) and len(meta['frames']) == 16
colors = set(image.get_flattened_data())
assert {c[3] for c in colors} == {0, 255}
assert len({c[:3] for c in colors if c[3]}) <= 25
assert {t['name']: (t['from'], t['to']) for t in meta['meta']['frameTags']} == {'idle': (0, 3), 'attack': (4, 15)}
rows = []
for index, item in enumerate(meta['frames']):
    r = item['frame']
    assert r['w'] == 160 and r['h'] == 160 and item['duration'] > 0
    frame = image.crop((r['x'], r['y'], r['x']+160, r['y']+160))
    box = frame.getchannel('A').getbbox()
    assert box and box[0] > 0 and box[1] > 0 and box[2] < 160 and box[3] < 160
    contacts = [x for x in range(160) if any(frame.getpixel((x, y))[3] for y in range(142, 145))]
    assert contacts
    rows.append({'frame': index+1, 'bounds': box, 'ground_span': [min(contacts), max(contacts)], 'duration_ms': item['duration']})
source = ROOT / 'art-source/rin-motion-v2/rin-motion-v2.generated.aseprite'
assert source.is_file()
receipt = {'structure_pass': True, 'motion_acceptance': 'unapproved', 'source': str(source),
           'frames': rows, 'idle_ms': sum(f['duration'] for f in meta['frames'][:4]),
           'attack_ms': sum(f['duration'] for f in meta['frames'][4:]),
           'note': 'Complete silhouettes recovered from irregular source grid; no grid-crop claim. Contacts/volume/transitions still require visual review.'}
(ROOT / 'evidence/art-structure-05.json').write_text(json.dumps(receipt, indent=2), 'utf-8')
print(json.dumps(receipt, indent=2))
