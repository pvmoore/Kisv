module kisv.helper.QueueHelper;

import kisv.all;

struct QueueInfo {
    uint index;
    uint numQueues;
}

final class QueueHelper {
private:
    KisvContext context;
    VkQueueFamilyProperties[] queueFamilies;
public:
    this(KisvContext context) {
        this.context = context;
        this.queueFamilies = context.physicalDevice.queueFamilies;
    }
    QueueInfo[] find(VkQueueFlagBits withFlags, VkQueueFlagBits withoutFlags = 0.as!VkQueueFlagBits) {
        QueueInfo[] list;
        foreach(i, f; queueFamilies) {
            if(f.queueCount==0) continue;
            if((f.queueFlags & withoutFlags) != 0) continue;
            if((f.queueFlags & withFlags) == withFlags) {
                list ~= QueueInfo(i.as!uint, f.queueCount);
            }
        }
        return list;
    }
    bool supports(uint family, VkQueueFlagBits flags) {
        return (queueFamilies[family].queueFlags & flags) == flags;
    }
}