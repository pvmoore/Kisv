module kisv.util.rt_util;

import kisv.all;

/**
 * Create and return an identity (3x4) matrix
 *
 * 1  0  0  0
 * 0  1  0  0
 * 0  0  1  0
 */
VkTransformMatrixKHR identityTransformMatrix() {

    VkTransformMatrixKHR transform = { matrix: [
        [1.0f, 0.0f, 0.0f, 0.0f],
        [0.0f, 1.0f, 0.0f, 0.0f],
        [0.0f, 0.0f, 1.0f, 0.0f]]
    };

    return transform;
}

/** Display in row-major order */
string toString(VkTransformMatrixKHR t) {
    return format("%s %s %s %s\n%s %s %s %s\n%s %s %s %s", 
        t.matrix[0][0], t.matrix[0][1], t.matrix[0][2], t.matrix[0][3],
        t.matrix[1][0], t.matrix[1][1], t.matrix[1][2], t.matrix[1][3],
        t.matrix[2][0], t.matrix[2][1], t.matrix[2][2], t.matrix[2][3]);
}

VkDeviceAddress getDeviceAddress(VkDevice device, VkBuffer buffer) {
    VkBufferDeviceAddressInfo info = {
        sType: VK_STRUCTURE_TYPE_BUFFER_DEVICE_ADDRESS_INFO,
        buffer: buffer
    };
    return vkGetBufferDeviceAddressKHR(device, &info);
}

VkDeviceAddress getDeviceAddress(VkDevice device, VkAccelerationStructureKHR as) {
    VkAccelerationStructureDeviceAddressInfoKHR info = {
        sType: VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_DEVICE_ADDRESS_INFO_KHR,
        accelerationStructure: as
    };
    return vkGetAccelerationStructureDeviceAddressKHR(device, &info);
}

// void dumpAccelerationStructure(string prefix, ulong size, VkAccelerationStructureKHR handle) {
//     VkBuffer tempBuffer = context.buffers.createBuffer("temp" ~ prefix,
//         size,
//         VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT |
//         VK_BUFFER_USAGE_ACCELERATION_STRUCTURE_STORAGE_BIT_KHR |
//         VK_BUFFER_USAGE_TRANSFER_DST_BIT);

//     ulong offset = context.memory.bind(MEM_DOWNLOAD, tempBuffer, 0);

//     VkCopyAccelerationStructureToMemoryInfoKHR copyToMemory = {
//         sType: VK_STRUCTURE_TYPE_COPY_ACCELERATION_STRUCTURE_TO_MEMORY_INFO_KHR,
//         mode: VK_COPY_ACCELERATION_STRUCTURE_MODE_SERIALIZE_KHR,
//         src: handle
//     };
//     copyToMemory.dst.deviceAddress = getDeviceAddress(context.device, tempBuffer);

//     auto cmd2 = allocCommandBuffer(context.device, buildCommandPool);
//     cmd2.beginOneTimeSubmit();
//     vkCmdCopyAccelerationStructureToMemoryKHR(cmd2, &copyToMemory);
//     cmd2.end();

//     auto queue2 = context.queues.getQueue(graphicsComputeQueueFamily, 0);
//     queue2.submitAndWaitFor(cmd2, context);

//     freeCommandBuffer(context.device, buildCommandPool, cmd2);

//     ubyte* map = cast(ubyte*)context.memory.map(MEM_DOWNLOAD, 0, VK_WHOLE_SIZE);
//     invalidateMemory(context.device, context.memory.getMemory(MEM_DOWNLOAD).handle, 0, VK_WHOLE_SIZE);

//     log("%s:", prefix);
//     log("%s", (map+offset)[0..size]);

//     context.memory.unmap(MEM_DOWNLOAD);
// }
// void writeAccelerationStructure(string prefix, VkAccelerationStructureKHR handle, ubyte[] data) {

//     string bufferKey = "tempSrcAS" ~ prefix;

//     VkBuffer tempBuffer = context.buffers.createBuffer(bufferKey,
//         data.length,
//         VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT |
//         VK_BUFFER_USAGE_ACCELERATION_STRUCTURE_STORAGE_BIT_KHR |
//         VK_BUFFER_USAGE_TRANSFER_SRC_BIT);

//     ulong offset = context.memory.bind(MEM_UPLOAD, tempBuffer, 0);

//     ubyte* map = cast(ubyte*)context.memory.map(MEM_UPLOAD, 0, VK_WHOLE_SIZE);
//     memcpy(map + offset, data.ptr, data.length);

//     VkCopyMemoryToAccelerationStructureInfoKHR copy = {
//         sType: VK_STRUCTURE_TYPE_COPY_MEMORY_TO_ACCELERATION_STRUCTURE_INFO_KHR,
//         mode: VK_COPY_ACCELERATION_STRUCTURE_MODE_DESERIALIZE_KHR,
//         dst: handle
//     };
//     copy.src.deviceAddress = getDeviceAddress(context.device, tempBuffer);

//     auto cmd = allocCommandBuffer(context.device, buildCommandPool);
//     cmd.beginOneTimeSubmit();
//     vkCmdCopyMemoryToAccelerationStructureKHR(cmd, &copy);
//     cmd.end();

//     auto queue = context.queues.getQueue(graphicsComputeQueueFamily, 0);
//     queue.submitAndWaitFor(cmd, context);

//     freeCommandBuffer(context.device, buildCommandPool, cmd);

//     context.memory.unmap(MEM_UPLOAD);
// }
