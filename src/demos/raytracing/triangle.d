module demos.raytracing.triangle;

import std.format       : format;
import std.string       : toStringz;
import core.stdc.string : memcpy;

import kisv;

import demos.raytracing.demo_ray_tracing;
import demos.raytracing.RayTracingSubDemo;

/**
 * Render a single triangle using a single triangle geometry primitive and the built-in intersection shader.
 */
final class Triangle : RayTracingSubDemo {
public:
    this(KisvContext context, VkCommandPool commandPool, uint queueFamilyIndex) {
        super(context, commandPool, queueFamilyIndex);
    }
    override void destroy() {
        if(pipeline) pipeline.destroy();
        if(tlas) tlas.destroy();
        if(blas) blas.destroy();
    }
    override VkShaderStageFlagBits[] getDSShaderStageFlags() {
        // 0 -> acceleration structure
        // 1 -> target image
        // 2 -> uniform buffer
        // 3 -> storage buffer
        return [ 
            VK_SHADER_STAGE_RAYGEN_BIT_KHR, 
            VK_SHADER_STAGE_RAYGEN_BIT_KHR, 
            VK_SHADER_STAGE_RAYGEN_BIT_KHR,
            VK_SHADER_STAGE_RAYGEN_BIT_KHR 
        ];
    }
    override KisvRayTracingPipeline getPipeline(string sbtMemoryKey, VkDescriptorSetLayout dsLayout) {
        doCreatePipeline(sbtMemoryKey, dsLayout);
        return pipeline;
    }
    override KisvAccelerationStructure getAccelerationStructures(string deviceMemoryKey) {
        createTriangleBLAS(deviceMemoryKey);
        createTLAS(deviceMemoryKey);
        return tlas;
    }
    override VkBuffer getUniformBuffer(string deviceMemoryKey) {

        struct UBO { static assert(UBO.sizeof==2*16*4);
            float16 viewInverse;
            float16 projInverse;
        }

        // Uniform buffers must be a multiple of 16 bytes
        static assert(UBO.sizeof%16 == 0);

        VkBuffer uniformBuffer = context.buffers.createBuffer(BUF_UNIFORM, UBO.sizeof,
                                                     VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT |
                                                     VK_BUFFER_USAGE_TRANSFER_DST_BIT);

        context.memory.bind(deviceMemoryKey, uniformBuffer, 0);

        UBO ubo;

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

        context.transfer.transferAndWaitFor([ubo], uniformBuffer);

        return uniformBuffer;
    }
    override VkBuffer getStorageBuffer(string deviceMemoryKey) { 
        VkBuffer buffer = context.buffers.createBuffer(BUF_STORAGE, 16,
                                                     VK_BUFFER_USAGE_STORAGE_BUFFER_BIT |
                                                     VK_BUFFER_USAGE_TRANSFER_DST_BIT);

        // Bind the buffer to GPU memory
        context.memory.bind(deviceMemoryKey, buffer, 0);
        return buffer; 
    }
private:
    // Keys
    enum : string {
        BUF_UNIFORM   = "buf_uniform",
        BUF_STORAGE   = "buf_storage",
        // blas
        BUF_VERTEX    = "buf_vertex",
        BUF_INDEX     = "buf_index",
        BUF_TRANSFORM = "buf_transform",
        // tlas
        BUF_INSTANCE  = "buf_instance"
    }

    // Objects we must destroy
    KisvRayTracingPipeline pipeline;
    KisvAccelerationStructure tlas;
    KisvAccelerationStructure blas;

    // These objects are managed by BufferHelper and DescriptorHelper
    VkBuffer vertexBuffer;      
    VkBuffer indexBuffer;       
    VkBuffer transformBuffer;   
    VkBuffer instanceBuffer; 
  
