#version 460
#extension GL_ARB_separate_shader_objects : enable
#extension GL_ARB_shading_language_420pack : enable

// input from vertex shader
layout(location = 0) in vec4 fragColor;
layout(location = 1) in vec2 fragUV;

// output
layout(location = 0) out vec4 outColor;

// descriptor bindings
layout(set = 0, binding = 1) uniform sampler2D sampler0;

void main() {
    outColor = texture(sampler0, fragUV) * fragColor;
}