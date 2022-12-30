module demo_hello_world;

import std.format : format;

import kisv;
import demo : DemoApplication;

final class HelloWorld : DemoApplication {
private:
    VkClearValue bgColour;
    KisvContext context;
    QueueFamily graphicsQueueFamily;
    QueueFamily transferQueueFamily;

    KisvProperties props = {
        appName: "HelloWorld",
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

        this.context = new KisvContext(props);

        context.selectPhysicalDevice((KisvPhysicalDevice[] devices) {
            foreach(i, d; devices) {
                if(d.properties.deviceType == VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU &&
                  d.supportsExtensions(props.deviceExtensions) &&
                  d.supportsVersion(props.apiVersion))
                {
                    return i.as!int;
                }
            }
            throw new Exception("No suitable physical device found");
        });

        context.selectQueueFamilies((QueueHelper h) {
            // Look for a graphics queue family
            auto graphics = h.find(VK_QUEUE_GRAPHICS_BIT);
            throwIf(graphics.length == 0, "No graphics queues available");
            graphicsQueueFamily = graphics[0];
            graphicsQueueFamily.numQueues = 1;
            log("Selected graphics queue family %s", graphicsQueueFamily);

            // Look for a transfer queue family
            if(h.supports(graphicsQueueFamily, VK_QUEUE_TRANSFER_BIT)) {
                // Use the graphics queue for transfer
                transferQueueFamily = graphicsQueueFamily;
            } else {
                auto transfer = h.find(VK_QUEUE_TRANSFER_BIT);
                throwIf(transfer.length == 0, "No transfer queues available");
                transferQueueFamily = transfer[0];
                transferQueueFamily.numQueues = 1;
            }
            log("Selected transfer queue family %s", transferQueueFamily);
        });

        // Select the device features that we want to use
        VkPhysicalDeviceAccelerationStructureFeaturesKHR asFeatures = {
            sType: VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_ACCELERATION_STRUCTURE_FEATURES_KHR
        };
        VkPhysicalDeviceRayTracingPipelineFeaturesKHR rtpFeatures = {
            sType: VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_RAY_TRACING_PIPELINE_FEATURES_KHR
        };
        VkPhysicalDeviceBufferDeviceAddressFeaturesEXT bdaFeatures = {
            sType: VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_BUFFER_DEVICE_ADDRESS_FEATURES
        };

        context.selectDeviceFeatures((FeatureHelper f) {
            f.addFeature(&asFeatures)
             .addFeature(&rtpFeatures)
             .addFeature(&bdaFeatures);
        });

        logStructure(asFeatures);
        logStructure(rtpFeatures);
        logStructure(bdaFeatures);

        if(graphicsQueueFamily.index == transferQueueFamily.index) {
            // Create device with 1 queue
            context.createLogicalDevice(graphicsQueueFamily);
        } else {
            // Create device with 2 queues
            context.createLogicalDevice(graphicsQueueFamily, transferQueueFamily);
        }
        context.createWindow();

        context.createStandardRenderPass();

        context.createTransferCommandPool(transferQueueFamily.index);

        context.createRenderLoop(graphicsQueueFamily.index);

        initialiseScene();

        import core.cpuid: processor;
        context.window.setTitle("Hello World %s :: %s, %s".format(
            VERSION, context.physicalDevice.name(), processor()));
    }
    override void destroy() {
        if(context) context.destroy();
    }
    override void run() {
        context.window.show();

        context.startRenderLoop((KisvFrame frame) {
            renderScene(frame);
        });
    }
private:
    void renderScene(KisvFrame frame) {
        auto cmd = frame.commands;
        cmd.beginOneTimeSubmit();

        // Perform code that needs to be outside the render pass here

        cmd.beginRenderPass(
            context.renderPass,
            frame.frameBuffer,
            toVkRect2D(0, 0, context.window.size()),
            [ bgColour ]
        );

        // We are inside the render pass here

        cmd.endRenderPass();
        cmd.end();

            /// Submit our render buffer
        context.getQueue(graphicsQueueFamily.index, 0)
               .submit(
            [cmd],                                           // VkCommandBuffers
            [frame.imageAvailable],                          // wait semaphores
            [VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT], // wait stages
            [frame.renderFinished],                          // signal semaphores
            frame.fence
        );
    }
    void initialiseScene() {
        this.bgColour = clearValue(0.25f, 0, 0, 1);
    }
}
