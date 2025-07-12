module kisv.helper.FeatureHelper;

import kisv.all;

final class FeatureHelper {
public:
    this(KisvContext context) {
        this.context = context;
    }
    auto add(VkPhysicalDeviceVulkan11Features feature) {
        this.vulkan11Features = feature;
        pointers ~= cast(FeatureStructure*)&vulkan11Features;
        return this;
    }
    auto add(VkPhysicalDeviceVulkan12Features feature) {
        this.vulkan12Features = feature;
        pointers ~= cast(FeatureStructure*)&vulkan12Features;
        return this;
    }
    auto add(VkPhysicalDeviceVulkan13Features feature) {
        this.vulkan13Features = feature;
        pointers ~= cast(FeatureStructure*)&vulkan13Features;
        return this;
    }
    auto add(VkPhysicalDeviceVulkan14Features feature) {
        this.vulkan14Features = feature;
        pointers ~= cast(FeatureStructure*)&vulkan14Features;
        return this;
    }
    auto add(VkPhysicalDeviceAccelerationStructureFeaturesKHR feature) {
        this.accelerationStructureFeatures = feature;
        pointers ~= cast(FeatureStructure*)&accelerationStructureFeatures;
        return this;
    }
    auto add(VkPhysicalDeviceRayTracingPipelineFeaturesKHR feature) {
        this.rayTracingPipelineFeatures = feature;
        pointers ~= cast(FeatureStructure*)&rayTracingPipelineFeatures;
        return this;
    }
    auto add(VkPhysicalDeviceBufferDeviceAddressFeaturesEXT feature) {
        this.bufferDeviceAddressFeatures = feature;
        pointers ~= cast(FeatureStructure*)&bufferDeviceAddressFeatures;
        return this;
    }
    void* query() {
        features2.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2;
        void* next = null;

        foreach(f; pointers) {
            f.pNext = next;
            next = f;
        }
        features2.pNext = next;

        vkGetPhysicalDeviceFeatures2(context.physicalDevice.handle, &features2);

        return &features2;
    }
private:
    KisvContext context;
    VkPhysicalDeviceFeatures2 features2;
    struct FeatureStructure { VkStructureType sType; void* pNext; /** the rest of the structure here... */ }

    FeatureStructure*[] pointers;
    VkPhysicalDeviceVulkan11Features vulkan11Features;
    VkPhysicalDeviceVulkan12Features vulkan12Features;
    VkPhysicalDeviceVulkan13Features vulkan13Features;
    VkPhysicalDeviceVulkan14Features vulkan14Features;
    VkPhysicalDeviceAccelerationStructureFeaturesKHR accelerationStructureFeatures;
    VkPhysicalDeviceRayTracingPipelineFeaturesKHR rayTracingPipelineFeatures;
    VkPhysicalDeviceBufferDeviceAddressFeaturesEXT bufferDeviceAddressFeatures;
}
