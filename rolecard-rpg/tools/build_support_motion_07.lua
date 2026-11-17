-- Rebuildable animation candidates. Never overwrite manual .aseprite work.
local pc=app.pixelColor
local actor=assert(app.params.actor)
local root=assert(app.params.root)
local config=json.decode(assert(io.open(root..'/art-source/support-motion-07/'..actor..'-analysis.json')):read('*a'))
local sprite=Sprite(192,192,ColorMode.RGB)
sprite.layers[1].name='body-candidate-needs-motion-review'
local images={}
for _,s in ipairs({'a','b','c'}) do images[s]=Image{fromFile=root..'/'..config.source_images[s]} end
local scale=config.scale
local index=0
local ranges={}
local report={actor=actor,status='candidate-not-accepted',scale=scale,canvas={192,192},frames={}}
for _,action in ipairs(config.actions) do
 local start=index+1
 for n,part in ipairs(action.frames) do
  index=index+1
  local source=images[part.sheet];local b=part.bounds
  local img=Image(192,192,ColorMode.RGB)
  local w,h=math.ceil((b[3]-b[1])/scale),math.ceil((b[4]-b[2])/scale)
  local dx=96-math.floor(part.anchor_x/scale);local dy=174-h+1
  for y=0,h-1 do for x=0,w-1 do
   local p=source:getPixel(math.min(b[3]-1,b[1]+math.floor((x+.5)*scale)),math.min(b[4]-1,b[2]+math.floor((y+.5)*scale)))
   if pc.rgbaA(p)>=240 and dx+x>=0 and dx+x<192 and dy+y>=0 and dy+y<192 then
    -- quantize in Aseprite; preserve alpha, no Python image manipulation
    img:putPixel(dx+x,dy+y,pc.rgba(math.floor(pc.rgbaR(p)/8)*8,math.floor(pc.rgbaG(p)/8)*8,math.floor(pc.rgbaB(p)/8)*8,255))
   end
  end end
  local f=index==1 and sprite.frames[1] or sprite:newEmptyFrame(index)
  f.duration=action.durations[n]/1000
  sprite:newCel(sprite.layers[1],f,img,Point(0,0))
  report.frames[index]={action=action.id,source=part,offset={dx,dy},duration_ms=action.durations[n]}
 end
 ranges[#ranges+1]={name=action.id,first=start,last=index}
end
for _,range in ipairs(ranges) do local tag=sprite:newTag(range.first,range.last);tag.name=range.name end
sprite.data='Support animation 07: generated candidate; no driver acceptance. Sources/prompts and review in art-source/support-motion-07.'
local output=root..'/art-source/support-motion-07/'..actor..'.generated'
sprite:saveAs(output..'.aseprite');app.activeSprite=sprite
app.command.ExportSpriteSheet{ui=false,type=SpriteSheetType.ROWS,columns=10,textureFilename=root..'/assets/characters/'..actor..'-07/motion.png',dataFilename=root..'/assets/characters/'..actor..'-07/motion.json',dataFormat=SpriteSheetDataFormat.JSON_ARRAY,listTags=true,trimSprite=false,trim=false,mergeDuplicates=false}
sprite:saveCopyAs(output..'.gif')
local out=assert(io.open(output..'-normalization.json','w'));out:write(json.encode(report));out:close()
