"""Validate deliverable animation structure; never awards motion/user acceptance."""
from pathlib import Path
from PIL import Image
import json,hashlib,argparse
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--actors',nargs='+',default=['mingkong','ye']);args=p.parse_args()
report={}
for actor in args.actors:
    base=ROOT/'assets/characters'/f'{actor}-07';data=json.loads((base/'motion.json').read_text('utf-8'));im=Image.open(base/'motion.png').convert('RGBA')
    assert len(data['frames'])==60
    tags=data['meta']['frameTags'];assert {t['name'] for t in tags}=={'idle','attack','skill_1','skill_2','ultimate','hit','guard','down','settlement'}
    covered=[];actions={}
    for tag in tags:
        indices=list(range(tag['from'],tag['to']+1));covered+=indices;assert len(indices)==(12 if tag['name']=='ultimate' else 6)
        frames=[];digests=set()
        for i in indices:
            f=data['frames'][i];r=f['frame'];assert r['w']==r['h']==192 and 40<=f['duration']<=500
            tile=im.crop((r['x'],r['y'],r['x']+r['w'],r['y']+r['h']));box=tile.getbbox();assert box and 0<box[0]<box[2]<192 and 0<box[1]<box[3]<192
            alpha=set(tile.getchannel('A').getdata());assert alpha<={0,255}
            digests.add(hashlib.sha256(tile.tobytes()).hexdigest());frames.append({'frame':i,'bounds':box,'duration_ms':f['duration']})
        assert len(digests)>1, 'static duplicates do not make animation'
        actions[tag['name']]={'frame_count':len(indices),'unique_images':len(digests),'frames':frames,'motion_acceptance':'unverified','personality_acceptance':'unverified'}
    assert sorted(covered)==list(range(60)), 'overlapping or missing action tags'
    report[actor]={'structure':'pass','actions':actions,'runtime_sheet_sha256':hashlib.sha256((base/'motion.png').read_bytes()).hexdigest(),'formal_accepted':False}
(ROOT/'evidence/support-animation-07-structure.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),'utf-8')
print(json.dumps({actor:{'structure':r['structure'],'actions':9,'frames':60,'formal_accepted':False} for actor,r in report.items()},ensure_ascii=False))
