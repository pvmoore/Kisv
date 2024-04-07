module kisv.helper.MemoryHelper;

import kisv.all;

struct MemoryInfo {
    VkDeviceMemory handle;
    VkMemoryPropertyFlags flags;
    ulong size;
}

final class MemoryHelper {
public:
    this(KisvContext context) {
        this.context = context;
        this.memoryTypes = context.physicalDevice.getMemoryTypes();
        this.memoryHeaps = context.physicalDevice.getMemoryHeaps();
        selectTypes();
    }
    void destroy() {
        log("\tDestroying MemoryHelper");
        foreach(e; allocatedMemory.byKeyValue()) {
            log("\t\tFreeing memory '%s'", e.key);
            vkFreeMemory(context.device, e.value.handle, null);
        }
    }
    MemoryInfo* getMemory(string key) {
        MemoryInfo* ptr = key in allocatedMemory;
        throwIf(!ptr, "Memory '%s' not allocated", key);
        return ptr;
    }
    MemoryInfo allocateDeviceMemory(string key, ulong size, VkMemoryAllocateFlagBits flags = 0.as!VkMemoryAllocateFlagBits) {
        log("Allocating device memory: '%s' %s", key, mbToString(size));
        VkDeviceMemory handle = allocateMemory(context.device, deviceType, size, flags);
        auto info = MemoryInfo(handle, memoryTypes[deviceType].propertyFlags, size);
        allocatedMemory[key] = info;
        memoryToAllocOffset[key] = 0;
        return info;
    }
    MemoryInfo allocateStagingUploadMemory(string key, ulong size, VkMemoryAllocateFlagBits flags = 0.as!VkMemoryAllocateFlagBits) {
        log("Allocating staging upload memory: '%s' %s", key, mbToString(size));
        VkDeviceMemory handle = allocateMemory(context.device, hostUploadType, size, flags);
        auto info = MemoryInfo(handle, memoryTypes[hostUploadType].propertyFlags, size);
        allocatedMemory[key] = info;
        memoryToAllocOffset[key] = 0;
        return info;
    }
    MemoryInfo allocateStagingDownloadMemory(string key, ulong size, VkMemoryAllocateFlagBits flags = 0.as!VkMemoryAllocateFlagBits) {
        log("Allocating staging download memory: '%s' %s", key, mbToString(size));
        VkDeviceMemory handle = allocateMemory(context.device, hostDownloadType, size, flags);
        auto info = MemoryInfo(handle, memoryTypes[hostDownloadType].propertyFlags, size);
        allocatedMemory[key] = info;
        memoryToAllocOffset[key] = 0;
        return info;
    }
    /** Bind the buffer to the memory and return the memory offset */
    ulong bind(string memoryKey, VkBuffer buffer, ulong delegate(ulong) customAlignment = null) {
        MemoryInfo* memory = getMemory(memoryKey);
        ulong offset = memoryToAllocOffset[memoryKey];

        // Get requirements
        VkMemoryRequirements memRequirements;
        vkGetBufferMemoryRequirements(context.device, buffer, &memRequirements);

        // Align
        offset = alignedTo(offset, memRequirements.alignment);

        if(customAlignment) {
            offset = customAlignment(offset);
        }

        throwIf(offset + memRequirements.size > memory.size,
            "Memory allocation exceeded. allocation size = %s, current offset = %s, request size = %s",
            memory.size, offset, memRequirements.size);

        log("Binding buffer to memory '%s' at offset %s size %s (%%%.2f used)", memoryKey, offset,
            memRequirements.size, (offset+memRequirements.size).as!double / memory.size*100.0);
        log("\tRequirements = %s", memRequirements.toString());

        // Bind
        check(vkBindBufferMemory(context.device, buffer, memory.handle, offset));

        ulong nextOffset = offset + memRequirements.size;
        memoryToAllocOffset[memoryKey] = nextOffset;
        return offset;
    }
    /** Bind the image to the memory and return the memory offset */
    ulong bind(string memoryKey, VkImage image) {
        MemoryInfo* memory = getMemory(memoryKey);
        ulong offset = memoryToAllocOffset[memoryKey];

        // Get requirements
        VkMemoryRequirements memRequirements;
        vkGetImageMemoryRequirements(context.device, image, &memRequirements);

        // Align
        offset = alignedTo(offset, memRequirements.alignment);

        throwIf(offset + memRequirements.size > memory.size,
            "Memory allocation exceeded. allocation size = %s, current offset = %s, request size = %s",
            memory.size, offset, memRequirements.size);

        log("Binding image to memory '%s' at offset %s size %s (%%%.2f used)", memoryKey, offset,
            memRequirements.size, (offset+memRequirements.size).as!double / memory.size*100.0);

        // Bind
        check(vkBindImageMemory(context.device, image, memory.handle, offset));

        ulong nextOffset = offset + memRequirements.size;
        memoryToAllocOffset[memoryKey] = nextOffset;
        return offset;
    }
    void* map(string memoryKey, ulong offset, ulong size) {
        MemoryInfo* mem = getMemory(memoryKey);
        return mapMemory(context.device, mem.handle, offset, size);
    }
    void unmap(string memoryKey) {
        MemoryInfo* mem = getMemory(memoryKey);
        vkUnmapMemory(context.device, mem.handle);
    }
private:
    KisvContext context;
    VkMemoryType[] memoryTypes;
    VkMemoryHeap[] memoryHeaps;
    uint deviceType = uint.max;
    uint sharedType = uint.max;
    uint hostUploadType = uint.max;
    uint hostDownloadType = uint.max;

