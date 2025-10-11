package main

import "core:fmt"
import im "shared:odin-imgui"
import "shared:odin-imgui/imgui_impl_glfw"
import "shared:odin-imgui/imgui_impl_opengl3"
import gl "vendor:OpenGL"
import b2 "vendor:box2d"
import "vendor:glfw"

WIDTH :: 1600
HEIGHT :: 900

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

                    im.EndTabItem()
                }

                ion_editor(game)
                im.EndTabBar()
            }
        }
        im.End()
    }

    /*
    if im.Begin("Editor"){
    im.BeginTabBar("Editor tab")

    ion_editor_shape(game)
    im.EndTabBar()
    }
    im.End()
    */
}

ion_editor :: proc(game: ^game_state) {
    if im.BeginTabItem("Game") {
        for type in game_mode {
            if im.RadioButton(fmt.ctprint(type), game.mode == type) {
                game.mode = type
            }
        }
        im.EndTabItem()
    }
    curr_room := level_get_curr_room(game)
    using curr_room

    if game.mode == .EDIT{

        if im.BeginTabItem("Editor"){
            if im.BeginCombo("edit mode", fmt.ctprint(game.edit_mode)){

                for type in interface_edit_modes{
                    if im.Selectable(fmt.ctprint(type), game.edit_mode == type) do game.edit_mode = type
                }
                im.EndCombo()
            }

            if game.selected_index != -1{
                im.Separator()

                entity  := &entities[game.selected_index]
                def_old := entity_defs[game.selected_index]
                def     := &entity_defs[game.selected_index]

                if im.CollapsingHeader("Entity Misc"){
                    if im.BeginCombo("Entity type", fmt.ctprint(def.type)){
                        for type in entity_type{
                            if im.Selectable(fmt.ctprint(type)) do def.type = type
                        }
                        im.EndCombo()
                    }

                    for flag in entity_flags_enum{
                        contains := flag in def.flags
                        if im.Checkbox(fmt.ctprint(flag), &contains) do def.flags ~= {flag}
                    }

                    im.SliderFloat("Scale", &def.scale, 0, 10)

                    //Static static_indexes

                    if def.index != 0{
                        //TODO: static index editor
                    }
                    im.InputInt("Static Index", &def.index)
                }
                im.Separator()

                if im.CollapsingHeader("Shape edit"){
                    interface_shape_def_editor(game, curr_room)
                }
                im.Separator()
                if im.CollapsingHeader("Body edit"){
                    interface_body_def_editor(game, curr_room)
                }

                if def_old != def^ do level_reload(game, curr_room)
            }
            im.EndTabItem()
        }
        if game.edit_mode == .INSERT{
            if ion_is_pressed(.MOUSE_RIGHT){
                fmt.println("Right click")
                mpos :[2]f32= {f32(state.input.mouse_x), f32(state.input.mouse_y)}
                mpos = camera_convert_screen_to_world(&state.draw.cam, mpos)

                def := entity_get_default_def(mpos)
                def.type = .NPC
                def.shape_type = .polygonShape
                def.flags += {.POLYGON_IS_BOX}
                append(&entity_defs, def)
                level_reload(game, curr_room)
            }
        }
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

        ion_process_inputs()

        ion_update_frame(&state)


        interface_handle_input(&game)


        game_step(&game)

        draw_flush(&state.draw)

        update_ui(&game)
        ion_end_frame(&state)
    }
    ion_cleanup(&state)
}
