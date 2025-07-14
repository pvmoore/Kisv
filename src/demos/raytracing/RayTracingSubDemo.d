module demos.raytracing.RayTracingSubDemo;

import kisv;

abstract class RayTracingSubDemo {
public:
    this(KisvContext context, VkCommandPool commandPool, uint queueFamilyIndex) {
        this.context = context;
        this.commandPool = commandPool;
        this.queueFamilyIndex = queueFamilyIndex;
    }
    abstract void destroy();

    abstract VkShaderStageFlagBits[] getDSShaderStageFlags();
    abstract VkBuffer getUniformBuffer(string deviceMemoryKey);
    abstract VkBuffer getStorageBuffer(string deviceMemoryKey);
    abstract KisvRayTracingPipeline getPipeline(string sbtMemoryKey, VkDescriptorSetLayout dsLayout);
    abstract KisvAccelerationStructure getAccelerationStructures(string deviceMemoryKey);

protected:
    KisvContext context;
    VkCommandPool commandPool;
    uint queueFamilyIndex;

    void buildAccelerationStructure(KisvAccelerationStructure as) {
        VkCommandBuffer cmd = allocCommandBuffer(context.device, commandPool);

        cmd.beginOneTimeSubmit();
        as.buildAll(cmd, VK_BUILD_ACCELERATION_STRUCTURE_PREFER_FAST_TRACE_BIT_KHR);
        cmd.end();

        context.queues.getQueue(queueFamilyIndex, 0).submitAndWaitFor(cmd, context);

        freeCommandBuffer(context.device, commandPool, cmd);
    }
private:
}
