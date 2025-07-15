module demos.raytracing.spheres;

import std.format       : format;
import std.string       : toStringz;
import core.stdc.string : memcpy;
import std.algorithm    : map;
import std.range        : array;
import std.random       : uniform01, Mt19937, unpredictableSeed;

import kisv;

import demos.raytracing.demo_ray_tracing;
import demos.raytracing.RayTracingSubDemo;

/**
 * Render spheres using AABB geometry primitives and an intersection shader.
 *
 * Option 1 : Create multiple sphere AABBs in a single BLAS with a single TLAS instance.
 * Option 2 : Create a single sphere AABB in a single BLAS and multiple TLAS instances pointing to the same BLAS.
 *
 * Option 1 seems to be a bit faster. Maybe the BVH is more efficient. 
 * Not sure how this affects updating the geometry though . Will try that next. 
 * It might be faster to move the spheres by updating the TLAS
 * instance transforms and then updating the TLAS than updating the BLAS. 
 * Need to check whether this would also require the TLAS to be updated. I assume so but /shrug
 *
 */
final class Spheres : RayTracingSubDemo {
public:
    enum OPTION        = 1;
    enum NUM_SPHERES   = 1000;

    this(KisvContext context, VkCommandPool commandPool, uint queueFamilyIndex) {
        super(context, commandPool, queueFamilyIndex);
        createSpheres();
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
            VK_SHADER_STAGE_RAYGEN_BIT_KHR | VK_SHADER_STAGE_CLOSEST_HIT_BIT_KHR | VK_SHADER_STAGE_INTERSECTION_BIT_KHR,
            VK_SHADER_STAGE_INTERSECTION_BIT_KHR | VK_SHADER_STAGE_CLOSEST_HIT_BIT_KHR
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

        struct UBO { 
            float16 viewInverse;
            float16 projInverse;
            float4 lightPos;
        }

        // Uniform buffers must be a multiple of 16 bytes
        static assert(UBO.sizeof%16 == 0);

        VkBuffer uniformBuffer = context.buffers.createBuffer(BUF_UNIFORM, UBO.sizeof,
                                                     VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT |
                                                     VK_BUFFER_USAGE_TRANSFER_DST_BIT);

        context.memory.bind(deviceMemoryKey, uniformBuffer, 16);

        UBO ubo;

        ubo.viewInverse = float16.rowMajor(
            1, 0, 0, 0,
            0, 1, 0, 0,
            0, 0, 1, 60, // 2.5
            0, 0, 0, 1
        );
        ubo.projInverse = float16.rowMajor(
            1.010363, 0,        0,         0,
            0,        0.577350, 0,         0,
            0,        0,        0,        -1,
            0,        0,       -9.998046,  10
        );

        import std.math : sin, cos;

        float radians(float degrees) {
            return degrees * 0.01745329251994329576923690768489;
        }

        float timer = .95;

        ubo.lightPos = float4(
            cos(radians(timer * 360.0f)) * 60.0f, 
            //0.0f, 
            25.0f + sin(radians(timer * 360.0f)) * 60.0f, 
            25f,
            0.0f);
        
        context.transfer.transferAndWaitFor([ubo], uniformBuffer);
        log("viewInverse:\n%s", ubo.viewInverse);
        log("projInverse:\n%s", ubo.projInverse);

        return uniformBuffer;
    }
    override VkBuffer getStorageBuffer(string deviceMemoryKey) { 

        VkBuffer buffer = context.buffers.createBuffer(BUF_SPHERES, Sphere.sizeof * spheres.length, 
            VK_BUFFER_USAGE_TRANSFER_DST_BIT | VK_BUFFER_USAGE_STORAGE_BUFFER_BIT);

        context.memory.bind(deviceMemoryKey, buffer, 0);

        context.transfer.transferAndWaitFor(spheres, buffer);

        return buffer; 
    }
private:
    // Keys
    enum : string {
        BUF_UNIFORM   = "buf_uniform",
        BUF_STORAGE   = "buf_storage",
        // blas
        BUF_AABBS     = "buf_aabbs",
        BUF_SPHERES   = "buf_spheres",
        BUF_TRANSFORM = "buf_transform",
        // tlas
        BUF_INSTANCE  = "buf_instance"
    }
    static struct Sphere {
        float3 center;
        float radius;
        float4 colour;
    }
    static struct AABB {
        float3 min;
        float3 max;
    }

