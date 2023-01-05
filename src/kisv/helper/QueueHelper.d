module kisv.helper.QueueHelper;

import kisv.all;

struct QueueInfo {
    uint index;
    uint numQueues;
}

final class QueueHelper {
public:
    this(KisvContext context) {
        this.context = context;
    }
    void destroy() {
        // Nothing to do
    }
    void initialise() {
        this.queueFamilies = context.physicalDevice.queueFamilies;
    }
    void deviceCreated(VkDevice device, uint[uint] queuesPerFamily) {
        foreach(entry; queuesPerFamily.byKeyValue()) {
            uint family = entry.key();
            uint numQueues = entry.value();

            VkQueue[] queueList = new VkQueue[numQueues];

            foreach(i; 0..numQueues) {
                vkGetDeviceQueue(device, family, i.as!int, &queueList[i]);
            }
            queuesMap[family] = queueList;
        }
    }
    VkQueue getQueue(uint family, uint index) {
        auto list = family in queuesMap;
        throwIf(!list, "Queue family %s is not in the list", family);
        throwIf(index >= list.length, "Queue index %s >= %s", index, list.length);
        return (*list)[index];
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
private:
    KisvContext context;
    VkQueueFamilyProperties[] queueFamilies;
    VkQueue[][uint] queuesMap;
}