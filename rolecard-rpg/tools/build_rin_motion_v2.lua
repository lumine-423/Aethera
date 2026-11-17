-- New generated draft; never overwrites the previous study or a hand-finished source.
local pc=app.pixelColor
local input=assert(app.params.input)
local output=assert(app.params.output)
local runtime=assert(app.params.runtime)
local components=assert(io.open(app.params.components,'r'))
local parts=json.decode(components:read('*a'));components:close()
assert(#parts==16,'Expected sixteen complete connected silhouettes')
local original=Image{fromFile=input}
local palette={{20,25,40},{29,35,53},{42,48,68},{62,67,88},{82,93,119},{106,126,153},{135,157,184},{163,185,206},{190,208,223},{216,226,235},{238,241,239},{253,250,241},{22,53,104},{31,77,147},{43,112,183},{67,168,204},{128,219,232},{136,86,99},{181,120,129},{215,157,161},{243,193,185},{255,223,204},{105,84,56},{166,133,69},{222,188,116}}
local cache={}
local function quantize(p)
 local r,g,b=pc.rgbaR(p),pc.rgbaG(p),pc.rgbaB(p)
 if pc.rgbaA(p)<128 or (b>200 and r<35 and g<80) then return 0 end
 local key=p&0xffffff;if cache[key] then return cache[key] end
 local best,d=palette[1],math.huge
 for _,c in ipairs(palette) do local n=.3*(r-c[1])^2+.5*(g-c[2])^2+.2*(b-c[3])^2;if n<d then best,d=c,n end end
 local q=pc.rgba(best[1],best[2],best[3],255);cache[key]=q;return q
end
local sprite=Sprite(160,160,ColorMode.RGB);sprite.layers[1].name='coherence-draft-05'
local timings={300,300,300,300,130,100,90,60,50,55,55,70,90,100,120,180}
local record={status='draft-not-approved',canvas={160,160},anchor={58,144},palette_colors=25,frames={},normalization='connected-component full silhouettes, uniform 2.5 reduction; root aligned; no foot shear'}
for index=1,16 do
 local b=parts[index].bounds
 local width,height=b[3]-b[1],b[4]-b[2]
 local sw,sh=math.ceil(width/2.5),math.ceil(height/2.5)
 local small=Image(sw,sh,ColorMode.RGB)
 for y=0,sh-1 do for x=0,sw-1 do
  local sx,sy=math.min(b[3]-1,b[1]+math.floor((x+.5)*2.5)),math.min(b[4]-1,b[2]+math.floor((y+.5)*2.5))
  small:putPixel(x,y,quantize(original:getPixel(sx,sy)))
 end end
 local bottom=-1
 for y=0,sh-1 do for x=0,sw-1 do if pc.rgbaA(small:getPixel(x,y))>0 then bottom=y end end end
 assert(bottom>90,'Incomplete silhouette')
 local foot={}
 for x=0,sw-1 do for y=bottom-2,bottom do if pc.rgbaA(small:getPixel(x,y))>0 then foot[#foot+1]=x;break end end end
 local l,r=foot[1],foot[1]
 for j=2,#foot do if foot[j]-r>2 then break end;r=foot[j] end
 local dx,dy=58-math.floor((l+r)/2),144-bottom
 local image=Image(160,160,ColorMode.RGB);image:drawImage(small,Point(dx,dy))
 local f=index==1 and sprite.frames[1] or sprite:newEmptyFrame(index);f.duration=timings[index]/1000
 sprite:newCel(sprite.layers[1],f,image,Point(0,0))
 record.frames[index]={source_bounds=b,offset={dx,dy},duration_ms=timings[index]}
end
local idle=sprite:newTag(1,4);idle.name='idle';idle.aniDir=AniDir.FORWARD
local attack=sprite:newTag(5,16);attack.name='attack';attack.aniDir=AniDir.FORWARD
local root=sprite:newSlice(Rectangle(0,0,160,160));root.name='root';root.pivot=Point(58,144)
sprite.data='Unapproved draft 05. See evidence/art-review-05.md. Generated grid was NOT regular.'
sprite:saveAs(output..'.aseprite');app.activeSprite=sprite
app.command.ExportSpriteSheet{ui=false,type=SpriteSheetType.ROWS,columns=4,textureFilename=runtime..'/motion.png',dataFilename=runtime..'/motion.json',dataFormat=SpriteSheetDataFormat.JSON_ARRAY,listTags=true,listSlices=true,trimSprite=false,trim=false,mergeDuplicates=false}
sprite:saveCopyAs(output..'.gif')
local file=assert(io.open(output..'-normalization.json','w'));file:write(json.encode(record));file:close()