    void doCreatePipeline(string sbtMemoryKey, VkDescriptorSetLayout dsLayout) {
        this.pipeline = new KisvRayTracingPipeline(context, sbtMemoryKey);

        pipeline.addDescriptorSetLayout(dsLayout);

        pipeline.addShader(VK_SHADER_STAGE_RAYGEN_BIT_KHR, context.shaders.get("ray_tracing/triangle/generate_rays.rgen", "spirv1.4"));
        pipeline.addShader(VK_SHADER_STAGE_MISS_BIT_KHR, context.shaders.get("ray_tracing/triangle/miss.rmiss", "spirv1.4"));
        pipeline.addShader(VK_SHADER_STAGE_CLOSEST_HIT_BIT_KHR, context.shaders.get("ray_tracing/triangle/hit_closest.rchit", "spirv1.4"));

        pipeline.addRaygenGroup(0);
        pipeline.addMissGroup(1);
        pipeline.addTriangleHitGroup(2, VK_SHADER_UNUSED_KHR);

        pipeline.build();
    }
    void createTriangleBLAS(string deviceMemoryKey) {

        static struct Vertex { static assert(Vertex.sizeof==12);
		    float x,y,z;
	    }
	    Vertex[] vertices = [
            Vertex(1.0f, 1.0f, 0.0f),
            Vertex(-1.0f, 1.0f, 0.0f),
            Vertex(0.0f, -1.0f, 0.0f)
        ];

        ushort[] indices = [ 0, 1, 2 ];

        VkTransformMatrixKHR transform = identityTransformMatrix();

        // Create buffers for vertices, indices and transforms
        auto bufferFlags = 
            VK_BUFFER_USAGE_ACCELERATION_STRUCTURE_BUILD_INPUT_READ_ONLY_BIT_KHR |
            VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT |
            VK_BUFFER_USAGE_TRANSFER_DST_BIT;

        vertexBuffer = context.buffers.createBuffer(BUF_VERTEX, Vertex.sizeof*vertices.length, bufferFlags);
        indexBuffer = context.buffers.createBuffer(BUF_INDEX, ushort.sizeof*indices.length, bufferFlags);
        transformBuffer = context.buffers.createBuffer(BUF_TRANSFORM, VkTransformMatrixKHR.sizeof, bufferFlags);

        // Bind to GPU memory
        context.memory.bind(deviceMemoryKey, vertexBuffer, 0);
        context.memory.bind(deviceMemoryKey, indexBuffer, 0);
        context.memory.bind(deviceMemoryKey, transformBuffer, 16);

        // Upload the vertex, index and transform data
        context.transfer.transferAndWaitFor(vertices, vertexBuffer);
        context.transfer.transferAndWaitFor(indices, indexBuffer);
        context.transfer.transferAndWaitFor([transform], transformBuffer);

        // Get the device addresses
        auto vertexBufferDeviceAddress = getDeviceAddress(context.device, vertexBuffer);
        auto indexBufferDeviceAddress = getDeviceAddress(context.device, indexBuffer);
        auto transformBufferDeviceAddress = getDeviceAddress(context.device, transformBuffer);

        // Create the bottom level acceleration structure
        blas = new KisvAccelerationStructure(context, "BLAS", false, deviceMemoryKey);

        uint numTriangles = 1;
        VkAccelerationStructureGeometryTrianglesDataKHR triangles = {
            sType: VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_GEOMETRY_TRIANGLES_DATA_KHR,
            vertexFormat: VK_FORMAT_R32G32B32_SFLOAT,
            vertexData: { deviceAddress: vertexBufferDeviceAddress },
            maxVertex: 3,
            vertexStride: Vertex.sizeof,
            indexType: VK_INDEX_TYPE_UINT16,
            indexData: { deviceAddress: indexBufferDeviceAddress },
            transformData: { deviceAddress: transformBufferDeviceAddress }
        };  

        blas.addTriangles(VK_GEOMETRY_OPAQUE_BIT_KHR, triangles, numTriangles);
        
        buildAccelerationStructure(blas);
    }
    void createTLAS(string deviceMemoryKey) {
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
            instanceBuffer = context.buffers.createBuffer(BUF_INSTANCE,
                    VkAccelerationStructureInstanceKHR.sizeof,
                    VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT |
                    VK_BUFFER_USAGE_ACCELERATION_STRUCTURE_BUILD_INPUT_READ_ONLY_BIT_KHR |
                    VK_BUFFER_USAGE_TRANSFER_DST_BIT);

            // Bind to memory
            context.memory.bind(deviceMemoryKey, instanceBuffer, 16);

            // Copy the instance data to the GPU
            context.transfer.transferAndWaitFor([instance], instanceBuffer);
        }

        auto instanceDataDeviceAddress = getDeviceAddress(context.device, instanceBuffer);

        // Create the top level acceleration structure
        tlas = new KisvAccelerationStructure(context, "tlas", true, deviceMemoryKey);

        VkAccelerationStructureGeometryInstancesDataKHR instances = {
            sType: VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_GEOMETRY_INSTANCES_DATA_KHR,
            arrayOfPointers: VK_FALSE,
            data: { deviceAddress: instanceDataDeviceAddress }
        };

        tlas.addInstances(VK_GEOMETRY_OPAQUE_BIT_KHR, instances, 1);

        buildAccelerationStructure(tlas);
    }
}
