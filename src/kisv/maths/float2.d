module kisv.maths.float2;

import kisv.all;
import std.math : isClose;

struct float2 {
    float x = 0;
    float y = 0;

    ref float u() { return x; }
    ref float v() { return y; }
    void u(float v) { x = v; }
    void v(float v) { y = v; }

    float* ptr() { return &x; }
    float opIndex(int i) { assert(i >= 0 && i<2); return (&x)[i]; }
	float opIndexAssign(float value, int i) { assert(i >= 0 && i<2); ptr()[i] = value; return value; }

    bool opEquals(inout float2 o) {
        if(!isClose!(float, float)(x, o.x)) return false;
        if(!isClose!(float, float)(y, o.y)) return false;
        return true;
	}
    size_t toHash() {
        uint* p = cast(uint*)&x;
        ulong a = 5381;
        a  = (a << 7) + p[0];
        a ^= (a << 13) + p[1];
        return a;
    }
    string toString() {
        return "(%5.%f, %5.%f)".format(x, y);
    }
}