module kisv.misc.VkVersion;

import kisv.all;

struct VkVersion {
private:
    int major;
    int minor;
    int patch;
public:
    this(int major, int minor, int patch) {
        this.major = major;
        this.minor = minor;
        this.patch = patch;
    }
    this(int v) {
        this(v>>>22, (v >>> 12) & 0x3ff, v & 0xfff);
    }

    int intValue() {
        return (major << 22) | (minor << 12) | patch;
    }

    bool isEqualOrGreaterThan(VkVersion other) {
        if(major > other.major) return true;
        if(major < other.major) return false;
        if(minor > other.minor) return true;
        if(minor < other.minor) return false;
        return patch >= other.patch;
    }

    string toString() {
        return "VkVersion{%s, %s, %s}".format(major, minor, patch);
    }
}