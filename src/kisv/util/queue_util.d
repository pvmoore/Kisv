module kisv.util.queue_util;

import kisv.all;

void submit(VkQueue queue,
            VkCommandBuffer[] cmdBuffers,
            VkSemaphore[] waitSemaphores,
            VkPipelineStageFlags[] waitStages,
            VkSemaphore[] signalSemaphores,
            VkFence fence)
{
    VkSubmitInfo info = {
        sType: VK_STRUCTURE_TYPE_SUBMIT_INFO,
        waitSemaphoreCount: waitSemaphores.length.as!int,
        pWaitSemaphores: waitSemaphores.ptr,
        pWaitDstStageMask: waitStages.ptr,
        signalSemaphoreCount: signalSemaphores.length.as!int,
        pSignalSemaphores: signalSemaphores.ptr,
        commandBufferCount: cmdBuffers.length.as!int,
        pCommandBuffers: cmdBuffers.ptr
    };

    check(vkQueueSubmit(queue, 1, &info, fence));
}