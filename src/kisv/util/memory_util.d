module kisv.util.memory_util;

import kisv.all;

VkDeviceMemory allocateMemory(VkDevice device,
                              uint typeIndex,
                              ulong sizeBytes,
                              VkMemoryAllocateFlagBits allocateFlags = 0.as!VkMemoryAllocateFlagBits)
{
    void* pNext = null;

    // Add VkMemoryAllocateFlagsInfo to the chain
    if(allocateFlags != 0) {
        // VK_MEMORY_ALLOCATE_DEVICE_MASK_BIT
        // VK_MEMORY_ALLOCATE_DEVICE_ADDRESS_BIT
        // VK_MEMORY_ALLOCATE_DEVICE_ADDRESS_CAPTURE_REPLAY_BIT

        VkMemoryAllocateFlagsInfo flagsInfo = {
            sType: VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_FLAGS_INFO,
            pNext: null,
            flags: allocateFlags,
            deviceMask: 0
        };
        pNext = &flagsInfo;
    }

    VkMemoryAllocateInfo info = {
        sType: VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
        pNext: pNext,
        memoryTypeIndex: typeIndex,
        allocationSize: sizeBytes
    };

    VkDeviceMemory memory;
    check(vkAllocateMemory(device, &info, null, &memory));
    return memory;
}
void freeMemory(VkDevice device, VkDeviceMemory memory) {
    vkFreeMemory(device, memory, null);
}

void bindBufferToMemory(VkDevice device, VkBuffer buffer, VkDeviceMemory memory, ulong offset=0) {
    check(vkBindBufferMemory(device, buffer, memory, offset));
}
void bindImageToMemory(VkDevice device, VkImage image, VkDeviceMemory memory, ulong offset=0) {
    check(vkBindImageMemory(device, image, memory, offset));
}

void* mapMemory(VkDevice device, VkDeviceMemory memory, ulong offset, ulong sizeBytes) {
    void* data;
    VkMemoryMapFlags flags = 0;
    check(vkMapMemory(device, memory, offset, sizeBytes, flags, &data));
    return data;
}
void flushMappedMemory(VkDevice device, VkDeviceMemory memory, ulong offset, ulong size) {
    VkMappedMemoryRange r = {
        sType: VK_STRUCTURE_TYPE_MAPPED_MEMORY_RANGE,
        memory: memory,
        offset: offset,
        size: size
    };
    flushMappedMemoryRanges(device, [r]);
}
void flushMappedMemoryRanges(VkDevice device, VkMappedMemoryRange[] ranges) {
    check(vkFlushMappedMemoryRanges(device, ranges.length.as!uint, ranges.ptr));
}