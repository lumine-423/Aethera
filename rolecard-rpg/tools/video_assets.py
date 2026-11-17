"""Local FFmpeg video->RGBA PNG->sprite atlas. No downloads, cloud calls, or source overwrite."""
from pathlib import Path
import argparse,subprocess,json,shutil,hashlib,sys,math
from fractions import Fraction

def run(args):
    result=subprocess.run([str(x) for x in args],capture_output=True,text=True,encoding='utf-8',errors='replace')
    if result.returncode:raise RuntimeError(result.stderr[-5000:])
    return result.stdout

def binary(name):
    value=shutil.which(name)
    if not value:raise ValueError(f'{name}未找到；请指定工具PATH，不会自动下载安装。')
    return value

def inspect(path):
    data=json.loads(run([binary('ffprobe'),'-v','error','-select_streams','v:0','-show_streams','-show_format','-of','json',path]))
    if not data.get('streams'):raise ValueError('未找到视频流')
    return data

def fresh(path):
    path=Path(path).resolve()
    if path.exists():raise ValueError(f'输出目录已存在，避免覆盖，请换一个批次目录：{path}')
    path.mkdir(parents=True)
    return path

def write(path,data):path.write_text(json.dumps(data,ensure_ascii=False,indent=2),'utf-8')

def extract(a):
    source=Path(a.input).resolve()
    if not source.is_file():raise ValueError('输入视频不存在')
    if a.fps is not None and not 1<=a.fps<=60:raise ValueError('抽帧fps应在1–60；省略即保留原生时间采样')
    if not 0.01<=a.similarity<=0.5 or not 0<=a.blend<=1:raise ValueError('无效抠除参数')
    if a.mode=='chroma' and (len(a.color)!=6 or any(c not in '0123456789abcdefABCDEF' for c in a.color)):raise ValueError('底色须为6位RGB，如FF00FF')
    probe=inspect(source);duration=float(probe['format'].get('duration',0))
    if duration<=0 or duration>60:raise ValueError('单动作素材限定0–60秒，请先裁成一个动作')
    stream=probe['streams'][0]
    if int(stream['width'])*int(stream['height'])>3840*2160:raise ValueError('输入超过4K，请先缩小，防止意外资源消耗')
    native=float(Fraction(stream.get('avg_frame_rate','0/1')))
    if a.fps and a.fps>native+0.1:raise ValueError(f'源仅{native:.3f}fps；提高采样率只会重复帧，已拒绝。')
    estimated_frames=math.ceil(duration*(a.fps or native))
    if estimated_frames>600 or int(stream['width'])*int(stream['height'])*4*estimated_frames>2_000_000_000:raise ValueError('本批超过600帧或预计2GB原始像素，请先裁成更短的单动作')
    out=fresh(a.output)
    filters=[]
    if a.fps:filters.append(f'fps={a.fps}')
    filters.append('format=rgba')
    if a.mode=='chroma':filters.append(f'colorkey=0x{a.color}:{a.similarity}:{a.blend}')
    cmd=[binary('ffmpeg'),'-v','error','-nostdin','-n','-i',source,'-an','-vf',','.join(filters),'-fps_mode','passthrough',out/'frame-%05d.png']
    write(out/'job.json',{'status':'running','source':str(source),'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'probe':probe,'command':[str(x) for x in cmd]})
    try:
        run(cmd)
        from PIL import Image
        frames=sorted(out.glob('frame-*.png'))
        if not frames:raise ValueError('未抽取到帧')
        alpha_extrema=[]
        for frame in frames:
            with Image.open(frame) as im:alpha_extrema.append(im.convert('RGBA').getchannel('A').getextrema())
        if a.mode=='chroma' and all(lo==255 for lo,hi in alpha_extrema):raise ValueError('抠除未产生透明像素，请检查底色/相似度；产物保留供诊断')
        write(out/'result.json',{'status':'extracted-not-visually-accepted','frames':len(frames),'source_fps':native,'output_fps':a.fps or native,'alpha_extrema':alpha_extrema,'mode':a.mode,'note':'抽帧不生成新运动；须人工检查边缘闪烁/头发服饰误抠/帧间漂移。原生可变帧率应先明确统一时间采样。'})
        print(f'已抽取{len(frames)}帧至{out}；视觉质量未自动验收。')
    except Exception as error:
        write(out/'failure.json',{'status':'failed','error':str(error),'partial_outputs_preserved':True});raise

def pack(a):
    from PIL import Image
    frames=sorted(Path(a.frames).glob('frame-*.png'))
    if not frames or len(frames)>600 or not 1<=a.fps<=60 or not 1<=a.columns<=32:raise ValueError('帧数1–600，fps1–60，列数1–32')
    with Image.open(frames[0]) as first:w,h=first.size
    if not 0<=a.anchor_x<w or not 0<=a.anchor_y<h:raise ValueError('锚点必须位于实际帧画布内')
    rows=math.ceil(len(frames)/a.columns)
    if w*a.columns>4096 or h*rows>4096:raise ValueError('图集将超过4096边长，请先统一缩小帧或缩短动作；禁止逐帧独立裁切')
    out=fresh(a.output);atlas=Image.new('RGBA',(w*a.columns,h*rows));items=[]
    for index,path in enumerate(frames):
        with Image.open(path) as im:
            if im.size!=(w,h):raise ValueError('帧画布尺寸不一致，拒绝自动缩放/逐帧裁切')
            image=im.convert('RGBA');x=(index%a.columns)*w;y=(index//a.columns)*h;atlas.paste(image,(x,y));items.append({'filename':path.name,'frame':{'x':x,'y':y,'w':w,'h':h},'duration':1000/a.fps,'sourceSize':{'w':w,'h':h},'spriteSourceSize':{'x':0,'y':0,'w':w,'h':h},'trimmed':False,'rotated':False})
    atlas.save(out/'motion.png');write(out/'motion.json',{'frames':items,'meta':{'image':'motion.png','size':{'w':atlas.width,'h':atlas.height},'frameTags':[{'name':a.action,'from':0,'to':len(frames)-1,'direction':'forward'}]},'asset_contract':{'actor':a.actor,'form':a.form,'action':a.action,'fps':a.fps,'anchor':[a.anchor_x,a.anchor_y],'loop':a.action=='idle','status':'needs-visual-review','fixed_canvas':True}})
    print(f'图集已生成：{out}；固定画布/锚点，人设与动画仍需验收。')

def main():
    p=argparse.ArgumentParser(description=__doc__);sub=p.add_subparsers(dest='command',required=True)
    sub.add_parser('doctor')
    i=sub.add_parser('inspect');i.add_argument('input')
    e=sub.add_parser('extract');e.add_argument('input');e.add_argument('output');e.add_argument('--fps',type=float);e.add_argument('--mode',choices=['keep','chroma'],default='keep');e.add_argument('--color',default='FF00FF');e.add_argument('--similarity',type=float,default=.12);e.add_argument('--blend',type=float,default=.04)
    k=sub.add_parser('pack');k.add_argument('frames');k.add_argument('output');k.add_argument('--fps',type=float,required=True);k.add_argument('--columns',type=int,default=8);k.add_argument('--actor',required=True);k.add_argument('--form',default='base');k.add_argument('--action',required=True);k.add_argument('--anchor-x',type=int,required=True);k.add_argument('--anchor-y',type=int,required=True)
    a=p.parse_args()
    if a.command=='doctor':print(json.dumps({name:run([binary(name),'-version']).splitlines()[0] for name in ['ffmpeg','ffprobe']},ensure_ascii=False))
    elif a.command=='inspect':print(json.dumps(inspect(a.input),ensure_ascii=False,indent=2))
    elif a.command=='extract':extract(a)
    else:pack(a)

if __name__=='__main__':
    try:main()
    except (ValueError,RuntimeError,OSError) as error:print('失败：'+str(error),file=sys.stderr);raise SystemExit(1)
