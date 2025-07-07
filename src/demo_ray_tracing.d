module demo_ray_tracing;

import std.format       : format;
import std.string       : toStringz;
import core.stdc.string : memcpy;

import kisv;
import demo : DemoApplication;

final class RayTracing : DemoApplication {
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

        logStructure(asFeatures);
        logStructure(rtpFeatures);
        logStructure(bdaFeatures);

        uint[uint] queueRequest;
        queueRequest[graphicsQueueFamily]++;
        if(transferQueueFamily != graphicsQueueFamily) {
            queueRequest[transferQueueFamily]++;
        }
        context.createLogicalDevice(queueRequest);

        context.createWindow(VK_IMAGE_USAGE_TRANSFER_DST_BIT);

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

        // Todo - tidy
        if(rtPipeline) vkDestroyPipeline(context.device, rtPipeline, null);
        if(rtPipelineLayout) vkDestroyPipelineLayout(context.device, rtPipelineLayout, null);

        if(buildCommandPool) vkDestroyCommandPool(context.device, buildCommandPool, null);

        if(blas.handle) vkDestroyAccelerationStructureKHR(context.device, blas.handle, null);
        if(tlas.handle) vkDestroyAccelerationStructureKHR(context.device, tlas.handle, null);

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

        MEM_VERTICES        = "uploadvertices",
        MEM_INDICES         = "uploadindices",
        MEM_TRANSFORMS      = "uploadtransforms",

        MEM_DOWNLOAD        = "download1",
        IMG_TARGET          = "target1",
        BUF_UNIFORM         = "uniform",
        BUF_TLAS            = "tlas1",
        BUF_BLAS            = "blas1",
        BUF_VERTEX          = "vertices1",
        BUF_INDEX           = "index1",
        BUF_TRANSFORM       = "transform1",
        BUF_BLAS_SCRATCH    = "scratch1",
        BUF_TLAS_SCRATCH    = "scratch2",
        BUF_INSTANCES       = "instances1",
        DS_LAYOUT           = "layout1",
        DS_POOL             = "pool1",

