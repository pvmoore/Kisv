module kisv.helper.FeatureHelper;

import kisv.all;

final class FeatureHelper {
private:
    KisvContext context;
    VkPhysicalDeviceFeatures2 features2;
    FeatureStructure*[] features;
    struct FeatureStructure { ulong sType; void* pNext; /** the rest of the structure here... */ }
public:
    this(KisvContext context) {
        this.context = context;
    }
    auto addFeature(void* feature) {
        this.features ~= feature.as!(FeatureStructure*);
        return this;
    }
    void* query() {
        features2.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2;
        void* next = null;

        foreach(f; features) {
            f.pNext = next;
            next = f;
        }
        features2.pNext = next;

        vkGetPhysicalDeviceFeatures2(context.physicalDevice.handle, &features2);

        return &features2;
    }
}