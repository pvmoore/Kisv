module kisv.util.buffer_util;

import kisv.all;

void copyBuffer(VkCommandBuffer cmd, VkBuffer src, ulong srcOffset, VkBuffer dest, ulong destOffset, ulong size) {
    VkBufferCopy region = {
        srcOffset: srcOffset,
        dstOffset: destOffset,
        size: size
    };
    copyBuffer(cmd, src, dest, [region]);
}
void copyBuffer(VkCommandBuffer cmdbuffer, VkBuffer srcBuffer, VkBuffer dstBuffer, VkBufferCopy[] regions) {
    vkCmdCopyBuffer(cmdbuffer, srcBuffer, dstBuffer, cast(uint)regions.length, regions.ptr);
}