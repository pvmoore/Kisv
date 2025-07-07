module demo_rectangle;

import std.format : format;

import kisv;
import demo : DemoApplication;

final class Rectangle : DemoApplication {
public:
    override void initialise() {
        this.context = new KisvContext(props);

        context.selectPhysicalDevice((KisvPhysicalDevice[] devices) {
            foreach(i, d; devices) {
                if(d.properties.deviceType == VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU &&
                  d.supportsExtensions(props.deviceExtensions) &&
                  d.supportsVersion(props.apiVersion))
                {
                    return i.as!int;
                }
            }
            foreach(i, d; devices) {
                if(d.properties.deviceType == VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU &&
                  d.supportsExtensions(props.deviceExtensions) &&
                  d.supportsVersion(props.apiVersion))
                {
                    return i.as!int;
                }
            }
            throw new Exception("No suitable physical device found");
        });

        context.selectQueueFamilies((QueueHelper h) {
            // Look for a graphics queue family
            auto graphics = h.find(VK_QUEUE_GRAPHICS_BIT);
            throwIf(graphics.length == 0, "No graphics queues available");
            graphicsQueueFamily = graphics[0].index;
            log("Selected graphics queue family %s", graphicsQueueFamily);

            // Look for a transfer queue family
            if(h.supports(graphicsQueueFamily, VK_QUEUE_TRANSFER_BIT)) {
                // Use the graphics queue for transfer
                transferQueueFamily = graphicsQueueFamily;
            } else {
                auto transfer = h.find(VK_QUEUE_TRANSFER_BIT);
                throwIf(transfer.length == 0, "No transfer queues available");
                transferQueueFamily = transfer[0].index;
            }
            log("Selected transfer queue family %s", transferQueueFamily);
        });

        uint[uint] queueRequest;
        queueRequest[graphicsQueueFamily]++;
        if(transferQueueFamily != graphicsQueueFamily) {
            queueRequest[transferQueueFamily]++;
        }
        context.createLogicalDevice(queueRequest);

        context.createWindow();

        context.createStandardRenderPass();

        context.createTransferHelper(transferQueueFamily);

        context.createRenderLoop(graphicsQueueFamily);

        initialiseScene();

        import core.cpuid: processor;
        context.window.setTitle("%s %s :: %s, %s".format(
            props.appName,
            VERSION, context.physicalDevice.name(), processor()));
    }
    override void destroy() {
        // Always ensure the device is idle before destroying device objects
        vkDeviceWaitIdle(context.device);

        if(pipeline) vkDestroyPipeline(context.device, pipeline, null);
        if(pipelineLayout) vkDestroyPipelineLayout(context.device, pipelineLayout, null);

        if(context) context.destroy();
    }
    override void run() {
        context.window.show();

        context.startRenderLoop((KisvFrame frame, uint imageIndex) {
            renderScene(frame, imageIndex);
        });
    }
//──────────────────────────────────────────────────────────────────────────────────────────────────
private:
    // Keys
    enum : string {
        MEM_GPU             = "gpu",
        MEM_STAGING_UPLOAD  = "staging_up",
        BUF_VERTEX          = "vertex",
        BUF_INDEX           = "index",
        BUF_UNIFORM         = "uniform",
        IMG_BIRDS           = "birds",
        DS_LAYOUT           = "layout1",
        DS_POOL             = "pool1"
    }

    KisvProperties props = {
        appName: "Textured Rectangle",
        apiVersion: VkVersion(1, 1, 0),
        instanceLayers: [
            "VK_LAYER_KHRONOS_validation"//,
            //"VK_LAYER_LUNARG_api_dump"
            //"VK_LAYER_LUNARG_monitor"
        ],
        instanceExtensions: [
            "VK_KHR_surface",
            "VK_KHR_win32_surface",
            "VK_EXT_debug_report"
        ],
        deviceExtensions: [
            "VK_KHR_swapchain",
            "VK_KHR_maintenance1"
        ],
        windowed: true,
        windowWidth: 1200,
        windowHeight: 1000,
        windowVsync: false
    };
    struct Vertex { static assert(Vertex.sizeof==8*float.sizeof);
        float2 pos;
        float4 colour;
        float2 uv;
    }
    struct UBO { static assert(UBO.sizeof==3*16*4);
        float16 model;
        float16 view;
        float16 proj;
    }
    ushort[] indices = [
        0, 1, 2,
        0, 2, 3
    ];
    // 0--1
    // |\ |
    // | \|
    // 3--2
    //
    Vertex[] vertices = [
        Vertex(float2(-0.5, -0.5), float4(1,1,1,1), float2(0,0)), // [0]
        Vertex(float2( 0.5, -0.5), float4(1,1,1,1), float2(1,0)), // [1]
        Vertex(float2( 0.5,  0.5), float4(1,1,1,1), float2(1,1)), // [2]
        Vertex(float2(-0.5,  0.5), float4(1,1,1,1), float2(0,1)), // [3]
    ];

