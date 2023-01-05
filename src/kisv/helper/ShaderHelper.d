module kisv.helper.ShaderHelper;

import kisv.all;

final class ShaderHelper {
public:
    this(KisvContext context) {
        this.context = context;
        this.srcDirectory = "resources/shaders_src/";
        this.destDirectory = "resources/shaders_spv/";
    }
    void destroy() {
        log("\tDestroying ShaderHelper");
        foreach(e; shaderMap.byKeyValue()) {
            log("\t\tDestroying shader '%s'", e.key);
            vkDestroyShaderModule(context.device, e.value, null);
        }
    }
    VkShaderModule get(string key) {
        auto ptr = key in shaderMap;
        if(ptr) return *ptr;

        compile(key);
        auto mod = readSpv(key);
        shaderMap[key] = mod;
        return mod;
    }
private:
    enum COMPILER = "glslangValidator.exe";
    KisvContext context;
    string srcDirectory;
    string destDirectory;
    VkShaderModule[string] shaderMap;

    void compile(string key) {
        import std.string : strip;
        import std.process : execute, Config;

        string src = srcDirectory ~ key;
        string dest = destDirectory ~ key ~ ".spv";

        if(spirvAlreadyCompiled(src, dest)) {
            return;
        }

        auto result = execute(
            [
                COMPILER,
                "-V",
                "-Os",
                "-t",
                //"--target-env vulkan1.1",
                "-o",
                dest,
                src
            ],
            null,   // env
            Config.suppressConsole
        );

        if(result.status != 0) {
            auto o = result.output.strip;
            throw new Exception("Shader compilation failed %s".format(o));
        }
    }
    bool spirvAlreadyCompiled(string src, string dest) {
        // TODO - check whether the spv exists and was created later than the src
        return false;
    }
    VkShaderModule readSpv(string key) {
        import std.file : read;

        ubyte[] bytes = cast(ubyte[])read(destDirectory ~ key ~ ".spv");

        VkShaderModuleCreateInfo info = {
            sType: VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
            flags: 0,
            codeSize: bytes.length,    // in bytes
            pCode: cast(uint*)bytes.ptr
        };

        VkShaderModule handle;
        check(vkCreateShaderModule(context.device, &info, null, &handle));
        return handle;
    }
}