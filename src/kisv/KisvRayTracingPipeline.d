module kisv.KisvRayTracingPipeline;

import kisv.all;

/**
 * Shader binding table:

 * hitGroupRecordAddress = start + stride * (offset + sbtRecordOffset + (geometry index * sbtRecordStride))
 *
 * start            = VkStridedDeviceAddressRegionKHR::deviceAddress passed to ckCmdTraceRaysKHR 
 * stride           = VkStridedDeviceAddressRegionKHR::stride        passed to ckCmdTraceRaysKHR 
 * geometry index   = index of gemeometry in BLAS
 * offset           = VkAccelerationStructureInstanceKHR::instanceShaderBindingTableRecordOffset
 * sbtRecordOffset  = traceRayEXT.sbtRecordOffset parameter (this is index not bytes)
 * sbtRecordStride  = traceRayEXT.sbtRecordStride parameter (this is index not bytes)
 *
 * missRecordAddress = start + stride * missIndex
 *
 * start            = VkStridedDeviceAddressRegionKHR::deviceAddress passed to ckCmdTraceRaysKHR 
 * stride           = VkStridedDeviceAddressRegionKHR::stride        passed to ckCmdTraceRaysKHR 
 * missIndex        = traceRayEXT.missIndex parameter 
 */
final class KisvRayTracingPipeline {
public:

    VkPipeline getPipeline() { return pipeline; }
    VkPipelineLayout getLayout() { return pipelineLayout; }
    uint getSbtHandleSize() { return sbtHandleSize; }
    uint getSbtHandleSizeAligned() { return sbtHandleSizeAligned; }

    VkStridedDeviceAddressRegionKHR* getRaygenStridedDeviceAddressRegionPtr() { return &raygenStridedDeviceAddressRegion; }
    VkStridedDeviceAddressRegionKHR* getMissStridedDeviceAddressRegionPtr() { return &missStridedDeviceAddressRegion; }
    VkStridedDeviceAddressRegionKHR* getHitStridedDeviceAddressRegionPtr() { return &hitStridedDeviceAddressRegion; }
    VkStridedDeviceAddressRegionKHR* getCallableStridedDeviceAddressRegionPtr() { return &callableStridedDeviceAddressRegion; }  

