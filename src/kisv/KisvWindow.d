module kisv.KisvWindow;

import kisv.all;

final class KisvWindow {
private:
    KisvContext context;
public:
    uint width;
    uint height;
    VkSurfaceKHR surface;
    GLFWwindow* glfwWindow;

    // swapchain
    VkImageUsageFlagBits swapchainUsage;
    VkSwapchainKHR swapchain;
    VkFormat colorFormat;
    VkColorSpaceKHR colorSpace;
    VkExtent2D extent;
    VkImage[] images;
    VkImageView[] views;
    VkFramebuffer[] frameBuffers;

    VkExtent2D size() { return VkExtent2D(width, height); }
    uint numImages() { return images.length.as!uint; }

    void setTitle(string title) {
        context.props.windowTitle = title;
        glfwSetWindowTitle(glfwWindow, title.toStringz());
    }

    this(KisvContext context) {
        this.context = context;
    }
    void destroy() {
        log("\tDestroying KisvWindow");
        log("\t\tDestroying %s swapchain frame buffers", frameBuffers.length);
        foreach(f; frameBuffers) {
            vkDestroyFramebuffer(context.device, f, null);
        }
        log("\t\tDestroying %s swapchain image views", views.length);
        foreach(v; views) {
            vkDestroyImageView(context.device, v, null);
        }
        log("\t\tDestroying swapchain");
        if(swapchain) vkDestroySwapchainKHR(context.device, swapchain, null);
        log("\t\tDestroying surface");
        if(surface) vkDestroySurfaceKHR(context.instance, surface, null);
        log("\t\tDestroying GLFW window");
        if(glfwWindow) glfwDestroyWindow(glfwWindow);
    }
    void create(VkImageUsageFlagBits usage) {
        this.swapchainUsage = usage;

        createWindow();
        createSurface();
        createSwapchain();
    }
    void createFrameBuffers(VkRenderPass renderPass) {
        log("\tCreating frame buffers");
        throwIf(renderPass is null);
        frameBuffers.length = numImages();
        foreach(i, imageView; views) {

            auto frameBufferViews = [imageView];

            frameBuffers[i] = createFrameBuffer(
                context.device,
                renderPass,
                frameBufferViews,
                extent.width,
                extent.height,
                1
            );
        }
    }
    void show() {
        glfwShowWindow(glfwWindow);
    }
    void hide() {
        glfwHideWindow(glfwWindow);
    }
    uint acquireNext(VkSemaphore imageAvailableSemaphore, VkFence fence) {
        uint imageIndex;

        auto result = vkAcquireNextImageKHR(
            context.device,
            swapchain,
            ulong.max,
            imageAvailableSemaphore,
            fence,
            &imageIndex
        );

        switch(result) {
            case VK_SUCCESS:
                break;
            case VK_ERROR_OUT_OF_DATE_KHR:
                log("Swapchain is out of date");
                break;
            case VK_SUBOPTIMAL_KHR:
                log("Swapchain is suboptimal");
                break;
            case VK_NOT_READY:
                log("Swapchain not ready");
                break;
            default:
                throw new Error("Swapchain acquire error: %s".format(result));
        }
        return imageIndex;
    }
    void queuePresent(VkQueue queue, uint imageIndex, VkSemaphore[] waitSemaphores) {
        VkResult[] results;

        VkPresentInfoKHR info = {
            sType: VkStructureType.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
            waitSemaphoreCount: waitSemaphores.length.as!int,
            pWaitSemaphores: waitSemaphores.ptr,
            swapchainCount: 1,
            pSwapchains: &swapchain,
            pImageIndices: &imageIndex,
            pResults: results.ptr
        };

        auto result = vkQueuePresentKHR(queue, &info);

        switch(result) {
            case VK_SUCCESS:
                break;
            case VK_ERROR_OUT_OF_DATE_KHR:
                log("Swapchain is out of date");
                break;
            case VK_SUBOPTIMAL_KHR:
                log("Swapchain is suboptimal");
                break;
            case VK_NOT_READY:
                log("Swapchain not ready");
                break;
            default:
                throw new Exception("Swapchain present error: %s".format(result));
        }
    }
//──────────────────────────────────────────────────────────────────────────────────────────────────
private:
    void createWindow() {
        log("Creating GLFW window");
        GLFWmonitor* monitor = glfwGetPrimaryMonitor();
        GLFWvidmode* vidmode = glfwGetVideoMode(monitor);
        if(context.props.windowed) {
            log("\tWindowed mode selected");
            monitor = null;
            glfwWindowHint(GLFW_VISIBLE, 0);
            glfwWindowHint(GLFW_RESIZABLE, context.props.windowResizable ? 1 : 0);
            glfwWindowHint(GLFW_DECORATED, context.props.windowDecorated ? 1 : 0);
            this.width  = context.props.windowWidth;
            this.height = context.props.windowHeight;
            log("\tWindow resizable = %s", context.props.windowResizable);
            log("\tWindow decorated = %s", context.props.windowDecorated);
        } else {
            log("\tFull screen mode selected");
            //glfwWindowHint(GLFW_REFRESH_RATE, 60);
            this.width  = vidmode.width;
            this.height = vidmode.height;
        }

        // other window hints
        //glfwWindowHint(GLFW_DOUBLEBUFFER, 1);
//        if(hints.samples > 0) {
//            glfwWindowHint(GLFW_SAMPLES, hints.samples);
//        }
        glfwWindowHint(GLFW_AUTO_ICONIFY, context.props.windowAutoIconify ? 1 : 0);
        log("\tWindow auto iconify = %s", context.props.windowAutoIconify);
        log("\tWindow size {%s, %s}", width, height);

        glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API);
        GLFWwindow* share = null;
        this.glfwWindow = glfwCreateWindow(width, height, context.props.windowTitle.toStringz(), monitor, share);

