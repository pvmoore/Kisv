module demo;

import core.sys.windows.windows :
    HINSTANCE, LPSTR, MessageBoxA, CommandLineToArgvW, GetCommandLineW,
    MB_OK, MB_ICONEXCLAMATION;

import core.runtime;
import std.string   : toStringz, fromStringz;
import std.utf      : toUTF8;

import demo_hello_world;
import demo_ray_tracing;
import demo_rectangle;

pragma(lib, "user32.lib");

//extern(C) __gshared string[] rt_options = [
//    "gcopt=profile:1"
//];

interface DemoApplication {
    void initialise();
    void run();
    void destroy();
}

extern(Windows)
int WinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance, LPSTR lpCmdLine, int iCmdShow) {
	int result = 0;
    DemoApplication app;

    try{
        Runtime.initialize();

        auto args = getArgs();
        if(args.length > 1) {
            switch(args[1]) {
                case "raytracing":
                    app = new RayTracing();
                    break;
                case "rectangle":
                    app = new Rectangle();
                    break;
                case "helloworld":
                default:
                    app = new HelloWorld();
                    break;
            }
        } else {
            app = new HelloWorld();
        }
        app.initialise();
        app.run();

    }catch(Throwable e) {
		MessageBoxA(null, e.toString().toStringz(), "Error", MB_OK | MB_ICONEXCLAMATION);
		result = -1;
    }finally{
		if(app) app.destroy();
		Runtime.terminate();
	}

    return result;
}

private:

/**
 *  getArgs()[0] should always be the program name
 */
string[] getArgs() {
    int nArgs;
    auto ptr = CommandLineToArgvW(GetCommandLineW(), &nArgs);

    string[] arguments;
    if(ptr !is null && nArgs>0) {
        foreach(i; 0..nArgs) {
            auto arg = fromStringz!wchar(*ptr);
            arguments ~= arg.toUTF8();
            ptr++;
        }
    }
    return arguments;
}