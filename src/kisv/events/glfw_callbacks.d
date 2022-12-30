module kisv.events.glfw_callbacks;

import kisv.all;

extern(C):

// void errorCallback(int error, const(char)* description) nothrow {
//     log("glfw error: %s %s", error, description);
// }
void onKeyEvent(GLFWwindow* window, int key, int scancode, int action, int mods) nothrow {
	if(key == GLFW_KEY_ESCAPE && action == GLFW_PRESS) {
		glfwSetWindowShouldClose(window, true);
		return;
	}
	//bool shiftClick = (mods & GLFW_MOD_SHIFT) != 0;
	//bool ctrlClick	= (mods & GLFW_MOD_CONTROL) != 0;
	//bool altClick	= (mods & GLFW_MOD_ALT ) != 0;

    try{
        // foreach(l; g_vulkan.windowEventListeners) {
        //     l.keyPress(key, scancode, cast(KeyAction)action, mods);
        // }
	}catch(Throwable t) {

    }
}
void onWindowFocusEvent(GLFWwindow* window, int focussed) nothrow {
	//this.log("window focus changed to %s FOCUS", focussed?"GAINED":"LOST");
    try{
        // foreach(l; g_vulkan.windowEventListeners) {
        //     l.focus(focussed!=0);
        // }
    }catch(Throwable t) {

    }
}
void onIconifyEvent(GLFWwindow* window, int iconified) nothrow {
	//this.log("window %s", iconified ? "iconified":"non iconified");
    try{
        // g_vulkan.isIconified = iconified!=0;
        // foreach(l; g_vulkan.windowEventListeners) {
        //     l.iconify(iconified!=0);
        // }
    }catch(Throwable t) {

    }
}
void onMouseClickEvent(GLFWwindow* window, int button, int action, int mods) nothrow {
	bool pressed = (action == 1);
	double x,y;
	glfwGetCursorPos(window, &x, &y);

	try{
        // foreach(l; g_vulkan.windowEventListeners) {
        //     l.mouseButton(button, cast(float)x, cast(float)y, pressed, mods);
        // }
    }catch(Throwable t) {

    }

    // auto mouseState = &g_vulkan.mouseState;

	// if(pressed) {
	// 	mouseState.button = button;
	// } else {
	// 	mouseState.button = -1;
	// 	if(mouseState.isDragging) {
	// 		mouseState.isDragging = false;
	// 		mouseState.dragEnd = float2(x,y);
	// 	}
	// }
}
void onMouseMoveEvent(GLFWwindow* window, double x, double y) nothrow {
	//this.log("mouse move %s %s", x, y);
	try{
        // foreach(l; g_vulkan.windowEventListeners) {
        //     l.mouseMoved(cast(float)x, cast(float)y);
        // }
	}catch(Throwable t) {

    }

    // auto mouseState = &g_vulkan.mouseState;

	// mouseState.pos = Vector2(x,y);
	// if(!mouseState.isDragging && mouseState.button >= 0) {
	// 	mouseState.isDragging = true;
	// 	mouseState.dragStart = Vector2(x,y);
	// }
}
void onScrollEvent(GLFWwindow* window, double xoffset, double yoffset) nothrow {
	//this.log("scroll event: %s %s", xoffset, yoffset);
	try{
        double x,y;
        glfwGetCursorPos(window, &x, &y);

        // g_vulkan.mouseState.wheel += yoffset;

        // foreach(l; g_vulkan.windowEventListeners) {
        //     l.mouseWheel(cast(float)xoffset, cast(float)yoffset, cast(float)x, cast(float)y);
        // }
	}catch(Throwable t) {

    }
}
void onMouseEnterEvent(GLFWwindow* window, int enterred) nothrow {
	//this.log("mouse %s", enterred ? "enterred" : "exited");
    try{
        // foreach(l; g_vulkan.windowEventListeners) {
        //     double x,y;
        //     glfwGetCursorPos(window, &x, &y);
        //     l.mouseEnter(x,y, enterred!=0);
        // }
    }catch(Throwable t) {

    }
}
