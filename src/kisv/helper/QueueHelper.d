module kisv.helper.QueueHelper;

import kisv.all;

final class QueueHelper {
private:
    KisvContext context;
    VkQueueFamilyProperties[] queueFamilies;
public:
    this(KisvContext context) {
        this.context = context;
        this.queueFamilies = context.physicalDevice.queueFamilies;
    }
    QueueFamily[] find(VkQueueFlagBits withFlags, VkQueueFlagBits withoutFlags = 0.as!VkQueueFlagBits) {
        QueueFamily[] list;
        foreach(i, f; queueFamilies) {
            if(f.queueCount==0) continue;
            if((f.queueFlags & withoutFlags) != 0) continue;
            if((f.queueFlags & withFlags) == withFlags) {
                list ~= QueueFamily(i.as!uint, f.queueCount);
            }
        }
        return list;
    }
    bool supports(QueueFamily family, VkQueueFlagBits flags) {
        return (queueFamilies[family.index].queueFlags & flags) == flags;
    }
}