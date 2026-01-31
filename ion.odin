/*
    Ion is a single file odin library that intregates dear imgui,
    glfw input and box2d for 2d graphics and rapid game prototyping
*/
package main

import "base:runtime"
import "core:fmt"
import "core:math"
import im "shared:odin-imgui"
import "shared:odin-imgui/imgui_impl_glfw"
import "shared:odin-imgui/imgui_impl_opengl3"
import gl "vendor:OpenGL"
import b2 "vendor:box2d"
import "vendor:glfw"


ion_draw_state :: struct {}

ion_state :: struct {
	window :         glfw.WindowHandle,
	draw :           Draw,
	restart, pause : bool,
	substep_count :  u32,

	//Must be set before calling ion_init
	width, height :  i32,
	title :          cstring,
	time :           f32,
	text_line :      u32,
	input :          ion_input,
	drop_callback :  glfw.DropProc,
}

ion_mouse_wheel_callback :: proc "c" (
	window : glfw.WindowHandle,
	x_offset, y_offset : f64,
) {
	//context = runtime.default_context()
	//state.draw.cam.zoom -= f32(y_offset)/5.0
	state.input.mouse_wheel_x = x_offset
	state.input.mouse_wheel_y = y_offset
}

ion_mouse_position_callback :: proc "c" (
	window : glfw.WindowHandle,
	x_pos, y_pos : f64,
) {
	//context = runtime.default_context()
	state.input.mouse_x = x_pos
	state.input.mouse_y = y_pos
}

/*
When a json file is droppped validate it and add to the game
*/
ion_init :: proc(state : ^ion_state) {

	assert(glfw.Init() == true)

	glfw.WindowHint(glfw.SCALE_TO_MONITOR, 1)


	state.window = glfw.CreateWindow(
		state.width,
		state.height,
		state.title,
		nil,
		nil,
	)

	if state.window == nil {
		fmt.eprintln("GLFW has failed to load the window.")
	}
	glfw.SetScrollCallback(state.window, ion_mouse_wheel_callback)
	glfw.SetCursorPosCallback(state.window, ion_mouse_position_callback)
	glfw.SetDropCallback(state.window, state.drop_callback)

	glfw.MakeContextCurrent(state.window)
	glfw.SwapInterval(1)

	gl.load_up_to(GL_MAJOR_VERSION, GL_MINOR_VERSION, glfw.gl_set_proc_address)

	//Imgui
	im.CHECKVERSION()
	im.CreateContext()

	io := im.GetIO()
	io.ConfigFlags += {
		.NavEnableKeyboard,
		.NavEnableGamepad,
		.DpiEnableScaleFonts,
		.DockingEnable,
		.ViewportsEnable,
	}

	imgui_impl_glfw.InitForOpenGL(state.window, true)
	imgui_impl_opengl3.Init("#version 150")

	state.draw.cam = camera_init()

	display_w, display_h := glfw.GetFramebufferSize(state.window)
	state.draw.cam.width = display_w
	state.draw.cam.height = display_h
	state.draw.cam.zoom = 10

	state.draw.show_ui = true

	draw_create(&state.draw, &state.draw.cam)

	gl.ClearColor(0.2, 0.2, 0.2, 1.0)
}

/*

*/

ion_update_frame :: proc(state : ^ion_state) {

	state.input.mouse_wheel_x = 0
	state.input.mouse_wheel_y = 0
	glfw.PollEvents()

	ion_process_inputs()

	gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)
	new_width, new_height := glfw.GetWindowSize(state.window)
	state.draw.cam.width = new_width
	state.draw.cam.height = new_height

	display_w, display_h := glfw.GetFramebufferSize(state.window)
	gl.Viewport(0, 0, display_w, display_h)

	imgui_impl_opengl3.NewFrame()
	imgui_impl_glfw.NewFrame()

	im.NewFrame()

	if state.draw.debug_draw.drawBounds || state.draw.debug_draw.drawMass {
		x, y := glfw.GetWindowPos(state.window)
		im.SetNextWindowPos({f32(x), f32(y) + 10})
		im.SetNextWindowSize(
			{f32(state.draw.cam.width), f32(state.draw.cam.height - 10)},
		)
		im.SetNextWindowBgAlpha(0)
	}

	state.text_line = 0
}


