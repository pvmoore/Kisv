module kisv.util.command_pool_util;

import kisv.all;

/**
 * VK_COMMAND_POOL_CREATE_TRANSIENT_BIT
 * VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT
 * VK_COMMAND_POOL_CREATE_PROTECTED_BIT
 */
VkCommandPool createCommandPool(VkDevice device,
                                uint queueFamily,
                                VkCommandPoolCreateFlags flags = 0)
{

    VkCommandPoolCreateInfo createInfo = {
        sType: VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
        flags: flags,
        queueFamilyIndex: queueFamily
    };

    VkCommandPool pool;
    check(vkCreateCommandPool(device, &createInfo, null, &pool));
    return pool;
}

VkCommandBuffer allocCommandBuffer(VkDevice device,
                                     VkCommandPool pool,
                                     VkCommandBufferLevel level = VK_COMMAND_BUFFER_LEVEL_PRIMARY)
{
    VkCommandBufferAllocateInfo createInfo = {
        sType: VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        commandPool: pool,
        level: level,
        commandBufferCount: 1
    };

    auto buffers = new VkCommandBuffer[1];
    check(vkAllocateCommandBuffers(device, &createInfo, buffers.ptr));
    return buffers[0];
}

void freeCommandBuffer(VkDevice device, VkCommandPool pool, VkCommandBuffer buffer) {
    vkFreeCommandBuffers(device, pool, 1, &buffer);
}