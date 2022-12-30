module demo_triangle;

import kisv;
import demo : DemoApplication;

final class Triangle : DemoApplication {
private:
    KisvProperties props = {
        appName: "Triangle",
        apiVersion: VkVersion(1, 1, 0),
        instanceLayers: [
            "VK_LAYER_KHRONOS_validation"//,
            //"VK_LAYER_LUNARG_api_dump"
            //"VK_LAYER_LUNARG_monitor"
        ],
        instanceExtensions: [
            "VK_KHR_surface",
            "VK_KHR_win32_surface",
            "VK_EXT_debug_report"
        ],
        deviceExtensions: [
            "VK_KHR_swapchain",
            "VK_KHR_maintenance1"
        ],
        windowed: true,
        windowWidth: 1280,
        windowHeight: 1024,
        windowVsync: false
    };
public:
    override void initialise() {

    }
    override void destroy() {

    }
    override void run() {

    }
}