    UBO ubo;
    VkClearValue bgColour;
    KisvContext context;
    uint graphicsQueueFamily;
    uint transferQueueFamily;

    VkPipeline pipeline;
    VkPipelineLayout pipelineLayout;
    VkSampler sampler;

    VkDescriptorSetLayout dsLayout;
    VkDescriptorPool descriptorPool;
    VkDescriptorSet descriptorSet;

    VkBuffer vertexBuffer;
    VkBuffer indicesBuffer;
    VkBuffer uniformBuffer;

    ImageInfo birdsImage;

    void initialiseScene() {
        log("Initialising scene");
        this.bgColour = clearValue(0.0f, 0, 0, 1);

        allocateGPUMemory();

        createSampler();
        createAndUploadSamplerTexture();

        createAndUploadVertexBuffer();
        createAndUploadIndexBuffer();
        createAndUploadUniformBuffer();
        createDescriptorBindings();
        createGraphicsPipeline();
    }
    void allocateGPUMemory() {
        // Allocate 8 MB on the GPU which should be plenty
        context.memory.allocateDeviceMemory(MEM_GPU, 8 * 1024*1024);
    }
    void createSampler() {
        this.sampler = context.samplers.createLinear("sampler0", (ref VkSamplerCreateInfo info) {
            // Use the standard linear sampler properties
        });
    }
    void createAndUploadSamplerTexture() {
        log("Creating sampler texture");

        // Load the image data
        this.birdsImage = context.images.load("resources/images/birds.bmp");

        // Create the image
        VkImage image = context.images.createImage(IMG_BIRDS,
                                                   birdsImage.extent3D(),
                                                   birdsImage.format,
                                                   VK_IMAGE_USAGE_SAMPLED_BIT | VK_IMAGE_USAGE_TRANSFER_DST_BIT);
        // Bind the image to the GPU memory
        context.memory.bind(MEM_GPU, image);

        // Upload the data to the image on the GPU
        context.transfer.transferAndWaitFor(birdsImage.data, image, birdsImage.extent3D());
    }

