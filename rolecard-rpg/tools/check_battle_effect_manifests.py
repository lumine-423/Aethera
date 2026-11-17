import hashlib,json,math,sys
from pathlib import Path
r=Path(__file__).resolve().parents[1]
files=['shared_speedline_neutral.json','rin_base_attack_body_trail.json','rin_base_attack_space_cut.json']
result=[]
for f in files:
 d=json.loads((r/'data/battle_presentation'/f).read_text(encoding='utf-8-sig')); fps=d['fps']; n=len(d['frames']); required=math.ceil(d['duration_seconds']*fps-1e-8)
 assert fps>=24 and n>=required,(f,fps,n,required)
 assert d['classification'] in ('shared','character_specific')
 if d['classification']=='character_specific': assert all(d.get(k) for k in ('actor_id','form_id','action_id'))
 if d['classification']=='shared': assert not any(d.get(k) for k in ('actor_id','form_id','action_id'))
 paths=[r/x.removeprefix('res://') for x in d['frames']];assert all(x.is_file() for x in paths)
 hashes=[hashlib.sha256(x.read_bytes()).hexdigest() for x in paths];assert len(set(hashes))==n,(f,'duplicate frames')
 result.append({'file':f,'classification':d['classification'],'fps':fps,'duration':d['duration_seconds'],'unique_images':n,'required':required})
print(json.dumps(result,ensure_ascii=False,indent=2))
