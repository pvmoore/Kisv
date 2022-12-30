module kisv.misc.dbg_callback;

import kisv.all;

extern(Windows):

uint dbgFunc(uint msgFlags,
             VkDebugReportObjectTypeEXT objType,
			 ulong srcObject,
             size_t location,
             int msgCode,
			 const(char)* pLayerPrefix,
			 const(char)* pMsg,
             void* pUserData) nothrow
{
    try{
        string level;
        if(msgFlags & VK_DEBUG_REPORT_ERROR_BIT_EXT) {
            level = "ERROR";
        } else if (msgFlags & VK_DEBUG_REPORT_WARNING_BIT_EXT) {
            level = "WARN";
        } else if(msgFlags & VK_DEBUG_REPORT_INFORMATION_BIT_EXT) {
            level = "INFO";
        } else if(msgFlags & VK_DEBUG_REPORT_PERFORMANCE_WARNING_BIT_EXT) {
            level = "PERF";
        } else if(msgFlags & VK_DEBUG_REPORT_DEBUG_BIT_EXT) {
            level = "DEBUG";
        } else {
            level = "";
        }
        auto s = pMsg.fromStringz;
        log("[%s] %s", level, s);

	}catch(Exception e) {
		// ignore
	}
	return 0;
}
