module kisv.util.vulkan_util;

import kisv.all;

void check(VkResult r) {
    if(r != VK_SUCCESS) {
        throw new Exception("API call returned %s".format(r));
    }
}

VkExtent3D toVkExtent3D(VkExtent2D extent, uint z) {
    return VkExtent3D(extent.width, extent.height, z);
}

VkRect2D toVkRect2D(int x, int y, uint w, uint h) {
    return VkRect2D(VkOffset2D(x,y), VkExtent2D(w,h));
}
VkRect2D toVkRect2D(int x, int y, VkExtent2D e) {
    return VkRect2D(VkOffset2D(x,y), e);
}

string versionToString(uint v) {
    return "%s.%s.%s".format(
        v >> 22,
        (v >> 12) & 0x3ff,
        v & 0xfff
    );
}

VkClearValue clearValue(float r, float g, float b, float a) {
    VkClearColorValue value;
    value.float32 = [r,g,b,a];
    return value.as!VkClearValue;
}

string toString(VkMemoryRequirements req) {
    return "VkMemoryRequirements{size:%s align:%s types:%b}".format(req.size, req.alignment, req.memoryTypeBits);
}