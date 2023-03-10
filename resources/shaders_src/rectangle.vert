#version 460
#extension GL_ARB_separate_shader_objects : enable
#extension GL_ARB_shading_language_420pack : enable

// input from pipeline
layout(location = 0) in vec2 inPosition;
layout(location = 1) in vec4 inColor;
layout(location = 2) in vec2 inUV;

// output to fragment shader
layout(location = 0) out vec4 fragColor;
layout(location = 1) out vec2 fragUV;

// descriptor bindings
layout(set = 0, binding = 0, std140) uniform UBO {
    mat4 model;
    mat4 view;
    mat4 proj;
} ubo;

void main() {
    mat4 trans = ubo.proj * ubo.view * ubo.model;

    gl_Position = trans * vec4(inPosition, 0, 1);

    fragColor   = inColor;
    fragUV      = inUV;
}