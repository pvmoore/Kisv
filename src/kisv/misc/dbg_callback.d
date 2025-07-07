module kisv.misc.dbg_callback;

import kisv.all;

extern(Windows) 
VkBool32 debugUtilsMessengerCallbackEXTFunc(VkDebugUtilsMessageSeverityFlagBitsEXT messageSeverity, 
				  							VkDebugUtilsMessageTypeFlagsEXT messageTypes, 
				  							VkDebugUtilsMessengerCallbackDataEXT* pCallbackData, 
				  							void* pUserData) nothrow
{
    string level;
    string type;
    switch(messageSeverity) {
        case VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT: level = "VERBOSE"; break;
        case VK_DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT   : level = "INFO" ; break;
        case VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT: level = "WARN"; break;
        case VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT  : level = "ERROR"; break;
        default: level = "?"; break;
    }
    switch(messageTypes) {
        case VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT: type = "GENERAL"; break;
        case VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT: type = "VALIDATION"; break;
        case VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT: type = "PERFORMANCE"; break;
        case VK_DEBUG_UTILS_MESSAGE_TYPE_DEVICE_ADDRESS_BINDING_BIT_EXT: type = "DEVICE_ADDRESS_BINDING"; break;
        default: type = "?"; break;
    }
    try{
        log("[%s] [%s] %s\n", level, type, pCallbackData.pMessage.fromStringz());
    }catch(Exception e){
        // ignore
    }
	return 0;
}
