module kisv.util.renderpass_util;

import kisv.all;

VkRenderPass createRenderPass(VkDevice device,
                              VkAttachmentDescription[] attachmentDescriptions,
                              VkSubpassDescription[] subpassDescriptions,
                              VkSubpassDependency[] subpassDependencies)
{
    log("Creating render pass");
    VkRenderPassCreateInfo createInfo = {
        sType: VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
        flags: 0,
        attachmentCount: attachmentDescriptions.length.as!uint,
        pAttachments: attachmentDescriptions.ptr,
        subpassCount: subpassDescriptions.length.as!uint,
        pSubpasses: subpassDescriptions.ptr,
        dependencyCount: subpassDependencies.length.as!uint,
        pDependencies: subpassDependencies.ptr
    };

    VkRenderPass renderPass;

    check(vkCreateRenderPass(device, &createInfo, null, &renderPass));
    return renderPass;
}

VkRenderPass createRenderPass(KisvContext context) {
    VkAttachmentDescription colorAttachment = {
        flags: 0,
        format: context.window.colorFormat,
        samples: VkSampleCountFlagBits.VK_SAMPLE_COUNT_1_BIT,
        loadOp: VK_ATTACHMENT_LOAD_OP_CLEAR,
        storeOp: VK_ATTACHMENT_STORE_OP_STORE,
        stencilLoadOp: VK_ATTACHMENT_LOAD_OP_DONT_CARE,
        stencilStoreOp: VK_ATTACHMENT_STORE_OP_DONT_CARE,
        initialLayout: VK_IMAGE_LAYOUT_UNDEFINED,
        finalLayout: VK_IMAGE_LAYOUT_PRESENT_SRC_KHR
    };

    VkAttachmentReference colorAttachmentRef = {
        attachment: 0,
        layout: VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL
    };

    VkSubpassDescription subpassDesc = {
        pipelineBindPoint: VK_PIPELINE_BIND_POINT_GRAPHICS,
        colorAttachmentCount: 1,
        pColorAttachments: &colorAttachmentRef
    };

    VkRenderPass renderPass = createRenderPass(
        context.device,
        [colorAttachment],
        [subpassDesc],
        subpassDependencies()
    );
    return renderPass;
}

VkSubpassDependency[] subpassDependencies() {
    VkSubpassDependency d1 = {
        srcSubpass: VK_SUBPASS_EXTERNAL,
        dstSubpass: 0,
        srcStageMask: VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT,
        srcAccessMask: VK_ACCESS_MEMORY_READ_BIT,
        dstStageMask: VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
        dstAccessMask: VK_ACCESS_COLOR_ATTACHMENT_READ_BIT | VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
        dependencyFlags: VkDependencyFlagBits.VK_DEPENDENCY_BY_REGION_BIT
    };
    VkSubpassDependency d2 = {
        srcSubpass: 0,
        dstSubpass: VK_SUBPASS_EXTERNAL,
        srcStageMask: VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
        srcAccessMask: VK_ACCESS_COLOR_ATTACHMENT_READ_BIT | VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
        dstStageMask: VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT,
        dstAccessMask: VK_ACCESS_MEMORY_READ_BIT,
        dependencyFlags: VkDependencyFlagBits.VK_DEPENDENCY_BY_REGION_BIT
    };
    return [d1, d2];
}