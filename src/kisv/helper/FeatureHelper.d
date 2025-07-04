module kisv.helper.FeatureHelper;

import kisv.all;

final class FeatureHelper {
public:
    this(KisvContext context) {
        this.context = context;
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
    VkPhysicalDeviceAccelerationStructureFeaturesKHR accelerationStructureFeatures;
    VkPhysicalDeviceRayTracingPipelineFeaturesKHR rayTracingPipelineFeatures;
    VkPhysicalDeviceBufferDeviceAddressFeaturesEXT bufferDeviceAddressFeatures;
}
