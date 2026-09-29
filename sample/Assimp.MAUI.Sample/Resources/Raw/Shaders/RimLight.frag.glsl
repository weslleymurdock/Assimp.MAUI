#version 300 es
precision highp float;

in vec3 vNormal;
in vec2 vUv;
out vec4 outColor;

uniform float uTime;

void main()
{
    vec3 normal = normalize(vNormal);
    float rim = pow(1.0 - max(normal.z, 0.0), 2.5);
    vec3 color = mix(vec3(0.04, 0.08, 0.18), vec3(0.2, 0.75, 1.0), rim);
    color += 0.08 * sin(uTime + vUv.xyx * 6.0);
    outColor = vec4(color, 1.0);
}
