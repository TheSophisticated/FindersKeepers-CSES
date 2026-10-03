shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

uniform float blur_radius : hint_range(0.0, 50.0) = 3;
uniform vec4 glass_tint : source_color = vec4(0.0, 0.0, 0.0, 0.4);
uniform float noise_strength : hint_range(0.0, 0.1) = 0.008;
uniform float noise_scale : hint_range(10.0, 2000.0) = 500.0;

float random(vec2 p)
{
    return fract(
        sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453
    );
}

void fragment() {
    // Convert blur radius into a mip level.
    float mip = blur_radius;

    // Sample the screen at a lower-resolution mip level.
    vec4 background = textureLod(
        screen_texture,
        SCREEN_UV,
        mip
    );

    // Add translucent glass tint.
    vec3 glass = mix(
        background.rgb,
        glass_tint.rgb,
        glass_tint.a
    );
	
	   float noise = random(
        floor(SCREEN_UV * noise_scale)
    );

    // Convert 0..1 to -0.5..0.5
    noise -= 0.5;

    glass += noise * noise_strength;


    COLOR = vec4(glass, 1.0);
}