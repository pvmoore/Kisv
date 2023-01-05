module kisv.KisvContext;

import kisv.all;

final class KisvContext {
public:
    KisvProperties props;
    VkInstance instance;
    VkDevice device;
    VkRenderPass renderPass;

    MemoryHelper memory;
    BufferHelper buffers;
    ImageHelper images;
    TransferHelper transfer;
    ShaderHelper shaders;
    QueueHelper queues;

    KisvPhysicalDevice physicalDevice;
    KisvWindow window;

    this(KisvProperties props) {
        this.props = props;
        this.shaders = new ShaderHelper(this);
        this.buffers = new BufferHelper(this);
        this.images = new ImageHelper(this);
        this.queues = new QueueHelper(this);

        // Keep it simple. Drop support for Vulkan 1.0
        throwIf(!props.apiVersion.isEqualOrGreaterThan(VkVersion(1,1,0)), "The minimum supported Vulkan version is 1.1");

        log("Creating Kisv context");
        log("Loading shared libraries");
        GLFWLoader.load();
        VulkanLoader.load();
        vkLoadGlobalCommandFunctions();

        log("Initialising GLFW %s", glfwGetVersionString().fromStringz);
        if(!glfwInit()) {
            glfwTerminate();
            throw new Exception("glfwInit failed");
        }
        if(!glfwVulkanSupported()) {
            throw new Exception("Vulkan is not supported on this device");
        }
        log("GLFW initialised");

        uint driverApiVersion;
        vkEnumerateInstanceVersion(&driverApiVersion);
        auto driverVersion = VkVersion(driverApiVersion);
        log("Vulkan driver supports API version %s", driverVersion);

        // Ensure the driver can support the Vulkan version requested
        if(!driverVersion.isEqualOrGreaterThan(props.apiVersion)) {
            throw new Exception("The driver does not support the requested Vulkan version %s".format(props.appVersion));
        }

        // Dump supported instance layers
        uint count;
        vkEnumerateInstanceLayerProperties(&count, null);
        auto layerProps = new VkLayerProperties[count];
        vkEnumerateInstanceLayerProperties(&count, layerProps.ptr);
        log("Supported instance layers:");
        foreach(lp; layerProps) {
            log("\t%s", lp.layerName.fromStringz());
        }

        // Dump supported instance extensions
        vkEnumerateInstanceExtensionProperties(null, &count, null);
        auto extensionProps = new VkExtensionProperties[count];
        vkEnumerateInstanceExtensionProperties(null, &count, extensionProps.ptr);
        log("Supported instance extensions:");
        foreach(ep; extensionProps) {
            log("\t%s", ep.extensionName.fromStringz());
        }

        auto layers = props.instanceLayers
                           .map!(it=>it.toStringz())
                           .array();
        auto extensions = props.instanceExtensions
                               .map!(it=>it.toStringz())
                               .array();

        VkApplicationInfo appInfo = {
            sType: VK_STRUCTURE_TYPE_APPLICATION_INFO,
            pApplicationName: props.appName.toStringz(),
            applicationVersion: props.appVersion,
            pEngineName: props.engineName.toStringz(),
            engineVersion:props.engineVersion,
            apiVersion: props.apiVersion.intValue()
        };

        VkInstanceCreateInfo createInfo = {
            sType: VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
            pApplicationInfo: &appInfo,
            enabledLayerCount: props.instanceLayers.length.as!int,
            ppEnabledLayerNames: layers.ptr,
            enabledExtensionCount: props.instanceExtensions.length.as!int,
            ppEnabledExtensionNames: extensions.ptr
        };

        log("Requesting instance layers:");
        foreach(it; props.instanceLayers) {
            log("\t%s", it);
        }

        log("Requesting instance extensions:");
        foreach(it; props.instanceExtensions) {
            log("\t%s", it);
        }

        log("Creating VkInstance");
        check(vkCreateInstance(&createInfo, null, &instance));

        log("Loading instance functions");
        vkLoadInstanceFunctions(instance);

        // Direct Vulkan debug messages to the kisv.log (via dbgFunc)
        VkDebugReportCallbackCreateInfoEXT dbgCreateInfo = {
            sType: VK_STRUCTURE_TYPE_DEBUG_REPORT_CREATE_INFO_EXT,
            flags: 0
				| VK_DEBUG_REPORT_ERROR_BIT_EXT
				| VK_DEBUG_REPORT_WARNING_BIT_EXT
			//	| VK_DEBUG_REPORT_INFORMATION_BIT_EXT
            //  | VK_DEBUG_REPORT_DEBUG_BIT_EXT
				| VK_DEBUG_REPORT_PERFORMANCE_WARNING_BIT_EXT,
            pfnCallback: &dbgFunc
        };

        check(vkCreateDebugReportCallbackEXT(instance, &dbgCreateInfo, null, &debugCallback));
    }
    void destroy() {
        log("Destroying Kisv");
        if(device) {
            vkDeviceWaitIdle(device);

            if(renderLoop) renderLoop.destroy();
            if(transfer) transfer.destroy();
            if(window) window.destroy();
            if(renderPass) vkDestroyRenderPass(device, renderPass, null);
            if(shaders) shaders.destroy();
            if(buffers) buffers.destroy();
            if(images) images.destroy();
            if(memory) memory.destroy();
            if(queues) queues.destroy();

            log("\tDestroying device");
            vkDestroyDevice(device, null);
        }
        if(instance) {
            log("\tDestroying instance");
            if(debugCallback) vkDestroyDebugReportCallbackEXT(instance, debugCallback, null);
            vkDestroyInstance(instance, null);
        }
        log("\tUnloading");
        glfwTerminate();
        GLFWLoader.unload();
        VulkanLoader.unload();
    }
    void startRenderLoop(void delegate(KisvFrame) renderCallback) {
        renderLoop.run(renderCallback);
    }
    void selectPhysicalDevice(int delegate(KisvPhysicalDevice[]) func) {
        auto physicalDevices = KisvPhysicalDevice.enumerateAll(this);

        int selected = func(physicalDevices);
        throwIf(selected >= physicalDevices.length);
        this.physicalDevice = physicalDevices[selected];
        log("\tSelected physical device '%s'", physicalDevice.name());

        this.memory = new MemoryHelper(this);
    }
    void selectQueueFamilies(void delegate(QueueHelper queues) func) {
        queues.initialise();
        func(queues);
    }
    void selectDeviceFeatures(void delegate(FeatureHelper) func) {
        auto helper = new FeatureHelper(this);
        func(helper);
        this.features2 = helper.query();
    }
    void createLogicalDevice(uint[uint] queuesPerFamily) {
        VkDeviceQueueCreateInfo[] queueCreateInfos;

        foreach(entry; queuesPerFamily.byKeyValue()) {
            uint family = entry.key();
            uint numQueues = entry.value();

            float[] priorities = new float[numQueues];
            priorities[] = 1.0f;

            VkDeviceQueueCreateInfo queueInfo = {
                sType: VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
                queueFamilyIndex: family,
                queueCount: numQueues,
                pQueuePriorities: priorities.ptr
            };
            queueCreateInfos ~= queueInfo;
        }

        auto extensions = props.deviceExtensions.map!(it=>it.toStringz()).array;

        VkDeviceCreateInfo createInfo = {
            sType: VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
            flags: 0,
            enabledExtensionCount: props.deviceExtensions.length.as!int,
            ppEnabledExtensionNames: extensions.ptr,
            pQueueCreateInfos: queueCreateInfos.ptr,
            queueCreateInfoCount: queueCreateInfos.length.as!int,
            pNext: features2
        };

        check(vkCreateDevice(physicalDevice.handle, &createInfo, null, &device));

        // Fetch the queues
        queues.deviceCreated(device, queuesPerFamily);
    }
    void createWindow(VkImageUsageFlagBits usage = 0.as!VkImageUsageFlagBits) {
        this.window = new KisvWindow(this);
        window.create(usage);
    }
    void createStandardRenderPass() {
        this.renderPass = createRenderPass(this);
        window.createFrameBuffers(renderPass);
    }
    void createTransferHelper(uint family) {
        this.transfer = new TransferHelper(this, family);
    }
    void createRenderLoop(uint graphicsQueueFamily) {
        throwIf(!physicalDevice.canPresent(window.surface, graphicsQueueFamily),
            "This surface cannot present on queue %s", graphicsQueueFamily);
        this.renderLoop = new KisvRenderLoop(this, graphicsQueueFamily);
    }
private:
    VkDebugReportCallbackEXT debugCallback;
    void* features2;
    KisvRenderLoop renderLoop;
}