    void createAndUploadVertexBuffer() {
        ulong verticesSize = Vertex.sizeof * vertices.length;

        // Create the buffer
        vertexBuffer = context.buffers.createBuffer(BUF_VERTEX, verticesSize,
                                                    VK_BUFFER_USAGE_VERTEX_BUFFER_BIT |
                                                    VK_BUFFER_USAGE_TRANSFER_DST_BIT);

        // Bind the buffer to GPU memory
        context.memory.bind(MEM_GPU, vertexBuffer, 0);

        // Upload the vertices to the GPU
        context.transfer.transferAndWaitFor(vertices, vertexBuffer);
    }
    void createAndUploadIndexBuffer() {
        ulong indicesSize = ushort.sizeof * indices.length;

        // Create the buffer
        indicesBuffer = context.buffers.createBuffer(BUF_INDEX, indicesSize,
                                                     VK_BUFFER_USAGE_INDEX_BUFFER_BIT |
                                                     VK_BUFFER_USAGE_TRANSFER_DST_BIT);

        // Bind the buffer to GPU memory
        context.memory.bind(MEM_GPU, indicesBuffer, 0);

        // Upload the indices to the GPU
        context.transfer.transferAndWaitFor(indices, indicesBuffer);
    }
    void createAndUploadUniformBuffer() {
        enum uniformSize = UBO.sizeof;

        // Uniform buffers must be a multiple of 16 bytes
        static assert(uniformSize%16 == 0);

        // Create the buffer
        uniformBuffer = context.buffers.createBuffer(BUF_UNIFORM, uniformSize,
                                                     VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT |
                                                     VK_BUFFER_USAGE_TRANSFER_DST_BIT);

        // Bind the buffer to GPU memory
        context.memory.bind(MEM_GPU, uniformBuffer, 16);

        // Initialise the view and projection matrices
        float size = 2;
        float aspectRatio = props.windowWidth.as!float / props.windowHeight;
        ubo.model = float16.scale(
            size,
            size * aspectRatio,
            size);
        ubo.view = float16.rowMajor(
            1, 0, 0, 0,
            0, 1, 0, 0,
            0, 0, 1, -2.5,
            0, 0, 0, 1
        );
        ubo.proj = float16.rowMajor(
            0.989743, 0,        0,         0,
            0,        1.732051, 0,         0,
            0,        0,       -1.000195, -0.100020,
            0,        0,       -1.000000,  0
        );

        // Upload the UBO to the GPU
        context.transfer.transferAndWaitFor([ubo], uniformBuffer);
    }
    void createDescriptorBindings() {
        log("Creating descriptor bindings");

        /** Create the bindings */
        // Binding 0: uniform buffer
        VkDescriptorSetLayoutBinding uniformBufferBinding = {
            binding: 0,
            descriptorType: VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
            descriptorCount: 1,
            stageFlags: VK_SHADER_STAGE_VERTEX_BIT,
            pImmutableSamplers: null
        };
        // Binding 1: Image and sampler
        VkDescriptorSetLayoutBinding imageSamplerBinding = {
            binding: 1,
            descriptorType: VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
            descriptorCount: 1,
            stageFlags: VK_SHADER_STAGE_FRAGMENT_BIT,
            pImmutableSamplers: null
        };

        /** Create the layout with the bindings*/
        this.dsLayout = context.descriptors.createLayout(DS_LAYOUT, [uniformBufferBinding, imageSamplerBinding]);

        /** Create the descriptor pool */
        VkDescriptorPoolSize uniformPoolSize = {
            type: VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
            descriptorCount: 1
        };
        VkDescriptorPoolSize imagePoolSize = {
            type: VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
            descriptorCount: 1
        };

        // We will only need 1 set
        uint maxSets = 1;
        this.descriptorPool = context.descriptors.createPool(DS_POOL, maxSets,  [uniformPoolSize, imagePoolSize]);

        /** Allocate our single descriptor set */
        this.descriptorSet = context.descriptors.allocateSet(DS_POOL, DS_LAYOUT);

        /** Write the data to the descriptor set */
        // Create an image view
        VkImageView imageView = context.images.getOrCreateView(IMG_BIRDS,
                                                               VK_IMAGE_VIEW_TYPE_2D,
                                                               birdsImage.format);


        VkDescriptorBufferInfo bufferInfo = {
            buffer: uniformBuffer,
            offset: 0,
            range: UBO.sizeof
        };
        VkWriteDescriptorSet writeUniformBuffer = {
            sType: VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
            dstSet: descriptorSet,
            dstBinding: 0,
            dstArrayElement: 0,
            descriptorCount: 1,
            descriptorType: VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
            pBufferInfo: [bufferInfo].ptr
        };

        VkDescriptorImageInfo imageInfo = {
            sampler: sampler,
            imageView: imageView,
            imageLayout: VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL
        };
        VkWriteDescriptorSet writeImage = {
            sType: VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
            dstSet: descriptorSet,
            dstBinding: 1,
            dstArrayElement: 0,
            descriptorCount: 1,
            descriptorType: VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
            pImageInfo: [imageInfo].ptr
        };

        VkWriteDescriptorSet[] writes = [writeUniformBuffer, writeImage];

        vkUpdateDescriptorSets(
            context.device,
            writes.length.as!uint,
            writes.ptr,
            0,
            null);
    }
    void createGraphicsPipeline() {
        /** Shader stages */
        VkPipelineShaderStageCreateInfo vertexStage = {
            sType: VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            flags: 0,
            stage: VK_SHADER_STAGE_VERTEX_BIT,
            module_: context.shaders.get("rectangle/rectangle.vert"),
            pName: "main".ptr,
            pSpecializationInfo: null
        };
        VkPipelineShaderStageCreateInfo fragmentStage = {
            sType: VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            flags: 0,
            stage: VK_SHADER_STAGE_FRAGMENT_BIT,
            module_: context.shaders.get("rectangle/rectangle.frag"),
            pName: "main".ptr,
            pSpecializationInfo: null
        };

        /** Vertex input state */
        // layout(location = 0) in vec2 inPosition;
        // layout(location = 1) in vec4 inColor;
        // layout(location = 2) in vec2 inUV;
        VkVertexInputBindingDescription binding = {
            binding: 0,
            stride: Vertex.sizeof,
            inputRate: VK_VERTEX_INPUT_RATE_VERTEX
        };
        VkVertexInputAttributeDescription inPosition = {
            location: 0,
            binding: 0,
            format: VK_FORMAT_R32G32_SFLOAT,
            offset: Vertex.pos.offsetof
        };
        VkVertexInputAttributeDescription inColor = {
            location: 1,
            binding: 0,
            format: VK_FORMAT_R32G32B32A32_SFLOAT,
            offset: Vertex.colour.offsetof
        };
        VkVertexInputAttributeDescription inUV = {
            location: 2,
            binding: 0,
            format: VK_FORMAT_R32G32_SFLOAT,
            offset: Vertex.uv.offsetof
        };

        VkPipelineVertexInputStateCreateInfo vertexInputState = {
            sType: VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
            flags: 0,
            vertexBindingDescriptionCount: 1,
            pVertexBindingDescriptions: [binding].ptr,
            vertexAttributeDescriptionCount: 3,
            pVertexAttributeDescriptions: [inPosition, inColor, inUV].ptr
        };

        /** Input assembly state */
        VkPipelineInputAssemblyStateCreateInfo inputAssemblyState = {
            sType: VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
            flags: 0,
            topology: VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
            primitiveRestartEnable: VK_FALSE
        };

        /** Viewport state */
        VkPipelineViewportStateCreateInfo viewportState = {
            sType: VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
            flags:0,
            viewportCount: 1,
            pViewports: [VkViewport(0, 0, context.window.width, context.window.height,
                                    0.0f, 1.0f)].ptr,
            scissorCount: 1,
            pScissors: [VkRect2D(VkOffset2D(0,0), context.window.size())].ptr
        };

        /** Rasterization state */
        VkPipelineRasterizationStateCreateInfo rasterizationState = {
            sType: VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
            flags:0,
            depthClampEnable: VK_FALSE,
            rasterizerDiscardEnable: VK_FALSE,
            polygonMode: VK_POLYGON_MODE_FILL,
            cullMode: VK_CULL_MODE_NONE,
            frontFace: VK_FRONT_FACE_CLOCKWISE,
            depthBiasEnable: VK_FALSE,
            depthBiasConstantFactor: 0,
            depthBiasClamp: 0,
            depthBiasSlopeFactor: 0,
            lineWidth: 1
        };

        /** Multisample state */
        VkPipelineMultisampleStateCreateInfo multisampleState = {
            sType: VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
            flags: 0,
            sampleShadingEnable: VK_FALSE,  // per sample if true, otherwise per fragment
            rasterizationSamples: VK_SAMPLE_COUNT_1_BIT,
            minSampleShading: 1.0f,
            pSampleMask: null,
            alphaToCoverageEnable: VK_FALSE,
            alphaToOneEnable: VK_FALSE
        };

        /** Depth/Stencil state */
        VkPipelineDepthStencilStateCreateInfo depthStencilState = {
            sType: VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
            flags: 0,
            depthTestEnable: VK_FALSE,
            depthWriteEnable: VK_FALSE,
            depthCompareOp: VK_COMPARE_OP_NEVER,
            depthBoundsTestEnable: VK_FALSE,
            stencilTestEnable: VK_FALSE,
            front: VkStencilOpState(),
            back: VkStencilOpState(),
            minDepthBounds: 0,
            maxDepthBounds: 1
        };

        /** Color blend state */
        VkPipelineColorBlendAttachmentState colorBlendAttachment = {
            blendEnable: VK_FALSE,
            srcColorBlendFactor: VK_BLEND_FACTOR_SRC_ALPHA,
            dstColorBlendFactor: VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
            srcAlphaBlendFactor: VK_BLEND_FACTOR_ONE,
            dstAlphaBlendFactor: VK_BLEND_FACTOR_ZERO,
            colorBlendOp: VK_BLEND_OP_ADD,
            alphaBlendOp: VK_BLEND_OP_ADD,
            colorWriteMask:
                VK_COLOR_COMPONENT_R_BIT |
                VK_COLOR_COMPONENT_G_BIT |
                VK_COLOR_COMPONENT_B_BIT |
                VK_COLOR_COMPONENT_A_BIT
        };

        VkPipelineColorBlendStateCreateInfo colorBlendState = {
            sType: VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
            flags: 0,
            logicOpEnable: VK_FALSE,
            logicOp: VK_LOGIC_OP_COPY,
            attachmentCount: 1,
            pAttachments: [colorBlendAttachment].ptr,
            blendConstants: [0.0f, 0, 0, 0]
        };

        /** Layout **/
        VkPipelineLayoutCreateInfo layoutInfo = {
            sType: VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
            flags: 0,
            setLayoutCount: 1,
            pSetLayouts: &dsLayout,
            pushConstantRangeCount: 0,
            pPushConstantRanges: null
        };

        check(vkCreatePipelineLayout(context.device, &layoutInfo, null, &pipelineLayout));

        VkGraphicsPipelineCreateInfo pipelineCreateInfo = {
            sType: VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
            flags: 0,
            stageCount: 2,
            pStages: [vertexStage, fragmentStage].ptr,
            pVertexInputState: &vertexInputState,
            pInputAssemblyState: &inputAssemblyState,
            pTessellationState: null,
            pViewportState: &viewportState,
            pRasterizationState: &rasterizationState,
            pMultisampleState: &multisampleState,
            pDepthStencilState: &depthStencilState,
            pColorBlendState: &colorBlendState,
            pDynamicState: null,
            layout: pipelineLayout,
            renderPass: context.renderPass,
            subpass: 0,
            basePipelineHandle: null,
            basePipelineIndex: -1
        };

        check(vkCreateGraphicsPipelines(context.device, null, 1, &pipelineCreateInfo, null, &pipeline));
    }
    void renderScene(KisvFrame frame, uint imageIndex) {
        auto cmd = frame.commands;
        cmd.beginOneTimeSubmit();

        // Perform code that needs to be outside the render pass here eg. transfers

        cmd.beginRenderPass(
            context.renderPass,
            frame.frameBuffer,
            toVkRect2D(0, 0, context.window.size()),
            [ bgColour ]
        );

        // We are inside the render pass here

        cmd.vkCmdBindPipeline(VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline);

        cmd.vkCmdBindDescriptorSets(
            VK_PIPELINE_BIND_POINT_GRAPHICS,
            pipelineLayout,
            0,
            1,
            &descriptorSet,
            0,
            null);

        cmd.vkCmdBindVertexBuffers(
            0,                      // firstBinding
            1,                      // bindingCount
            &vertexBuffer,          // VkBuffer* pBuffers
            [0UL].ptr);             // ulong* pOffsets

        cmd.vkCmdBindIndexBuffer(
            indicesBuffer,          // buffer
            0,                      // offset
            VK_INDEX_TYPE_UINT16);  // type

        cmd.vkCmdDrawIndexed(
            6,                      // indexCount
            1,                      // instanceCount
            0,                      // firstIndex
            0,                      // vertexOffset
            0);                     // firstInstance

        cmd.endRenderPass();
        cmd.end();

        // Submit our render buffer
        context.queues.getQueue(graphicsQueueFamily, 0)
               .submit(
            [cmd],                                           // VkCommandBuffers
            [frame.imageAvailable],                          // wait semaphores
            [VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT], // wait stages
            [frame.renderFinished],                          // signal semaphores
            frame.fence
        );
    }
}
