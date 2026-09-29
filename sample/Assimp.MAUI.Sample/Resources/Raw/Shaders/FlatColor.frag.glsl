#version 300 es
precision highp float;

in vec3 vNormal;
in vec2 vUv;
out vec4 outColor;

uniform float uTime;

void main()
{
    vec3 baseColor = vec3(0.18, 0.48, 0.95);
    float light = 0.35 + max(dot(normalize(vNormal), normalize(vec3(-0.4, 0.7, 0.6))), 0.0) * 0.65;
    outColor = vec4(baseColor * light, 1.0);
}
