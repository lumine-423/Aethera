extends Control
## UV polygon cut: preserve source pixels/rims; no local repaint or rectangular screenshot hit area.
var texture:Texture2D
var polygons:Array=[]
var source_bounds:=Rect2()
var pieces:Array[Polygon2D]=[]
func configure(source:Texture2D, outlines:Array, paint:ShaderMaterial) -> void:
	texture=source; polygons=outlines; mouse_filter=Control.MOUSE_FILTER_IGNORE
	var points:PackedVector2Array=[]
	for outline in outlines:
		for p in outline: points.append(Vector2(p[0],p[1]))
	source_bounds=Rect2(points[0],Vector2.ZERO)
	for p in points: source_bounds=source_bounds.expand(p)
	var texture_size:=texture.get_size()
	paint.set_shader_parameter("art_region",Vector4(source_bounds.position.x/texture_size.x,source_bounds.position.y/texture_size.y,source_bounds.size.x/texture_size.x,source_bounds.size.y/texture_size.y))
	for outline in outlines:
		var part:=Polygon2D.new(); var uv:PackedVector2Array=[]
		for p in outline: uv.append(Vector2(p[0],p[1]))
		part.texture=source; part.uv=uv; part.material=paint; part.antialiased=true
		add_child(part); pieces.append(part)
	resized.connect(arrange); arrange()
func arrange() -> void:
	if source_bounds.size.x<=0.0: return
	for i in range(polygons.size()):
		var points:PackedVector2Array=[]
		for p in polygons[i]: points.append((Vector2(p[0],p[1])-source_bounds.position)*size/source_bounds.size)
		pieces[i].polygon=points