        BUF_SBT_RAYGEN      ="sbt_raygen",
        BUF_SBT_MISS        ="sbt_miss",
        BUF_SBT_HIT         ="sbt_hit",
    }
    KisvProperties props = {
        appName: "RayTracing",
        apiVersion: VkVersion(1, 2, 0),
        instanceLayers: [
            "VK_LAYER_KHRONOS_validation"//,
            //"VK_LAYER_LUNARG_api_dump"
            //"VK_LAYER_LUNARG_monitor"
        ],
        instanceExtensions: [
            "VK_KHR_surface",
            "VK_KHR_win32_surface"
        ],
        deviceExtensions: [
            "VK_KHR_swapchain",

            //"VK_KHR_maintenance1",

            // Ray tracing
            "VK_KHR_acceleration_structure",
            "VK_KHR_ray_tracing_pipeline",
            // Acceleration structure
            "VK_KHR_deferred_host_operations",
            "VK_KHR_buffer_device_address",
            // SPIRV 1.4
            "VK_KHR_spirv_1_4",
            "VK_KHR_shader_float_controls",

            "VK_EXT_descriptor_indexing"
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
    static struct AccelerationStructure {
        VkAccelerationStructureKHR handle;
        VkDeviceAddress deviceAddress;
        VkBuffer buffer;
        VkBuffer scratchBuffer;
        VkDeviceAddress scratchBufferDeviceAddress;
    }
    VkClearValue bgColour;
    KisvContext context;
    uint graphicsQueueFamily;
    uint transferQueueFamily;
    UBO ubo;                    // Host data for the uniform buffer
    VkBuffer uniformBuffer;     // Uniform buffer
    VkCommandPool buildCommandPool;

    AccelerationStructure tlas; // RT Top level acceleration structure
    AccelerationStructure blas; // RT Bottom level acceleration structure
    VkBuffer vertexBuffer;      // RT vertices
    VkBuffer indexBuffer;       // RT indices
    VkBuffer transformBuffer;   // RT transforms
    VkBuffer instanceBuffer;    // RT instances

    VkBuffer sbtRaygenBuffer;   // RT shader binding table raygen buffer
    VkBuffer sbtMissBuffer;
    VkBuffer sbtHitBuffer;

    VkImage storageImage;       // RT target image

    VkPipelineLayout rtPipelineLayout;
    VkPipeline rtPipeline;

    VkDescriptorSet descriptorSet;

    void initialiseScene() {
        this.bgColour = clearValue(0, 0.25f, 0, 1);

        // import std.string : toStringz;
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

        logStructure(context.physicalDevice.rtPipelineProperties);
        logStructure(context.physicalDevice.accelerationStructureProperties);

        createBuildCommandPool();
        allocateMemory();
        createAndUploadUniformBuffer();
        createStorageImage();

        createBottomLevelAccelerationStructure();
        createTopLevelAccelerationStructure();
        createRayTracingPipeline();
        createDescriptorSet();
        createShaderBindingTable();
    }
    void allocateMemory() {
        // Allocate 16 MB on the GPU
        // Set the VK_MEMORY_ALLOCATE_DEVICE_ADDRESS_BIT flag so that we can get device addesses later
        context.memory.allocateDeviceMemory(MEM_GPU, 16.megabytes(), VK_MEMORY_ALLOCATE_DEVICE_ADDRESS_BIT);

        context.memory.allocateStagingUploadMemory(MEM_UPLOAD, 16.megabytes(), VK_MEMORY_ALLOCATE_DEVICE_ADDRESS_BIT);

        context.memory.allocateStagingDownloadMemory(MEM_DOWNLOAD, 16.megabytes(), VK_MEMORY_ALLOCATE_DEVICE_ADDRESS_BIT);
    }
    void createAndUploadUniformBuffer() {
        log("Creating uniform buffer");
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

        float* ptr = cast(float*)&ubo;
        log("Ubo data = %s", ptr[0..UBO.sizeof/4]);

        log("viewInverse:\n%s", ubo.viewInverse);
        log("projInverse:\n%s", ubo.projInverse);

        log("Uploading uniform buffer data to the GPU");
        context.transfer.transferAndWaitFor([ubo], uniformBuffer);
    }
    void createStorageImage() {
        log("Creating storage image");

        this.storageImage = context.images.createImage(
            IMG_TARGET,
            toVkExtent3D(context.window.size(), 1),
            VK_FORMAT_R8G8B8A8_UNORM,
            VK_IMAGE_USAGE_TRANSFER_SRC_BIT | VK_IMAGE_USAGE_STORAGE_BIT);

        context.memory.bind(MEM_GPU, storageImage);
    }
    void createBuildCommandPool() {
        this.buildCommandPool = createCommandPool(context.device, graphicsQueueFamily,
            VK_COMMAND_POOL_CREATE_TRANSIENT_BIT);
    }
    void createBottomLevelAccelerationStructure() {

        *(cast(void**)&vkCmdBuildAccelerationStructuresKHR) = vkGetDeviceProcAddr(context.device, toStringz("vkCmdBuildAccelerationStructuresKHR"));
        *(cast(void**)&vkGetAccelerationStructureBuildSizesKHR) = vkGetDeviceProcAddr(context.device, toStringz("vkGetAccelerationStructureBuildSizesKHR"));
        *(cast(void**)&vkCreateAccelerationStructureKHR) = vkGetDeviceProcAddr(context.device, toStringz("vkCreateAccelerationStructureKHR"));
        *(cast(void**)&vkGetBufferDeviceAddressKHR) = vkGetDeviceProcAddr(context.device, toStringz("vkGetBufferDeviceAddressKHR"));
        *(cast(void**)&vkGetAccelerationStructureDeviceAddressKHR) = vkGetDeviceProcAddr(context.device, toStringz("vkGetAccelerationStructureDeviceAddressKHR"));
        *(cast(void**)&vkCmdCopyAccelerationStructureToMemoryKHR) = vkGetDeviceProcAddr(context.device, toStringz("vkCmdCopyAccelerationStructureToMemoryKHR"));

        static struct Vertex { static assert(Vertex.sizeof==12);
		    float x,y,z;
	    }
	    Vertex[] vertices = [
            Vertex(1.0f, 1.0f, 0.0f),
            Vertex(-1.0f, 1.0f, 0.0f),
            Vertex(0.0f, -1.0f, 0.0f)
        ];

        uint[] indices = [ 0, 1, 2 ];

        VkTransformMatrixKHR transform = identityTransformMatrix();

        log("Vertices size = %s", vertices.length*Vertex.sizeof);
        log("Indices size = %s", indices.length * uint.sizeof);
        log("Transform size = %s", VkTransformMatrixKHR.sizeof);

        log("Vertices = %s", (cast(ubyte*)vertices.ptr)[0..vertices.length*Vertex.sizeof]);
        log("Indices = %s", (cast(ubyte*)indices.ptr)[0..indices.length*uint.sizeof]);
        log("Transform = %s", (cast(ubyte*)&transform)[0..VkTransformMatrixKHR.sizeof]);

        // Create buffers for vertices, indices and transforms
        vertexBuffer = context.buffers.createBuffer(BUF_VERTEX,
            Vertex.sizeof*vertices.length,
            VK_BUFFER_USAGE_ACCELERATION_STRUCTURE_BUILD_INPUT_READ_ONLY_BIT_KHR |
            VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT |
            VK_BUFFER_USAGE_TRANSFER_DST_BIT);
        indexBuffer = context.buffers.createBuffer(BUF_INDEX,
            uint.sizeof*indices.length,
            VK_BUFFER_USAGE_ACCELERATION_STRUCTURE_BUILD_INPUT_READ_ONLY_BIT_KHR |
            VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT |
            VK_BUFFER_USAGE_TRANSFER_DST_BIT);
        transformBuffer = context.buffers.createBuffer(BUF_TRANSFORM,
            VkTransformMatrixKHR.sizeof,
            VK_BUFFER_USAGE_ACCELERATION_STRUCTURE_BUILD_INPUT_READ_ONLY_BIT_KHR |
            VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT |
            VK_BUFFER_USAGE_TRANSFER_DST_BIT);

        enum OPT = 2;

        static if(OPT==0) {
            context.memory.allocateStagingUploadMemory(MEM_VERTICES, 1.megabytes(), VK_MEMORY_ALLOCATE_DEVICE_ADDRESS_BIT);
            context.memory.allocateStagingUploadMemory(MEM_INDICES, 1.megabytes(), VK_MEMORY_ALLOCATE_DEVICE_ADDRESS_BIT);
            context.memory.allocateStagingUploadMemory(MEM_TRANSFORMS, 1.megabytes(), VK_MEMORY_ALLOCATE_DEVICE_ADDRESS_BIT);

            context.memory.bind(MEM_VERTICES, vertexBuffer, 0);
            context.memory.bind(MEM_INDICES, indexBuffer, 0);
            context.memory.bind(MEM_TRANSFORMS, transformBuffer, 0);

            void* map1 = context.memory.map(MEM_VERTICES, 0, VK_WHOLE_SIZE);
            void* map2 = context.memory.map(MEM_INDICES, 0, VK_WHOLE_SIZE);
            void* map3 = context.memory.map(MEM_TRANSFORMS, 0, VK_WHOLE_SIZE);

            memcpy(map1, vertices.ptr, Vertex.sizeof*vertices.length);
            memcpy(map2, indices.ptr, uint.sizeof*indices.length);
            memcpy(map3, &transform, VkTransformMatrixKHR.sizeof);

            context.memory.unmap(MEM_VERTICES);
            context.memory.unmap(MEM_INDICES);
            context.memory.unmap(MEM_TRANSFORMS);

        } else static if(OPT==1) {
            context.memory.allocateDeviceMemory(MEM_VERTICES, 1.megabytes(), VK_MEMORY_ALLOCATE_DEVICE_ADDRESS_BIT);
            context.memory.allocateDeviceMemory(MEM_INDICES, 1.megabytes(), VK_MEMORY_ALLOCATE_DEVICE_ADDRESS_BIT);
            context.memory.allocateDeviceMemory(MEM_TRANSFORMS, 1.megabytes(), VK_MEMORY_ALLOCATE_DEVICE_ADDRESS_BIT);

            context.memory.bind(MEM_VERTICES, vertexBuffer, 0);
            context.memory.bind(MEM_INDICES, indexBuffer, 0);
            context.memory.bind(MEM_TRANSFORMS, transformBuffer, 0);

            // Upload the vertex, index and transform data
            context.transfer.transferAndWaitFor(vertices, vertexBuffer);
            context.transfer.transferAndWaitFor(indices, indexBuffer);
            context.transfer.transferAndWaitFor([transform], transformBuffer);

        } else static if(OPT==2) {
            // Bind to GPU memory
            context.memory.bind(MEM_GPU, vertexBuffer, 0);
            context.memory.bind(MEM_GPU, indexBuffer, 0);
            context.memory.bind(MEM_GPU, transformBuffer, 0);

            // Upload the vertex, index and transform data
            context.transfer.transferAndWaitFor(vertices, vertexBuffer);
            context.transfer.transferAndWaitFor(indices, indexBuffer);
            context.transfer.transferAndWaitFor([transform], transformBuffer);
        } else {
            // Bind to host memory
            auto vertexBufferOffset = context.memory.bind(MEM_UPLOAD, vertexBuffer);
            auto indexBufferOffset = context.memory.bind(MEM_UPLOAD, indexBuffer);
            auto transformBufferOffset = context.memory.bind(MEM_UPLOAD, transformBuffer);

            void* map = context.memory.map(MEM_UPLOAD, 0, VK_WHOLE_SIZE);

            memcpy(map + vertexBufferOffset, vertices.ptr, Vertex.sizeof*vertices.length);
            memcpy(map + indexBufferOffset, indices.ptr, uint.sizeof*indices.length);
            memcpy(map + transformBufferOffset, &transform, VkTransformMatrixKHR.sizeof);

            flushMappedMemory(context.device, context.memory.getMemory(MEM_UPLOAD).handle, 0, VK_WHOLE_SIZE);
            context.memory.unmap(MEM_UPLOAD);
        }

        // Get the device addresses
        auto vertexBufferDeviceAddress = getDeviceAddress(context.device, vertexBuffer);
        auto indexBufferDeviceAddress = getDeviceAddress(context.device, indexBuffer);
        auto transformBufferDeviceAddress = getDeviceAddress(context.device, transformBuffer);

        log("vertexBufferDeviceAddress = %s", vertexBufferDeviceAddress);
        log("indexBufferDeviceAddress = %s", indexBufferDeviceAddress);
        log("transformBufferDeviceAddress = %s", transformBufferDeviceAddress);

        // Build the geometry
        VkAccelerationStructureGeometryKHR accelerationStructureGeometry = {
           sType: VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_GEOMETRY_KHR,
           flags: VK_GEOMETRY_OPAQUE_BIT_KHR,
           geometryType: VK_GEOMETRY_TYPE_TRIANGLES_KHR
        };
        accelerationStructureGeometry.geometry.triangles.sType = VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_GEOMETRY_TRIANGLES_DATA_KHR;
        accelerationStructureGeometry.geometry.triangles.vertexFormat = VK_FORMAT_R32G32B32_SFLOAT;
        accelerationStructureGeometry.geometry.triangles.vertexData.deviceAddress = vertexBufferDeviceAddress;
        accelerationStructureGeometry.geometry.triangles.maxVertex = 3;
        accelerationStructureGeometry.geometry.triangles.vertexStride = Vertex.sizeof;
        accelerationStructureGeometry.geometry.triangles.indexType = VK_INDEX_TYPE_UINT32;
        accelerationStructureGeometry.geometry.triangles.indexData.deviceAddress = indexBufferDeviceAddress;
        accelerationStructureGeometry.geometry.triangles.transformData.deviceAddress = transformBufferDeviceAddress;

        // Get size info
		VkAccelerationStructureBuildGeometryInfoKHR accelerationStructureBuildGeometryInfo = {
            sType: VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_BUILD_GEOMETRY_INFO_KHR,
            type: VK_ACCELERATION_STRUCTURE_TYPE_BOTTOM_LEVEL_KHR,
            flags: VK_BUILD_ACCELERATION_STRUCTURE_PREFER_FAST_TRACE_BIT_KHR,
            geometryCount: 1,
            pGeometries: &accelerationStructureGeometry
        };

        uint numTriangles = 1;
		VkAccelerationStructureBuildSizesInfoKHR accelerationStructureBuildSizesInfo ={
            sType: VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_BUILD_SIZES_INFO_KHR
        };
		vkGetAccelerationStructureBuildSizesKHR(
			context.device,
			VK_ACCELERATION_STRUCTURE_BUILD_TYPE_DEVICE_KHR,
			&accelerationStructureBuildGeometryInfo,
			&numTriangles,
			&accelerationStructureBuildSizesInfo);

        // blas size: 464
        // blas scratch size: 220
        log("blas size: %s", accelerationStructureBuildSizesInfo.accelerationStructureSize);
		log("blas scratch size: %s", accelerationStructureBuildSizesInfo.buildScratchSize);

        blas.buffer = context.buffers.createBuffer(BUF_BLAS,
            accelerationStructureBuildSizesInfo.accelerationStructureSize,
            VK_BUFFER_USAGE_ACCELERATION_STRUCTURE_STORAGE_BIT_KHR | VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT);

        context.memory.bind(MEM_GPU, blas.buffer, 0);

        // Create the acceleration structure
        VkAccelerationStructureCreateInfoKHR accelerationStructureCreateInfo = {
            sType: VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_CREATE_INFO_KHR,
		    buffer: blas.buffer,
		    size: accelerationStructureBuildSizesInfo.accelerationStructureSize,
		    type: VK_ACCELERATION_STRUCTURE_TYPE_BOTTOM_LEVEL_KHR
        };

		check(vkCreateAccelerationStructureKHR(context.device, &accelerationStructureCreateInfo, null, &blas.handle));

        blas.scratchBuffer = context.buffers.createBuffer(BUF_BLAS_SCRATCH, accelerationStructureBuildSizesInfo.buildScratchSize,
            VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT);

        context.memory.bind(MEM_GPU, blas.scratchBuffer, context.physicalDevice.accelerationStructureProperties.minAccelerationStructureScratchOffsetAlignment);

        blas.scratchBufferDeviceAddress = getDeviceAddress(context.device, blas.scratchBuffer);

        // Build
        VkAccelerationStructureBuildGeometryInfoKHR accelerationBuildGeometryInfo = {
            sType: VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_BUILD_GEOMETRY_INFO_KHR,
            type: VK_ACCELERATION_STRUCTURE_TYPE_BOTTOM_LEVEL_KHR,
            flags: VK_BUILD_ACCELERATION_STRUCTURE_PREFER_FAST_TRACE_BIT_KHR,
            mode: VK_BUILD_ACCELERATION_STRUCTURE_MODE_BUILD_KHR,
            dstAccelerationStructure: blas.handle,
            geometryCount: 1,
            pGeometries: &accelerationStructureGeometry
        };
        accelerationBuildGeometryInfo.scratchData.deviceAddress = blas.scratchBufferDeviceAddress;

        VkAccelerationStructureBuildRangeInfoKHR accelerationStructureBuildRangeInfo = {
            primitiveCount: numTriangles,
            primitiveOffset: 0,
            firstVertex: 0,
            transformOffset: 0
        };
		VkAccelerationStructureBuildRangeInfoKHR*[] accelerationBuildStructureRangeInfos = [
             &accelerationStructureBuildRangeInfo
        ];

        // We need a command buffer to build our acceleration structure




        auto cmd = allocCommandBuffer(context.device, buildCommandPool);
        cmd.beginOneTimeSubmit();

        vkCmdBuildAccelerationStructuresKHR(
            cmd,
            1,
            &accelerationBuildGeometryInfo,             // VkAccelerationStructureBuildGeometryInfoKHR*
            accelerationBuildStructureRangeInfos.ptr    // VkAccelerationStructureBuildRangeInfoKHR**
        );

        cmd.end();

        auto queue = context.queues.getQueue(graphicsQueueFamily, 0);
        queue.submitAndWaitFor(cmd, context);

        freeCommandBuffer(context.device, buildCommandPool, cmd);

        blas.deviceAddress = getDeviceAddress(context.device, blas.handle);
        log("BLAS deviceAddress = %s", blas.deviceAddress);


        // ubyte[] data = [
        //     0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 8, 2, 0, 0, 0, 0, 0, 0, 208, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 128, 0, 248, 2, 3, 0, 0, 0, 128, 0, 0, 0, 3, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 21, 0, 0, 0, 0, 0, 0, 0, 255, 255, 255, 255, 9, 0, 4, 0, 128, 0, 0, 0, 208, 1, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 128, 0, 0, 0, 0, 1, 0, 0, 64, 1, 0, 0, 76, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 6, 0, 15, 0, 106, 37, 47, 109, 9, 0, 0, 0, 0, 0, 0, 0, 0, 0, 128, 191, 0, 0, 128, 191, 0, 0, 0, 0, 0, 0, 128, 63, 0, 0, 128, 63, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 208, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 32, 0, 0, 0, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 0, 0, 128, 191, 0, 0, 128, 191, 0, 0, 0, 0, 0, 0, 128, 63, 0, 0, 128, 63, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 5, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 128, 63, 0, 0, 128, 63, 0, 0, 0, 0, 0, 0, 128, 191, 0, 0, 128, 63, 0, 0, 0, 0
        // ];
        // writeAccelerationStructure("blas", blas.handle, data);

        {
            dumpAccelerationStructure("BLAS", accelerationStructureBuildSizesInfo.accelerationStructureSize, blas.handle);

            // ours
            // [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 8, 2, 0, 0, 0, 0, 0, 0, 208, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 128, 0, 94, 3, 3, 0, 0, 0, 128, 0, 0, 0, 3, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 21, 0, 0, 0, 0, 0, 0, 0, 255, 255, 255, 255, 9, 0, 4, 0, 128, 0, 0, 0, 208, 1, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 128, 0, 0, 0, 0, 1, 0, 0, 64, 1, 0, 0, 76, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 6, 0, 15, 0, 106, 37, 47, 109, 9, 0, 0, 0, 0, 0, 0, 0, 0, 0, 128, 191, 0, 0, 128, 191, 0, 0, 0, 0, 0, 0, 128, 63, 0, 0, 128, 63, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 208, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 32, 0, 0, 0, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 0, 0, 128, 191, 0, 0, 128, 191, 0, 0, 0, 0, 0, 0, 128, 63, 0, 0, 128, 63, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 5, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 128, 63, 0, 0, 128, 63, 0, 0, 0, 0, 0, 0, 128, 191, 0, 0, 128, 63, 0, 0, 0, 0]
            // [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 8, 2, 0, 0, 0, 0, 0, 0, 208, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 128, 0, 94, 3, 3, 0, 0, 0, 128, 0, 0, 0, 3, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 21, 0, 0, 0, 0, 0, 0, 0, 255, 255, 255, 255, 9, 0, 4, 0, 128, 0, 0, 0, 208, 1, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 128, 0, 0, 0, 0, 1, 0, 0, 64, 1, 0, 0, 76, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 6, 0, 15, 0, 106, 37, 47, 109, 9, 0, 0, 0, 0, 0, 0, 0, 0, 0, 128, 191, 0, 0, 128, 191, 0, 0, 0, 0, 0, 0, 128, 63, 0, 0, 128, 63, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 208, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 32, 0, 0, 0, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 0, 0, 128, 191, 0, 0, 128, 191, 0, 0, 0, 0, 0, 0, 128, 63, 0, 0, 128, 63, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 5, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 128, 63, 0, 0, 128, 63, 0, 0, 0, 0, 0, 0, 128, 191, 0, 0, 128, 63, 0, 0, 0, 0]

            // [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 8, 2, 0, 0, 0, 0, 0, 0, 208, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 128, 0, 248, 2, 3, 0, 0, 0, 128, 0, 0, 0, 3, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 21, 0, 0, 0, 0, 0, 0, 0, 255, 255, 255, 255, 9, 0, 4, 0, 128, 0, 0, 0, 208, 1, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 128, 0, 0, 0, 0, 1, 0, 0, 64, 1, 0, 0, 76, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 6, 0, 15, 0, 106, 37, 47, 109, 9, 0, 0, 0, 0, 0, 0, 0, 0, 0, 128, 191, 0, 0, 128, 191, 0, 0, 0, 0, 0, 0, 128, 63, 0, 0, 128, 63, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 208, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 32, 0, 0, 0, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 0, 0, 128, 191, 0, 0, 128, 191, 0, 0, 0, 0, 0, 0, 128, 63, 0, 0, 128, 63, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 5, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 128, 63, 0, 0, 128, 63, 0, 0, 0, 0, 0, 0, 128, 191, 0, 0, 128, 63, 0, 0, 0, 0]
            // [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 8, 2, 0, 0, 0, 0, 0, 0, 208, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 128, 0, 48, 1, 3, 0, 0, 0, 128, 0, 0, 0, 3, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 21, 0, 0, 0, 0, 0, 0, 0, 255, 255, 255, 255, 9, 0, 4, 0, 128, 0, 0, 0, 208, 1, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 128, 0, 0, 0, 0, 1, 0, 0, 64, 1, 0, 0, 76, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 6, 0, 15, 0, 106, 37, 47, 109, 9, 0, 0, 0, 0, 0, 0, 0, 0, 0, 128, 191, 0, 0, 128, 191, 0, 0, 0, 0, 0, 0, 128, 63, 0, 0, 128, 63, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 208, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 32, 0, 0, 0, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 0, 0, 128, 191, 0, 0, 128, 191, 0, 0, 0, 0, 0, 0, 128, 63, 0, 0, 128, 63, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 5, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 128, 63, 0, 0, 128, 63, 0, 0, 0, 0, 0, 0, 128, 191, 0, 0, 128, 63, 0, 0, 0, 0]
            // theirs
        }
    }
    void createTopLevelAccelerationStructure() {

        // Create and upload instance data
        {
            VkTransformMatrixKHR transformMatrix = identityTransformMatrix();

            // This struct uses bitfields which is not natively supported in D.
            VkAccelerationStructureInstanceKHR instance = {
                transform: transformMatrix,
                accelerationStructureReference: blas.deviceAddress
            };
            // Set the bitfield members
            instance.setInstanceCustomIndex(0);
            instance.setMask(0xFF);
            instance.setInstanceShaderBindingTableRecordOffset(0);
            instance.setFlags(VK_GEOMETRY_INSTANCE_TRIANGLE_FACING_CULL_DISABLE_BIT_KHR);

            // Buffer for instance data
            instanceBuffer = context.buffers.createBuffer(BUF_INSTANCES,
                    VkAccelerationStructureInstanceKHR.sizeof,
                    VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT |
                    VK_BUFFER_USAGE_ACCELERATION_STRUCTURE_BUILD_INPUT_READ_ONLY_BIT_KHR |
                    VK_BUFFER_USAGE_TRANSFER_DST_BIT);

            static if(true) {
                // Use GPU
                context.memory.bind(MEM_GPU, instanceBuffer, 16);

                // Copy the instance data to the GPU
                context.transfer.transferAndWaitFor([instance], instanceBuffer);
            } else {
                // Use HOST
                ulong offset = context.memory.bind(MEM_UPLOAD, instanceBuffer, (ulong offset) {
                    // The instances must be 16 byte aligned
                    return alignedTo(offset, 16);
                });

                void* map = context.memory.map(MEM_UPLOAD, 0, VK_WHOLE_SIZE);

                memcpy(map + offset, &instance, VkAccelerationStructureInstanceKHR.sizeof);

                flushMappedMemory(context.device, context.memory.getMemory(MEM_UPLOAD).handle, 0, VK_WHOLE_SIZE);

                context.memory.unmap(MEM_UPLOAD);
            }
        }

        auto instanceDataDeviceAddress = getDeviceAddress(context.device, instanceBuffer);

        VkAccelerationStructureGeometryKHR accelerationStructureGeometry = {
            sType: VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_GEOMETRY_KHR,
            geometryType: VK_GEOMETRY_TYPE_INSTANCES_KHR,
            flags: VK_GEOMETRY_OPAQUE_BIT_KHR
        };
		accelerationStructureGeometry.geometry.instances.sType = VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_GEOMETRY_INSTANCES_DATA_KHR;
		accelerationStructureGeometry.geometry.instances.arrayOfPointers = VK_FALSE;
		accelerationStructureGeometry.geometry.instances.data.deviceAddress = instanceDataDeviceAddress;


        VkAccelerationStructureBuildGeometryInfoKHR accelerationStructureBuildGeometryInfo = {
            sType: VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_BUILD_GEOMETRY_INFO_KHR,
            type: VK_ACCELERATION_STRUCTURE_TYPE_TOP_LEVEL_KHR,
            flags: VK_BUILD_ACCELERATION_STRUCTURE_PREFER_FAST_TRACE_BIT_KHR,
            geometryCount: 1,
            pGeometries: &accelerationStructureGeometry
        };

        uint primitive_count = 1;

		VkAccelerationStructureBuildSizesInfoKHR accelerationStructureBuildSizesInfo = {
            sType: VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_BUILD_SIZES_INFO_KHR
        };

		vkGetAccelerationStructureBuildSizesKHR(
			context.device,
			VK_ACCELERATION_STRUCTURE_BUILD_TYPE_DEVICE_KHR,
			&accelerationStructureBuildGeometryInfo,
			&primitive_count,
			&accelerationStructureBuildSizesInfo);

        log("TLAS as size = %s", accelerationStructureBuildSizesInfo.accelerationStructureSize);
		log("TLAS scratch size = %s", accelerationStructureBuildSizesInfo.buildScratchSize);


        // Create the tlas acceleration structure buffer
        tlas.buffer = context.buffers.createBuffer(BUF_TLAS,
            accelerationStructureBuildSizesInfo.accelerationStructureSize,
            VK_BUFFER_USAGE_ACCELERATION_STRUCTURE_STORAGE_BIT_KHR | VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT);

        context.memory.bind(MEM_GPU, tlas.buffer, 0);

        // Create the tlas acceleration structure
        VkAccelerationStructureCreateInfoKHR accelerationStructureCreateInfo = {
            sType: VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_CREATE_INFO_KHR,
            buffer: tlas.buffer,
            size: accelerationStructureBuildSizesInfo.accelerationStructureSize,
            type: VK_ACCELERATION_STRUCTURE_TYPE_TOP_LEVEL_KHR
        };
		vkCreateAccelerationStructureKHR(context.device, &accelerationStructureCreateInfo, null, &tlas.handle);

        // Create the scratch buffer
        tlas.scratchBuffer = context.buffers.createBuffer(BUF_TLAS_SCRATCH, accelerationStructureBuildSizesInfo.buildScratchSize,
            VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT);

        context.memory.bind(MEM_GPU, tlas.scratchBuffer, context.physicalDevice.accelerationStructureProperties.minAccelerationStructureScratchOffsetAlignment);

        tlas.scratchBufferDeviceAddress = getDeviceAddress(context.device, tlas.scratchBuffer);

        VkAccelerationStructureBuildGeometryInfoKHR accelerationBuildGeometryInfo = {
            sType: VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_BUILD_GEOMETRY_INFO_KHR,
            type: VK_ACCELERATION_STRUCTURE_TYPE_TOP_LEVEL_KHR,
            flags: VK_BUILD_ACCELERATION_STRUCTURE_PREFER_FAST_TRACE_BIT_KHR,
            mode: VK_BUILD_ACCELERATION_STRUCTURE_MODE_BUILD_KHR,
            dstAccelerationStructure: tlas.handle,
            geometryCount: 1,
            pGeometries: &accelerationStructureGeometry
        };
        accelerationBuildGeometryInfo.scratchData.deviceAddress = tlas.scratchBufferDeviceAddress;

        VkAccelerationStructureBuildRangeInfoKHR accelerationStructureBuildRangeInfo = {
            primitiveCount: 1,
            primitiveOffset: 0,
            firstVertex: 0,
            transformOffset: 0
        };
		VkAccelerationStructureBuildRangeInfoKHR*[] accelerationBuildStructureRangeInfos =
            [ &accelerationStructureBuildRangeInfo ];

        // Build the acceleration structure

        auto cmd = allocCommandBuffer(context.device, buildCommandPool);
        cmd.beginOneTimeSubmit();

        vkCmdBuildAccelerationStructuresKHR(
            cmd,
            1,
            &accelerationBuildGeometryInfo,             // VkAccelerationStructureBuildGeometryInfoKHR*
            accelerationBuildStructureRangeInfos.ptr    // VkAccelerationStructureBuildRangeInfoKHR**
        );

        cmd.end();

        auto queue = context.queues.getQueue(graphicsQueueFamily, 0);
        queue.submitAndWaitFor(cmd, context);

        freeCommandBuffer(context.device, buildCommandPool, cmd);

        tlas.deviceAddress = getDeviceAddress(context.device, tlas.handle);

        log("TLAS deviceAddress          = %s (%s)", tlas.deviceAddress, tlas.deviceAddress - blas.deviceAddress);
        log("TLAS buffer device address2 = %s", getDeviceAddress(context.device, tlas.buffer));

        // We don't need the instancesBuffer after this point
        // or the tlas.scratchBuffer

        // ubyte[] data = [
        //     0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 68, 2, 0, 0, 0, 0, 0, 0, 4, 2, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 248, 2, 3, 0, 0, 0, 128, 0, 88, 7, 3, 0, 0, 0, 128, 0, 0, 0, 4, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 21, 0, 0, 0, 0, 0, 0, 0, 255, 255, 255, 255, 8, 0, 4, 0, 128, 0, 0, 0, 4, 2, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 128, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 128, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 6, 0, 15, 0, 106, 37, 47, 109, 9, 0, 0, 0, 0, 0, 0, 0, 0, 0, 128, 191, 0, 0, 128, 191, 0, 0, 0, 0, 0, 0, 128, 63, 0, 0, 128, 63, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 4, 2, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 38, 0, 0, 0, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 0, 0, 128, 191, 0, 0, 128, 191, 0, 0, 0, 0, 0, 0, 128, 63, 0, 0, 128, 63, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 4, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 128, 63, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 128, 63, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 128, 63, 0, 0, 0, 0, 0, 0, 0, 255, 0, 0, 0, 1, 16, 0, 95, 96, 0, 0, 0, 129, 0, 0, 0, 0

        // ];
        // writeAccelerationStructure("tlas", tlas.handle, data);

        {
            dumpAccelerationStructure("TLAS", accelerationStructureBuildSizesInfo.accelerationStructureSize, tlas.handle);

            // ours
            // [0, 0, 0, 0, 32, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 68, 2, 0, 0, 0, 0, 0, 0, 4, 2, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 128, 0, 0, 0, 4, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 255, 255, 255, 255, 8, 0, 4, 0, 128, 0, 0, 0, 4, 2, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 128, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 128, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 6, 0, 15, 0, 106, 37, 47, 109, 9, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 132, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]

            // [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 68, 2, 0, 0, 0, 0, 0, 0, 4, 2, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 8, 0, 248, 2, 3, 0, 0, 0, 128, 3, 94, 3, 3, 0, 0, 0, 128, 0, 0, 0, 56, 0, 0, 0, 28, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 21, 0, 0, 0, 0, 0, 0, 0, 255, 255, 255, 255, 8, 0, 4, 0, 128, 0, 0, 0, 4, 2, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 128, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 128, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 95, 96, 0, 0, 15, 0, 106, 37, 47, 109, 9, 0, 0, 0, 0, 0, 0, 0, 0, 0, 128, 191, 0, 0, 128, 191, 0, 0, 0, 0, 0, 0, 128, 63, 0, 0, 128, 63, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 4, 2, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 38, 0, 0, 0, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 0, 0, 128, 191, 0, 0, 128, 191, 0, 0, 0, 0, 0, 0, 128, 63, 0, 0, 128, 63, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 4, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 128, 63, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 128, 63, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 128, 63, 0, 0, 0, 0, 0, 0, 0, 255, 0, 0, 0, 1, 16, 0, 95, 96, 0, 0, 0, 129, 0, 0, 0, 0]
            // [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 68, 2, 0, 0, 0, 0, 0, 0, 4, 2, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 248, 2, 3, 0, 0, 0, 128, 0, 88, 7, 3, 0, 0, 0, 128, 0, 0, 0, 4, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 21, 0, 0, 0, 0, 0, 0, 0, 255, 255, 255, 255, 8, 0, 4, 0, 128, 0, 0, 0, 4, 2, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 128, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 128, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 6, 0, 15, 0, 106, 37, 47, 109, 9, 0, 0, 0, 0, 0, 0, 0, 0, 0, 128, 191, 0, 0, 128, 191, 0, 0, 0, 0, 0, 0, 128, 63, 0, 0, 128, 63, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 4, 2, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 38, 0, 0, 0, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 0, 0, 128, 191, 0, 0, 128, 191, 0, 0, 0, 0, 0, 0, 128, 63, 0, 0, 128, 63, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 4, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 128, 63, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 128, 63, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 128, 63, 0, 0, 0, 0, 0, 0, 0, 255, 0, 0, 0, 1, 16, 0, 95, 96, 0, 0, 0, 129, 0, 0, 0, 0]
            // theirs
        }
    }
    void createRayTracingPipeline() {
        log("Creating ray tracing pipeline");

        // 0 -> acceleration structure
        // 1 -> target image
        // 2 -> uniform buffer
        VkDescriptorSetLayoutBinding accelerationStructureLayoutBinding = {
            binding: 0,
            descriptorType: VK_DESCRIPTOR_TYPE_ACCELERATION_STRUCTURE_KHR,
            descriptorCount: 1,
            stageFlags: VK_SHADER_STAGE_RAYGEN_BIT_KHR
        };
        VkDescriptorSetLayoutBinding resultImageLayoutBinding = {
            binding: 1,
            descriptorType: VK_DESCRIPTOR_TYPE_STORAGE_IMAGE,
            descriptorCount: 1,
            stageFlags: VK_SHADER_STAGE_RAYGEN_BIT_KHR
        };
        VkDescriptorSetLayoutBinding uniformBufferBinding = {
            binding: 2,
            descriptorType: VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
            descriptorCount: 1,
            stageFlags: VK_SHADER_STAGE_RAYGEN_BIT_KHR
        };

        VkDescriptorSetLayout descriptorSetLayout = context.descriptors.createLayout(DS_LAYOUT,
            accelerationStructureLayoutBinding,
            resultImageLayoutBinding,
            uniformBufferBinding);

        VkPipelineLayoutCreateInfo pipelineLayoutCI = {
            sType: VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
            setLayoutCount: 1,
            pSetLayouts: &descriptorSetLayout
        };

		check(vkCreatePipelineLayout(context.device, &pipelineLayoutCI, null, &rtPipelineLayout));

        VkRayTracingShaderGroupCreateInfoKHR rgenShaderGroup = {
            sType: VK_STRUCTURE_TYPE_RAY_TRACING_SHADER_GROUP_CREATE_INFO_KHR,
            type: VK_RAY_TRACING_SHADER_GROUP_TYPE_GENERAL_KHR,
            generalShader: 0,
            closestHitShader: VK_SHADER_UNUSED_KHR,
            anyHitShader: VK_SHADER_UNUSED_KHR,
            intersectionShader: VK_SHADER_UNUSED_KHR
        };
        VkRayTracingShaderGroupCreateInfoKHR missShaderGroup = {
            sType: VK_STRUCTURE_TYPE_RAY_TRACING_SHADER_GROUP_CREATE_INFO_KHR,
            type: VK_RAY_TRACING_SHADER_GROUP_TYPE_GENERAL_KHR,
            generalShader: 1,
            closestHitShader: VK_SHADER_UNUSED_KHR,
            anyHitShader: VK_SHADER_UNUSED_KHR,
            intersectionShader: VK_SHADER_UNUSED_KHR
        };
        VkRayTracingShaderGroupCreateInfoKHR closestHitShaderGroup = {
            sType: VK_STRUCTURE_TYPE_RAY_TRACING_SHADER_GROUP_CREATE_INFO_KHR,
            type: VK_RAY_TRACING_SHADER_GROUP_TYPE_TRIANGLES_HIT_GROUP_KHR,
            generalShader: VK_SHADER_UNUSED_KHR,
            closestHitShader: 2,
            anyHitShader: VK_SHADER_UNUSED_KHR,
            intersectionShader: VK_SHADER_UNUSED_KHR
        };

        VkPipelineShaderStageCreateInfo rgenStage = {
            sType: VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            flags: 0,
            stage: VK_SHADER_STAGE_RAYGEN_BIT_KHR,
            module_: context.shaders.get("ray_tracing/generate_rays.rgen", "spirv1.4"),
            pName: "main".ptr,
            pSpecializationInfo: null
        };
        VkPipelineShaderStageCreateInfo missStage = {
            sType: VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            flags: 0,
            stage: VK_SHADER_STAGE_MISS_BIT_KHR,
            module_: context.shaders.get("ray_tracing/miss.rmiss", "spirv1.4"),
            pName: "main".ptr,
            pSpecializationInfo: null
        };
        VkPipelineShaderStageCreateInfo closestHitStage = {
            sType: VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            flags: 0,
            stage: VK_SHADER_STAGE_CLOSEST_HIT_BIT_KHR,
            module_: context.shaders.get("ray_tracing/hit_closest.rchit", "spirv1.4"),
            pName: "main".ptr,
            pSpecializationInfo: null
        };

        VkRayTracingPipelineCreateInfoKHR rayTracingPipelineCI = {
            sType: VK_STRUCTURE_TYPE_RAY_TRACING_PIPELINE_CREATE_INFO_KHR,
            stageCount: 3,
            pStages: [rgenStage, missStage, closestHitStage].ptr,
            groupCount: 3,
            pGroups: [rgenShaderGroup, missShaderGroup, closestHitShaderGroup].ptr,
            maxPipelineRayRecursionDepth: 1,
            layout: rtPipelineLayout
        };

        check(vkCreateRayTracingPipelinesKHR(context.device, VK_NULL_HANDLE, VK_NULL_HANDLE, 1, &rayTracingPipelineCI, null, &rtPipeline));
    }
    void createDescriptorSet() {
        log("Creating descriptor set");

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
    void createShaderBindingTable() {
        log("Creating shader binding table");

        uint handleSize = context.physicalDevice.rtPipelineProperties.shaderGroupHandleSize;
		uint handleSizeAligned = alignedTo(handleSize, context.physicalDevice.rtPipelineProperties.shaderGroupHandleAlignment).as!uint;
		uint groupCount = 3;
		uint sbtSize = groupCount * handleSizeAligned;

        log("handleSize = %s", handleSize);
        log("handleSizeAligned = %s", handleSizeAligned);
        log("sbtSize = %s", sbtSize);

        // Fetch the shader group handles
        ubyte[] shaderHandleStorage = new ubyte[sbtSize];
		check(vkGetRayTracingShaderGroupHandlesKHR(context.device, rtPipeline, 0, groupCount, sbtSize, shaderHandleStorage.ptr));

        log("shaderHandlerStorage = %s", shaderHandleStorage);

        sbtRaygenBuffer = context.buffers.createBuffer(BUF_SBT_RAYGEN, handleSize, VK_BUFFER_USAGE_SHADER_BINDING_TABLE_BIT_KHR | VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT);
        sbtMissBuffer = context.buffers.createBuffer(BUF_SBT_MISS, handleSize, VK_BUFFER_USAGE_SHADER_BINDING_TABLE_BIT_KHR | VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT);
        sbtHitBuffer = context.buffers.createBuffer(BUF_SBT_HIT, handleSize, VK_BUFFER_USAGE_SHADER_BINDING_TABLE_BIT_KHR | VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT);

        ulong raygenOffset = context.memory.bind(MEM_UPLOAD, sbtRaygenBuffer, context.physicalDevice.rtPipelineProperties.shaderGroupBaseAlignment);
        ulong missOffset = context.memory.bind(MEM_UPLOAD, sbtMissBuffer, context.physicalDevice.rtPipelineProperties.shaderGroupBaseAlignment);
        ulong hitOffset = context.memory.bind(MEM_UPLOAD, sbtHitBuffer, context.physicalDevice.rtPipelineProperties.shaderGroupBaseAlignment);

        log("raygenOffset = %s", raygenOffset);
        log("missOffset = %s", missOffset);
        log("hitOffset = %s", hitOffset);

        // Copy the handles
        ubyte* dest = cast(ubyte*)context.memory.map(MEM_UPLOAD, 0, VK_WHOLE_SIZE);

        memcpy(dest + raygenOffset, shaderHandleStorage.ptr, handleSize);
		memcpy(dest + missOffset, shaderHandleStorage.ptr + handleSizeAligned, handleSize);
		memcpy(dest + hitOffset, shaderHandleStorage.ptr + handleSizeAligned * 2, handleSize);

        log("raygen = %s", (dest+raygenOffset)[0..32]);
        log("miss   = %s", (dest+missOffset)[0..32]);
        log("hit    = %s", (dest+hitOffset)[0..32]);
    }
    void dumpAccelerationStructure(string prefix, ulong size, VkAccelerationStructureKHR handle) {
        VkBuffer tempBuffer = context.buffers.createBuffer("temp" ~ prefix,
            size,
            VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT |
            VK_BUFFER_USAGE_ACCELERATION_STRUCTURE_STORAGE_BIT_KHR |
            VK_BUFFER_USAGE_TRANSFER_DST_BIT);

        ulong offset = context.memory.bind(MEM_DOWNLOAD, tempBuffer, 0);

        VkCopyAccelerationStructureToMemoryInfoKHR copyToMemory = {
            sType: VK_STRUCTURE_TYPE_COPY_ACCELERATION_STRUCTURE_TO_MEMORY_INFO_KHR,
            mode: VK_COPY_ACCELERATION_STRUCTURE_MODE_SERIALIZE_KHR,
            src: handle
        };
        copyToMemory.dst.deviceAddress = getDeviceAddress(context.device, tempBuffer);

        auto cmd2 = allocCommandBuffer(context.device, buildCommandPool);
        cmd2.beginOneTimeSubmit();
        vkCmdCopyAccelerationStructureToMemoryKHR(cmd2, &copyToMemory);
        cmd2.end();

        auto queue2 = context.queues.getQueue(graphicsQueueFamily, 0);
        queue2.submitAndWaitFor(cmd2, context);

        freeCommandBuffer(context.device, buildCommandPool, cmd2);

        ubyte* map = cast(ubyte*)context.memory.map(MEM_DOWNLOAD, 0, VK_WHOLE_SIZE);
        invalidateMemory(context.device, context.memory.getMemory(MEM_DOWNLOAD).handle, 0, VK_WHOLE_SIZE);

        log("%s:", prefix);
        log("%s", (map+offset)[0..size]);

        context.memory.unmap(MEM_DOWNLOAD);
    }
    void writeAccelerationStructure(string prefix, VkAccelerationStructureKHR handle, ubyte[] data) {

        string bufferKey = "tempSrcAS" ~ prefix;

        VkBuffer tempBuffer = context.buffers.createBuffer(bufferKey,
            data.length,
            VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT |
            VK_BUFFER_USAGE_ACCELERATION_STRUCTURE_STORAGE_BIT_KHR |
            VK_BUFFER_USAGE_TRANSFER_SRC_BIT);

        ulong offset = context.memory.bind(MEM_UPLOAD, tempBuffer, 0);

        ubyte* map = cast(ubyte*)context.memory.map(MEM_UPLOAD, 0, VK_WHOLE_SIZE);
        memcpy(map + offset, data.ptr, data.length);

        VkCopyMemoryToAccelerationStructureInfoKHR copy = {
            sType: VK_STRUCTURE_TYPE_COPY_MEMORY_TO_ACCELERATION_STRUCTURE_INFO_KHR,
            mode: VK_COPY_ACCELERATION_STRUCTURE_MODE_DESERIALIZE_KHR,
            dst: handle
        };
        copy.src.deviceAddress = getDeviceAddress(context.device, tempBuffer);

        auto cmd = allocCommandBuffer(context.device, buildCommandPool);
        cmd.beginOneTimeSubmit();
        vkCmdCopyMemoryToAccelerationStructureKHR(cmd, &copy);
        cmd.end();

        auto queue = context.queues.getQueue(graphicsQueueFamily, 0);
        queue.submitAndWaitFor(cmd, context);

        freeCommandBuffer(context.device, buildCommandPool, cmd);

        context.memory.unmap(MEM_UPLOAD);
    }
    void renderScene(KisvFrame frame, uint imageIndex) {

        VkImage swapchainImage = context.window.images[imageIndex];

        uint handleSize = context.physicalDevice.rtPipelineProperties.shaderGroupHandleSize;
		uint handleSizeAligned = alignedTo(handleSize, context.physicalDevice.rtPipelineProperties.shaderGroupHandleAlignment).as!uint;

        VkStridedDeviceAddressRegionKHR raygenShaderSbtEntry = {
            deviceAddress: getDeviceAddress(context.device, sbtRaygenBuffer),
            stride: handleSizeAligned,
            size: handleSizeAligned
        };
        VkStridedDeviceAddressRegionKHR missShaderSbtEntry = {
            deviceAddress: getDeviceAddress(context.device, sbtMissBuffer),
            stride: handleSizeAligned,
            size: handleSizeAligned
        };
        VkStridedDeviceAddressRegionKHR hitShaderSbtEntry = {
            deviceAddress: getDeviceAddress(context.device, sbtHitBuffer),
            stride: handleSizeAligned,
            size: handleSizeAligned
        };
        VkStridedDeviceAddressRegionKHR callableShaderSbtEntry = {};

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

        vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_RAY_TRACING_KHR, rtPipeline);
        vkCmdBindDescriptorSets(
            cmd,
            VK_PIPELINE_BIND_POINT_RAY_TRACING_KHR,
            rtPipelineLayout,
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
            &raygenShaderSbtEntry,
            &missShaderSbtEntry,
            &hitShaderSbtEntry,
            &callableShaderSbtEntry,
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
               .getQueue(graphicsQueueFamily, 0)
               .submit(
            [cmd],                                           // VkCommandBuffers
            [frame.imageAvailable],                          // wait semaphores
            [VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT], // wait stages
            [frame.renderFinished],                          // signal semaphores
            frame.fence
        );
    }
}
