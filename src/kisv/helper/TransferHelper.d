module kisv.helper.TransferHelper;

import kisv.all;

struct BufferInfo {
    VkBuffer buffer;
    ulong offset;
    ulong size;
}

final class TransferHelper {
public:
    this(KisvContext context, uint transferQueueFamily) {
        this.context = context;
        this.transferQueueFamily = transferQueueFamily;
        createCommandPool();
    }
    void destroy() {
        log("\tDestroying TransferHelper");
        if(stagingUploadMemory.handle) {
            vkUnmapMemory(context.device, stagingUploadMemory.handle);
        }
        if(transferCP) vkDestroyCommandPool(context.device, transferCP, null);
    }
    void transferAndWaitFor(BufferInfo src, BufferInfo dest) {
        throwIf(src.size != dest.size, "Buffer sizes are different");

        auto cmd = allocCommandBuffer(context.device, transferCP);
        cmd.beginOneTimeSubmit();
        cmd.copyBuffer(src.buffer, src.offset, dest.buffer, dest.offset, src.size);
        cmd.end();

        auto transferQueue = context.queues.getQueue(transferQueueFamily, 0);

        transferQueue.submitAndWaitFor(cmd, context);

        freeCommandBuffer(context.device, transferCP, cmd);
    }
    /**
     * Upload buffer data to the GPU. This blocks until the transfer is complete.
     */
    void transferAndWaitFor(T)(T[] src, VkBuffer dest) {
        if(!stagingUploadBuffer) createUploadBuffer();

        ulong size = T.sizeof * src.length;

        memcpy(memoryMap, src.ptr, size);

        log("Transfering %s bytes: %s", size, memoryMap[0..size]);

        // If the memory is host coherent we don't need to flush
        bool isHostCoherent = stagingUploadMemory.flags.isSet(VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
        if(!isHostCoherent) {
            ulong flushAlignedSize = size.alignedTo(context.physicalDevice.properties.limits.nonCoherentAtomSize);
            flushMappedMemory(context.device, stagingUploadMemory.handle, 0, flushAlignedSize);
        }

        transferAndWaitFor(stagingUploadBuffer, dest, size);
    }
    /**
     * Upload image data to the GPU. This blocks until the transfer is complete.
     */
    void transferAndWaitFor(T)(T[] src, VkImage dest, VkExtent3D extent) {
        if(!stagingUploadBuffer) createUploadBuffer();

        ulong size = T.sizeof * src.length;

        memcpy(memoryMap, src.ptr, size);

        // If the memory is host coherent we don't need to flush
        bool isHostCoherent = stagingUploadMemory.flags.isSet(VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
        if(!isHostCoherent) {
            ulong flushAlignedSize = size.alignedTo(context.physicalDevice.properties.limits.nonCoherentAtomSize);
            flushMappedMemory(context.device, stagingUploadMemory.handle, 0, flushAlignedSize);
        }

        VkImageMemoryBarrier imageBarrierTransfer = {
            sType: VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
            oldLayout: VK_IMAGE_LAYOUT_UNDEFINED,
            newLayout: VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
            srcAccessMask: 0,
            dstAccessMask: VK_ACCESS_TRANSFER_WRITE_BIT,
            image: dest,
            srcQueueFamilyIndex: VK_QUEUE_FAMILY_IGNORED,
            dstQueueFamilyIndex: VK_QUEUE_FAMILY_IGNORED,
            subresourceRange: VkImageSubresourceRange(
                VK_IMAGE_ASPECT_COLOR_BIT, 0, VK_REMAINING_MIP_LEVELS, 0, VK_REMAINING_ARRAY_LAYERS
            )
        };

        VkImageMemoryBarrier imageBarrierOptimal = {
            sType: VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
            oldLayout: VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
            newLayout: VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
            srcAccessMask: VK_ACCESS_TRANSFER_WRITE_BIT,
            dstAccessMask: VK_ACCESS_SHADER_READ_BIT,
            image: dest,
            srcQueueFamilyIndex: VK_QUEUE_FAMILY_IGNORED,
            dstQueueFamilyIndex: VK_QUEUE_FAMILY_IGNORED,
            subresourceRange: VkImageSubresourceRange(
                VK_IMAGE_ASPECT_COLOR_BIT, 0, VK_REMAINING_MIP_LEVELS, 0, VK_REMAINING_ARRAY_LAYERS
            )
        };

        VkBufferImageCopy region = {
            bufferOffset: 0,
            bufferRowLength: 0,
            bufferImageHeight: 0,
            imageSubresource: VkImageSubresourceLayers(VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1),
            imageOffset: VkOffset3D(0, 0, 0),
            imageExtent: extent
        };

        auto cmd = allocCommandBuffer(context.device, transferCP);
        cmd.beginOneTimeSubmit();

        // Convert the image layout to transfer optimal
        cmd.vkCmdPipelineBarrier(VK_PIPELINE_STAGE_HOST_BIT,
                                 VK_PIPELINE_STAGE_TRANSFER_BIT,
                                 0,                 // dependencyFlags
                                 0,                 // memoryBarrierCount
                                 null,
                                 0,                 // bufferMemoryBarrierCount
                                 null,
                                 1,                 // imageMemoryBarrierCount
                                 &imageBarrierTransfer);

        cmd.vkCmdCopyBufferToImage(
            stagingUploadBuffer,
            dest,
            VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
            1,
            &region);

        // Convert the image layout to shader read optimal
        cmd.vkCmdPipelineBarrier(VK_PIPELINE_STAGE_TRANSFER_BIT,
                                 VK_PIPELINE_STAGE_ALL_COMMANDS_BIT,
                                 0,                 // dependencyFlags
                                 0,                 // memoryBarrierCount
                                 null,
                                 0,                 // bufferMemoryBarrierCount
                                 null,
                                 1,                 // imageMemoryBarrierCount
                                 &imageBarrierOptimal);

        cmd.end();

        log("Uploading image (%s bytes, %s)", src.length*T.sizeof, extent);

        auto transferQueue = context.queues.getQueue(transferQueueFamily, 0);
        transferQueue.submitAndWaitFor(cmd, context);

        freeCommandBuffer(context.device, transferCP, cmd);
    }
    void transferAndWaitFor(VkBuffer src, VkBuffer dest, ulong size) {
        auto cmd = allocCommandBuffer(context.device, transferCP);
        cmd.beginOneTimeSubmit();
        cmd.copyBuffer(src, 0, dest, 0, size);
        cmd.end();

        auto transferQueue = context.queues.getQueue(transferQueueFamily, 0);
        transferQueue.submitAndWaitFor(cmd, context);

        freeCommandBuffer(context.device, transferCP, cmd);
    }
private:
    KisvContext context;
    MemoryInfo stagingUploadMemory;
    VkBuffer stagingUploadBuffer;
    VkCommandPool transferCP;
    uint transferQueueFamily;
    void* memoryMap;

    void createCommandPool() {
        this.transferCP = .createCommandPool(context.device, transferQueueFamily,
            VK_COMMAND_POOL_CREATE_TRANSIENT_BIT);
    }
    void createUploadBuffer() {
        // Create 8 MB of upload memory
        // Ensure the bufferSize is aligned to a multiple of the flush/invalidate
        ulong bufferSize = alignedTo(8 * 1024*1024, context.physicalDevice.properties.limits.nonCoherentAtomSize);

        this.stagingUploadMemory = context.memory.allocateStagingUploadMemory("TransferHelper-staging-upload", bufferSize);

        this.stagingUploadBuffer = context.buffers.createBuffer("TransferHelper-staging-upload", bufferSize, VK_BUFFER_USAGE_TRANSFER_SRC_BIT);

        context.memory.bind("TransferHelper-staging-upload", stagingUploadBuffer);

        // Map the memory
        this.memoryMap = mapMemory(context.device, stagingUploadMemory.handle, 0, bufferSize);
    }
}