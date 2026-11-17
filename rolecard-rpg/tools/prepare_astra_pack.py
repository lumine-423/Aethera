from pathlib import Path
import json,hashlib,shutil,html,sys,re,urllib.request
from PIL import Image
sys.stdout.reconfigure(encoding='utf-8')
root=Path(__file__).resolve().parents[1]/'design-reference'
manifest=json.loads((root/'sources.json').read_text('utf-8'))
if '--large-arknights' in sys.argv:
    game=manifest['games']['arknights']
    for item in game['items']:
        url=re.sub(r'/360x480bb.jpg$', '/2048x2048bb.jpg',item['source_url'])
        try:
            data=urllib.request.urlopen(url,timeout=30).read();path=root/item['path'];path.write_bytes(data)
            with Image.open(path) as im:item.update(width=im.width,height=im.height)
            item.update(source_url=url,bytes=len(data),sha256=hashlib.sha256(data).hexdigest())
        except Exception as e: print('larger image failed',e)
    (root/'sources.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),'utf-8')

local=[]
def add(source,game,index):
    folder=root/game;folder.mkdir(exist_ok=True);path=folder/f'local-{index:03}.png';shutil.copy2(source,path)
    with Image.open(path) as im:w,h=im.size
    local.append({'id':game+'/'+path.stem,'path':str(path.relative_to(root)).replace('\\','/'),'original_path':str(source),'width':w,'height':h,'bytes':path.stat().st_size,'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'rights':'reference-only; not runtime licensed','visual_review':'not-individually-reviewed'})
files=sorted(Path('E:/多娜多娜/解包输出_v2/CG_PNG').glob('系统／*.png'))
chosen=[p for p in files if 'コミュ' not in p.name and any(k in p.name for k in ['按钮','背景','窗口','选','ゲージ','パネル','メニュー','ウィンド','タイトル','ベース','枠','戦闘','战斗','ステータス','セーブ','ロード'])][:140]
for i,p in enumerate(chosen):add(p,'local-dohnadohna',i+1)
q=Path('F:/AIC_extract/out/Textures')
chosen=[p for p in q.glob('*.png') if p.name.startswith(('MapChip_','ui_album.','_icons_l.','_patterns.'))]
for i,p in enumerate(chosen):add(p,'local-aic',i+1)
(root/'local-assets.json').write_text(json.dumps({'schema':1,'items':local,'roots':['E:/多娜多娜/解包输出_v2','F:/AIC_extract/out'],'note':'AIC raw atlases: frame order/slice/anchor unknown; not an animation library'},ensure_ascii=False,indent=2),'utf-8')
cards=[]
for game,value in manifest['games'].items():
    for item in value['items']:
        cards.append((game,item,item.get('source_page',value.get('page',''))))
for item in local:cards.append((item['path'].split('/')[0],item,item['original_path']))
body=''.join('<article data-game="'+html.escape(game)+'"><a href="'+html.escape(item['path'])+'"><img loading="lazy" src="'+html.escape(item['path'])+'"></a><h3>'+html.escape(item['id'])+'</h3><p>'+str(item['width'])+' × '+str(item['height'])+'</p><small>'+html.escape(source)+'</small></article>' for game,item,source in cards)
options=''.join('<option>'+html.escape(k)+'</option>' for k in sorted(set(g for g,i,s in cards)))
(root/'index.html').write_text('<!doctype html><html lang="zh"><meta charset="utf-8"><title>Astra UI参考素材</title><style>body{font:16px system-ui;background:#101820;color:#eee;margin:30px}header{position:sticky;top:0;background:#101820;padding:12px}main{display:grid;grid-template-columns:repeat(auto-fill,minmax(310px,1fr));gap:18px}article{background:#25313d;padding:12px;overflow-wrap:anywhere}img{width:100%;height:220px;object-fit:contain;background:repeating-conic-gradient(#36414b 0% 25%,#26313b 0% 50%) 0/20px 20px}small{color:#bac7d2}select{padding:8px}a{color:#aee0cd}</style><header><h1>Astra · UI参考素材</h1><p>原始公开截图与本地UI/原始图集。用于参考和原创重绘，未作为游戏运行资源；点击图片看原尺寸。</p><a href="ASTRA_START.md">先读接手说明</a> <select id="filter"><option value="">全部</option>'+options+'</select></header><main>'+body+'</main><script>document.querySelector("select").onchange=e=>document.querySelectorAll("article").forEach(a=>a.hidden=!!e.target.value&&a.dataset.game!==e.target.value)</script></html>','utf-8')
print(json.dumps({'public_images':sum(len(v['items']) for v in manifest['games'].values()),'local_copies':len(local),'local_dohnadohna':sum(i['id'].startswith('local-dohnadohna') for i in local),'local_aic':sum(i['id'].startswith('local-aic') for i in local)},ensure_ascii=False))
