module demos.raytracing.demo_ray_tracing;

import std.format       : format;
import std.string       : toStringz;
import core.stdc.string : memcpy;

import kisv;
import demos.demo : DemoApplication;
import demos.raytracing.simple_triangle;

interface RayTracingSubDemo {
    KisvRayTracingPipeline getRayTracingPipeline();
    KisvAccelerationStructure getTopLevelAccelerationStructure();
    void destroy();

    RayTracingSubDemo createDSLayout(string dsLayoutKey);
    RayTracingSubDemo createPipeline(string sbtMemoryKey);
    RayTracingSubDemo createAccelerationStructures(string deviceMemoryKey, VkCommandPool commandPool, uint queueFamilyIndex);
}

final class RayTracing : DemoApplication {
public:
    override void initialise(string[] args) {
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
            // Look for a graphics with compute queue family
            auto graphics = h.find(VK_QUEUE_GRAPHICS_BIT | VK_QUEUE_COMPUTE_BIT);
            throwIf(graphics.length == 0, "No graphics queues available");
            graphicsComputeQueueFamily = graphics[0].index;
            log("Selected graphics/compute queue family %s", graphicsComputeQueueFamily);

            // Look for a transfer queue family
            if(h.supports(graphicsComputeQueueFamily, VK_QUEUE_TRANSFER_BIT)) {
                // Use the graphics queue for transfer
                transferQueueFamily = graphicsComputeQueueFamily;
            } else {
                auto transfer = h.find(VK_QUEUE_TRANSFER_BIT);
                throwIf(transfer.length == 0, "No transfer queues available");
                transferQueueFamily = transfer[0].index;
            }
            log("Selected transfer queue family %s", transferQueueFamily);
        });

        // Select the device features that we want to use
        VkPhysicalDeviceAccelerationStructureFeaturesKHR asFeatures = {
            sType: VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_ACCELERATION_STRUCTURE_FEATURES_KHR,
            accelerationStructure: VK_TRUE
        };
        VkPhysicalDeviceRayTracingPipelineFeaturesKHR rtpFeatures = {
            sType: VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_RAY_TRACING_PIPELINE_FEATURES_KHR,
            rayTracingPipeline: VK_TRUE
        };
        VkPhysicalDeviceBufferDeviceAddressFeaturesEXT bdaFeatures = {
            sType: VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_BUFFER_DEVICE_ADDRESS_FEATURES,
            bufferDeviceAddress: VK_TRUE
        };

        context.selectDeviceFeatures((FeatureHelper f) {
            f.add(asFeatures)
             .add(rtpFeatures)
             .add(bdaFeatures);
        });

        uint[uint] queueRequest;
        queueRequest[graphicsComputeQueueFamily]++;
        if(transferQueueFamily != graphicsComputeQueueFamily) {
            queueRequest[transferQueueFamily]++;
        }
        context.createLogicalDevice(queueRequest);
        context.createWindow(VK_IMAGE_USAGE_TRANSFER_DST_BIT);
        context.createStandardRenderPass();
        context.createTransferHelper(transferQueueFamily);
        context.createRenderLoop(graphicsComputeQueueFamily);

        initialiseScene();

        import core.cpuid: processor;
        context.window.setTitle("%s %s :: %s, %s".format(
            props.appName,
            VERSION, context.physicalDevice.name(), processor()));

    }
    override void destroy() {
        // Always ensure the device is idle before destroying device objects
        vkDeviceWaitIdle(context.device);

        if(demo) demo.destroy();

        if(buildCommandPool) vkDestroyCommandPool(context.device, buildCommandPool, null);
        if(context) context.destroy();
    }
    override void run() {
        context.window.show();

        context.startRenderLoop((KisvFrame frame, uint imageIndex) {
            renderScene(frame, imageIndex);
        });
    }