    this(KisvContext context, string memUploadKey) {
        this.context = context;
        this.memUploadKey = memUploadKey;
        this.sbtHandleSize = context.physicalDevice.rtPipelineProperties.shaderGroupHandleSize;
		this.sbtHandleSizeAligned = alignedTo(sbtHandleSize, context.physicalDevice.rtPipelineProperties.shaderGroupHandleAlignment).as!uint;
    }
    void destroy() {
        if(pipeline) vkDestroyPipeline(context.device, pipeline, null);
        if(pipelineLayout) vkDestroyPipelineLayout(context.device, pipelineLayout, null);
    }
    auto addPushConstantRange(VkShaderStageFlags stages, uint offset, uint size) {
        VkPushConstantRange pcRange = {
            stageFlags: stages,
            offset: offset,
            size: size
        };
        pushConstantRanges ~= pcRange;
        return this;
    }
    auto addDescriptorSetLayout(VkDescriptorSetLayout layout) {
        descriptorSetLayouts ~= layout;
        return this;
    }
    auto setMaxRecursionDepth(int depth) {
        this.maxRecursionDepth = minOf(depth, context.physicalDevice.rtPipelineProperties.maxRayRecursionDepth);
        return this;
    }
    auto addRaygenGroup(uint shaderIndex) {
        numRaygenGroups++;
        addGroup(VK_RAY_TRACING_SHADER_GROUP_TYPE_GENERAL_KHR, 
            shaderIndex, 
            VK_SHADER_UNUSED_KHR, 
            VK_SHADER_UNUSED_KHR, 
            VK_SHADER_UNUSED_KHR);
        return this;
    }
    auto addMissGroup(uint shaderIndex) {
        numMissGroups++;
        addGroup(VK_RAY_TRACING_SHADER_GROUP_TYPE_GENERAL_KHR, 
            shaderIndex, 
            VK_SHADER_UNUSED_KHR, 
            VK_SHADER_UNUSED_KHR, 
            VK_SHADER_UNUSED_KHR);
        return this;
    }
    auto addCallableGroup(uint shaderIndex) {
        numCallableGroups++;
        addGroup(VK_RAY_TRACING_SHADER_GROUP_TYPE_GENERAL_KHR, 
            shaderIndex, 
            VK_SHADER_UNUSED_KHR, 
            VK_SHADER_UNUSED_KHR, 
            VK_SHADER_UNUSED_KHR);
        return this;
    }
    auto addTriangleHitGroup(uint closestHitShaderIndex, uint anyHitShaderIndex) {
        numHitGroups++;
        addGroup(VK_RAY_TRACING_SHADER_GROUP_TYPE_TRIANGLES_HIT_GROUP_KHR, 
            VK_SHADER_UNUSED_KHR, 
            closestHitShaderIndex, 
            anyHitShaderIndex, 
            VK_SHADER_UNUSED_KHR);
        return this;
    }
    auto addProceduralHitGroup(uint closestHitShaderIndex, uint anyHitShaderIndex, uint intersectionShaderIndex) {
        numHitGroups++;
        addGroup(VK_RAY_TRACING_SHADER_GROUP_TYPE_PROCEDURAL_HIT_GROUP_KHR, 
            VK_SHADER_UNUSED_KHR, 
            closestHitShaderIndex, 
            anyHitShaderIndex, 
            intersectionShaderIndex);
        return this;
    }
    auto addShader(VkShaderStageFlagBits stage, 
                   VkShaderModule module_, 
                   string main = "main", 
                   VkSpecializationInfo* specInfo = null) 
    in{
        assert(stage.isOneOf(VK_SHADER_STAGE_RAYGEN_BIT_KHR,
                             VK_SHADER_STAGE_ANY_HIT_BIT_KHR,
                             VK_SHADER_STAGE_CLOSEST_HIT_BIT_KHR,
                             VK_SHADER_STAGE_MISS_BIT_KHR,
                             VK_SHADER_STAGE_INTERSECTION_BIT_KHR,
                             VK_SHADER_STAGE_CALLABLE_BIT_KHR));
    }
    do{
        VkPipelineShaderStageCreateInfo createInfo = {
            sType: VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            flags: 0,
            stage: stage,
            module_: module_,
            pName: main.toStringz(),
            pSpecializationInfo: specInfo
        };
        shaderStages ~= createInfo;
        return this;
    }
    auto build() {
        createPipelineLayout();
        createPipeline();
        createSBT();
        return this;
    }
private:
    KisvContext context;
    string memUploadKey;

    VkPipeline pipeline;
    VkPipelineLayout pipelineLayout;
    VkDescriptorSetLayout[] descriptorSetLayouts;
    VkPushConstantRange[] pushConstantRanges;
    VkRayTracingShaderGroupCreateInfoKHR[] shaderGroups;
    VkPipelineShaderStageCreateInfo[] shaderStages;
    uint maxRecursionDepth = 1;
    uint sbtHandleSize;
    uint sbtHandleSizeAligned;

    VkBuffer sbtRaygenBuffer;
    VkBuffer sbtMissBuffer;
    VkBuffer sbtHitBuffer;
    VkBuffer sbtCallableBuffer;
    uint numRaygenGroups;
    uint numMissGroups;
    uint numHitGroups;
    uint numCallableGroups;
    VkStridedDeviceAddressRegionKHR raygenStridedDeviceAddressRegion;
    VkStridedDeviceAddressRegionKHR missStridedDeviceAddressRegion;
    VkStridedDeviceAddressRegionKHR hitStridedDeviceAddressRegion;
    VkStridedDeviceAddressRegionKHR callableStridedDeviceAddressRegion;

