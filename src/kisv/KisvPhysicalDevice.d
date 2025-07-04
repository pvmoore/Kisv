module kisv.KisvPhysicalDevice;

import kisv.all;

final class KisvPhysicalDevice {
public:
    VkPhysicalDevice handle;

    VkExtensionProperties[] extensions;
    VkPhysicalDeviceProperties properties;
    VkQueueFamilyProperties[] queueFamilies;
    VkPhysicalDeviceMemoryProperties memoryProperties;
    VkPhysicalDeviceRayTracingPipelinePropertiesKHR rtPipelineProperties;
    VkPhysicalDeviceAccelerationStructurePropertiesKHR accelerationStructureProperties;

    bool supportsVersion(VkVersion ver) {
        return VkVersion(properties.apiVersion).isEqualOrGreaterThan(ver);
    }
    bool supportsExtensions(string[] requestedExtensions) {
        bool[string] found;
        foreach(e; extensions) {
            string name = e.extensionName.fromStringz().as!string;
            if(!requestedExtensions.find(name).empty) {
                found[name] = true;
            }
        }
        return found.length == requestedExtensions.length;
    }
    bool supportsFormat(VkFormat format) {
        auto fp = getFormatProperties(format);
        return fp.linearTilingFeatures != 0 ||
               fp.optimalTilingFeatures != 0 ||
               fp.bufferFeatures != 0;
    }

    string name() { return properties.deviceName.fromStringz().as!string; }

    VkMemoryType[] getMemoryTypes() {
        return memoryProperties.memoryTypes[0..memoryProperties.memoryTypeCount];
    }
    VkMemoryHeap[] getMemoryHeaps() {
        return memoryProperties.memoryHeaps[0..memoryProperties.memoryHeapCount];
    }

