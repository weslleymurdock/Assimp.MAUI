#version 300 es
precision highp float;

in vec3 vNormal;
in vec2 vUv;
out vec4 outColor;

void main()
{
    outColor = vec4(normalize(vNormal) * 0.5 + 0.5, 1.0);
}
