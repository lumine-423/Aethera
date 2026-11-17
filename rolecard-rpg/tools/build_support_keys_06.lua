-- Nine separate candidate keys; these are not complete animation clips.
local pc=app.pixelColor
local source=Image{fromFile=assert(app.params.input)}
local output=assert(app.params.output)
assert(source.width==1536 and source.height==1024,'Unexpected sheet dimensions; inspect before cutting')
local names={'idle','attack','skill_1','skill_2','ultimate','hit','guard','down','settlement'}
local sprite=Sprite(160,160,ColorMode.RGB)
sprite.layers[1].name='candidate-keys-not-animation'
for i=1,9 do
 local row=math.floor((i-1)/3); local col=(i-1)%3
 local x0,x1=col*512,(col+1)*512-1
 local y0,y1=row*341,(row==2 and 1023 or (row+1)*341-1)
 local l,t,r,b=x1,y1,x0,y0
 for y=y0,y1 do for x=x0,x1 do
  if pc.rgbaA(source:getPixel(x,y))>=240 then l=math.min(l,x);r=math.max(r,x);t=math.min(t,y);b=math.max(b,y) end
 end end
 assert(r>l and b>t,'Missing pose in cell '..i)
 local scale=2.6; local w=math.ceil((r-l+1)/scale);local h=math.ceil((b-t+1)/scale)
 assert(w<=154 and h<=140,'Pose outside target canvas: '..i)
 local img=Image(160,160,ColorMode.RGB);local ox=80-math.floor(w/2);local oy=145-h+1
 for y=0,h-1 do for x=0,w-1 do
  local sx=math.min(r,l+math.floor((x+.5)*scale));local sy=math.min(b,t+math.floor((y+.5)*scale))
  local p=source:getPixel(sx,sy)
  if pc.rgbaA(p)>=240 then img:putPixel(ox+x,oy+y,pc.rgba(pc.rgbaR(p),pc.rgbaG(p),pc.rgbaB(p),255)) end
 end end
 local frame=i==1 and sprite.frames[1] or sprite:newEmptyFrame(i)
 frame.duration=.2;sprite:newCel(sprite.layers[1],frame,img,Point(0,0))
 local tag=sprite:newTag(i,i);tag.name=names[i]
end
sprite.data='Unreviewed single key per action, not an animation; see support-motion-06/action-direction.md.'
sprite:saveAs(output..'.aseprite'); app.activeSprite=sprite
app.command.ExportSpriteSheet{ui=false,type=SpriteSheetType.ROWS,columns=3,textureFilename=output..'.png',dataFilename=output..'.json',dataFormat=SpriteSheetDataFormat.JSON_ARRAY,listTags=true,trimSprite=false,trim=false,mergeDuplicates=false}
