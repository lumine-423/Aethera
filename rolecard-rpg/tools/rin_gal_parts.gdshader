shader_type canvas_item;
render_mode unshaded;
uniform int mode=0;
uniform int uniform_count=0;
uniform vec2 uniform_points[48];
uniform int hole_count=0;
uniform vec2 hole_points[48];
uniform int face_count=0;
uniform vec2 face_points[48];
uniform vec2 extent=vec2(1024.0,1536.0);
uniform vec2 patch_position=vec2(0.0);
uniform float patch_scale=1.0;
uniform vec4 patch_uv=vec4(0.0,0.0,1.0,1.0);
uniform int neck_count=0;
uniform vec2 neck_points[48];
bool inside_polygon(vec2 p,int count,vec2 points[48]) {
	bool inside=false; int j=count-1;
	for(int i=0;i<48;i++) {
		if(i>=count) break;
		vec2 a=points[i]; vec2 b=points[j];
		if((a.y>p.y)!=(b.y>p.y) && p.x<(b.x-a.x)*(p.y-a.y)/(b.y-a.y)+a.x) inside=!inside;
		j=i;
	}
	return inside;
}
void fragment() {
	vec4 c=texture(TEXTURE,UV);
	vec2 p=(UV-patch_uv.xy)/patch_uv.zw*extent;
	bool outfit=inside_polygon(p,uniform_count,uniform_points) && !inside_polygon(p,hole_count,hole_points) && !inside_polygon(p,neck_count,neck_points);
	float outfit_edge=1000.0; int previous=uniform_count-1;
	for(int i=0;i<48;i++) {
		if(i>=uniform_count) break;
		vec2 a=uniform_points[i]; vec2 b=uniform_points[previous]; vec2 v=b-a;
		float q=clamp(dot(p-a,v)/max(dot(v,v),0.001),0.0,1.0);
		outfit_edge=min(outfit_edge,length(p-a-v*q)); previous=i;
	}
	if(mode==1 && (p.y<315.0 || outfit)) c.a=0.0;
	if(mode==2 && !outfit) c.a=0.0;
	if(mode==5) {
		bool neck=p.x>460.0 && p.x<550.0 && p.y>210.0 && p.y<320.0;
		if(!outfit && !neck) c.a*=1.0-smoothstep(0.0,10.0,outfit_edge);
	}
	if(mode==3 && (p.y>=315.0 || outfit)) c.a=0.0;
	if(mode==4) {
		p=patch_position+p*patch_scale;
		if(!inside_polygon(p,face_count,face_points)) c.a=0.0;
		float edge=1000.0; int j=face_count-1;
		for(int i=0;i<48;i++) {
			if(i>=face_count) break;
			vec2 a=face_points[i]; vec2 b=face_points[j]; vec2 v=b-a;
			float q=clamp(dot(p-a,v)/max(dot(v,v),0.001),0.0,1.0);
			edge=min(edge,length(p-a-v*q)); j=i;
		}
		c.a*=smoothstep(0.0,3.0,edge);
	}
	COLOR=c;
}
