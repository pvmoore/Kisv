# Version History

## 0.0.1 Initial commit

- Hello world demo available which sets up Vulkan, creates a window and runs a render loop

## 0.0.2 Tweaks and small fixes

- Move some physical device code from a helper class to a static method in KisvPhysicalDevice
- Fix a couple of small bugs

## 0.0.3 Add TransferHelper

- Add new **TransferHelper** class to handle uploads from staging buffer to device buffer

## 0.0.4

- Change demo_triangle to demo_rectangle and implement it
- Add float2, float4 and float16
- Add rectangle shader source files
- Add birds.bmp image
- Add BMP utility to load BMP files
- Implement **ShaderHelper** to compile and load shader files (requires glslangValidator.exe)
- Implement **MemoryHelper** to help to select, allocate and manage Vulkan memory
- Implement **BufferHelper** to manage created buffers and buffer views
- Implement **ImageHelper** to manage created images and image views
- Add/modify various *_util files

## 0.0.5

- Implement **SamplerHelper** to manage samplers
- Implement **DescriptorHelper** to manage descriptors and layouts
- Refactor the demo_rectangle to use the above new classes

## 0.0.6

- Implement demo_ray_tracing (Not currently working)
