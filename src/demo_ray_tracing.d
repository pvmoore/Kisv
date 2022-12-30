module demo_ray_tracing;

import kisv;
import demo : DemoApplication;

final class RayTracing : DemoApplication {
private:
    KisvProperties props = {
        appName: "RayTracing",
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
            "VK_KHR_maintenance1",
            // Ray tracing
            "VK_KHR_acceleration_structure",
            "VK_KHR_ray_tracing_pipeline",
            // Acceleration structure
            "VK_KHR_deferred_host_operations",
            "VK_KHR_buffer_device_address",
            // SPIRV 1.4
            "VK_KHR_spirv_1_4",
            "VK_KHR_shader_float_controls",

            "VK_EXT_descriptor_indexing"
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