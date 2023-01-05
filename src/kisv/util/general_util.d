module kisv.util.general_util;

import kisv.all;
import std.traits : isSomeFunction;

void throwIf(bool result) {
    if(result) {
        throw new Exception("Expectation failed");
    }
}
void throwIf(bool result, string msg) {
    if(result) {
        throw new Exception(msg);
    }
}
void throwIf(A...)(bool result, string fmt, A args) {
    if(result) {
        string msg = format(fmt, args);
        throw new Exception(msg);
    }
}

T as(T,K)(K k) {
    return cast(T)k;
}

bool isSet(T,E)(T value, E flag) if((is(T==enum) || isInteger!T) && (is(E==enum) || isInteger!E)) {
    return (value & flag) == flag;
}
bool isUnset(T,E)(T value, E flag) if((is(T==enum) || isInteger!T) && (is(E==enum) || isInteger!E)) {
    return (value & flag) == 0;
}

T maxOf(T)(T a, T b) if(isInteger!T || isReal!T) {
    return a > b ? a : b;
}
T minOf(T)(T a, T b) if(isInteger!T || isReal!T) {
    return a < b ? a : b;
}

template isStruct(T) {
	const bool isStruct = is(T==struct);
}
template isObject(T) {
    const bool isObject = is(T==class) || is(T==interface);
}
template isInteger(T) {
    const bool isInteger =
        is(T==byte)  || is(T==ubyte)  ||
        is(T==short) || is(T==ushort) ||
        is(T==int)   || is(T==uint)   ||
        is(T==long)  || is(T==ulong)  ||

        is(T==const(int));
}
template isReal(T) {
    const bool isReal = is(T==float) || is(T==double);
}

string[] getAllProperties(T)() if(isStruct!T || isObject!T) {
	string[] props;
	foreach(m; __traits(allMembers, T)) {
		static if(!isSomeFunction!(__traits(getMember, T, m)) && m!="Monitor") {
			props ~= m;
		}
	}
	return props;
}

string repeat(string s, long count) {
    if(count<=0) return "";
    auto app = appender!(string[]);
    for(auto i=0; i<count; i++) {
        app ~= s;
    }
    return app.data.join();
}

/*
 *  auto b = enumToString!VkFormatFeatureFlagBits(bits);
 */
string enumToString(E)(uint bits,) if (is(E == enum)) {
    import std.traits : EnumMembers;
    import std.format : format;
     import core.bitop : popcnt;

    string buf = "[";
    foreach(i, e; EnumMembers!E) {

        if(bits & e) {
            // Skip enum members that have more than one bit set
            if(popcnt(e) > 1) continue;

            string s = "%s".format(e);
            buf ~= (buf.length==1 ? "" : ", ") ~ s;
        }
    }
    return buf ~ "]";
}

string mbToString(ulong size) {
    enum MB = 1024.0*1024;
    return "%.2f MB".format(size / MB);
}

ulong alignedTo(ulong value, ulong alignment) {
    ulong mask = alignment-1;
    return (value + mask) & ~mask;
}