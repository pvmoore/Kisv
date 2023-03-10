module kisv.events.KisvEvents;

import kisv.all;

final class KisvEvents {
public:
    this() {

    }
private:
}
//──────────────────────────────────────────────────────────────────────────────────────────────────
enum EventT {
    KEY_UP,
    KEY_DOWN,
    MOUSE_BUTTON,
}

struct KeyEvent {
    uint code;
}
struct MouseButtonEvent {
    uint button;
}

struct Event {
    EventT type;
    union event {
        KeyEvent key;
        MouseButtonEvent mouseButton;
    }
}