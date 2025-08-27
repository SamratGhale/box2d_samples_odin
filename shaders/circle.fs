#version 330

in vec2  f_position;
in vec4  f_color;
in float f_thickness;


out vec4 fragColor;

void main(){
	float radius = 1.0;

	//distance to circle
	vec2 w = f_position;
	float dw = length(w);
	float d  = abs(dw - radius);

	fragColor = vec4(f_color.rgb, smoothstep(f_thickness, 0.0, d));
}