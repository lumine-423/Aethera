"""Read-only pixel analysis; actual image normalization/export is Aseprite Lua."""
from pathlib import Path
from PIL import Image
import json, hashlib, argparse
ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT/'art-source/support-motion-07'
LAYOUT={'a':['idle','attack','skill_1'],'b':['skill_2','ultimate','ultimate','hit'],'c':['guard','down','settlement']}
DURATIONS={'idle':[220,180,180,220,180,220],'attack':[140,100,70,100,130,180],'skill_1':[160,120,100,100,140,200],'skill_2':[160,120,100,150,140,200],'ultimate':[180,160,140,140,120,180,90,180,140,140,160,220],'hit':[60,65,90,120,150,170],'guard':[120,100,120,220,180,160],'down':[120,90,100,140,170,400],'settlement':[180,150,180,240,180,220]}
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--actors',nargs='+',choices=['mingkong','ye'],default=['mingkong','ye'])
args=parser.parse_args()
for actor in args.actors:
    actions={};inputs=[];idle_h=None;source_images={}
    for sheet,rows in LAYOUT.items():
        path=BASE/f'{actor}-{sheet}.png'
        fixed=BASE/f'{actor}-{sheet}-fixed.png'
        if fixed.exists():path=fixed
        source_images[sheet]=str(path.relative_to(ROOT)).replace('\\','/')
        im=Image.open(path).convert('RGBA')
        inputs.append({'path':str(path.relative_to(ROOT)),'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'size':im.size})
        # Generated grids may cross theoretical column boundaries. Locate complete
        # alpha-connected bodies first, then associate by actual row and x order.
        px=im.load();seen=set();components=[]
        for sy in range(im.height):
            for sx in range(im.width):
                if (sx,sy) in seen or px[sx,sy][3]<240:continue
                stack=[(sx,sy)];seen.add((sx,sy));points=[]
                while stack:
                    x,y=stack.pop();points.append((x,y))
                    for nx,ny in ((x-1,y),(x+1,y),(x,y-1),(x,y+1)):
                        if 0<=nx<im.width and 0<=ny<im.height and (nx,ny) not in seen and px[nx,ny][3]>=240:seen.add((nx,ny));stack.append((nx,ny))
                if len(points)>1000:components.append(points)
        if len(components)!=len(rows)*6:raise ValueError(f'Expected {len(rows)*6} full silhouettes, got {len(components)} in {actor}/{sheet}')
        bands={row:[] for row in range(len(rows))}
        for points in components:
            cy=(min(y for x,y in points)+max(y for x,y in points))/2
            bands[min(len(rows)-1,int(cy/im.height*len(rows)))].append(points)
        for row,action in enumerate(rows):
            if len(bands[row])!=6:raise ValueError(f'Irregular row count in {actor}/{sheet}/{row}')
            bands[row].sort(key=lambda p:min(x for x,y in p))
            for col in range(6):
                x0,x1=col*im.width//6,(col+1)*im.width//6;y0,y1=row*im.height//len(rows),(row+1)*im.height//len(rows)
                points=bands[row][col]
                if not points:raise ValueError(f'Empty frame: {actor}/{sheet}/{row}/{col}')
                l=min(x for x,y in points);r=max(x for x,y in points);t=min(y for x,y in points);b=max(y for x,y in points)
                if l==0 or r==im.width-1 or t==0 or b==im.height-1:raise ValueError(f'Clipped at source edge: {actor}/{sheet}/{row}/{col}')
                feet=sorted(set(x for x,y in points if y>=b-2));left=feet[0];end=left
                for x in feet[1:]:
                    if x-end>2:break
                    end=x
                anchor=(left+end)/2-l
                if action=='down':anchor=(r-l)/2
                if idle_h is None:idle_h=b-t+1
                actions.setdefault(action,[]).append({'sheet':sheet,'bounds':[l,t,r+1,b+1],'anchor_x':anchor,'cell':[col,row],'touches_grid':False})
    result={'actor':actor,'status':'candidate-not-accepted','inputs':inputs,'source_images':source_images,'scale':idle_h/136,'actions':[{'id':a,'frames':frames,'durations':DURATIONS[a]} for a,frames in actions.items()]}
    assert len(result['actions'])==9 and sum(len(x['frames']) for x in result['actions'])==60
    (BASE/f'{actor}-analysis.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),'utf-8')
    print(actor, '9 actions / 60 source frames analyzed; no images changed')