    void createPipelineLayout() {
        assert(descriptorSetLayouts.length > 0);

        VkPipelineLayoutCreateInfo createInfo = {
            sType: VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
            setLayoutCount: descriptorSetLayouts.length.as!int,
            pSetLayouts: descriptorSetLayouts.ptr
        };

		check(vkCreatePipelineLayout(context.device, &createInfo, null, &pipelineLayout));
    }
    void createPipeline() {
        VkRayTracingPipelineCreateInfoKHR createInfo = {
            sType: VK_STRUCTURE_TYPE_RAY_TRACING_PIPELINE_CREATE_INFO_KHR,
            stageCount: shaderStages.length.as!int,
            pStages: shaderStages.ptr,
            groupCount: shaderGroups.length.as!int,
            pGroups: shaderGroups.ptr,
            maxPipelineRayRecursionDepth: maxRecursionDepth,
            layout: pipelineLayout
        };

        check(vkCreateRayTracingPipelinesKHR(context.device, null, null, 1, &createInfo, null, &pipeline));
    }
    void addGroup(VkRayTracingShaderGroupTypeKHR type,
                  uint generalShader,       // raygen, miss or callable shader index
                  uint closestHitShader,    // closest hit shader index
                  uint anyHitShader,        // any hit shader index
                  uint intersectionShader)  // intersection shader index
    {
        VkRayTracingShaderGroupCreateInfoKHR rgenShaderGroup = {
            sType: VK_STRUCTURE_TYPE_RAY_TRACING_SHADER_GROUP_CREATE_INFO_KHR,
            type: type,
            generalShader: generalShader,
            closestHitShader: closestHitShader,
            anyHitShader: anyHitShader,
            intersectionShader: intersectionShader
        };
        shaderGroups ~= rgenShaderGroup;
    }
    void createSBT() {
        log("Creating shader binding table");
        uint firstGroup = 0;
		uint groupCount = shaderGroups.length.as!uint;
		uint sbtSize = groupCount * sbtHandleSizeAligned;

        log("handleSize        = %s bytes", sbtHandleSize);
        log("handleSizeAligned = %s bytes", sbtHandleSizeAligned);
        log("sbtSize           = %s bytes", sbtSize);

        // Fetch the shader group handles
        ubyte[] shaderHandleStorage = new ubyte[sbtSize];
		check(vkGetRayTracingShaderGroupHandlesKHR(context.device, pipeline, firstGroup, groupCount, sbtSize, shaderHandleStorage.ptr));

        log("shaderHandleStorage: (%s bytes)", shaderHandleStorage.length);
        foreach(i; 0..shaderHandleStorage.length / sbtHandleSize) {
            log("[% 3s]%s", i*sbtHandleSize, shaderHandleStorage[i*sbtHandleSize..i*sbtHandleSize+sbtHandleSize]);
        }

        uint raygenSize = numRaygenGroups * sbtHandleSize;
        uint missSize = numMissGroups * sbtHandleSize;
        uint hitSize = numHitGroups * sbtHandleSize;
        uint callableSize = numCallableGroups * sbtHandleSize;

        log("raygenSize = %s", raygenSize);
        log("missSize = %s", missSize);
        log("hitSize = %s", hitSize);
        log("callableSize = %s", callableSize);

        auto flags =  VK_BUFFER_USAGE_SHADER_BINDING_TABLE_BIT_KHR | VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT;

        // Create buffers with a min size of 16 in case any are empty. 
        // This is harmless and will prevent a validation warning
        this.sbtRaygenBuffer = context.buffers.createBuffer("rtp-buf-raygen", maxOf(16, raygenSize), flags);
        this.sbtMissBuffer = context.buffers.createBuffer("rtp-buf-miss", maxOf(16, missSize), flags);
        this.sbtHitBuffer = context.buffers.createBuffer("rtp-buf-hit", maxOf(16, hitSize), flags);
        this.sbtCallableBuffer = context.buffers.createBuffer("rtp-buf-callable", maxOf(16, callableSize), flags);

        ulong raygenMemOffset = context.memory.bind(memUploadKey, sbtRaygenBuffer, context.physicalDevice.rtPipelineProperties.shaderGroupBaseAlignment);
        ulong missMemOffset = context.memory.bind(memUploadKey, sbtMissBuffer, context.physicalDevice.rtPipelineProperties.shaderGroupBaseAlignment);
        ulong hitMemOffset = context.memory.bind(memUploadKey, sbtHitBuffer, context.physicalDevice.rtPipelineProperties.shaderGroupBaseAlignment);
        ulong callableMemOffset = context.memory.bind(memUploadKey, sbtCallableBuffer, context.physicalDevice.rtPipelineProperties.shaderGroupBaseAlignment);

        log("raygenMemOffset = %s", raygenMemOffset);
        log("missMemOffset = %s", missMemOffset);
        log("hitMemOffset = %s", hitMemOffset);
        log("callableMemOffset = %s", callableMemOffset);

        // Copy the handles.
        // NB. This assumes:
        //  1. The groups are contiguous. ie. miss groups are together, hit groups are together, etc.
        //  2. The handles are in this order: raygen, miss, hit, callable
        //  3. There are no gaps 

        ubyte* dest = cast(ubyte*)context.memory.map(memUploadKey, 0, VK_WHOLE_SIZE);

        ubyte* raygenSrc = shaderHandleStorage.ptr;
        ubyte* missSrc = raygenSrc + raygenSize;
        ubyte* hitSrc = missSrc + missSize;
        ubyte* callableSrc = hitSrc + hitSize;

        memcpy(dest + raygenMemOffset, raygenSrc, raygenSize);
		memcpy(dest + missMemOffset, missSrc, missSize);
		memcpy(dest + hitMemOffset, hitSrc, hitSize);
		memcpy(dest + callableMemOffset, callableSrc, callableSize);

        log("raygen = %s", (dest+raygenMemOffset)[0..32]);
        log("miss   = %s", (dest+missMemOffset)[0..32]);
        log("hit    = %s", (dest+hitMemOffset)[0..32]);
        log("callable = %s", (dest+callableMemOffset)[0..32]);

        context.memory.flush(memUploadKey, 0, VK_WHOLE_SIZE);
        context.memory.unmap(memUploadKey);

        this.raygenStridedDeviceAddressRegion = VkStridedDeviceAddressRegionKHR(
            getDeviceAddress(context.device, sbtRaygenBuffer),
            sbtHandleSizeAligned,
            raygenSize
        );
        this.missStridedDeviceAddressRegion = VkStridedDeviceAddressRegionKHR(
            getDeviceAddress(context.device, sbtMissBuffer),
            sbtHandleSizeAligned,
            missSize
        );
        this.hitStridedDeviceAddressRegion = VkStridedDeviceAddressRegionKHR(
            getDeviceAddress(context.device, sbtHitBuffer),
            sbtHandleSizeAligned,
            hitSize
        );
        this.callableStridedDeviceAddressRegion = VkStridedDeviceAddressRegionKHR(
            getDeviceAddress(context.device, sbtCallableBuffer),
            sbtHandleSizeAligned,
            callableSize
        );  

        log("========================");
        log("Groups:");
        log("========================");
        uint j;
        foreach(i; 0..numRaygenGroups) {
            log("[%s] %-11s   raygen", j++, shaderGroups[i].generalShader);
        }
        log("------------------------");
        foreach(i; 0..numMissGroups) {
            log("[%s] %-11s     miss", j++, shaderGroups[i+numRaygenGroups].generalShader);
        }
        log("------------------------");
        foreach(i; 0..numHitGroups) {
            auto g = shaderGroups[i+numRaygenGroups+numMissGroups];
            log("[%s] %-3s %-3s %-3s      hit", j++, 
                    g.closestHitShader == VK_SHADER_UNUSED_KHR ? "-" : "%s".format(g.closestHitShader), 
                    g.anyHitShader == VK_SHADER_UNUSED_KHR ? "-" : "%s".format(g.anyHitShader), 
                    g.intersectionShader == VK_SHADER_UNUSED_KHR ? "-" : "%s".format(g.intersectionShader));
        }
        log("------------------------");
        foreach(i; 0..numCallableGroups) {
            auto g = shaderGroups[i+numRaygenGroups+numMissGroups+numHitGroups];
            log("[%s] %-11s callable", j++, g.generalShader);
        }
    }
}
