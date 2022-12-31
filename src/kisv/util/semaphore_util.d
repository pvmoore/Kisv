module kisv.util.semaphore_util;

import kisv.all;

VkSemaphore createSemaphore(VkDevice device) {
    VkSemaphoreCreateInfo info = {
        sType: VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
        flags: 0
    };

    VkSemaphore semaphore;
    check(vkCreateSemaphore(device, &info, null, &semaphore));
    return semaphore;
}