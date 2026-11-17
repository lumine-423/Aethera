"""Create a resumable external keyframe inventory. Does not draw or claim completed images."""
from pathlib import Path
import argparse,json,shutil
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('destination');a=p.parse_args();dest=Path(a.destination).resolve()
catalog=json.loads((ROOT/'data/actors.json').read_text('utf-8'))
profiles=json.loads((ROOT/'art-source/personality-profiles.json').read_text('utf-8'))['profiles']
audit=json.loads((ROOT/'evidence/character-source-audit-03.json').read_text('utf-8'))
manifest=dest/'关键帧任务清单.json'
if manifest.exists():raise SystemExit('清单已存在，拒绝覆盖已有绘制状态；按清单续接。')
actions={'idle':'待机','attack':'普攻或基础援护','skill_1':'技能1','skill_2':'技能2','ultimate':'大招','hit':'受击','guard':'防御','down':'倒地','settlement':'结算'}
rows=[]
for actor_id,actor in catalog['actors'].items():
    folder=dest/'角色关键帧'/actor['name'];folder.mkdir(parents=True,exist_ok=True)
    source=next((c for c in audit['characters'] if c['name']==actor['name']),{})
    (folder/'角色参考.json').write_text(json.dumps({'actor_id':actor_id,'source_art':source.get('art',[]),'personality':profiles[actor_id],'reference_policy':'身份/发型/服装参考本角色原画；比例与像素语言共同参考凛零原图和像素稿；旧06/07错误稿不可作唯一参考。'},ensure_ascii=False,indent=2),'utf-8')
    for form_id,form in actor['forms'].items():
        sub=folder/(form['label']+'_'+form_id);sub.mkdir(exist_ok=True)
        for action_id,name in actions.items():rows.append({'actor':actor_id,'name':actor['name'],'form':form_id,'action':action_id,'file':str((sub/(action_id+'_'+name+'_五关键帧.png')).relative_to(dest)),'frames':5,'layout':'one-horizontal-row','status':'not_drawn'})
    if 'released' in actor['forms']:rows.append({'actor':actor_id,'name':actor['name'],'form':'base-to-released','action':'liberate','file':str((folder/'解放过渡_五关键帧.png').relative_to(dest)),'frames':5,'layout':'one-horizontal-row','status':'not_drawn'})
manifest.write_text(json.dumps({'schema':1,'strategy':'five-keyframes-to-external-video-to-rgba-atlas','characters':len(catalog['actors']),'actions':len(rows),'completed_strips':0,'tasks':rows},ensure_ascii=False,indent=2),'utf-8')
(dest/'工具').mkdir(exist_ok=True)
shutil.copy2(ROOT/'tools/video_assets.py',dest/'工具/video_assets.py')
print(json.dumps({'destination':str(dest),'actors':len(catalog['actors']),'planned_strips':len(rows),'drawn':0},ensure_ascii=False))