private:
    // Keys
    enum : string {
        MEM_GPU             = "gpu1",
        MEM_UPLOAD          = "upload1",
        MEM_DOWNLOAD        = "download1",
        IMG_TARGET          = "target1",
        BUF_UNIFORM         = "uniform",
        DS_LAYOUT           = "layout1",
        DS_POOL             = "pool1",
    }
    KisvProperties props = {
        appName: "RayTracing",
        apiVersion: VkVersion(1, 2, 0),
        instanceLayers: [
            "VK_LAYER_KHRONOS_validation"
        ],
        instanceExtensions: [
            "VK_KHR_surface",
            "VK_KHR_win32_surface"
        ],
        // Vulkan 1.2 automatically enables:
        //  - Spirv 1.5
        //  - VK_KHR_maintenance1
        //  - VK_KHR_maintenance2
        //  - VK_KHR_maintenance3
        deviceExtensions: [
            "VK_KHR_swapchain",

            // Ray tracing
            "VK_KHR_acceleration_structure",
            "VK_KHR_ray_tracing_pipeline",
            // Acceleration structure
            "VK_KHR_deferred_host_operations",

            "VK_KHR_buffer_device_address",
            "VK_EXT_descriptor_indexing",
            "VK_KHR_shader_float_controls"
        ],
        windowed: true,
        windowWidth: 1400,
        windowHeight: 1000,
        windowVsync: false
    };
    static struct UBO { static assert(UBO.sizeof==2*16*4);
        float16 viewInverse;
        float16 projInverse;
    }
    UBO ubo;                    
    VkClearValue bgColour;
    KisvContext context;
    uint graphicsComputeQueueFamily;
    uint transferQueueFamily;
    VkCommandPool buildCommandPool;

    VkBuffer uniformBuffer; 
    VkImage storageImage;       
    VkDescriptorSet descriptorSet;

    RayTracingSubDemo demo;
    KisvRayTracingPipeline pipeline;
    KisvAccelerationStructure tlas;

    void setDeviceFunctions() {
        // Uncomment these to get the ray tracing functions from the device.
        // These will be slightly lower overhead than the instance ones that we already have
        // because some of the layer hooks are bypassed.

        // *(cast(void**)&vkGetBufferDeviceAddressKHR) = vkGetDeviceProcAddr(context.device, toStringz("vkGetBufferDeviceAddressKHR"));
        // *(cast(void**)&vkCmdBuildAccelerationStructuresKHR) = vkGetDeviceProcAddr(context.device, toStringz("vkCmdBuildAccelerationStructuresKHR"));
        // *(cast(void**)&vkBuildAccelerationStructuresKHR) = vkGetDeviceProcAddr(context.device, toStringz("vkBuildAccelerationStructuresKHR"));
        // *(cast(void**)&vkCreateAccelerationStructureKHR) = vkGetDeviceProcAddr(context.device, toStringz("vkCreateAccelerationStructureKHR"));
        // *(cast(void**)&vkDestroyAccelerationStructureKHR) = vkGetDeviceProcAddr(context.device, toStringz("vkDestroyAccelerationStructureKHR"));
        // *(cast(void**)&vkGetAccelerationStructureBuildSizesKHR) = vkGetDeviceProcAddr(context.device, toStringz("vkGetAccelerationStructureBuildSizesKHR"));
        // *(cast(void**)&vkGetAccelerationStructureDeviceAddressKHR) = vkGetDeviceProcAddr(context.device, toStringz("vkGetAccelerationStructureDeviceAddressKHR"));
        // *(cast(void**)&vkCmdTraceRaysKHR) = vkGetDeviceProcAddr(context.device, toStringz("vkCmdTraceRaysKHR"));
        // *(cast(void**)&vkGetRayTracingShaderGroupHandlesKHR) = vkGetDeviceProcAddr(context.device, toStringz("vkGetRayTracingShaderGroupHandlesKHR"));
        // *(cast(void**)&vkCreateRayTracingPipelinesKHR) = vkGetDeviceProcAddr(context.device, toStringz("vkCreateRayTracingPipelinesKHR"));
    }

    void initialiseScene() {
        setDeviceFunctions();

        this.bgColour = clearValue(0, 0.25f, 0, 1);
        
        logStructure(context.physicalDevice.rtPipelineProperties);
        logStructure(context.physicalDevice.accelerationStructureProperties);

        allocateMemory();
        createBuildCommandPool();
        createAndUploadUniformBuffer();
        createStorageImage();

        this.demo = new SimpleTriangle(context)
            .createDSLayout(DS_LAYOUT)
            .createPipeline(MEM_UPLOAD)
            .createAccelerationStructures(MEM_GPU, buildCommandPool, graphicsComputeQueueFamily);

        this.pipeline = demo.getRayTracingPipeline();
        this.tlas = demo.getTopLevelAccelerationStructure();

        createDescriptorSet();
    }
    void allocateMemory() {
        // Allocate 16 MB on the GPU
        // Set the VK_MEMORY_ALLOCATE_DEVICE_ADDRESS_BIT flag so that we can get device addesses later
        context.memory.allocateDeviceMemory(MEM_GPU, 16.megabytes(), VK_MEMORY_ALLOCATE_DEVICE_ADDRESS_BIT);

        context.memory.allocateStagingUploadMemory(MEM_UPLOAD, 16.megabytes(), VK_MEMORY_ALLOCATE_DEVICE_ADDRESS_BIT);

        context.memory.allocateStagingDownloadMemory(MEM_DOWNLOAD, 16.megabytes(), VK_MEMORY_ALLOCATE_DEVICE_ADDRESS_BIT);
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
        context.memory.bind(MEM_GPU, uniformBuffer, 0);

        // Initialise the view and projection matrices

        ubo.viewInverse = float16.rowMajor(
            1, 0, 0, 0,
            0, 1, 0, 0,
            0, 0, 1, 2.5,
            0, 0, 0, 1
        );
        ubo.projInverse = float16.rowMajor(
            1.010363, 0,        0,         0,
            0,        0.577350, 0,         0,
            0,        0,        0,        -1,
            0,        0,       -9.998046,  10
        );

        log("viewInverse:\n%s", ubo.viewInverse);
        log("projInverse:\n%s", ubo.projInverse);

        log("Uploading uniform buffer data to the GPU");
        context.transfer.transferAndWaitFor([ubo], uniformBuffer);
    }
    void createStorageImage() {
        this.storageImage = context.images.createImage(
            IMG_TARGET,
            toVkExtent3D(context.window.size(), 1),
            VK_FORMAT_R8G8B8A8_UNORM,
            VK_IMAGE_USAGE_TRANSFER_SRC_BIT | VK_IMAGE_USAGE_STORAGE_BIT);

        context.memory.bind(MEM_GPU, storageImage);
    }
    void createBuildCommandPool() {
        this.buildCommandPool = createCommandPool(context.device, graphicsComputeQueueFamily,
            VK_COMMAND_POOL_CREATE_TRANSIENT_BIT);
    }
    void createDescriptorSet() {
        VkDescriptorPoolSize[] poolSizes = [
            VkDescriptorPoolSize(VK_DESCRIPTOR_TYPE_ACCELERATION_STRUCTURE_KHR, 1),
            VkDescriptorPoolSize(VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, 1),
            VkDescriptorPoolSize(VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, 1)
        ];

        context.descriptors.createPool(DS_POOL, 1, poolSizes);

        this.descriptorSet = context.descriptors.allocateSet(DS_POOL, DS_LAYOUT);

        VkWriteDescriptorSetAccelerationStructureKHR descriptorAccelerationStructureInfo = {
            sType: VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET_ACCELERATION_STRUCTURE_KHR,
            accelerationStructureCount: 1,
            pAccelerationStructures: &tlas.handle
        };
        VkWriteDescriptorSet accelerationStructureWrite = {
            sType: VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
            pNext: &descriptorAccelerationStructureInfo,
            dstSet: descriptorSet,
            dstBinding: 0,
            descriptorCount: 1,
            descriptorType: VK_DESCRIPTOR_TYPE_ACCELERATION_STRUCTURE_KHR
        };

        VkDescriptorImageInfo storageImageDescriptor = {
            imageView: context.images.getOrCreateView(IMG_TARGET, VK_IMAGE_VIEW_TYPE_2D, VK_FORMAT_R8G8B8A8_UNORM),
            imageLayout: VK_IMAGE_LAYOUT_GENERAL
        };

        VkWriteDescriptorSet imageWrite = {
            sType: VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
            dstSet: descriptorSet,
            dstBinding: 1,
            dstArrayElement: 0,
            descriptorCount: 1,
            descriptorType: VK_DESCRIPTOR_TYPE_STORAGE_IMAGE,
            pImageInfo: [storageImageDescriptor].ptr
        };

        VkDescriptorBufferInfo uniformBufferInfo = {
            buffer: uniformBuffer,
            offset: 0,
            range: VK_WHOLE_SIZE
        };
        VkWriteDescriptorSet uniformWrite = {
            sType: VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
            dstSet: descriptorSet,
            dstBinding: 2,
            dstArrayElement: 0,
            descriptorCount: 1,
            descriptorType: VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
            pBufferInfo: [uniformBufferInfo].ptr
        };

        VkWriteDescriptorSet[] writes = [
            accelerationStructureWrite,
            imageWrite,
            uniformWrite
        ];

        vkUpdateDescriptorSets(context.device, writes.length.as!uint, writes.ptr, 0, null);
    }
    void renderScene(KisvFrame frame, uint imageIndex) {

        VkImage swapchainImage = context.window.images[imageIndex];
        VkExtent2D size = context.window.size();

        VkImageSubresourceRange subresourceRange = {
            aspectMask: VK_IMAGE_ASPECT_COLOR_BIT,
            baseMipLevel: 0,
            levelCount: VK_REMAINING_MIP_LEVELS,
            baseArrayLayer: 0,
            layerCount: VK_REMAINING_ARRAY_LAYERS
        };

        VkImageMemoryBarrier swapchainToTransferDst = {
            sType: VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
            oldLayout: VK_IMAGE_LAYOUT_UNDEFINED,
            newLayout: VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
            srcAccessMask: 0,
            dstAccessMask: VK_ACCESS_TRANSFER_WRITE_BIT,
            image: swapchainImage,
            srcQueueFamilyIndex: VK_QUEUE_FAMILY_IGNORED,
            dstQueueFamilyIndex: VK_QUEUE_FAMILY_IGNORED,
            subresourceRange: subresourceRange
        };
        VkImageMemoryBarrier swapchainToPresent = {
            sType: VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
            oldLayout: VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
            newLayout: VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
            srcAccessMask: VK_ACCESS_TRANSFER_WRITE_BIT,
            dstAccessMask: 0,
            image: swapchainImage,
            srcQueueFamilyIndex: VK_QUEUE_FAMILY_IGNORED,
            dstQueueFamilyIndex: VK_QUEUE_FAMILY_IGNORED,
            subresourceRange: subresourceRange
        };

        VkImageMemoryBarrier imageToGeneral = {
            sType: VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
            oldLayout: VK_IMAGE_LAYOUT_UNDEFINED,
            newLayout: VK_IMAGE_LAYOUT_GENERAL,
            srcAccessMask: 0,
            dstAccessMask: VK_ACCESS_SHADER_WRITE_BIT,
            image: storageImage,
            srcQueueFamilyIndex: VK_QUEUE_FAMILY_IGNORED,
            dstQueueFamilyIndex: VK_QUEUE_FAMILY_IGNORED,
            subresourceRange: subresourceRange
        };

        VkImageMemoryBarrier imageToSrc = {
            sType: VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
            oldLayout: VK_IMAGE_LAYOUT_GENERAL,
            newLayout: VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
            srcAccessMask: VK_ACCESS_SHADER_WRITE_BIT,
            dstAccessMask: VK_ACCESS_TRANSFER_READ_BIT,
            image: storageImage,
            srcQueueFamilyIndex: VK_QUEUE_FAMILY_IGNORED,
            dstQueueFamilyIndex: VK_QUEUE_FAMILY_IGNORED,
            subresourceRange: subresourceRange
        };

        auto cmd = frame.commands;
        cmd.beginOneTimeSubmit();

        vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_RAY_TRACING_KHR, pipeline.getPipeline());
        vkCmdBindDescriptorSets(
            cmd,
            VK_PIPELINE_BIND_POINT_RAY_TRACING_KHR,
            pipeline.getLayout(),
            0,
            1,
            &descriptorSet,
            0,                  // dynamic offset count
            null);              // dynamic offsets

        cmd.vkCmdPipelineBarrier(VK_PIPELINE_STAGE_ALL_COMMANDS_BIT,
                                 VK_PIPELINE_STAGE_ALL_COMMANDS_BIT,
                                 0,                 // dependencyFlags
                                 0,                 // memoryBarrierCount
                                 null,
                                 0,                 // bufferMemoryBarrierCount
                                 null,
                                 1,                 // imageMemoryBarrierCount
                                 &imageToGeneral);

        vkCmdTraceRaysKHR(
            cmd,
            pipeline.getRaygenStridedDeviceAddressRegionPtr(),
            pipeline.getMissStridedDeviceAddressRegionPtr(),
            pipeline.getHitStridedDeviceAddressRegionPtr(),
            pipeline.getCallableStridedDeviceAddressRegionPtr(),
            size.width,
            size.height,
            1);

        /** Copy ray tracing output to swap chain image */
        cmd.vkCmdPipelineBarrier(VK_PIPELINE_STAGE_ALL_COMMANDS_BIT,
                                 VK_PIPELINE_STAGE_ALL_COMMANDS_BIT,
                                 0,                 // dependencyFlags
                                 0,                 // memoryBarrierCount
                                 null,
                                 0,                 // bufferMemoryBarrierCount
                                 null,
                                 1,                 // imageMemoryBarrierCount
                                 &imageToSrc);

        cmd.vkCmdPipelineBarrier(VK_PIPELINE_STAGE_ALL_COMMANDS_BIT,
                                 VK_PIPELINE_STAGE_ALL_COMMANDS_BIT,
                                 0,                 // dependencyFlags
                                 0,                 // memoryBarrierCount
                                 null,
                                 0,                 // bufferMemoryBarrierCount
                                 null,
                                 1,                 // imageMemoryBarrierCount
                                 &swapchainToTransferDst);

        // copy here
        VkImageCopy copyRegion = {
            srcSubresource: VkImageSubresourceLayers(VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1),
            srcOffset: VkOffset3D(0, 0, 0),
            dstSubresource: VkImageSubresourceLayers(VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1),
            dstOffset: VkOffset3D(0, 0, 0),
            extent: VkExtent3D(size.width, size.height, 1)
        };

        vkCmdCopyImage(
            cmd,
            storageImage, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
            swapchainImage, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
            1,
            &copyRegion);

        cmd.vkCmdPipelineBarrier(VK_PIPELINE_STAGE_ALL_COMMANDS_BIT,
                                 VK_PIPELINE_STAGE_ALL_COMMANDS_BIT,
                                 0,                 // dependencyFlags
                                 0,                 // memoryBarrierCount
                                 null,
                                 0,                 // bufferMemoryBarrierCount
                                 null,
                                 1,                 // imageMemoryBarrierCount
                                 &swapchainToPresent);

        // Perform code that needs to be outside the render pass here

        // cmd.beginRenderPass(
        //     context.renderPass,
        //     frame.frameBuffer,
        //     toVkRect2D(0, 0, context.window.size()),
        //     [ bgColour ]
        // );

        // // We are inside the render pass here

        // cmd.endRenderPass();

        cmd.end();

        /// Submit our render buffer
        context.queues
               .getQueue(graphicsComputeQueueFamily, 0)
               .submit(
            [cmd],                                           // VkCommandBuffers
            [frame.imageAvailable],                          // wait semaphores
            [VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT], // wait stages
            [frame.renderFinished],                          // signal semaphores
            frame.fence
        );
    }
}
