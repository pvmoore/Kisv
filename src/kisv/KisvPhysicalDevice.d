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

    string name() { return properties.deviceName.fromStringz().as!string; }

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

    override string toString() {
        return "PhysicalDevice{name:'%s', type:%s, apiVersion:%s, driverVersion:%s}".format(
            name(),
            properties.deviceType,
            VkVersion(properties.apiVersion),
            versionToString(properties.driverVersion)
        );
    }
}