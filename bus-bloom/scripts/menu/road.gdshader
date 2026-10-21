shader_type canvas_item;
render_mode unshaded;
uniform sampler2D road_texture : source_color, filter_linear, repeat_disable;
uniform float scroll = 0.0;
uniform float curvature = 1.43;
uniform float span = 0.72;
uniform float perspective = 0.64;
// Six boundaries: both shoulders and both sides of the center dash.
// Pixel coordinates from the top/bottom rows of the 1536px artwork.
const float seam_top[8] = float[8](0.0,516.0,600.0,782.0,819.0,1008.0,1082.0,1536.0);
const float seam_bottom[8] = float[8](0.0,498.0,574.0,755.0,792.0,1012.0,1095.0,1536.0);
float aligned_sample_x(float x, float v) {
    float weight = 1.0-smoothstep(0.0,0.06,min(v,1.0-v));
    float px = x*1536.0;
    for (int i=0; i<7; i++) {
        float left = (seam_top[i]+seam_bottom[i])*0.5;
        float right = (seam_top[i+1]+seam_bottom[i+1])*0.5;
        if (px<=right) {
            float a = v<0.5 ? seam_top[i] : seam_bottom[i];
            float b = v<0.5 ? seam_top[i+1] : seam_bottom[i+1];
            return mix(px,mix(a,b,(px-left)/(right-left)),weight)/1536.0;
        }
    }
    return x;
}
void fragment() {
    float y = UV.y * 2.0 - 1.0;
    // Upper half bends toward the horizon; the foreground stays flat.
    // Matching derivatives at the midpoint keep scrolling continuous.
    float angle = asin(clamp(min(y,0.0) * sin(curvature), -0.9999, 0.9999));
    float surface = y < 0.0 ? angle / curvature : y * sin(curvature) / curvature;
    float depth = mix(1.0, cos(angle), perspective);
    float x = (UV.x - 0.5) / depth + 0.5;
    float v = fract(scroll + surface * span * 0.5);
    x = aligned_sample_x(x,v);
    vec4 grass = texture(road_texture, vec2(0.0, v));
    vec4 tex = texture(road_texture, vec2(clamp(x, 0.0, 1.0), v));
    tex = mix(grass, tex, step(0.0,x)*step(x,1.0));
    tex.rgb *= mix(0.72, 1.0, cos(angle));
    COLOR = tex;
}
