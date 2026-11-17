extends SceneTree
func _initialize() -> void:
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/actors.json"))
	var receipt := []
	for id in catalog.actors:
		var actor_name: String = catalog.actors[id].name
		var source := "F:/艾瑟拉/"+actor_name+"/"+actor_name+".png"
		if id == "ye": source = "F:/艾瑟拉/头像/叶.png"
		if id == "mingkong": source = "F:/艾瑟拉/头像/明空.png"
		if not FileAccess.file_exists(source): print("MISSING ",source); continue
		var picture := Image.load_from_file(source)
		var original := picture.get_size()
		var scale_value := minf(1.0,1200.0/maxf(original.x,original.y))
		picture.resize(roundi(original.x*scale_value),roundi(original.y*scale_value),Image.INTERPOLATE_LANCZOS)
		var target: String = "res://assets/ui/portraits/"+id+".webp"
		picture.save_webp(target,true,0.88)
		var avatar_source := "F:/艾瑟拉/头像/"+actor_name+".png"
		if FileAccess.file_exists(avatar_source):
			var avatar := Image.load_from_file(avatar_source)
			avatar.resize(256,256,Image.INTERPOLATE_LANCZOS)
			avatar.save_webp("res://assets/ui/portraits/"+id+"-avatar.webp",true,0.88)
			receipt.append({"id":str(id)+"-avatar","source":avatar_source,"output":"res://assets/ui/portraits/"+id+"-avatar.webp","processing":"256 square thumbnail from user-supplied avatar"})
		receipt.append({"id":id,"source":source,"output":target,"source_size":[original.x,original.y],"runtime_size":[picture.get_width(),picture.get_height()],"processing":"format conversion and bounded resampling only; no generated or repainted content","rights":"user-supplied project art; commercial release rights not audited"})
	var file := FileAccess.open("res://docs/ui-10-portrait-provenance.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(receipt,"  ")); file.close()
	quit()

