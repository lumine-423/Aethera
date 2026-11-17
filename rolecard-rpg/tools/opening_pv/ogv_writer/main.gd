extends TextureRect
## 姣忓啓鍑轰竴涓?movie 甯у氨鎹笅涓€寮?PV 甯э紙f_00000.jpg 璧凤級锛屾斁瀹屽氨閫€鍑恒€?## 鎸夆€滅湡姝ｇ敾鍑烘潵鐨勫抚鈥濇帹杩涳紝绐楀彛琚伄鎸℃椂涔熶笉浼氫涪甯ф垨閿欎綅銆?## 鐢ㄦ硶锛堝湪鏈洰褰曪級锛?##   Godot --path . --resolution 1920x1080 --write-movie <out>.ogv --fixed-fps 30 -- --frames=<_frames 鐩綍> [--start=0] [--count=N]

var dir := ""
var start := 0
var total := 0
var shown := -1
var base_drawn := 0

func _ready() -> void:
	var count := -1
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--frames="):
			dir = a.substr(9)
		elif a.begins_with("--start="):
			start = int(a.substr(8))
		elif a.begins_with("--count="):
			count = int(a.substr(8))
	while FileAccess.file_exists(dir.path_join("f_%05d.jpg" % (start + total))) and (count < 0 or total < count):
		total += 1
	print("frames=", total, " start=", start, " dir=", dir)
	if total == 0:
		get_tree().quit(1)
		return
	base_drawn = Engine.get_frames_drawn()
	_show(0)

func _show(i: int) -> void:
	shown = i
	var im := Image.load_from_file(dir.path_join("f_%05d.jpg" % (start + i)))
	texture = ImageTexture.create_from_image(im)
	position = Vector2.ZERO
	size = Vector2(1920, 1080)

func _process(_dt: float) -> void:
	if total == 0:
		return
	var i := Engine.get_frames_drawn() - base_drawn
	if i == shown:
		return
	if i >= total:
		print("done ", i)
		get_tree().quit(0)
		return
	_show(i)