        if(context.props.windowed) {
            glfwSetWindowPos(
                glfwWindow,
                ((cast(int)vidmode.width - width) / 2),
                ((cast(int)vidmode.height - height) / 2)
            );
        }

        // TODO - this stuff may not be needed and shouldn't be here anyway
        glfwSetKeyCallback(glfwWindow, &onKeyEvent);
        glfwSetWindowFocusCallback(glfwWindow, &onWindowFocusEvent);
        glfwSetMouseButtonCallback(glfwWindow, &onMouseClickEvent);
        glfwSetScrollCallback(glfwWindow, &onScrollEvent);
        glfwSetCursorPosCallback(glfwWindow, &onMouseMoveEvent);
        glfwSetCursorEnterCallback(glfwWindow, &onMouseEnterEvent);
        glfwSetWindowIconifyCallback(glfwWindow, &onIconifyEvent);

        //glfwSetWindowRefreshCallback(window, &refreshWindow);
        //glfwSetWindowSizeCallback(window, &resizeWindow);
        //glfwSetWindowCloseCallback(window, &onWindowCloseEvent);
        //glfwSetDropCallback(window, &onDropEvent);

        //glfwSetInputMode(window, GLFW_STICKY_KEYS, 1);

        if(context.props.appIcon.pixels !is null) {
            glfwSetWindowIcon(glfwWindow, 1, &context.props.appIcon);
        }
    }
    void createSurface() {
        log("\tCreating surface");
        check(glfwCreateWindowSurface(context.instance, glfwWindow, null, &surface));
    }
    void createSwapchain() {
        selectSurfaceFormat();
        createSwapChain();
        getSwapChainImages();
        createImageViews();
    }
    void selectSurfaceFormat() {
        log("\tSelecting surface format...");
        VkSurfaceFormatKHR[] formats = context.physicalDevice.getFormats(surface);
        throwIf(formats.length < 1, "No surface formats found");

        log("\tPossible formats: (%s) {", formats.length);
        foreach(pf; formats) {
            log("\t\tformat: %s, colorSpace: %s", pf.format, pf.colorSpace);
        }
        log("\t}");

        VkFormat desiredFormat            = VK_FORMAT_B8G8R8A8_UNORM;
        VkColorSpaceKHR desiredColorSpace = VK_COLOR_SPACE_SRGB_NONLINEAR_KHR;

        /* If we are using the swapchain image as storage we need to ensure
         * that the format supports it.
         * Generally it is probably a bad idea to do this.
         */
        if(swapchainUsage.isSet(VK_IMAGE_USAGE_STORAGE_BIT)) {
            VkFormatProperties p = context.physicalDevice.getFormatProperties(desiredFormat);
            if(p.optimalTilingFeatures.isUnset(VK_FORMAT_FEATURE_STORAGE_IMAGE_BIT)) {
                /* Try rgba */
                desiredFormat = VkFormat.VK_FORMAT_R8G8B8A8_UNORM;
            }
        }

        // If the format list includes just one entry of VK_FORMAT_UNDEFINED,
        // the surface has no preferred format. Otherwise, at least one
        // supported format will be returned
        if(formats.length == 1 && formats[0].format == VkFormat.VK_FORMAT_UNDEFINED) {
            this.colorFormat = VkFormat.VK_FORMAT_B8G8R8A8_UNORM;
            this.colorSpace  = formats[0].colorSpace;
        } else {
            this.colorFormat = formats[0].format;
            this.colorSpace  = formats[0].colorSpace;

            foreach(f; formats) {
                if(f.format==desiredFormat && f.colorSpace==desiredColorSpace) {
                    this.colorFormat = f.format;
                    this.colorSpace  = f.colorSpace;
                }
            }

        }
        log("\tSelected colour space  = %s", this.colorSpace);
        log("\tSelected colour format = %s", this.colorFormat);
    }
    void createSwapChain() {
        VkSurfaceCapabilitiesKHR surfaceCaps = context.physicalDevice.getCapabilities(surface);

        log("\tCreating swap chain %s", surfaceCaps.currentExtent);

        VkSwapchainCreateInfoKHR createInfo = {
            sType: VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
            flags: 0,
            surface: surface,
            minImageCount: selectNumImages(surfaceCaps),
            imageFormat: colorFormat,
            imageColorSpace: colorSpace,
            imageExtent: selectExtent(surfaceCaps),
            imageArrayLayers: 1,
            imageUsage: VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | swapchainUsage,
            imageSharingMode: VK_SHARING_MODE_EXCLUSIVE,
            preTransform: selectPreTransform(surfaceCaps),
            compositeAlpha: VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
            presentMode: selectPresentMode(surface),
            clipped: VK_TRUE,
            oldSwapchain: null
        };

        check(vkCreateSwapchainKHR(context.device, &createInfo, null, &swapchain));
        log("\tSwapchain created");
    }
    uint selectNumImages(VkSurfaceCapabilitiesKHR caps) {
        throwIf(context.props.frameBuffers==0);
        uint num = maxOf(caps.minImageCount, context.props.frameBuffers);
        if(caps.maxImageCount>0 && num>caps.maxImageCount) {
            num = caps.maxImageCount;
        }
        log("\tRequesting %s images", num);
        return num;
    }
    VkExtent2D selectExtent(VkSurfaceCapabilitiesKHR caps) {
        this.extent = caps.currentExtent;
        if(extent.width==uint.max) {
            // we can set it to what we want
            // todo - get values from somewhere
            extent = VkExtent2D(600,600);
        }
        log("\tSetting extent to %s", extent);
        return extent;
    }
    VkSurfaceTransformFlagBitsKHR selectPreTransform(VkSurfaceCapabilitiesKHR caps) {
        auto trans = caps.currentTransform;
        if(caps.supportedTransforms & VK_SURFACE_TRANSFORM_IDENTITY_BIT_KHR) {
            trans = VK_SURFACE_TRANSFORM_IDENTITY_BIT_KHR;
        }
        log("\tSetting preTransform to %s", trans);
        return trans;
    }
    VkPresentModeKHR selectPresentMode(VkSurfaceKHR surface) {
        log("\tSelecting present mode (user requested vsync=%s) ...", context.props.windowVsync);
        VkPresentModeKHR[] presentModes = context.physicalDevice.getPresentModes(surface);
        log("\tSupported present modes:");
        foreach(p; presentModes) {
            log("\t\t%s", p);
        }

        auto mode = VK_PRESENT_MODE_FIFO_KHR;
        foreach(m; presentModes) {
            if(context.props.windowVsync) {
                // VK_PRESENT_MODE_FIFO_KHR
            } else {
                /// Use mailbox if available otherwise immediate
                if(m==VK_PRESENT_MODE_MAILBOX_KHR) {
                    mode = m;
                } else if(m==VK_PRESENT_MODE_IMMEDIATE_KHR) {
                    if(mode==VK_PRESENT_MODE_FIFO_KHR) {
                        mode = m;
                    }
                }
            }
        }
        log("\tSelecting present mode %s", mode);
        return mode;
    }
    void getSwapChainImages() {
        uint count;
        check(vkGetSwapchainImagesKHR(context.device, swapchain, &count, null));
        images.length = count;

        check(vkGetSwapchainImagesKHR(context.device, swapchain, &count, images.ptr));

        log("\tGot %s images", images.length);
    }
    void createImageViews() {
        log("\tCreating image views");
        views.length = images.length;
        foreach(i; 0..images.length) {
            VkImageViewCreateInfo createInfo = imageViewCreateInfo(images[i], colorFormat, VK_IMAGE_VIEW_TYPE_2D);
            check(vkCreateImageView(context.device, &createInfo, null, &views[i]));
        }
    }
}
