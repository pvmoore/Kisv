module kisv.helper.DescriptorHelper;

import kisv.all;

final class DescriptorHelper {
public:
    this(KisvContext context) {
        this.context = context;
    }
    void destroy() {
        log("\tDestroying DescriptorHelper");
        foreach(e; pools.byKeyValue()) {
            log("\t\tDestroying pool '%s'", e.key);
            vkDestroyDescriptorPool(context.device, e.value, null);
        }
        foreach(e; layouts.byKeyValue()) {
            log("\t\tDestroying layout '%s'", e.key);
            vkDestroyDescriptorSetLayout(context.device, e.value, null);
        }
    }
    VkDescriptorSetLayout getLayout(string layoutKey) {
        VkDescriptorSetLayout layout = layouts.get(layoutKey, null);
        throwIf(!layout, "Layout key not found '%s'", layoutKey);
        return layout;
    }
    VkDescriptorPool getPool(string poolKey) {
        VkDescriptorPool pool = pools.get(poolKey, null);
        throwIf(!pool, "Pool key not found '%s'", poolKey);
        return pool;
    }
    /**
     * createLayout("key", tuple(type, stage), tuple(type,stage) ...etc);
     */
    VkDescriptorSetLayout createLayout(string layoutKey, Tuple!(VkDescriptorType, VkShaderStageFlagBits)[] bindings...) {
        auto vkBindings = new VkDescriptorSetLayoutBinding[bindings.length];
        foreach(i, b; bindings) {
            VkDescriptorSetLayoutBinding bind = {
                binding: i.as!uint,
                descriptorType: b[0],
                descriptorCount: 1,
                stageFlags: b[1],
                pImmutableSamplers: null
            };
            vkBindings[i] = bind;
        }
        return createLayout(layoutKey, vkBindings);
    }
    VkDescriptorSetLayout createLayout(string layoutKey, VkDescriptorSetLayoutBinding[] bindings...) {
        throwIf((layoutKey in layouts) !is null, "Layout key already created '%s'", layoutKey);
        log("Creating VkDescriptorSetLayout '%s' %s bindings", layoutKey, bindings.length);

        VkDescriptorSetLayoutCreateInfo layoutCreateInfo = {
            sType: VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
            flags: 0,
            bindingCount: bindings.length.as!uint,
            pBindings: bindings.ptr
        };

        VkDescriptorSetLayout layout;
        check(vkCreateDescriptorSetLayout(context.device, &layoutCreateInfo, null, &layout));
        layouts[layoutKey] = layout;
        return layout;
    }
    VkDescriptorPool createPool(string poolKey, uint maxSets, Tuple!(VkDescriptorType, int)[] sizes...) {
        auto vkSizes = new VkDescriptorPoolSize[sizes.length];
        foreach(i, s; sizes) {
            VkDescriptorPoolSize size = {
                type: s[0],
                descriptorCount: s[1]
            };
            vkSizes[i] = size;
        }
        return createPool(poolKey, maxSets, vkSizes);
    }
    VkDescriptorPool createPool(string poolKey, uint maxSets, VkDescriptorPoolSize[] sizes...) {
        log("Creating VkDescriptorPool with %s", sizes.map!(it=>"{%s,%s}".format(it.type, it.descriptorCount)));
        VkDescriptorPoolCreateInfo poolCreateInfo = {
            sType: VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
            flags:0,
            maxSets: maxSets,
            poolSizeCount: sizes.length.as!uint,
            pPoolSizes: sizes.ptr
        };
        VkDescriptorPool pool;
        check(vkCreateDescriptorPool(context.device, &poolCreateInfo, null, &pool));
        pools[poolKey] = pool;
        return pool;
    }
    VkDescriptorSet allocateSet(string poolKey, string layoutKey) {
        VkDescriptorPool pool = getPool(poolKey);
        VkDescriptorSetLayout layout = getLayout(layoutKey);

        VkDescriptorSetAllocateInfo allocDescriptorSetInfo = {
            sType: VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
            descriptorPool: pool,
            descriptorSetCount: 1,
            pSetLayouts: &layout
        };
        VkDescriptorSet[] sets = new VkDescriptorSet[1];
        check(vkAllocateDescriptorSets(context.device, &allocDescriptorSetInfo, sets.ptr));
        return sets[0];
    }
private:
    KisvContext context;
    VkDescriptorSetLayout[string] layouts;
    VkDescriptorPool[string] pools;
}
//──────────────────────────────────────────────────────────────────────────────────────────────────
// final class DescriptorWrites {
// public:
//     auto write(VkDescriptorBufferInfo bufferInfo) {
//         return this;
//     }
//     auto write(VkDescriptorImageInfo imageInfo) {
//         return this;
//     }
// private:
//     VkWriteDescriptorSet[] writes;
// }