ion_end_frame :: proc(state : ^ion_state) {


	im.Render()
	imgui_impl_opengl3.RenderDrawData(im.GetDrawData())

	backup_current_window := glfw.GetCurrentContext()
	im.UpdatePlatformWindows()
	im.RenderPlatformWindowsDefault()
	glfw.MakeContextCurrent(backup_current_window)

	glfw.SwapBuffers(state.window)
}

ion_cleanup :: proc(state : ^ion_state) {
	imgui_impl_opengl3.Shutdown()
	imgui_impl_glfw.Shutdown()
}

ion_window_should_close :: proc(state : ^ion_state) -> b32 {
	return glfw.WindowShouldClose(state.window)
}

//Button stuffs
ion_button_state :: struct {
	//stores if the key is up or down
	ended_down :       bool,

	//stores if there was change in the key in this frame
	half_trans_count : i32,

	/*
    we can get the pressed and release
    pressed = half_trans_count is >0 and ended_down = false
    release = half_trans_count is >0 and ended_down = true
    */
}

ion_button :: enum {
	W,
	S,
	A,
	D,
	ACTION_UP,
	ACTION_DOWN,
	ACTION_LEFT,
	ACTION_RIGHT,
	LEFT_SHOULDER,
	RIGHT_SHOULDER,
	BACK,
	ENTER,
	ESCAPE,
	SPACE,
	DEL,
	F1,
	F2,
	F3,
	MOUSE_LEFT,
	MOUSE_RIGHT,
	LEFT_CTRL,
	RIGHT_CTRL,
	TAB,
	SEMICOLON,
	SHIFT,
	LEFT_ALT,
	RIGHT_ALT,
	DELETE,
	C,
	V,
	R,
}

//reprensets one input device, i.e keyboard, gamepad
ion_controller :: struct {
	is_connected, is_analog : b32,
	stick_x, stick_y :        f32,
	buttons :                 [ion_button]ion_button_state,
}

ion_input :: struct {
	dt_for_frame :                                            f32,
	mouse_wheel_x, mouse_wheel_y, mouse_x, mouse_y, mouse_z : f64,
	mouse_buttons :                                           ion_button_state,
	controllers :                                             [2]ion_controller,
}


ion_process_keyboard_input :: proc(
	button : ^ion_button_state,
	is_down : bool,
) {
	if (button.ended_down != is_down) {
		button.ended_down = is_down
		button.half_trans_count += 1
	}
}


ion_is_pressed :: proc(button : ion_button, index : int = 0) -> bool {
	input := &state.input
	keyboard_input := &state.input.controllers[index]

	key := keyboard_input.buttons[button]
	return key.ended_down && (key.half_trans_count > 0)
}

ion_is_down :: proc(button : ion_button, index : int = 0) -> bool {
	input := &state.input
	keyboard_input := &state.input.controllers[index]

	key := keyboard_input.buttons[button]
	return key.ended_down
}


