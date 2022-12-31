module kisv.util.command_buffer_util;

import kisv.all;

void beginOneTimeSubmit(VkCommandBuffer buffer) {
    buffer.begin(VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT);
}

/**
 * Flags:
 *  - VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT = Each recording of the command buffer will only be submitted once
 *  - VK_COMMAND_BUFFER_USAGE_RENDER_PASS_CONTINUE_BIT = A secondary command buffer is considered to be entirely inside a render pass
 *  - VK_COMMAND_BUFFER_USAGE_SIMULTANEOUS_USE_BIT = Allows the command buffer to be resubmitted to a queue while it is in the pending state
 */
void begin(VkCommandBuffer buffer,
           VkCommandBufferUsageFlags flags,
           VkCommandBufferInheritanceInfo* inheritanceInfo = null)
{
    VkCommandBufferBeginInfo beginInfo = {
        sType: VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        flags: flags,
        pInheritanceInfo: inheritanceInfo
    };

    check(vkBeginCommandBuffer(buffer, &beginInfo));
}
void end(VkCommandBuffer buffer) {
    check(vkEndCommandBuffer(buffer));
}


void beginRenderPass(VkCommandBuffer buffer,
                     VkRenderPass renderPass,
                     VkFramebuffer frameBuffer,
                     VkRect2D renderArea,
                     VkClearValue[] clearValues,
                     VkSubpassContents contents = VK_SUBPASS_CONTENTS_INLINE)
{
    VkRenderPassBeginInfo info = {
        sType: VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
        renderPass: renderPass,
        framebuffer: frameBuffer,
        renderArea: renderArea,
        clearValueCount: clearValues.length.as!int,
        pClearValues: clearValues.ptr
    };

    // union VkClearValue {
    //     VkClearColorValue           color;
    //     VkClearDepthStencilValue    depthStencil;
    // }
    //union VkClearColorValue {
    //    float       float32[4];
    //    int32_t     int32[4];
    //    uint32_t    uint32[4];
    //}
    //struct VkClearDepthStencilValue {
    //    float       depth;
    //    uint32_t    stencil;
    //}

    vkCmdBeginRenderPass(buffer, &info, contents);
}
void endRenderPass(VkCommandBuffer buffer) {
    vkCmdEndRenderPass(buffer);
}