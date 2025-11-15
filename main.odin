package main

import "core:fmt"
import im "shared:odin-imgui"
import "shared:odin-imgui/imgui_impl_glfw"
import "core:os"
import "shared:odin-imgui/imgui_impl_opengl3"
import "core:encoding/json"
import gl "vendor:OpenGL"
import b2 "vendor:box2d"
import "vendor:glfw"

WIDTH :: 1000
HEIGHT :: 1000

TITLE :: "My Window!"

GL_MAJOR_VERSION :: 4
GL_MINOR_VERSION :: 5

//sample_ctx :SampleContext
state: ion_state

game: game_state

main :: proc() {

    state.width         = WIDTH
    state.height        = HEIGHT
    state.title         = "ion demo"
    state.drop_callback = level_drop_callback

    ion_init(&state)


    game_init(&game)

    state.draw.show_ui = true

    for !ion_window_should_close(&state) {
        ion_update_frame(&state)

        interface_handle_input(&game)

        game_step(&game)

        draw_flush(&state.draw)

        interface_update_ui(&game)

        ion_end_frame(&state)
    }
    ion_cleanup(&state)
}
