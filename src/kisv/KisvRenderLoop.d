module kisv.KisvRenderLoop;

import kisv.all;

final class KisvRenderLoop {
public:
    this(KisvContext context, uint graphicsQueueFamily) {
        log("Creating render loop");
        this.context = context;
        this.window = context.window;
        this.graphicsQueueFamily = graphicsQueueFamily;
        createCommandPool();
        createFrameResources();
    }
    void destroy() {
        log("\tDestroying render loop");
        foreach(fr; frameResources) {
            if(fr.imageAvailable) vkDestroySemaphore(context.device, fr.imageAvailable, null);
            if(fr.renderFinished) vkDestroySemaphore(context.device, fr.renderFinished, null);
            if(fr.fence) vkDestroyFence(context.device, fr.fence, null);
        }
        if(graphicsCP) vkDestroyCommandPool(context.device, graphicsCP, null);
    }
    void run(void delegate(KisvFrame, uint) renderCallback) {
        this.renderCallback = renderCallback;
        log("╔═════════════════════════════════════════════════════════════════╗");
        log("║ Render loop started                                             ║");
        log("╚═════════════════════════════════════════════════════════════════╝");

        ulong lastFrameTotalNanos;
        ulong frameTimeNanos;
        ulong elapsedSecond;
        StopWatch watch;

        watch.start();

        while(!glfwWindowShouldClose(window.glfwWindow)) {
            glfwPollEvents();

            renderFrame();

            ulong time          = watch.peek().total!"nsecs";
            frameTimeNanos      = time - lastFrameTotalNanos;
            lastFrameTotalNanos = time;

            framePerSecond = frameTimeNanos/1_000_000_000.0;
            frameSeconds += framePerSecond;
            frameNumber++;

            if(time/1_000_000_000L > elapsedSecond) {
                elapsedSecond = time/1_000_000_000L;
                double fps = 1_000_000_000.0 / frameTimeNanos;

                log("Frame (number:%s, seconds:%.2f) perSecond=%.4f time:%.3f fps:%.2f",
                    frameNumber,
                    frameSeconds,
                    framePerSecond,
                    frameTimeNanos/1000000.0,
                    fps);
            }
        }
        log("╔═════════════════════════════════════════════════════════════════╗");
        log("║ Render loop exited                                              ║");
        log("╚═════════════════════════════════════════════════════════════════╝");
    }
private:
    KisvContext context;
    uint graphicsQueueFamily;
    KisvWindow window;
    KisvFrame[] frameResources;
    VkCommandPool graphicsCP;
    void delegate(KisvFrame, uint) renderCallback;
    double framePerSecond = 1;
    double frameSeconds = 0;
    ulong frameNumber;

    void renderFrame() {
        uint frameIndex = (frameNumber%frameResources.length).as!uint;
        KisvFrame frame = frameResources[frameIndex];

        // Set the transient frame properties
        frame.number = frameNumber;
        frame.seconds = frameSeconds.as!float;
        frame.perSecond = framePerSecond.as!float;

        // Wait for the fence
        waitForFence(context.device, frame.fence);
        resetFence(context.device, frame.fence);

        // Get the next available image view.
        uint imageIndex = window.acquireNext(frame.imageAvailable, null);

        // Let the app do its thing
        renderCallback(frame, imageIndex);

        // Present
        window.queuePresent(
            context.queues.getQueue(graphicsQueueFamily, 0),
            imageIndex,             // image index
            [frame.renderFinished]  // wait semaphores
        );

        frameIndex = (frameIndex + 1) % frameResources.length.as!uint;
    }
    void createCommandPool() {
        this.graphicsCP = .createCommandPool(context.device, graphicsQueueFamily,
            VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT | VK_COMMAND_POOL_CREATE_TRANSIENT_BIT);
    }
    void createFrameResources() {
        foreach(i; 0..window.numImages()) {
            auto f = new KisvFrame();
            f.index          = i.as!int;
            f.imageAvailable = createSemaphore(context.device);
            f.renderFinished = createSemaphore(context.device);
            f.fence          = createFence(context.device, true);
            f.commands       = allocCommandBuffer(context.device, graphicsCP);
            f.frameBuffer    = window.frameBuffers[i];
            f.seconds        = 0;
            f.perSecond      = 0;

            frameResources ~= f;
        }
        log("\tCreated %s frame resources", frameResources.length);
    }
}
