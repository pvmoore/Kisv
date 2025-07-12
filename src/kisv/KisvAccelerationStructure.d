module kisv.KisvAccelerationStructure;

import kisv.all;

final class KisvAccelerationStructure {
public:
    VkAccelerationStructureKHR handle;
    VkDeviceAddress deviceAddress;

    this(KisvContext context, string name, bool topLevel, string deviceMemoryKey) {
        this.context = context;
        this.name = name;
        this.topLevel = topLevel;
        this.deviceMemoryKey = deviceMemoryKey;
        this.type = topLevel ? 
            VK_ACCELERATION_STRUCTURE_TYPE_TOP_LEVEL_KHR : 
            VK_ACCELERATION_STRUCTURE_TYPE_BOTTOM_LEVEL_KHR;
        this.uid = UIDs++;
    }
    void destroy() {
        // BufferHelper will tidy up the buffers
        if(handle) vkDestroyAccelerationStructureKHR(context.device, handle, null);
    }
    auto addTriangles(VkGeometryFlagBitsKHR flags, VkAccelerationStructureGeometryTrianglesDataKHR triangles, uint maxPrimitives) {
        assert(!topLevel);

        // Useful flags:
        // VK_GEOMETRY_OPAQUE_BIT_KHR
        // VK_GEOMETRY_NO_DUPLICATE_ANY_HIT_INVOCATION_BIT_KHR

        VkAccelerationStructureGeometryKHR geometry = {
            sType: VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_GEOMETRY_KHR,
            flags: flags,
            geometryType: VK_GEOMETRY_TYPE_TRIANGLES_KHR,
            geometry: { triangles: triangles }   
        };
        VkAccelerationStructureBuildRangeInfoKHR buildRangeInfo = {
            primitiveCount: maxPrimitives,
            primitiveOffset: 0,
            firstVertex: 0,
            transformOffset: 0
        };
        geometries ~= geometry;
        buildRangeInfos ~= buildRangeInfo;
        maxPrimitiveCounts ~= maxPrimitives;
        return this;
    }
    auto addAABBs(VkGeometryFlagBitsKHR flags, VkAccelerationStructureGeometryAabbsDataKHR aabbs, uint maxPrimitives) {
        assert(!topLevel);

        // Useful flags:
        // VK_GEOMETRY_OPAQUE_BIT_KHR
        // VK_GEOMETRY_NO_DUPLICATE_ANY_HIT_INVOCATION_BIT_KHR

        VkAccelerationStructureGeometryKHR geometry = {
            sType: VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_GEOMETRY_KHR,
            flags: flags,
            geometryType: VK_GEOMETRY_TYPE_AABBS_KHR,
            geometry: {  aabbs: aabbs }
        };
        VkAccelerationStructureBuildRangeInfoKHR buildRangeInfo = {
            primitiveCount: maxPrimitives,
            primitiveOffset: 0,
            firstVertex: 0,
            transformOffset: 0
        };
        geometries ~= geometry;
        buildRangeInfos ~= buildRangeInfo;
        maxPrimitiveCounts ~= maxPrimitives;
        return this;
    }
    auto addInstances(VkGeometryFlagBitsKHR flags, VkAccelerationStructureGeometryInstancesDataKHR instances, uint numInstances) {
        assert(topLevel);
        assert(instances.data.deviceAddress);

        // Note that this can contain multiple instances if instance.arrayOfPointers is true
        if(instances.arrayOfPointers || numInstances > 1) {
            assert(false, "Implement array of pointers");
        }

        VkAccelerationStructureGeometryKHR geometry = {
            sType: VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_GEOMETRY_KHR,
            geometryType: VK_GEOMETRY_TYPE_INSTANCES_KHR,
            flags: flags,
            geometry: { instances: instances }
        };
        VkAccelerationStructureBuildRangeInfoKHR buildRangeInfo = {
            primitiveCount: numInstances,
            primitiveOffset: 0,
            firstVertex: 0,
            transformOffset: 0
        };
        geometries ~= geometry;
        buildRangeInfos ~= buildRangeInfo;
        maxPrimitiveCounts ~= 1;
        return this;
    }
    /**
     *
     * Useful build flags:
     *  VK_BUILD_ACCELERATION_STRUCTURE_ALLOW_UPDATE_BIT_KHR 
     *  VK_BUILD_ACCELERATION_STRUCTURE_ALLOW_COMPACTION_BIT_KHR 
	 *  VK_BUILD_ACCELERATION_STRUCTURE_PREFER_FAST_TRACE_BIT_KHR 
	 *  VK_BUILD_ACCELERATION_STRUCTURE_PREFER_FAST_BUILD_BIT_KHR 
	 *  VK_BUILD_ACCELERATION_STRUCTURE_LOW_MEMORY_BIT_KHR
     */
    auto buildAll(VkCommandBuffer cmd, VkBuildAccelerationStructureFlagBitsKHR buildFlags) {
        assert(geometries.length > 0);
        assert(geometries.length == maxPrimitiveCounts.length);
        assert(geometries.length == buildRangeInfos.length);

        getBuildSizes(buildFlags);
        createBuffer();
        createScratchBuffer();
        createAccelerationStructure();

        VkAccelerationStructureBuildRangeInfoKHR*[] rangePtrs;
        foreach(ref range; buildRangeInfos) {
            rangePtrs ~= &range;
        }
        doBuild(cmd, buildFlags, rangePtrs);

        return this;
    }
    auto update(VkCommandBuffer cmd, 
                VkBuildAccelerationStructureFlagBitsKHR buildFlags, 
                VkAccelerationStructureBuildRangeInfoKHR*[] rangePtrs) 
    {
        return this;
    }
private:
    static uint UIDs = 0;

