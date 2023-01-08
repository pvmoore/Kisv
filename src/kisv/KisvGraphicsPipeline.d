module kisv.KisvGraphicsPipeline;

import kisv.all;

final class KisvGraphicsPipeline {
public:
    VkPipeline pipeline;
    VkPipelineLayout pipelineLayout;

    this(KisvContext context) {
        this.context = context;
    }
    void destroy() {
        if(pipelineLayout) vkDestroyPipelineLayout(context.device, pipelineLayout, null);
        if(pipeline) vkDestroyPipeline(context.device, pipeline, null);
    }
    auto shaderStage(VkPipelineShaderStageCreateInfo shaderStage) {
        this.shaderStages ~= shaderStage;
        return this;
    }
    auto vertexInputState(VkVertexInputBindingDescription bindingDesc,
                          VkVertexInputAttributeDescription[] inputAttributes)
    {
        this.bindingDesc = bindingDesc;
        this.inputAttributes = inputAttributes;
        return this;
    }
    auto inputAssemblyState(VkPipelineInputAssemblyStateCreateInfo assemblyState) {
        this.asssemblyState = assemblyState;
        return this;
    }
    auto viewportState(VkPipelineViewportStateCreateInfo viewportState) {
        this.viewportState_ = viewportState;
        return this;
    }
    auto rasterizationState(VkPipelineRasterizationStateCreateInfo rasterizationState) {
        this.rasterizationState_ = rasterizationState;
        return this;
    }
    auto multisampleState(VkPipelineMultisampleStateCreateInfo multisampleState) {
        this.multisampleState_ = multisampleState;
        return this;
    }
    auto depthStencilState(VkPipelineDepthStencilStateCreateInfo depthStencilState) {
        this.depthStencilState_ = depthStencilState;
        return this;
    }
    auto colorBlendState(VkPipelineColorBlendStateCreateInfo colorBlendState,
                         VkPipelineColorBlendAttachmentState[] colorBlendAttachments)
    {
        this.colorBlendState_ = colorBlendState;
        this.colorBlendAttachments = colorBlendAttachments;
        return this;
    }
    auto layout(VkPipelineLayoutCreateInfo layoutInfo) {
        this.layoutInfo = layoutInfo;
        return this;
    }

    void build() {

    }
private:
    KisvContext context;
    VkPipelineShaderStageCreateInfo[] shaderStages;
    VkVertexInputBindingDescription bindingDesc;
    VkVertexInputAttributeDescription[] inputAttributes;
    VkPipelineInputAssemblyStateCreateInfo asssemblyState;
    VkPipelineViewportStateCreateInfo viewportState_;
    VkPipelineRasterizationStateCreateInfo rasterizationState_;
    VkPipelineMultisampleStateCreateInfo multisampleState_;
    VkPipelineDepthStencilStateCreateInfo depthStencilState_;
    VkPipelineColorBlendStateCreateInfo colorBlendState_;
    VkPipelineColorBlendAttachmentState[] colorBlendAttachments;
    VkPipelineLayoutCreateInfo layoutInfo;
}
