module kisv.helper.ImageHelper;

import kisv.all;

struct ImageInfo {
    uint width;
    uint height;
    uint bytesPerPixel;
    ubyte[] data;
    VkFormat format;

    VkExtent3D extent3D() { return VkExtent3D(width, height, 1); }
}

/**
 * Helper class to facilitate image creation and upload.
 * Also will manage image and image view lifetimes.
 */
final class ImageHelper {
public:
    this(KisvContext context) {
        this.context = context;
    }
    void destroy() {
        log("\tDestroying ImageHelper");
        foreach(e; views.byKeyValue()) {
            string imageKey = e.key;
            VkImageView[ulong] map = e.value;
            log("\t\tDestroying %s image view(s) for image '%s'", map.length, imageKey);
            foreach(v; map.values()) {
                vkDestroyImageView(context.device, v, null);
            }
        }
        foreach(e; images.byKeyValue()) {
            log("\t\tDestroying image '%s'", e.key);
            vkDestroyImage(context.device, e.value, null);
        }
    }
    /**
     * Load some image data and return it. Assumes BMP format.
     */
    static ImageInfo load(string filename) {
        log("Loading image '%s'", filename);
        auto bmp = BMP.read(filename);
        VkFormat format = bmp.bytesPerPixel == 3 ? VK_FORMAT_R8G8B8_UNORM :
                          bmp.bytesPerPixel == 4 ? VK_FORMAT_R8G8B8A8_UNORM : VK_FORMAT_UNDEFINED;

        throwIf(format==VK_FORMAT_UNDEFINED, "Todo - handle format of this image");

        auto info = ImageInfo(bmp.width, bmp.height, bmp.bytesPerPixel, bmp.data, format);
        log("\tImage loaded: width:%s height:%s format:%s) bpp:%s bytes:%s",
            info.width, info.height, info.bytesPerPixel, info.data.length, format);
        return info;
    }
    VkImage getImage(string imageKey) {
        VkImage image = images.get(imageKey, null);
        throwIf(!image, "Image key not found '%s'", imageKey);
        return image;
    }
    VkImage createImage(string imageKey, VkExtent3D extent, VkFormat format, VkImageUsageFlagBits usage) {
        throwIf((imageKey in images) !is null, "Image key already created '%s'", imageKey);
        log("Creating image '%s' %s %s %s", imageKey, extent, format, enumToString!VkImageUsageFlagBits(usage));
        VkImage image = createImage(extent, format, usage);
        images[imageKey] = image;
        return image;
    }
    VkImageView getOrCreateView(string imageKey, VkImageViewType viewType, VkFormat format) {
        throwIf(!images.get(imageKey, null), "Image key not found '%s'", imageKey);
        VkImageView[ulong] imageViews = views.get(imageKey, null);

        ulong key = viewType.as!ulong << 32 | format.as!ulong;
        VkImageView view = imageViews.get(key, null);
        if(!view) {
            log("Creating image view '%s' %s %s", imageKey, viewType, format);
            view = createView(images[imageKey], viewType, format);
            views[imageKey][key] = view;
        }
        return view;
    }
 private:
    KisvContext context;
    VkImage[string] images;              // images by image key
    VkImageView[ulong][string] views;    // views created per image key

    VkImage createImage(VkExtent3D extent, VkFormat format, VkImageUsageFlagBits usage) {
        VkImageType type = extent.depth != 1 ? VK_IMAGE_TYPE_3D :
                           extent.height != 1 ? VK_IMAGE_TYPE_2D :
                           VK_IMAGE_TYPE_1D;

        VkImageCreateInfo imageCreateInfo = {
            sType: VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
            flags: 0,
            imageType: type,
            format: format,
            extent: extent,
            mipLevels: 1,
            arrayLayers: 1,
            samples: VK_SAMPLE_COUNT_1_BIT,
            tiling: VK_IMAGE_TILING_OPTIMAL,
            usage: usage,
            sharingMode: VK_SHARING_MODE_EXCLUSIVE,
            initialLayout: VK_IMAGE_LAYOUT_UNDEFINED
        };
        VkImage image;
        check(vkCreateImage(context.device, &imageCreateInfo, null, &image));
        return image;
    }
    VkImageView createView(VkImage image, VkImageViewType viewType, VkFormat format) {
        VkImageViewCreateInfo createInfo = {
            sType: VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
            flags: 0,
            image: image,
            viewType: viewType,
            format: format,
            components: componentMapping!"rgba",
            subresourceRange: VkImageSubresourceRange(
                VK_IMAGE_ASPECT_COLOR_BIT,  // aspectMask
                0,                          // baseMipLevel
                VK_REMAINING_MIP_LEVELS,    // levelCount
                0,                          // baseArrayLayer
                VK_REMAINING_ARRAY_LAYERS   // layerCount
            )
        };
        VkImageView imageView;
        check(vkCreateImageView(context.device, &createInfo, null, &imageView));
        return imageView;
    }
}