module kisv.misc.keys;

import kisv.all;

private enum KeyBody =
    "string value;
    this() @disable;
    this(string key) {
        this.value = key;
    }
    string toString() {
        return value;
    }";


struct PoolKey { mixin(KeyBody); }
struct LayoutKey { mixin(KeyBody); }
