# Keep It Simple Vulkan (D Language)

Hopefully simple examples of Vulkan in action

This project contains D language conversions of the latest Vulkan SDK and GLFW header files.
No external dependencies are required other than the D language and its standard library.

- Vulkan SDK version 1.3.236.0 ([Vulkan SDK](src/kisv/misc/vulkan_api.d))
- GLFW version 3.3.8 [GLFW](src/kisv/misc/glfw_api.d)

This project is currently Windows only but minimal changes would be needed to port to other
Vulkan supported operating systems.

You will need _vulkan-1.dll_ (If your video card supports Vulkan you should already have this and
it should be automatically found).
The required glfw dll is provided in the root folder of this repository _glfw3.3.8.dll_
(Windows 64 bit version). This should also be automatically found if you run the demos from the
project root.

glslangValidator.exe (from the Vulkan SDK) is required for compiling shader files.

## Demos

- **Hello world** :: Sets up Vulkan, creates a Window and runs a minimal render loop
  until the window is closed
- **Textured Rectangle** :: Displays a textured rectangle. Demonstrates how to:
  - Select and allocate memory
  - Create and bind buffers and images to memory
  - Upload data from the host to the GPU via a staging buffer
  - Create an image sampler
  - Create fragment and vertex shaders
  - Setup descriptor bindings for shaders
  - Create and use a graphics pipeline

![0.0.4](/screenshots/0.0.4.png)

## Version History

[Version History](src/version.md)
