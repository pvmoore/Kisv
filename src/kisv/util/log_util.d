module kisv.util.log_util;

import kisv.all;
import std.stdio : File;

private __gshared File logFile;

__gshared static this() {
    import std;
    if(!exists(".logs/")) mkdir(".logs/");
    logFile = File(".logs/kisv.log", "wb");
}

__gshared static ~this() {
    logFile.close();
}

void log(A...)(string fmt, lazy A args) {
    logFile.write(format(fmt, args));
    logFile.write("\n");
    logFile.flush();
}

void logStructure(T)(T f, string prefix = null) if(__traits(compiles, T.sType.offsetof + T.pNext.offsetof)) {
    string prefixStr = prefix ? "%s = ".format(prefix) : "";
    log("%s%s {", prefixStr, typeof(f).stringof);

    auto maxPropertyLength = getAllProperties!T().map!(it=>it.length).maxElement() + 2;
    string s;

    foreach(m; __traits(allMembers, typeof(f))) {
        if(m=="sType" || m=="pNext") continue;

        s = m ~ " " ~ (".".repeat(maxPropertyLength-m.length));

        static if(isInteger!(typeof(__traits(getMember, f, m)))) {
            log("  %s %,3d", s, __traits(getMember, f, m));
        } else {
            log("  %s %s", s, __traits(getMember, f, m));
        }
    }
    log("}");
}