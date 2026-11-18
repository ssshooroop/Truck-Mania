shader_type canvas_item;
render_mode unshaded;
uniform sampler2D road_texture : source_color, filter_linear, repeat_disable;
uniform float scroll = 0.0;
uniform float curvature = 1.43;
uniform float span = 0.72;
uniform float perspective = 0.64;
// Fixed normalized segments avoid dynamic constant-array indexing on mobile GPUs.
// The matching inverse mapping lives in road_projection.gd.
highp float seam_segment(highp float x, highp float v, highp vec4 edges) {
    highp vec2 middle = (edges.xy + edges.zw) * 0.5 / 1536.0;
    highp vec2 source = (v < 0.5 ? edges.xy : edges.zw) / 1536.0;
    highp float weight = 1.0-smoothstep(0.0,0.06,min(v,1.0-v));
    return mix(x,mix(source.x,source.y,(x-middle.x)/(middle.y-middle.x)),weight);
}
highp float aligned_sample_x(highp float x, highp float v) {
    if (x <= 507.0/1536.0) return seam_segment(x,v,vec4(0.0,516.0,0.0,498.0));
    if (x <= 587.0/1536.0) return seam_segment(x,v,vec4(516.0,600.0,498.0,574.0));
    if (x <= 768.5/1536.0) return seam_segment(x,v,vec4(600.0,782.0,574.0,755.0));
    if (x <= 805.5/1536.0) return seam_segment(x,v,vec4(782.0,819.0,755.0,792.0));
    if (x <= 1010.0/1536.0) return seam_segment(x,v,vec4(819.0,1008.0,792.0,1012.0));
    if (x <= 1088.5/1536.0) return seam_segment(x,v,vec4(1008.0,1082.0,1012.0,1095.0));
    return seam_segment(x,v,vec4(1082.0,1536.0,1095.0,1536.0));
}
void fragment() {
    highp float y = UV.y * 2.0 - 1.0;
    // Upper half bends toward the horizon; the foreground stays flat.
    // Matching derivatives at the midpoint keep scrolling continuous.
    highp float angle = asin(clamp(min(y,0.0) * sin(curvature), -0.9999, 0.9999));
    highp float surface = y < 0.0 ? angle / curvature : y * sin(curvature) / curvature;
    highp float depth = mix(1.0, cos(angle), perspective);
    highp float x = (UV.x - 0.5) / depth + 0.5;
    highp float v = fract(scroll + surface * span * 0.5);
    x = aligned_sample_x(x,v);
    vec4 grass = texture(road_texture, vec2(0.0, v));
    vec4 tex = texture(road_texture, vec2(clamp(x, 0.0, 1.0), v));
    tex = mix(grass, tex, step(0.0,x)*step(x,1.0));
    tex.rgb *= mix(0.72, 1.0, cos(angle));
    COLOR = tex;
}
