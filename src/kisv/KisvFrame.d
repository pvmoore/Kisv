module kisv.KisvFrame;

import kisv.all;

final class KisvFrame {
    /** The frame index (0..swapchain.numImages()) */
    uint index;

    /** Current framebuffer */
    VkFramebuffer frameBuffer;

    /** Synchronisation */
    VkSemaphore imageAvailable;
    VkSemaphore renderFinished;
    VkFence fence;

    /** Use this for adhoc commands per frame on the graphics queue */
    VkCommandBuffer commands;

    /** The number of times <render> has been called */
    ulong number;

    /** Elapsed number of seconds */
    float seconds;

    /** 1.0 / frames per second. Multiply by this to keep calculations relative to frame speed */
    float perSecond;
}
