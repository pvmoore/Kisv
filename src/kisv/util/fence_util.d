module kisv.util.fence_util;

import kisv.all;

bool waitForFence(KisvContext context, VkFence fence, ulong timeoutNanos = ulong.max) {
    auto result = vkWaitForFences(context.device, 1, &fence, true, timeoutNanos);
    return VK_SUCCESS == result;
}

void resetFence(KisvContext context, VkFence fence) {
    vkResetFences(context.device, 1, &fence);
}