"""Structural art checks; never substitutes for motion or human visual review."""
from pathlib import Path
from PIL import Image
import json
ROOT=Path(__file__).resolve().parents[1]
base=ROOT/'assets'/'characters'/'rin-study'
meta=json.loads((base/'cast-study.json').read_text(encoding='utf-8'))
image=Image.open(base/'cast-study.png').convert('RGBA')
assert image.size==(480,320)
assert len(meta['frames'])==6
colors=set(image.getdata())
assert {c[3] for c in colors}=={0,255}
assert len({c[:3] for c in colors if c[3]})<=25
assert all(f['sourceSize']=={'w':160,'h':160} and f['duration']>0 for f in meta['frames'])
assert (ROOT/'art-source'/'rin-cast-study'/'rin-cast-study.aseprite').is_file()
rows=[]
for frame in meta['frames']:
 r=frame['frame'];im=image.crop((r['x'],r['y'],r['x']+r['w'],r['y']+r['h']))
 box=im.getchannel('A').getbbox();assert box and box[0]>0 and box[1]>0 and box[2]<160 and box[3]<160
 xs=[x for x in range(160) if any(im.getpixel((x,y))[3] for y in range(142,145))]
 rows.append({'bounds':box,'ground_contact_span':(min(xs),max(xs)),'duration_ms':frame['duration']})
receipt={'structural_pass':True,'visual_status':'draft-not-approved','canvas':[160,160],
 'palette_colors':len({c[:3] for c in colors if c[3]}),'total_ms':sum(f['duration'] for f in meta['frames']),
 'frames':rows,'note':'Ground contact span differences require visual foot-slip review; this is not natural-animation acceptance.'}
(ROOT/'evidence'/'art-structure-02.json').write_text(json.dumps(receipt,indent=2),encoding='utf-8')
print(json.dumps(receipt,indent=2))
