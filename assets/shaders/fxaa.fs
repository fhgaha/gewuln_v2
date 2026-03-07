#version 330

in vec2 fragTexCoord;
out vec4 fragColor;

uniform sampler2D texture0;
uniform vec2 resolution;
uniform float intensity;

void main() {
    vec2 texelSize = vec2(1.0/resolution.x, 1.0/resolution.y);
    
    vec3 rgbNW = texture(texture0, fragTexCoord + vec2(-1.0, -1.0) * texelSize).rgb;
    vec3 rgbNE = texture(texture0, fragTexCoord + vec2(1.0, -1.0) * texelSize).rgb;
    vec3 rgbSW = texture(texture0, fragTexCoord + vec2(-1.0, 1.0) * texelSize).rgb;
    vec3 rgbSE = texture(texture0, fragTexCoord + vec2(1.0, 1.0) * texelSize).rgb;
    vec3 rgbM  = texture(texture0, fragTexCoord).rgb;
    
    const vec3 toLuma = vec3(0.299, 0.587, 0.114);
    float lumaNW = dot(rgbNW, toLuma);
    float lumaNE = dot(rgbNE, toLuma);
    float lumaSW = dot(rgbSW, toLuma);
    float lumaSE = dot(rgbSE, toLuma);
    float lumaM  = dot(rgbM, toLuma);
    
    float lumaMin = min(lumaM, min(min(lumaNW, lumaNE), min(lumaSW, lumaSE)));
    float lumaMax = max(lumaM, max(max(lumaNW, lumaNE), max(lumaSW, lumaSE)));
    
    vec2 dir;
    dir.x = -((lumaNW + lumaNE) - (lumaSW + lumaSE));
    dir.y =  ((lumaNW + lumaSW) - (lumaNE + lumaSE));
    
    float dirReduce = max((lumaNW + lumaNE + lumaSW + lumaSE) * 0.25 * (1.0/8.0), 1.0/128.0);
    float rcpDirMin = 1.0 / (min(abs(dir.x), abs(dir.y)) + dirReduce);
    dir = min(vec2(8.0, 8.0), max(vec2(-8.0, -8.0), dir * rcpDirMin)) * texelSize;
    
    vec3 rgbA = 0.5 * (
        texture(texture0, fragTexCoord + dir * (1.0/3.0 - 0.5)).rgb +
        texture(texture0, fragTexCoord + dir * (2.0/3.0 - 0.5)).rgb);
    vec3 rgbB = rgbA * 0.5 + 0.25 * (
        texture(texture0, fragTexCoord + dir * -0.5).rgb +
        texture(texture0, fragTexCoord + dir * 0.5).rgb);
    
    float lumaB = dot(rgbB, toLuma);
    vec3 aaColor = ((lumaB < lumaMin) || (lumaB > lumaMax)) ? rgbA : rgbB;
    
    fragColor = vec4(mix(rgbM, aaColor, intensity), 1.0);
}
