module kisv.helper.TransferHelper;

import kisv.all;

struct BufferInfo {
    VkBuffer buffer;
    ulong offset;
    ulong size;
}

final class TransferHelper {
private:
    KisvContext context;
    VkBuffer stagingUploadBuffer;
    VkCommandPool transferCP;
    uint transferQueueFamily;
public:
    this(KisvContext context, uint transferQueueFamily) {
        this.context = context;
        this.transferQueueFamily = transferQueueFamily;
        createCommandPool();
    }
    void destroy() {
        if(transferCP) vkDestroyCommandPool(context.device, transferCP, null);
    }
    void transferAndWaitFor(BufferInfo src, BufferInfo dest) {
        throwIf(src.size != dest.size, "Buffer sizes are different");

        auto cmd = allocCommandBuffer(context.device, transferCP);
        cmd.beginOneTimeSubmit();
        cmd.copyBuffer(src.buffer, src.offset, dest.buffer, dest.offset, src.size);
        cmd.end();

        auto transferQueue = context.getQueue(transferQueueFamily, 0);

        transferQueue.submitAndWaitFor(cmd, context);

        freeCommandBuffer(context.device, transferCP, cmd);
    }
private:
    void createCommandPool() {
        this.transferCP = .createCommandPool(context.device, transferQueueFamily,
            VK_COMMAND_POOL_CREATE_TRANSIENT_BIT);
    }
}