shader_type canvas_item;
render_mode unshaded;
uniform sampler2D road_texture : source_color, filter_linear, repeat_disable;
uniform float scroll = 0.0;
uniform float curvature = 1.43;
uniform float span = 0.72;
uniform float perspective = 0.64;
void fragment() {
    float y = UV.y * 2.0 - 1.0;
    // Upper half bends toward the horizon; the foreground stays flat.
    // Matching derivatives at the midpoint keep scrolling continuous.
    float angle = asin(clamp(min(y,0.0) * sin(curvature), -0.9999, 0.9999));
    float surface = y < 0.0 ? angle / curvature : y * sin(curvature) / curvature;
    float depth = mix(1.0, cos(angle), perspective);
    float x = (UV.x - 0.5) / depth + 0.5;
    float v = fract(scroll + surface * span * 0.5);
    // Align the supplied tile's seven-pixel horizontal edge mismatch in UVs.
    float edge_shift = mix(0.0029686,0.0053,smoothstep(0.085,0.12,abs(x-0.4987)));
    x += edge_shift * (smoothstep(0.94,1.0,v) - (1.0-smoothstep(0.0,0.06,v)));
    vec4 grass = texture(road_texture, vec2(0.0, v));
    vec4 tex = texture(road_texture, vec2(clamp(x, 0.0, 1.0), v));
    tex = mix(grass, tex, step(0.0,x)*step(x,1.0));
    tex.rgb *= mix(0.72, 1.0, cos(angle));
    COLOR = tex;
}
