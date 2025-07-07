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
    SamplerHelper samplers;
    DescriptorHelper descriptors;

    KisvPhysicalDevice physicalDevice;
    KisvWindow window;

    this(KisvProperties props) {
        this.props = props;
        this.shaders = new ShaderHelper(this);
        this.buffers = new BufferHelper(this);
        this.images = new ImageHelper(this);
        this.queues = new QueueHelper(this);
        this.samplers = new SamplerHelper(this);
        this.descriptors = new DescriptorHelper(this);

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

        // Add the debug utils extension if it's supported and not already there.
        // VK_EXT_debug_utils is preferred to VK_EXT_debug_report
        bool debugUtilsSupported = extensionProps.find!(it=>it.extensionName.fromStringz() == "VK_EXT_debug_utils") != null;                         

        if(debugUtilsSupported) {
            if(props.instanceExtensions.find("VK_EXT_debug_utils") == null) {
                props.instanceExtensions ~= "VK_EXT_debug_utils";
            }
        }

        auto extensions = props.instanceExtensions
                               .map!(it=>it.toStringz())
                               .array();

        VkApplicationInfo appInfo = {
            sType: VK_STRUCTURE_TYPE_APPLICATION_INFO,
            pApplicationName: props.appName.toStringz(),
            applicationVersion: props.appVersion,
            pEngineName: props.engineName.toStringz(),
            engineVersion: props.engineVersion,
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

        if(debugUtilsSupported) {
            setupDebugUtils();
        }
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
            if(samplers) samplers.destroy();
            if(descriptors) descriptors.destroy();

            log("\tDestroying device");
            vkDestroyDevice(device, null);
        }
        if(instance) {
            log("\tDestroying instance");
            if(debugUtilsCallback) vkDestroyDebugUtilsMessengerEXT(instance, debugUtilsCallback, null);
            vkDestroyInstance(instance, null);
        }
        log("\tUnloading");
        glfwTerminate();
        GLFWLoader.unload();
        VulkanLoader.unload();
    }
    void startRenderLoop(void delegate(KisvFrame, uint) renderCallback) {
        renderLoop.run(renderCallback);
    }
    void selectPhysicalDevice(int delegate(KisvPhysicalDevice[]) func) {
        auto physicalDevices = KisvPhysicalDevice.enumerateAll(this);

        int selected = func(physicalDevices);
        throwIf(selected >= physicalDevices.length);
        this.physicalDevice = physicalDevices[selected];
        log("\tSelected physical device '%s'", physicalDevice.name());
        log("\tSupported extensions:");
        foreach(e; physicalDevice.extensions) {
            log("\t\t%s %s", e.extensionName.fromStringz(), versionToString(e.specVersion));
        }

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
        log("Creating logical device");
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
        log("\tEnabling extensions:");
        foreach(e; props.deviceExtensions) {
            log("\t\t%s", e);
        }

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
    void setupDebugUtils() {
        VkDebugUtilsMessengerCreateInfoEXT dbgCreateInfo = {
            sType: VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
            messageSeverity: 0
                //| VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT
                //| VK_DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT
                | VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT
                | VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT
                ,
            messageType: 0
                | VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT
                | VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT
                | VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT
                //| VK_DEBUG_UTILS_MESSAGE_TYPE_DEVICE_ADDRESS_BINDING_BIT_EXT
                ,
            pfnUserCallback: &debugUtilsMessengerCallbackEXTFunc
        };

        VkResult result = vkCreateDebugUtilsMessengerEXT(instance, &dbgCreateInfo, null, &debugUtilsCallback);
        if(result == VK_SUCCESS) {
            log("VK_EXT_debug_utils extension enabled");
        } else {
            log("[WARN] Failed to enable VK_EXT_debug_utils extension: %s", result);
        }
    }
private:
    VkDebugUtilsMessengerEXT debugUtilsCallback;
    void* features2;
    KisvRenderLoop renderLoop;
}
