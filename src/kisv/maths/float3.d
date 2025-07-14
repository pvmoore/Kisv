module kisv.maths.float3;

import kisv.all;
import std.math : isClose;

struct float3 {
    float x = 0;
    float y = 0;
    float z = 0;

    float* ptr() { return &x; }
    float opIndex(int i) { assert(i >= 0 && i<3); return (&x)[i]; }
	float opIndexAssign(float value, int i) { assert(i >= 0 && i<3); ptr()[i] = value; return value; }

    float3 opBinary(string op)(float rhs) const {
        return mixin("float3(x"~op~"rhs, y"~op~"rhs, z"~op~"rhs)");
    }
    float3 opBinary(string op)(float3 rhs) const {
        return mixin("float3(x"~op~"rhs.x, y"~op~"rhs.y, z"~op~"rhs.z)");
    }

    bool opEquals(inout float3 o) {
        if(!isClose!(float, float)(x, o.x)) return false;
        if(!isClose!(float, float)(y, o.y)) return false;
        if(!isClose!(float, float)(z, o.z)) return false;
        return true;
	}
    size_t toHash() {
        uint* p = cast(uint*)&x;
        ulong a = 5381;
        a  = (a << 7)  + p[0];
        a ^= (a << 13) + p[1];
        a  = (a << 19) + p[2];
        return a;
    }
    string toString() {
        return "(%5.%f, %5.%f, %5.%f)".format(x, y, z);
    }
}
