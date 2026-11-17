"""Collect public publisher store screenshots, never game binaries or private/leaked assets."""
from pathlib import Path
import urllib.request,urllib.parse,json,hashlib,time,re,html
from PIL import Image
ROOT=Path(__file__).resolve().parents[1]/'design-reference'
TARGETS=[('honkai3','崩坏3',1671200),('persona5r','女神异闻录5皇家版',1687950),('danganronpa','弹丸论破',413410),('ace-attorney','逆转裁判123',787480)]
ROOT.mkdir(exist_ok=True);(ROOT/'.gdignore').write_text('','utf-8')

def get(url):
    req=urllib.request.Request(url,headers={'User-Agent':'Mozilla/5.0 (reference research)','Accept-Language':'en-US,en;q=0.8'})
    with urllib.request.urlopen(req,timeout=40) as response:return response.read(),response.headers.get('Content-Type','')

def save_json(path,value):path.write_text(json.dumps(value,ensure_ascii=False,indent=2),'utf-8')

def download(folder,name,url,page,kind):
    parsed=urllib.parse.urlparse(url)
    if parsed.scheme!='https':raise ValueError('HTTPS images only')
    data,mime=get(url)
    if len(data)>25_000_000 or not mime.startswith('image/'):raise ValueError('not bounded image: '+mime)
    suffix='.png' if 'png' in mime else '.webp' if 'webp' in mime else '.jpg'
    path=folder/(name+suffix)
    path.write_bytes(data)
    with Image.open(path) as image:width,height=image.size
    return {'id':folder.name+'/'+name,'path':str(path.relative_to(ROOT)).replace('\\','/'),'source_url':url,'source_page':page,'kind':kind,'width':width,'height':height,'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest(),'rights':'reference-only; original publisher copyright; not runtime assets','visual_review':'pending'}

manifest_path=ROOT/'sources.json'
manifest=json.loads(manifest_path.read_text('utf-8')) if manifest_path.exists() else {'schema':1,'retrieved_date':'2026-10-28','scope':'private-ui-reference-pack','games':{},'failures':[]}
for key,name,appid in TARGETS:
    if key in manifest['games']:continue
    folder=ROOT/key;folder.mkdir(exist_ok=True)
    url=f'https://store.steampowered.com/api/appdetails?appids={appid}&l=english&cc=us'
    try:
        raw,_=get(url);(folder/'store-metadata.json').write_bytes(raw)
        data=json.loads(raw)[str(appid)]
        if not data.get('success'):raise ValueError('Steam appdetails unavailable')
        info=data['data'];items=[];page=f'https://store.steampowered.com/app/{appid}/'
        for index,shot in enumerate(info.get('screenshots',[])[:12]):
            try:items.append(download(folder,f'screen-{index+1:02}',shot['path_full'],page,'publisher-store-screenshot'))
            except Exception as error:manifest['failures'].append({'game':key,'url':shot['path_full'],'error':str(error)})
        manifest['games'][key]={'name':name,'publisher':info.get('publishers',[]),'page':page,'metadata':str((folder/'store-metadata.json').relative_to(ROOT)),'items':items}
        print(key,len(items),'images',flush=True)
    except Exception as error:manifest['failures'].append({'game':key,'url':url,'error':str(error)});print(key,str(error),flush=True)
    save_json(manifest_path,manifest)

if 'arknights' not in manifest['games']:
    folder=ROOT/'arknights';folder.mkdir(exist_ok=True)
    url='https://itunes.apple.com/lookup?id=1464872022&country=us'
    try:
        raw,_=get(url);(folder/'appstore-metadata.json').write_bytes(raw);info=json.loads(raw)['results'][0]
        screenshots=info.get('ipadScreenshotUrls') or info.get('screenshotUrls') or []
        items=[]
        for index,image_url in enumerate(screenshots[:10]):items.append(download(folder,f'screen-{index+1:02}',image_url,info['trackViewUrl'],'publisher-appstore-screenshot'))
        manifest['games']['arknights']={'name':'明日方舟','publisher':info.get('sellerName'),'page':info['trackViewUrl'],'store_version':info.get('version'),'metadata':'arknights/appstore-metadata.json','items':items}
        print('arknights',len(items),'images',flush=True)
    except Exception as error:manifest['failures'].append({'game':'arknights','url':url,'error':str(error)});print('arknights',str(error),flush=True)
    save_json(manifest_path,manifest)

guide='https://bh3.mihoyo.com/m/news/693/121297'
if 'honkai3-bridge-guide' not in manifest['games']:
    folder=ROOT/'honkai3-bridge-guide';folder.mkdir(exist_ok=True)
    try:
        raw,_=get(guide);(folder/'source.html').write_bytes(raw)
        text=raw.decode('utf-8','replace')
        urls=list(dict.fromkeys(html.unescape(u) for u in re.findall(r'(?:src|data-src)=["\'](https://[^"\']+\.(?:png|jpg|jpeg)(?:\?[^"\']*)?)["\']',text)))
        items=[]
        for index,url in enumerate(urls[:12]):
            try:items.append(download(folder,f'guide-{index+1:02}',url,guide,'official-historical-bridge-guide'))
            except Exception as error:manifest['failures'].append({'game':'honkai3-bridge-guide','url':url,'error':str(error)})
        manifest['games']['honkai3-bridge-guide']={'name':'崩坏3官方历史舰桥指南','page':guide,'note':'Historical article; not proof of current UI','items':items}
        print('honkai3-bridge-guide',len(items),'images',flush=True)
    except Exception as error:manifest['failures'].append({'game':'honkai3-bridge-guide','url':guide,'error':str(error)});print('bridge guide',str(error),flush=True)
    save_json(manifest_path,manifest)
print('DONE',sum(len(g['items']) for g in manifest['games'].values()),'local reference images',flush=True)
