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

bool waitForFence(KisvContext context, VkFence fence, ulong timeoutNanos = ulong.max) {
    auto result = vkWaitForFences(context.device, 1, &fence, true, timeoutNanos);
    return VK_SUCCESS == result;
}

void resetFence(KisvContext context, VkFence fence) {
    vkResetFences(context.device, 1, &fence);
}