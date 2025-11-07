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


update_ui :: proc(game: ^game_state) {

    max_workers: i32 = 8
    menu_width: f32 = 180.0

    if state.draw.show_ui {

        if im.Begin("Tools", &state.draw.show_ui) {

            if im.BeginTabBar("Control Tabs") {
                if im.BeginTabItem("Controls") {
                    debug_draw := &state.draw.debug_draw

                    im.Checkbox("Shapes", &debug_draw.drawShapes)
                    im.Checkbox("Joints", &debug_draw.drawJoints)
                    im.Checkbox("Joint Extras", &debug_draw.drawJointExtras)
                    im.Checkbox("Bounds", &debug_draw.drawBounds)
                    im.Checkbox("Contact Points", &debug_draw.drawContacts)
                    im.Checkbox("Contact Normals", &debug_draw.drawContactNormals)
                    im.Checkbox("Contact Inpulses", &debug_draw.drawContactImpulses)
                    im.Checkbox("Contact Features", &debug_draw.drawContactFeatures)
                    im.Checkbox("Friction Inpulses", &debug_draw.drawFrictionImpulses)
                    im.Checkbox("Mass ", &debug_draw.drawMass)
                    im.Checkbox("Body Names", &debug_draw.drawBodyNames)
                    im.Checkbox("Graph Colors", &debug_draw.drawGraphColors)
                    im.Checkbox("Islands ", &debug_draw.drawIslands)

                    im.SliderFloat("Rotation", &state.draw.cam.rotation, 0, 360)

                    im.EndTabItem()
                }

                game_editor(game)
                interface_edit_levels(game)

                im.EndTabBar()
            }
        }
        im.End()
    }
}
main :: proc() {

    //sample_register("Bodies", "Kinematic", kinematic_create)
    //sample := sample_entries[0].create_fcn(&sample_ctx)

    state.width = WIDTH
    state.height = HEIGHT
    state.title = "ion demo"

    ion_init(&state)


    game: game_state

    game_init(&game)



    state.draw.show_ui = true

    for !ion_window_should_close(&state) {
        ion_update_frame(&state)

        interface_handle_input(&game)

        game_step(&game)

        draw_flush(&state.draw)

        update_ui(&game)

        ion_end_frame(&state)
    }
    ion_cleanup(&state)
}
