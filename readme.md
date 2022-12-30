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

## Demos

- **Hello world** :: Sets up Vulkan, creates a Window and runs a minimal render loop
  until the window is closed

## Version History

[Version History](src/version.md)
