extends RefCounted
## CSS cubic-bezier: solve x(t), then evaluate y(t); not a named easing approximation.
const RISE := Vector4(0.2,0.8,0.2,1.0)
const WIPE := Vector4(0.75,0.0,0.25,1.0)
const EASE := Vector4(0.25,0.1,0.25,1.0)
static func ease(x: float, curve := RISE) -> float:
	if x<=0.0 or x>=1.0: return clampf(x,0.0,1.0)
	var lo:=0.0; var hi:=1.0; var t:=x
	for i in range(16):
		t=(lo+hi)*0.5
		var bx:=3.0*(1.0-t)*(1.0-t)*t*curve.x+3.0*(1.0-t)*t*t*curve.z+t*t*t
		if bx<x: lo=t
		else: hi=t
	return 3.0*(1.0-t)*(1.0-t)*t*curve.y+3.0*(1.0-t)*t*t*curve.w+t*t*t
