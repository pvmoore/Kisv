module kisv.util.image_util;

import kisv.all;

VkFramebuffer createFrameBuffer(VkDevice device,
                                VkRenderPass renderPass,
                                VkImageView[] views,
                                uint width,
                                uint height,
                                uint layers)
{
    VkFramebufferCreateInfo createInfo = {
        sType: VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
        flags: 0,
        renderPass: renderPass,
        attachmentCount: views.length.as!int,
        pAttachments: views.ptr,
        width: width,
        height: height,
        layers: layers
    };

    VkFramebuffer frameBuffer;
    check(vkCreateFramebuffer(device, &createInfo, null, &frameBuffer));
    return frameBuffer;
}

VkImageViewCreateInfo imageViewCreateInfo(VkImage image, VkFormat format, VkImageViewType type) {
    VkImageViewCreateInfo info = {
        sType: VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
        flags: 0,
        image: image,
        viewType: type,
        format: format,
        components: componentMapping!"rgba",
        subresourceRange: VkImageSubresourceRange(
            VK_IMAGE_ASPECT_COLOR_BIT,  // aspectMask
            0,                          // baseMipLevel
            VK_REMAINING_MIP_LEVELS,    // levelCount
            0,                          // baseArrayLayer
            VK_REMAINING_ARRAY_LAYERS   // layerCount
        )
    };
    return info;
}

/// eg.  componentMapping!"rgba";
VkComponentMapping componentMapping(string s)() {
    static assert(s.length==4);
    VkComponentSwizzle get(char c) {
        if(c=='r') return VkComponentSwizzle.VK_COMPONENT_SWIZZLE_R;
        if(c=='g') return VkComponentSwizzle.VK_COMPONENT_SWIZZLE_G;
        if(c=='b') return VkComponentSwizzle.VK_COMPONENT_SWIZZLE_B;
        if(c=='a') return VkComponentSwizzle.VK_COMPONENT_SWIZZLE_A;
        throwIf(true);
        assert(false);
    }
    return VkComponentMapping(get(s[0]), get(s[1]), get(s[2]), get(s[3]));
}