    bool canPresent(VkSurfaceKHR surface, uint queueFamilyIndex) {
        uint canPresent;
        vkGetPhysicalDeviceSurfaceSupportKHR(
            handle,
            queueFamilyIndex,
            surface,
            &canPresent);
        return canPresent==VK_TRUE;
    }
    VkSurfaceFormatKHR[] getFormats(VkSurfaceKHR surface) {
        VkSurfaceFormatKHR[] formats;
        VkFormat colorFormat;
        VkColorSpaceKHR colorSpace;
        uint formatCount;

        vkGetPhysicalDeviceSurfaceFormatsKHR(handle, surface, &formatCount, null);
        formats.length = formatCount;
        vkGetPhysicalDeviceSurfaceFormatsKHR(handle, surface, &formatCount, formats.ptr);

        return formats;
    }
    VkSurfaceCapabilitiesKHR getCapabilities(VkSurfaceKHR surface) {
        VkSurfaceCapabilitiesKHR caps;
        check(vkGetPhysicalDeviceSurfaceCapabilitiesKHR(handle, surface, &caps));
        return caps;
    }
    VkPresentModeKHR[] getPresentModes(VkSurfaceKHR surface) {
        VkPresentModeKHR[] presentModes;
        uint count;
        check(vkGetPhysicalDeviceSurfacePresentModesKHR(handle, surface, &count, null));
        presentModes.length = count;

        check(vkGetPhysicalDeviceSurfacePresentModesKHR(handle, surface, &count, presentModes.ptr));
        return presentModes;
    }
    VkFormatProperties getFormatProperties(VkFormat format) {
        VkFormatProperties props;
        vkGetPhysicalDeviceFormatProperties(handle, format, &props);
        return props;
    }
    VkExtensionProperties[] getExtensions() {
        VkExtensionProperties[] ext;
        uint count;
        vkEnumerateDeviceExtensionProperties(handle, null, &count, null);
        ext.length = count;
        vkEnumerateDeviceExtensionProperties(handle, null, &count, ext.ptr);
        return ext;
    }
    VkPhysicalDeviceProperties getProperties() {
        VkPhysicalDeviceProperties props;
        vkGetPhysicalDeviceProperties(handle, &props);
        return props;
    }
    VkQueueFamilyProperties[] getQueueFamilies() {
        VkQueueFamilyProperties[] qf;
        uint count;
        vkGetPhysicalDeviceQueueFamilyProperties(handle, &count, null);
        qf.length = count;
        vkGetPhysicalDeviceQueueFamilyProperties(handle, &count, qf.ptr);
        return qf;
    }
    VkPhysicalDeviceMemoryProperties getMemoryProperties() {
        VkPhysicalDeviceMemoryProperties mp;
        vkGetPhysicalDeviceMemoryProperties(handle, &mp);
        return mp;
    }
    VkPhysicalDeviceRayTracingPipelinePropertiesKHR getRayTracingPipelineProperties() {
        VkPhysicalDeviceRayTracingPipelinePropertiesKHR props = {
            sType: VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_RAY_TRACING_PIPELINE_PROPERTIES_KHR
        };
        getProperties2(&props);
        return props;
    }
    VkPhysicalDeviceAccelerationStructurePropertiesKHR getAccelerationStructureProperties() {
        VkPhysicalDeviceAccelerationStructurePropertiesKHR props = {
            sType: VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_ACCELERATION_STRUCTURE_PROPERTIES_KHR
        };
        getProperties2(&props);
        return props;
    }
    void getProperties2(void* pNext) {
        VkPhysicalDeviceProperties2 props2 = {
            sType: VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2,
            pNext: pNext
        };
        vkGetPhysicalDeviceProperties2(handle, &props2);
    }
    VkPhysicalDeviceBufferDeviceAddressFeatures getBufferDeviceAddressFeatures() {
        VkPhysicalDeviceBufferDeviceAddressFeatures feats = {
            sType: VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_BUFFER_DEVICE_ADDRESS_FEATURES
        };
        getFeatures2(&feats);
        return feats;
    }
    VkPhysicalDeviceAccelerationStructureFeaturesKHR getAccelerationStructureFeatures() {
        VkPhysicalDeviceAccelerationStructureFeaturesKHR feats = {
            sType: VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_ACCELERATION_STRUCTURE_FEATURES_KHR
        };
        getFeatures2(&feats);
        return feats;
    }
    VkPhysicalDeviceRayTracingPipelineFeaturesKHR getRayTracingPipelineFeatures() {
        VkPhysicalDeviceRayTracingPipelineFeaturesKHR feats = {
            sType: VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_RAY_TRACING_PIPELINE_FEATURES_KHR
        };
        getFeatures2(&feats);
        return feats;
    }
    void getFeatures2(void* pNext) {
        VkPhysicalDeviceFeatures2 feats2 = {
            sType: VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2,
            pNext: pNext
        };
        vkGetPhysicalDeviceFeatures2(handle, &feats2);
    }

    override string toString() {
        return "PhysicalDevice{name:'%s', type:%s, apiVersion:%s, driverVersion:%s}".format(
            name(),
            properties.deviceType,
            VkVersion(properties.apiVersion),
            versionToString(properties.driverVersion)
        );
    }

//──────────────────────────────────────────────────────────────────────────────────────────────────

    static KisvPhysicalDevice[] enumerateAll(KisvContext context) {
        log("Enumerating physical devices");
        uint count;
	    check(vkEnumeratePhysicalDevices(context.instance, &count, null));
        auto deviceHandles = new VkPhysicalDevice[count];
        check(vkEnumeratePhysicalDevices(context.instance, &count, deviceHandles.ptr));

        log("\tPhysical devices (found %s):", count);

        auto devices = new KisvPhysicalDevice[count];

        foreach(i, it; deviceHandles) {
            auto device = new KisvPhysicalDevice();
            devices[i] = device;
            devices[i].handle = it;
            devices[i].extensions = device.getExtensions();
            devices[i].properties = device.getProperties();
            devices[i].queueFamilies = device.getQueueFamilies();
            devices[i].memoryProperties = device.getMemoryProperties();
            devices[i].rtPipelineProperties = device.getRayTracingPipelineProperties();
            devices[i].accelerationStructureProperties = device.getAccelerationStructureProperties();

            log("\t[%s] %s", i, devices[i]);
        }
        return devices;
    }
}
