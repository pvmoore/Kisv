module kisv.util.rt_util;

import kisv.all;

/**
 * Create and return an identity (3x4) matrix
 *
 * 1  0  0  0
 * 0  1  0  0
 * 0  0  1  0
 */
VkTransformMatrixKHR identityTransformMatrix() {
    // struct VkTransformMatrixKHR {
    //     float[4][3] matrix;
    // }

    VkTransformMatrixKHR transform;

    float* fp = (&transform).as!(float*);
    fp[0..VkTransformMatrixKHR.sizeof/4] = 0.0f;

    transform.matrix[0][0] = 1;
    transform.matrix[1][1] = 1;
    transform.matrix[2][2] = 1;

    // transform.matrix[0] = 1;
    // transform.matrix[5] = 1;
    // transform.matrix[10] = 1;

    log("transform = %s", fp[0..12]);
    log("matrix = %s", transform.matrix);

    ubyte* f = (&transform).as!(ubyte*);

    log("%s", f[0..VkTransformMatrixKHR.sizeof]);  

    return transform;
}

VkDeviceAddress getDeviceAddress(VkDevice device, VkBuffer buffer) {
    VkBufferDeviceAddressInfo info = {
        sType: VK_STRUCTURE_TYPE_BUFFER_DEVICE_ADDRESS_INFO,
        buffer: buffer
    };
    return vkGetBufferDeviceAddressKHR(device, &info);
}

VkDeviceAddress getDeviceAddress(VkDevice device, VkAccelerationStructureKHR as) {
    VkAccelerationStructureDeviceAddressInfoKHR info = {
        sType: VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_DEVICE_ADDRESS_INFO_KHR,
        accelerationStructure: as
    };
    return vkGetAccelerationStructureDeviceAddressKHR(device, &info);
}