    MemoryInfo[string] allocatedMemory;
    ulong[string] memoryToAllocOffset;  // track next free allocation offset per memory

    void selectTypes() {
        ulong largestDeviceSize;
        ulong largestUploadSize;
        ulong largestDownloadSize;
        ulong largestSharedSize;

        log("Memory Heaps:");
        foreach(i, h; memoryHeaps) {
            log("\t[%s] %s %s", i, h.size, enumToString!VkMemoryHeapFlagBits(h.flags));
        }

        log("Memory Types:");
        foreach(i, t; memoryTypes) {
            log("\t[%s] %s %s", i, enumToString!VkMemoryPropertyFlagBits(t.propertyFlags), t.heapIndex);
        }

        foreach(i, t; memoryTypes) {

            // Device local
            if(t.propertyFlags.isSet(VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT) &&
               t.propertyFlags.isUnset(VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT))
            {
                if(memoryHeaps[t.heapIndex].size > largestDeviceSize) {
                    largestDeviceSize = memoryHeaps[t.heapIndex].size;
                    deviceType = i.as!uint;
                }
            }

            // Staging upload
            if(t.propertyFlags.isSet(VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT) &&
                t.propertyFlags.isUnset(VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT) &&
                t.propertyFlags.isSet(VK_MEMORY_PROPERTY_HOST_COHERENT_BIT) &&
                t.propertyFlags.isUnset(VK_MEMORY_PROPERTY_HOST_CACHED_BIT))
            {
                if(memoryHeaps[t.heapIndex].size > largestUploadSize) {
                    largestUploadSize = memoryHeaps[t.heapIndex].size;
                    hostUploadType = i.as!uint;
                }
            }

            // Staging download
            if(t.propertyFlags.isSet(VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT) &&
                t.propertyFlags.isUnset(VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT) &&
                t.propertyFlags.isSet(VK_MEMORY_PROPERTY_HOST_COHERENT_BIT) &&
                t.propertyFlags.isSet(VK_MEMORY_PROPERTY_HOST_CACHED_BIT))
            {
                if(memoryHeaps[t.heapIndex].size > largestDownloadSize) {
                    largestDownloadSize = memoryHeaps[t.heapIndex].size;
                    hostDownloadType = i.as!uint;
                }
            }

            // Shared
            if(t.propertyFlags.isSet(VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT) &&
               t.propertyFlags.isSet(VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT))
            {
                if(memoryHeaps[t.heapIndex].size > largestSharedSize) {
                    largestSharedSize = memoryHeaps[t.heapIndex].size;
                    sharedType = i.as!uint;
                }
            }
        }
        log("\tDevice type %s", deviceType);
        log("\tShared type %s", sharedType);
        log("\tHost upload type %s", hostUploadType);
        log("\tHost download type %s", hostDownloadType);
    }
}