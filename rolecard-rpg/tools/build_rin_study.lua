-- Aseprite 1.3 CLI. AI poses are a draft; this does not manufacture in-between art.
local pc = app.pixelColor
local input = assert(app.params.input, 'input is required')
local output = assert(app.params.output, 'output base is required')
local runtime = assert(app.params.runtime, 'runtime directory is required')
local source = Image{fromFile=input}
assert(source.width == 1536 and source.height == 1024, 'Unexpected key-pose grid')
local colors = {
  {20,25,40},{29,35,53},{42,48,68},{62,67,88},{82,93,119},
  {106,126,153},{135,157,184},{163,185,206},{190,208,223},
  {216,226,235},{238,241,239},{253,250,241},
  {22,53,104},{31,77,147},{43,112,183},{67,168,204},{128,219,232},
  {136,86,99},{181,120,129},{215,157,161},{243,193,185},{255,223,204},
  {105,84,56},{166,133,69},{222,188,116},
}
local cache = {}
local function quantize(pixel)
  if pc.rgbaA(pixel) < 128 then return 0 end
  local key = pixel & 0xffffff
  if cache[key] then return cache[key] end
  local r,g,b=pc.rgbaR(pixel),pc.rgbaG(pixel),pc.rgbaB(pixel)
  local best, distance = colors[1], math.huge
  for _,c in ipairs(colors) do
    local d = 0.3*(r-c[1])^2+0.5*(g-c[2])^2+0.2*(b-c[3])^2
    if d < distance then best,distance=c,d end
  end
  local value=pc.rgba(best[1],best[2],best[3],255)
  cache[key]=value
  return value
end
local sprite=Sprite(160,160,ColorMode.RGB)
sprite.layers[1].name='character-draft'
local durations={240,160,70,110,180,240}
local metadata={status='draft-not-approved',canvas={160,160},anchor={58,144},
  logical_scale_reduction=4,palette_colors=#colors,alpha='binary',frames={},
  limitations={'Six generated key poses only; no invented in-between frames',
    'Identity/volume/transition quality requires visual acceptance',
    'This gesture does not establish canon character abilities'}}
for index=1,6 do
  local gx=((index-1)%3)*512
  local gy=math.floor((index-1)/3)*512
  local small=Image(128,128,ColorMode.RGB)
  local bottom=-1
  for y=0,127 do for x=0,127 do
    local value=quantize(source:getPixel(gx+x*4+2,gy+y*4+2))
    small:putPixel(x,y,value)
    if value ~= 0 and y > bottom then bottom=y end
  end end
  assert(bottom > 80, 'Missing complete character')
  local footXs={}
  for x=0,127 do
    local count=0
    for y=math.max(0,bottom-2),bottom do
      if pc.rgbaA(small:getPixel(x,y)) > 0 then count=count+1 end
    end
    if count > 0 then footXs[#footXs+1]=x end
  end
  local left=assert(footXs[1],'No ground contact found')
  local right=left
  for i=2,#footXs do
    if footXs[i]-right > 2 then break end
    right=footXs[i]
  end
  local rear=math.floor((left+right)/2)
  local dx,dy=58-rear,144-bottom
  local normalized=Image(160,160,ColorMode.RGB)
  normalized:drawImage(small,Point(dx,dy))
  -- Localized front-leg correction, not whole-sprite motion. Original poses 3/4
  -- displaced the planted front shoe by 14/17 logical pixels with no stepping.
  local correction=({0,0,-14,-17,0,0})[index]
  if correction ~= 0 then
    local old=Image(normalized)
    for y=96,159 do for x=92,159 do normalized:putPixel(x,y,0) end end
    for y=96,159 do
      local amount=math.floor(correction*math.min(1,(y-96)/44)+0.5)
      for x=92,159 do
        local value=old:getPixel(x,y)
        if pc.rgbaA(value)>0 then normalized:putPixel(x+amount,y,value) end
      end
    end
  end
  local frame= index==1 and sprite.frames[1] or sprite:newEmptyFrame(index)
  frame.duration=durations[index]/1000
  sprite:newCel(sprite.layers[1],frame,normalized,Point(0,0))
  metadata.frames[index]={key=index,duration_ms=durations[index],
    source_cell={gx,gy,512,512},offset={dx,dy},rear_contact={rear,bottom},front_leg_correction=correction}
end
local tag=sprite:newTag(1,6)
tag.name='cast-study'
tag.aniDir=AniDir.FORWARD
local anchor=sprite:newSlice(Rectangle(0,0,160,160))
anchor.name='root'
anchor.pivot=Point(58,144)
sprite.data='Draft pose study, not production-approved animation. See art-review-02.md.'
sprite:saveAs(output..'.aseprite')
app.activeSprite=sprite
app.command.ExportSpriteSheet{ui=false,type=SpriteSheetType.ROWS,columns=3,
  textureFilename=runtime..'/cast-study.png',dataFilename=runtime..'/cast-study.json',
  dataFormat=SpriteSheetDataFormat.JSON_ARRAY,listTags=true,listSlices=true,
  trimSprite=false,trim=false,mergeDuplicates=false}
sprite:saveCopyAs(output..'.gif')
local file=assert(io.open(output..'-normalization.json','w'))
file:write(json.encode(metadata));file:close()
print(json.encode(metadata))
