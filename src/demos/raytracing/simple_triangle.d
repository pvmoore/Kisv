module demos.raytracing.simple_triangle;

import std.format       : format;
import std.string       : toStringz;
import core.stdc.string : memcpy;

import kisv;

import demos.raytracing.demo_ray_tracing;

final class SimpleTriangle : RayTracingSubDemo {
public:
    override KisvRayTracingPipeline getRayTracingPipeline() { return pipeline; }
    override KisvAccelerationStructure getTopLevelAccelerationStructure() { return tlas; }

    this(KisvContext context) {
        this.context = context;
    }
    override void destroy() {
        if(pipeline) pipeline.destroy();
        if(tlas) tlas.destroy();
        if(blas) blas.destroy();
    }
    override RayTracingSubDemo createDSLayout(string dsLayoutKey) {
        createDescriptorSetLayout(dsLayoutKey);
        return this;
    }
    override RayTracingSubDemo createPipeline(string sbtMemoryKey) {
        doCreatePipeline(sbtMemoryKey);
        return this;
    }
    override RayTracingSubDemo createAccelerationStructures(string deviceMemoryKey, VkCommandPool commandPool, uint queueFamilyIndex) {
        createTriangleBLAS(deviceMemoryKey, commandPool, queueFamilyIndex);
        createTLAS(deviceMemoryKey, commandPool, queueFamilyIndex);
        return this;
    }
private:
    // Keys
    enum : string {
        BUF_VERTEX    = "buf_vertex",
        BUF_INDEX     = "buf_index",
        BUF_TRANSFORM = "buf_trans",
        BUF_INSTANCE  = "buf_instance"
    }
    KisvContext context;

    // Objects we must destroy
    KisvRayTracingPipeline pipeline;
    KisvAccelerationStructure tlas;
    KisvAccelerationStructure blas;

    // These objects are managed by BufferHelper and DescriptorHelper
    VkBuffer vertexBuffer;      
    VkBuffer indexBuffer;       
    VkBuffer transformBuffer;   
    VkBuffer instanceBuffer; 
    VkDescriptorSetLayout dsLayout;

    void createDescriptorSetLayout(string dsLayoutKey) {
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

        this.dsLayout = context.descriptors.createLayout(dsLayoutKey,
            accelerationStructureLayoutBinding,
            resultImageLayoutBinding,
            uniformBufferBinding);    
    }   
    void doCreatePipeline(string sbtMemoryKey) {
        this.pipeline = new KisvRayTracingPipeline(context, sbtMemoryKey);

        pipeline.addDescriptorSetLayout(dsLayout);

        pipeline.addShader(VK_SHADER_STAGE_RAYGEN_BIT_KHR, context.shaders.get("ray_tracing/simple_triangle/generate_rays.rgen", "spirv1.4"));
        pipeline.addShader(VK_SHADER_STAGE_MISS_BIT_KHR, context.shaders.get("ray_tracing/simple_triangle/miss.rmiss", "spirv1.4"));
        pipeline.addShader(VK_SHADER_STAGE_CLOSEST_HIT_BIT_KHR, context.shaders.get("ray_tracing/simple_triangle/hit_closest.rchit", "spirv1.4"));

        pipeline.addRaygenGroup(0);
        pipeline.addMissGroup(1);
        pipeline.addTriangleHitGroup(2, VK_SHADER_UNUSED_KHR);

        pipeline.build();
    }
    void createTriangleBLAS(string deviceMemoryKey, VkCommandPool commandPool, uint queueFamilyIndex) {

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

        VkCommandBuffer cmd = allocCommandBuffer(context.device, commandPool);

        cmd.beginOneTimeSubmit();
        blas.buildAll(cmd, VK_BUILD_ACCELERATION_STRUCTURE_PREFER_FAST_TRACE_BIT_KHR);
        cmd.end();

        context.queues.getQueue(queueFamilyIndex, 0).submitAndWaitFor(cmd, context);

        freeCommandBuffer(context.device, commandPool, cmd);
    }
    void createTLAS(string deviceMemoryKey, VkCommandPool commandPool, uint queueFamilyIndex) {
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

        VkCommandBuffer cmd = allocCommandBuffer(context.device, commandPool);

        cmd.beginOneTimeSubmit();
        tlas.buildAll(cmd, VK_BUILD_ACCELERATION_STRUCTURE_PREFER_FAST_TRACE_BIT_KHR);
        cmd.end();

        context.queues.getQueue(queueFamilyIndex, 0).submitAndWaitFor(cmd, context);

        freeCommandBuffer(context.device, commandPool, cmd);
    }
}
