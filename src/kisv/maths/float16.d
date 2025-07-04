module kisv.maths.float16;

import kisv.all;

/**
 * This matrix is laid out in column major order (the natural ordering for OpenGL and Vulkan)
 */
struct float16 {
    float4 col0;
    float4 col1;
    float4 col2;
    float4 col3;

    static float16 columnMajor(float[] v...) { assert(v.length==16);
		float16 m;
		m.col0 = float4(v[0],  v[1],  v[2],  v[3]);
		m.col1 = float4(v[4],  v[5],  v[6],  v[7]);
		m.col2 = float4(v[8],  v[9],  v[10], v[11]);
		m.col3 = float4(v[12], v[13], v[14], v[15]);
		return m;
	}
    static float16 rowMajor(float[] v...) { assert(v.length==16);
		float16 m;
		m.col0 = float4(v[0], v[4], v[8],  v[12]);
		m.col1 = float4(v[1], v[5], v[9],  v[13]);
		m.col2 = float4(v[2], v[6], v[10], v[14]);
		m.col3 = float4(v[3], v[7], v[11], v[15]);
		return m;
	}
    static float16 identity() {
		float16 m;
		m.col0.x = 1;
        m.col1.y = 1;
        m.col2.z = 1;
        m.col3.w = 1;
		return m;
	}
	static float16 scale(float x, float y, float z) {
		float16 m = identity();
		m.col0.x = x;
        m.col1.y = y;
        m.col2.z = z;
		return m;
	}

    bool opEquals(float16 m) {
		return col0 == m.col0 && col1 == m.col1 && col2 == m.col2 && col3 == m.col3;
	}
	size_t toHash() {
		return col0.toHash() ^
			   col1.toHash() * 7 +
			   col2.toHash() * 13 ^
			   col3.toHash() * 19;
	}

    /** Display in row major order */
    string toString() {
    	return format("%5.2f %5.2f %5.2f %5.2f\n%5.2f %5.2f %5.2f %5.2f\n%5.2f %5.2f %5.2f %5.2f\n%5.2f %5.2f %5.2f %5.2f\n",
			col0[0], col1[0], col2[0], col3[0],
			col0[1], col1[1], col2[1], col3[1],
			col0[2], col1[2], col2[2], col3[2],
			col0[3], col1[3], col2[3], col3[3]
        );
    }
}
