extends Sprite2D
## Reusable independent-frame effect player. Explicit fps; no frame synthesis.
var frames: Array[Texture2D] = []
var fps := 24.0
var elapsed := 0.0
var complete := true
func configure(paths: Array, frame_rate: float) -> bool:
    if paths.is_empty() or frame_rate < 24.0: return false
    var loaded: Array[Texture2D] = []
    for path in paths:
        var img := Image.load_from_file(ProjectSettings.globalize_path(str(path)))
        if img == null or img.is_empty(): return false
        loaded.append(ImageTexture.create_from_image(img))
    frames = loaded; fps = frame_rate; visible = false; complete = true
    texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
    return true
func seek(seconds: float) -> int:
    var index := int(floor(maxf(0.0, seconds) * fps))
    complete = seconds < 0.0 or index >= frames.size()
    visible = not complete
    if visible: texture = frames[index]
    return -1 if complete else index
func configure_manifest(manifest_path: String) -> bool:
    if not FileAccess.file_exists(manifest_path): return false
    var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
    if not data is Dictionary or not data.get("frames") is Array: return false
    var rate := float(data.get("fps", 0.0))
    var seconds := float(data.get("duration_seconds", 0.0))
    if rate < 24.0 or seconds <= 0.0 or data.frames.size() < ceili(rate * seconds): return false
    return configure(data.frames, rate)