    // Static data
    uint uid;
    KisvContext context;
    string name;
    bool topLevel;
    string deviceMemoryKey;
    VkAccelerationStructureTypeKHR type;

    // Buffers
    VkBuffer buffer;
    VkBuffer scratchBuffer;
    VkDeviceAddress scratchBufferDeviceAddress;

    // Geometry/instances
    VkAccelerationStructureGeometryKHR[] geometries;
    VkAccelerationStructureBuildRangeInfoKHR[] buildRangeInfos;
    uint[] maxPrimitiveCounts;

    // Build sizes
    VkDeviceSize accelerationStructureSize;
	VkDeviceSize updateScratchSize;
	VkDeviceSize buildScratchSize;

    void getBuildSizes(VkBuildAccelerationStructureFlagsKHR buildFlags) {
        VkAccelerationStructureBuildGeometryInfoKHR buildGeometryInfo = {
                sType: VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_BUILD_GEOMETRY_INFO_KHR,
                type: type,
                flags: buildFlags,
                geometryCount: geometries.length.as!int,
                pGeometries: geometries.ptr
            };

        VkAccelerationStructureBuildSizesInfoKHR buildSizes = {
            sType: VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_BUILD_SIZES_INFO_KHR
        };
        vkGetAccelerationStructureBuildSizesKHR(
            context.device,
            VK_ACCELERATION_STRUCTURE_BUILD_TYPE_DEVICE_KHR,
            &buildGeometryInfo,
            maxPrimitiveCounts.ptr,
            &buildSizes);

        this.accelerationStructureSize = buildSizes.accelerationStructureSize;
        this.updateScratchSize = buildSizes.updateScratchSize;
        this.buildScratchSize = buildSizes.buildScratchSize;    
    }
    void createBuffer() {
        buffer = context.buffers.createBuffer("as-buf-%s".format(uid),
            accelerationStructureSize,
            VK_BUFFER_USAGE_ACCELERATION_STRUCTURE_STORAGE_BIT_KHR | 
            VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT);

        context.memory.bind(deviceMemoryKey, buffer, 0);
    }
    void createScratchBuffer() {
        scratchBuffer = context.buffers.createBuffer("as-buf-scratch-%s".format(uid), 
            buildScratchSize,
            VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | 
            VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT);

        context.memory.bind(deviceMemoryKey, scratchBuffer, context.physicalDevice.accelerationStructureProperties.minAccelerationStructureScratchOffsetAlignment);

        scratchBufferDeviceAddress = getDeviceAddress(context.device, scratchBuffer);
    }
    void createAccelerationStructure() {
        VkAccelerationStructureCreateInfoKHR createInfo = {
            sType: VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_CREATE_INFO_KHR,
		    buffer: buffer,
            offset: 0,
		    size: accelerationStructureSize,
		    type: type
        };

		check(vkCreateAccelerationStructureKHR(context.device, &createInfo, null, &handle));

        deviceAddress = getDeviceAddress(context.device, handle);
    }

    void doBuild(VkCommandBuffer cmd, 
                 VkBuildAccelerationStructureFlagsKHR buildFlags, 
                 VkAccelerationStructureBuildRangeInfoKHR*[] rangePtrs) 
    in{
        assert(rangePtrs.length > 0);
    }
    do{
        VkAccelerationStructureBuildGeometryInfoKHR buildGeometryInfo = {
            sType: VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_BUILD_GEOMETRY_INFO_KHR,
            type: type,
            flags: buildFlags,
            mode: VK_BUILD_ACCELERATION_STRUCTURE_MODE_BUILD_KHR,
            dstAccelerationStructure: handle,
            geometryCount: geometries.length.as!int,
            pGeometries: geometries.ptr,
            scratchData: {
                deviceAddress: scratchBufferDeviceAddress
            }
        };

        vkCmdBuildAccelerationStructuresKHR(
            cmd,
            1,
            &buildGeometryInfo,             
            rangePtrs.ptr    
        );
    }

    void doUpdate(VkCommandBuffer cmd, 
                  VkBuildAccelerationStructureFlagsKHR buildFlags, 
                  VkAccelerationStructureBuildRangeInfoKHR*[] rangePtrs) 
    in{
        assert(rangePtrs.length > 0);
    }
    do{
        VkAccelerationStructureBuildGeometryInfoKHR buildGeometryInfo = {
            sType: VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_BUILD_GEOMETRY_INFO_KHR,
            type: type,
            flags: buildFlags,
            mode: VK_BUILD_ACCELERATION_STRUCTURE_MODE_UPDATE_KHR,
            srcAccelerationStructure: handle,
            dstAccelerationStructure: handle,
            geometryCount: geometries.length.as!int,
            pGeometries: geometries.ptr,
            scratchData: {
                deviceAddress: scratchBufferDeviceAddress
            }
        };

        vkCmdBuildAccelerationStructuresKHR(
            cmd,
            1,
            &buildGeometryInfo,             
            rangePtrs.ptr    
        );
    }
}
