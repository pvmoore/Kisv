module kisv.util.fence_util;

import kisv.all;

VkFence createFence(VkDevice device, bool signalled = false) {
    VkFenceCreateInfo info = {
        sType: VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
        flags: signalled ? VK_FENCE_CREATE_SIGNALED_BIT : 0
    };

    VkFence fence;
    check(vkCreateFence(device, &info, null, &fence));
    return fence;
}

bool waitForFence(VkDevice device, VkFence fence, ulong timeoutNanos = ulong.max) {
    auto result = vkWaitForFences(device, 1, &fence, true, timeoutNanos);
    return VK_SUCCESS == result;
}

void resetFence(VkDevice device, VkFence fence) {
    vkResetFences(device, 1, &fence);
}