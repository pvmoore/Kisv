module kisv.KisvProperties;

import kisv.all;

struct KisvProperties {
    string appName = "Kisv Application";
    string engineName = "Kisv";
    VkVersion apiVersion = VkVersion(1, 1, 0);
    int appVersion = 1;
    int engineVersion = 1;
    string[] instanceLayers;
    string[] instanceExtensions;
    string[] deviceExtensions;

    uint frameBuffers = 3;

    bool headless = false;  // if headless==true then no window will be created
    bool windowed = true;
    bool windowVsync = false;
    bool windowResizable = false;
    bool windowDecorated = true;
    bool windowAutoIconify = false;
    string windowTitle = "Kisv Application";
    GLFWimage appIcon;
    uint windowWidth = 1024;    // if windowed == true
    uint windowHeight = 800;    // if windowed == true
}