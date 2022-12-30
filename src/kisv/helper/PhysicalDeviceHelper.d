module kisv.helper.PhysicalDeviceHelper;

import kisv.all;

final class PhysicalDeviceHelper {
private:
    KisvContext context;
public:
    KisvPhysicalDevice[] deviceInfos;

    this(KisvContext context) {
        this.context = context;

        log("Looking for physical devices");
        log("Requested device extensions:");
        foreach(e; context.props.deviceExtensions) {
            log("\t%s", e);
        }
        uint count;
	    check(vkEnumeratePhysicalDevices(context.instance, &count, null));
        auto deviceHandles = new VkPhysicalDevice[count];
        check(vkEnumeratePhysicalDevices(context.instance, &count, deviceHandles.ptr));

        log("\tPhysical devices (found %s):", count);

        deviceInfos.length = count;

        foreach(i, it; deviceHandles) {
            deviceInfos[i] = new KisvPhysicalDevice();
            deviceInfos[i].handle = it;
            deviceInfos[i].extensions = getExtensions(it);
            deviceInfos[i].properties = getProperties(it);
            deviceInfos[i].queueFamilies = getQueueFamilies(it);
            deviceInfos[i].memoryProperties = getMemoryProperties(it);
            deviceInfos[i].rtPipelineProperties = getRayTracingPipelineProperties(it);
            deviceInfos[i].accelerationStructureProperties = getAccelerationStructureProperties(it);

            log("\t[%s] %s", i, deviceInfos[i]);
        }
    }
private:
    void getProperties2(VkPhysicalDevice pDevice, void* pNext) {
        VkPhysicalDeviceProperties2 props2 = {
            sType: VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2,
            pNext: pNext
        };
        vkGetPhysicalDeviceProperties2(pDevice, &props2);
    }
    VkExtensionProperties[] getExtensions(VkPhysicalDevice pDevice) {
        VkExtensionProperties[] extensions;
        uint count;
        vkEnumerateDeviceExtensionProperties(pDevice, null, &count, null);
        extensions.length = count;
        vkEnumerateDeviceExtensionProperties(pDevice, null, &count, extensions.ptr);
        return extensions;
    }
    VkPhysicalDeviceProperties getProperties(VkPhysicalDevice pDevice) {
        VkPhysicalDeviceProperties properties;
        vkGetPhysicalDeviceProperties(pDevice, &properties);
        return properties;
    }
    VkQueueFamilyProperties[] getQueueFamilies(VkPhysicalDevice pDevice) {
        VkQueueFamilyProperties[] queueFamilies;
        uint count;
        vkGetPhysicalDeviceQueueFamilyProperties(pDevice, &count, null);
        queueFamilies.length = count;
        vkGetPhysicalDeviceQueueFamilyProperties(pDevice, &count, queueFamilies.ptr);
        return queueFamilies;
    }
    VkPhysicalDeviceMemoryProperties getMemoryProperties(VkPhysicalDevice pDevice) {
        VkPhysicalDeviceMemoryProperties memProperties;
        vkGetPhysicalDeviceMemoryProperties(pDevice, &memProperties);
        return memProperties;
    }
    VkPhysicalDeviceRayTracingPipelinePropertiesKHR getRayTracingPipelineProperties(VkPhysicalDevice pDevice) {
        VkPhysicalDeviceRayTracingPipelinePropertiesKHR rtProps = {
            sType: VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_RAY_TRACING_PIPELINE_PROPERTIES_KHR
        };
        getProperties2(pDevice, &rtProps);
        return rtProps;
    }
    VkPhysicalDeviceAccelerationStructurePropertiesKHR getAccelerationStructureProperties(VkPhysicalDevice pDevice) {
        VkPhysicalDeviceAccelerationStructurePropertiesKHR asProps = {
            sType: VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_ACCELERATION_STRUCTURE_PROPERTIES_KHR
        };
        getProperties2(pDevice, &asProps);
        return asProps;
    }
}