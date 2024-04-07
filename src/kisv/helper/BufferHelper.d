module kisv.helper.BufferHelper;

import kisv.all;

/**
 * Helper class to facilitate buffer creation and upload.
 * Also will manage buffer lifetime.
 */
final class BufferHelper {
public:
    this(KisvContext context) {
        this.context = context;
    }
    void destroy() {
        log("\tDestroying BufferHelper");
        foreach(e; buffers.byKeyValue()) {
            log("\t\tDestroying buffer '%s'", e.key);
            vkDestroyBuffer(context.device, e.value, null);
        }
    }
    VkBuffer getBuffer(string bufferKey) {
        VkBuffer buffer = buffers.get(bufferKey, null);
        throwIf(!buffer, "Buffer key not found '%s'", bufferKey);
        return buffer;
    }
    VkBuffer createBuffer(string bufferKey, ulong size, VkBufferUsageFlagBits usage, uint[] queueFamilies = null) {
        throwIf((bufferKey in buffers) !is null, "Buffer key already created '%s'", bufferKey);
        log("Creating buffer '%s' %s %s", bufferKey, size, enumToString!VkBufferUsageFlagBits(usage));
        VkBuffer buffer = createBuffer(size, usage, queueFamilies);
        buffers[bufferKey] = buffer;
        return buffer;
    }
private:
    KisvContext context;
    VkBuffer[string] buffers;   // All managed buffers by buffer key

    VkBuffer createBuffer(ulong size, VkBufferUsageFlagBits usage, uint[] queueFamilies) {
        VkBufferCreateInfo createInfo = {
            sType: VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
            flags: 0,
            size: size,
            usage: usage
        };

        if(queueFamilies.length==0) {
            createInfo.sharingMode            = VK_SHARING_MODE_EXCLUSIVE;
            createInfo.queueFamilyIndexCount  = 0;
            createInfo.pQueueFamilyIndices    = null;
        } else {
            createInfo.sharingMode            = VK_SHARING_MODE_CONCURRENT;
            createInfo.queueFamilyIndexCount  = queueFamilies.length.as!uint;
            createInfo.pQueueFamilyIndices    = queueFamilies.ptr;
        }

        VkBuffer buffer;
        check(vkCreateBuffer(context.device,&createInfo, null, &buffer));
        return buffer;
    }
}