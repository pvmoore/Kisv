module kisv.helper.SamplerHelper;

import kisv.all;

final class SamplerHelper {
public:
    this(KisvContext context) {
        this.context = context;
    }
    void destroy() {
        log("\tDestroying SamplerHelper");
        foreach(e; samplers.byKeyValue()) {
            log("\t\tDestroying sampler '%s'", e.key);
            vkDestroySampler(context.device, e.value, null);
        }
    }
    VkSampler get(string samplerKey) {
        VkSampler sampler = samplers.get(samplerKey, null);
        throwIf(!sampler, "Sampler key not found '%s'", samplerKey);
        return sampler;
    }
    VkSampler createLinear(string samplerKey, void delegate(ref VkSamplerCreateInfo) createInfo = null) {
        throwIf((samplerKey in samplers) !is null, "Sampler key already created '%s'", samplerKey);
        log("Creating sampler '%s'", samplerKey);
        VkSampler sampler = createLinear(createInfo);
        samplers[samplerKey] = sampler;
        return sampler;
    }
    VkSampler createNearest(string samplerKey, void delegate(ref VkSamplerCreateInfo) createInfo = null) {
        throwIf((samplerKey in samplers) !is null, "Sampler key already created '%s'", samplerKey);
        log("Creating sampler '%s'", samplerKey);
        VkSampler sampler = createNearest(createInfo);
        samplers[samplerKey] = sampler;
        return sampler;
    }
private:
    KisvContext context;
    VkSampler[string] samplers;

    /** Create a standard linear sampler and let the user modify as required */
    VkSampler createLinear(void delegate(ref VkSamplerCreateInfo) modifier) {
        VkSamplerCreateInfo createInfo = {
            sType: VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO,
            flags: 0,
            magFilter: VK_FILTER_LINEAR,
            minFilter: VK_FILTER_LINEAR,
            mipmapMode: VK_SAMPLER_MIPMAP_MODE_LINEAR,      // mipmapping
            addressModeU: VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
            addressModeV: VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
            addressModeW: VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
            compareEnable: VK_FALSE,
            compareOp: VK_COMPARE_OP_ALWAYS,
            mipLodBias: 0,                                  // mipmapping
            minLod: 0,                                      // mipmapping
            maxLod: 0,                                      // mipmapping
            borderColor: VK_BORDER_COLOR_INT_OPAQUE_BLACK,
            anisotropyEnable: VK_FALSE,
            maxAnisotropy: 1,
            unnormalizedCoordinates: VK_FALSE
        };
        if(modifier) modifier(createInfo);

        VkSampler sampler;
        check(vkCreateSampler(context.device, &createInfo, null, &sampler));
        return sampler;
    }
    /** Create a standard nearest sampler and let the user modify as required */
    VkSampler createNearest(void delegate(ref VkSamplerCreateInfo) modifier) {
        VkSamplerCreateInfo createInfo = {
            sType: VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO,
            flags: 0,
            magFilter: VK_FILTER_NEAREST,
            minFilter: VK_FILTER_NEAREST,
            mipmapMode: VK_SAMPLER_MIPMAP_MODE_NEAREST,     // mipmapping
            addressModeU: VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
            addressModeV: VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
            addressModeW: VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
            compareEnable: VK_FALSE,
            compareOp: VK_COMPARE_OP_ALWAYS,
            mipLodBias: 0,                                  // mipmapping
            minLod: 0,                                      // mipmapping
            maxLod: 0,                                      // mipmapping
            borderColor: VK_BORDER_COLOR_INT_OPAQUE_BLACK,
            anisotropyEnable: VK_FALSE,
            maxAnisotropy: 1,
            unnormalizedCoordinates: VK_FALSE
        };
        if(modifier) modifier(createInfo);

        VkSampler sampler;
        check(vkCreateSampler(context.device, &createInfo, null, &sampler));
        return sampler;
    }
}