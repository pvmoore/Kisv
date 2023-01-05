module kisv.maths.float4;

import kisv.all;
import std.math : isClose;

struct float4 {
    float x = 0;
    float y = 0;
    float z = 0;
    float w = 0;

    ref float r() { return x; }
	ref float g() { return y; }
	ref float b() { return z; }
	ref float a() { return w; }
    void r(float v) { x = v; }
    void g(float v) { y = v; }
    void b(float v) { z = v; }
    void a(float v) { w = v; }

    float* ptr() { return &x; }
    float opIndex(int i) { assert(i >= 0 && i<4); return (&x)[i]; }
	float opIndexAssign(float value, int i) { assert(i >= 0 && i<4); ptr()[i] = value; return value; }

    bool opEquals(inout float4 o) {
        if(!isClose!(float, float)(x, o.x)) return false;
        if(!isClose!(float, float)(y, o.y)) return false;
        if(!isClose!(float, float)(z, o.z)) return false;
        if(!isClose!(float, float)(w, o.w)) return false;
        return true;
	}
    size_t toHash() {
        uint* p = cast(uint*)&x;
        ulong a = 5381;
        a  = (a << 7) + p[0];
        a ^= (a << 13) + p[1];
        a  = (a << 19) + p[2];
        a ^= (a << 23) + p[3];
        return a;
    }
    string toString() {
        return "(%5.%f, %5.%f, %5.%f, %5.%f)".format(x, y, z, w);
    }
}