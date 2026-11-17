extends RefCounted
## Fixed-canvas video atlas reader. Missing clip is a deliberate static fallback.
var registry: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/animation_registry.json"))

func resolve_clip(actor: String, form: String, action: String) -> Dictionary:
	var key := actor+"."+form+"."+action
	if not registry.clips.has(key): return {"ok":false,"missing":true,"key":key}
	var binding: Dictionary = registry.clips[key]
	if binding.get("review") != "accepted" or not str(binding.get("metadata","")).begins_with("res://assets/characters/"): return {"ok":false,"error":"unreviewed_binding"}
	return load_atlas(binding.metadata)

func load_atlas(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {"ok":false,"error":"missing_metadata"}
	var meta: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not meta is Dictionary or not meta.get("frames") is Array or meta.frames.is_empty() or meta.frames.size() > 600 or not meta.get("asset_contract") is Dictionary: return {"ok":false,"error":"invalid_clip"}
	var contract: Dictionary = meta.asset_contract
	if not contract.get("fixed_canvas",false) or contract.get("fps",0) < 1 or contract.get("fps",0) > 60 or not contract.get("anchor") is Array or contract.anchor.size() != 2: return {"ok":false,"error":"invalid_contract"}
	var image_path := path.get_base_dir().path_join(str(meta.get("meta",{}).get("image","")))
	if image_path.get_base_dir() != path.get_base_dir(): return {"ok":false,"error":"atlas_outside_clip"}
	var image := Image.load_from_file(image_path)
	if image == null or image.is_empty() or image.get_width() > 4096 or image.get_height() > 4096: return {"ok":false,"error":"missing_or_oversize_atlas"}
	var texture := ImageTexture.create_from_image(image)
	var frames := SpriteFrames.new(); frames.remove_animation("default"); frames.add_animation(contract.action)
	frames.set_animation_speed(contract.action,1000.0); frames.set_animation_loop(contract.action,contract.action == "idle")
	var canvas := Vector2i.ZERO
	for frame in meta.frames:
		if not frame is Dictionary or not frame.get("frame") is Dictionary or frame.get("duration",0) <= 0: return {"ok":false,"error":"invalid_frame"}
		var box: Dictionary = frame.frame
		var rect := Rect2i(box.get("x",-1),box.get("y",-1),box.get("w",0),box.get("h",0))
		if rect.position.x < 0 or rect.position.y < 0 or rect.size.x <= 0 or rect.size.y <= 0 or rect.end.x > image.get_width() or rect.end.y > image.get_height(): return {"ok":false,"error":"frame_outside_atlas"}
		if canvas == Vector2i.ZERO: canvas = rect.size
		if rect.size != canvas: return {"ok":false,"error":"varying_frame_canvas"}
		var atlas := AtlasTexture.new(); atlas.atlas = texture; atlas.region = rect
		frames.add_frame(contract.action,atlas,float(frame.duration))
	var anchor := Vector2(float(contract.anchor[0]),float(contract.anchor[1]))
	if anchor.x < 0 or anchor.y < 0 or anchor.x >= canvas.x or anchor.y >= canvas.y: return {"ok":false,"error":"anchor_outside_canvas"}
	return {"ok":true,"frames":frames,"anchor":anchor,"canvas":canvas,"contract":contract}