ion_process_inputs :: proc() {
	keyboard_input := &state.input.controllers[0]

	window := state.window
	keyboard_input.is_connected = true
	keyboard_input.is_analog = false


	for &button in &keyboard_input.buttons {
		button.half_trans_count = 0
	}
	buttons := &keyboard_input.buttons

	ion_process_keyboard_input(
		&buttons[.W],
		glfw.GetKey(window, glfw.KEY_W) == glfw.PRESS,
	)
	ion_process_keyboard_input(
		&buttons[.S],
		glfw.GetKey(window, glfw.KEY_S) == glfw.PRESS,
	)
	ion_process_keyboard_input(
		&buttons[.A],
		glfw.GetKey(window, glfw.KEY_A) == glfw.PRESS,
	)
	ion_process_keyboard_input(
		&buttons[.D],
		glfw.GetKey(window, glfw.KEY_D) == glfw.PRESS,
	)
	ion_process_keyboard_input(
		&buttons[.ACTION_UP],
		glfw.GetKey(window, glfw.KEY_UP) == glfw.PRESS,
	)
	ion_process_keyboard_input(
		&buttons[.ACTION_DOWN],
		glfw.GetKey(window, glfw.KEY_DOWN) == glfw.PRESS,
	)
	ion_process_keyboard_input(
		&buttons[.ACTION_LEFT],
		glfw.GetKey(window, glfw.KEY_LEFT) == glfw.PRESS,
	)
	ion_process_keyboard_input(
		&buttons[.ACTION_RIGHT],
		glfw.GetKey(window, glfw.KEY_RIGHT) == glfw.PRESS,
	)
	ion_process_keyboard_input(
		&buttons[.LEFT_SHOULDER],
		glfw.GetKey(window, glfw.KEY_Q) == glfw.PRESS,
	)
	ion_process_keyboard_input(
		&buttons[.RIGHT_SHOULDER],
		glfw.GetKey(window, glfw.KEY_E) == glfw.PRESS,
	)
	ion_process_keyboard_input(
		&buttons[.BACK],
		glfw.GetKey(window, glfw.KEY_BACKSPACE) == glfw.PRESS,
	)
	ion_process_keyboard_input(
		&buttons[.ENTER],
		glfw.GetKey(window, glfw.KEY_ENTER) == glfw.PRESS,
	)
	ion_process_keyboard_input(
		&buttons[.ESCAPE],
		glfw.GetKey(window, glfw.KEY_ESCAPE) == glfw.PRESS,
	)
	ion_process_keyboard_input(
		&buttons[.SPACE],
		glfw.GetKey(window, glfw.KEY_SPACE) == glfw.PRESS,
	)
	ion_process_keyboard_input(
		&buttons[.F1],
		glfw.GetKey(window, glfw.KEY_F1) == glfw.PRESS,
	)
	ion_process_keyboard_input(
		&buttons[.F2],
		glfw.GetKey(window, glfw.KEY_F2) == glfw.PRESS,
	)
	ion_process_keyboard_input(
		&buttons[.F3],
		glfw.GetKey(window, glfw.KEY_F3) == glfw.PRESS,
	)
	ion_process_keyboard_input(
		&buttons[.DEL],
		glfw.GetKey(window, glfw.KEY_DELETE) == glfw.PRESS,
	)
	ion_process_keyboard_input(
		&buttons[.MOUSE_LEFT],
		glfw.GetMouseButton(window, glfw.MOUSE_BUTTON_LEFT) == glfw.PRESS,
	)
	ion_process_keyboard_input(
		&buttons[.MOUSE_RIGHT],
		glfw.GetMouseButton(window, glfw.MOUSE_BUTTON_RIGHT) == glfw.PRESS,
	)
	ion_process_keyboard_input(
		&buttons[.LEFT_CTRL],
		glfw.GetKey(window, glfw.KEY_LEFT_CONTROL) == glfw.PRESS,
	)
	ion_process_keyboard_input(
		&buttons[.RIGHT_CTRL],
		glfw.GetKey(window, glfw.KEY_RIGHT_CONTROL) == glfw.PRESS,
	)
	ion_process_keyboard_input(
		&buttons[.TAB],
		glfw.GetKey(window, glfw.KEY_TAB) == glfw.PRESS,
	)
	ion_process_keyboard_input(
		&buttons[.SEMICOLON],
		glfw.GetKey(window, glfw.KEY_SEMICOLON) == glfw.PRESS,
	)
	ion_process_keyboard_input(
		&buttons[.SHIFT],
		glfw.GetKey(window, glfw.KEY_LEFT_SHIFT) == glfw.PRESS,
	)
	ion_process_keyboard_input(
		&buttons[.LEFT_ALT],
		glfw.GetKey(window, glfw.KEY_LEFT_ALT) == glfw.PRESS,
	)
	ion_process_keyboard_input(
		&buttons[.RIGHT_ALT],
		glfw.GetKey(window, glfw.KEY_RIGHT_ALT) == glfw.PRESS,
	)
	ion_process_keyboard_input(
		&buttons[.DELETE],
		glfw.GetKey(window, glfw.KEY_DELETE) == glfw.PRESS,
	)
	ion_process_keyboard_input(
		&buttons[.C],
		glfw.GetKey(window, glfw.KEY_C) == glfw.PRESS,
	)
	ion_process_keyboard_input(
		&buttons[.V],
		glfw.GetKey(window, glfw.KEY_V) == glfw.PRESS,
	)
	ion_process_keyboard_input(
		&buttons[.R],
		glfw.GetKey(window, glfw.KEY_R) == glfw.PRESS,
	)
}