    // Objects we must destroy
    KisvRayTracingPipeline pipeline;
    KisvAccelerationStructure tlas;
    KisvAccelerationStructure blas;

    Sphere[] spheres;
    AABB[] aabbs;
    VkTransformMatrixKHR[] instanceTransforms;

    void createSpheres() {
        Mt19937 rng;

        // Use the same seed
        //rng.seed(unpredictableSeed());
        rng.seed(1);

        static if(OPTION == 1) {
            // A single TLAS instance
            instanceTransforms ~= identityTransformMatrix();

            // A single BLAS containing multiple spheres
            foreach(i; 0..NUM_SPHERES) {
                float3 origin = float3(uniform01(rng) * 2 - 1, uniform01(rng) * 2 - 1, uniform01(rng) * 2 - 1) * 30;
                float radius = maxOf(1, uniform01(rng) * 10);
                float4 colour = float4(uniform01(rng) + 0.2, uniform01(rng) + 0.2, uniform01(rng) + 0.2, 1);
                
                spheres ~= Sphere(origin, radius, colour);
                aabbs ~= AABB(origin - radius, origin + radius);
            }

        } else static if(OPTION == 2) {
            // A single BLAS AABB at the origin
            aabbs ~= AABB(float3(-10, -10, -10), float3(10, 10, 10));

            // Multiple TLAS instances with different transforms
            foreach(i; 0..NUM_SPHERES) {
                float3 origin = float3(uniform01(rng) * 2 - 1, uniform01(rng) * 2 - 1, uniform01(rng) * 2 - 1) * 30;
                float radius = maxOf(1, uniform01(rng) * 10);
                float4 colour = float4(uniform01(rng) + 0.2, uniform01(rng) + 0.2, uniform01(rng) + 0.2, 1);
                spheres ~= Sphere(origin, radius, colour);

                float s = radius / 10;

                VkTransformMatrixKHR transform = identityTransformMatrix();
                transform.translate(origin);
                transform.scale(float3(s, s, s));
                instanceTransforms ~= transform;
            }
        
        } else static assert(false);
    }
    void doCreatePipeline(string sbtMemoryKey, VkDescriptorSetLayout dsLayout) {
        this.pipeline = new KisvRayTracingPipeline(context, sbtMemoryKey);

        pipeline.addDescriptorSetLayout(dsLayout);

        uint option = OPTION;

        VkSpecializationMapEntry entry = {
            constantID: 0,
            offset: 0,
            size: 4
        };

        VkSpecializationInfo specConst = {
            mapEntryCount: 1,
            pMapEntries: &entry,
            dataSize: 4,
            pData: &option
        };

        pipeline.addShader(VK_SHADER_STAGE_RAYGEN_BIT_KHR, context.shaders.get("ray_tracing/sphere/generate_rays.rgen", "spirv1.4"));
        pipeline.addShader(VK_SHADER_STAGE_MISS_BIT_KHR, context.shaders.get("ray_tracing/sphere/miss.rmiss", "spirv1.4"));
        pipeline.addShader(
            VK_SHADER_STAGE_CLOSEST_HIT_BIT_KHR, 
            context.shaders.get("ray_tracing/sphere/hit_closest.rchit", "spirv1.4"),
            "main", 
            &specConst);
        pipeline.addShader(
            VK_SHADER_STAGE_INTERSECTION_BIT_KHR, 
            context.shaders.get("ray_tracing/sphere/intersection.rint", "spirv1.4"),
            "main", 
            &specConst);

        pipeline.addRaygenGroup(0);
        pipeline.addMissGroup(1);
        pipeline.addProceduralHitGroup(2, VK_SHADER_UNUSED_KHR, 3);

        pipeline.setMaxRecursionDepth(1);

        pipeline.build();
    }
    void createTriangleBLAS(string deviceMemoryKey) {

        VkBuffer aabbBuffer = context.buffers.createBuffer(BUF_AABBS, AABB.sizeof * aabbs.length, 
            VK_BUFFER_USAGE_ACCELERATION_STRUCTURE_BUILD_INPUT_READ_ONLY_BIT_KHR |
            VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT |
            VK_BUFFER_USAGE_TRANSFER_DST_BIT);

        context.memory.bind(deviceMemoryKey, aabbBuffer, 0);

        context.transfer.transferAndWaitFor(aabbs, aabbBuffer);

        // Get the device addresses
        auto aabbBufferDeviceAddress = getDeviceAddress(context.device, aabbBuffer);

        // Create the bottom level acceleration structure
        this.blas = new KisvAccelerationStructure(context, "BLAS", false, deviceMemoryKey);

        VkAccelerationStructureGeometryAabbsDataKHR aabbGeometry = {
            sType: VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_GEOMETRY_AABBS_DATA_KHR,
            data: { deviceAddress: aabbBufferDeviceAddress },
            stride: AABB.sizeof
        };

        blas.addAABBs(VK_GEOMETRY_OPAQUE_BIT_KHR, aabbGeometry, aabbs.length.as!int);

        buildAccelerationStructure(blas);
    }
    void createTLAS(string deviceMemoryKey) {
        // Create and upload instance data

        // This struct uses bitfields which is not natively supported in D.
        VkAccelerationStructureInstanceKHR[] instances;
        static if(OPTION == 1) {
            // A single instance
            VkAccelerationStructureInstanceKHR instance = {
                transform: instanceTransforms[0],
                accelerationStructureReference: blas.deviceAddress
            };
            instance.setInstanceCustomIndex(0);
            instance.setMask(0xFF);
            instance.setInstanceShaderBindingTableRecordOffset(0);
            instance.setFlags(VK_GEOMETRY_INSTANCE_TRIANGLE_FACING_CULL_DISABLE_BIT_KHR);
            instances ~= instance;

        } else static if(OPTION == 2) {
            foreach(i; 0..NUM_SPHERES) {
                // Multiple instances pointing to the same BLAS but with a different transform
                VkAccelerationStructureInstanceKHR instance = {
                    transform: instanceTransforms[i],
                    accelerationStructureReference: blas.deviceAddress
                };
                instance.setInstanceCustomIndex(0);
                instance.setMask(0xFF);
                instance.setInstanceShaderBindingTableRecordOffset(0);
                instance.setFlags(VK_GEOMETRY_INSTANCE_TRIANGLE_FACING_CULL_DISABLE_BIT_KHR);
                instances ~= instance;
            }
        } else static assert(false);

        // Buffer for instance data
        VkBuffer instanceBuffer = context.buffers.createBuffer(BUF_INSTANCE,
                VkAccelerationStructureInstanceKHR.sizeof * instances.length,
                VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT |
                VK_BUFFER_USAGE_ACCELERATION_STRUCTURE_BUILD_INPUT_READ_ONLY_BIT_KHR |
                VK_BUFFER_USAGE_TRANSFER_DST_BIT);

        // Bind to memory
        context.memory.bind(deviceMemoryKey, instanceBuffer, 16);

        // Copy the instance data to the GPU
        context.transfer.transferAndWaitFor(instances, instanceBuffer);

        auto instanceDataDeviceAddress = getDeviceAddress(context.device, instanceBuffer);

        // Create the top level acceleration structure
        this.tlas = new KisvAccelerationStructure(context, "tlas", true, deviceMemoryKey);

        VkAccelerationStructureGeometryInstancesDataKHR instanceGeometry = {
            sType: VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_GEOMETRY_INSTANCES_DATA_KHR,
            arrayOfPointers: VK_FALSE,
            data: { deviceAddress: instanceDataDeviceAddress }
        };

        tlas.addInstances(VK_GEOMETRY_OPAQUE_BIT_KHR, instanceGeometry, instances.length.as!int);

        buildAccelerationStructure(tlas);
    }
}
