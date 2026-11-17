extends SceneTree
const ROOT="res://art-source/rin-gal-01/"
const PART_SHADER=preload("res://tools/rin_gal_parts.gdshader")
var config:Dictionary
var viewport:SubViewport
var stage:Node2D
var textures:Dictionary={}
func _initialize() -> void: call_deferred("run")
func texture(path:String) -> Texture2D:
	if not textures.has(path): textures[path]=ImageTexture.create_from_image(Image.load_from_file(ROOT+path))
	return textures[path]
func material(mode:int,pose:String) -> ShaderMaterial:
	var m:=ShaderMaterial.new(); m.shader=PART_SHADER; m.set_shader_parameter("mode",mode)
	for entry in [["uniform",config["uniform_"+pose]],["hole",config.hand_b if pose=="b" else []],["neck",[[483,286],[514,281],[536,298],[525,316],[507,317],[490,306],[483,300]]],["face",config.face_polygon]]:
		var points:PackedVector2Array=[]
		for point in entry[1]: points.append(Vector2(point[0],point[1]))
		m.set_shader_parameter(entry[0]+"_count",points.size()); m.set_shader_parameter(entry[0]+"_points",points)
	return m
func piece(path:String,mode:int,pose:String) -> Sprite2D:
	var s:=Sprite2D.new(); s.centered=false; s.texture=texture(path); s.material=material(mode,pose); stage.add_child(s); return s
func clear() -> void:
	for c in stage.get_children(): c.free()
func body(pose:String) -> void:
	# Reconstruct concealed body only inside the outfit mask, preserve original exposed silhouette.
	piece("layers/pose-"+pose+"-body-base.png",2,pose)
	piece("full/pose-"+pose+"-neutral.png",1,pose)
func outfit(pose:String) -> void: piece("full/pose-"+pose+"-neutral.png",2,pose)
func head(index:int) -> void:
	piece("full/pose-a-neutral.png",3,"a")
	if index==0: return
	var cell:Array=config.atlas_cells[index]
	var s:=Sprite2D.new(); s.centered=false
	var atlas:=AtlasTexture.new(); atlas.atlas=texture("layers/heads-6.png"); atlas.region=Rect2(cell[0],cell[1],cell[2],cell[3]); atlas.filter_clip=true
	s.texture=atlas; s.position=Vector2(330,1.66+(8*0.66 if index>=3 else 0.0)); s.scale=Vector2.ONE*0.66
	var m:=material(4,"a"); m.set_shader_parameter("extent",Vector2(cell[2],cell[3])); m.set_shader_parameter("patch_uv",Vector4(cell[0]/1536.0,cell[1]/1024.0,cell[2]/1536.0,cell[3]/1024.0)); m.set_shader_parameter("patch_position",s.position); m.set_shader_parameter("patch_scale",0.66); s.material=m; stage.add_child(s)
func save_image(path:String) -> void:
	viewport.render_target_update_mode=SubViewport.UPDATE_ONCE
	await process_frame; await RenderingServer.frame_post_draw
	var error:=viewport.get_texture().get_image().save_png(ROOT+path)
	if error!=OK: push_error("Cannot save "+path); quit(1)
func review_background() -> void:
	var b:=ColorRect.new(); b.size=Vector2(viewport.size); b.color=Color("f5f6f8"); stage.add_child(b)
func review_label(caption:String,pos:Vector2) -> void:
	var label:=Label.new(); label.text=caption; label.position=pos; label.add_theme_font_override("font",load("res://assets/fonts/NotoSansSC.ttf")); label.add_theme_font_size_override("font_size",24); label.add_theme_color_override("font_color",Color("3c4652")); stage.add_child(label)
func run() -> void:
	config=JSON.parse_string(FileAccess.get_file_as_string(ROOT+"assembly.json"))
	DirAccess.make_dir_recursive_absolute(ROOT+"parts"); DirAccess.make_dir_recursive_absolute(ROOT+"assembled")
	viewport=SubViewport.new(); viewport.size=Vector2i(1024,1536); viewport.transparent_bg=true; viewport.disable_3d=true; root.add_child(viewport)
	stage=Node2D.new(); viewport.add_child(stage)
	for pose in ["a","b"]:
		clear(); body(pose); await save_image("parts/pose-"+pose+"-body.png")
		clear(); outfit(pose); await save_image("parts/pose-"+pose+"-uniform.png")
	for index in 6:
		clear(); head(index); await save_image("parts/head-"+config.expressions[index]+".png")
		for pose in ["a","b"]:
			clear(); body(pose); head(index); outfit(pose)
			await save_image("assembled/pose-"+pose+"-"+config.expressions[index]+".png")
	clear(); viewport.size=Vector2i(1280,980); review_background()
	for i in 2:
		var s:=Sprite2D.new(); s.centered=false; s.texture=texture("full/pose-"+("a" if i==0 else "b")+"-neutral.png"); s.scale=Vector2.ONE*0.60; s.position=Vector2(12+i*640,5); stage.add_child(s)
		review_label("自然站姿" if i==0 else "交谈姿态",Vector2(275+i*640,940))
	await save_image("preview-poses.png")
	clear(); viewport.size=Vector2i(1200,720); review_background()
	var captions=["平静","微笑","交谈","疑惑","惊讶","害羞"]
	for i in 6:
		var s:=Sprite2D.new(); s.centered=false; s.texture=ImageTexture.create_from_image(Image.load_from_file(ROOT+"parts/head-"+config.expressions[i]+".png")); s.region_enabled=true; s.region_rect=Rect2(320,0,390,315); s.scale=Vector2.ONE*0.94; s.position=Vector2(16+(i%3)*400,(i/3)*360); stage.add_child(s)
		review_label(captions[i],Vector2(170+(i%3)*400,310+(i/3)*360))
	await save_image("preview-expressions.png")
	print("RIN GAL: 10 transparent component renders and 12 complete assembly previews saved; source images unchanged.")
	quit()
