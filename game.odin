package main

import b2 "vendor:box2d"
import "core:fmt"
import "vendor:glfw"
import "core:math"
import "core:container/small_array"
import im "shared:odin-imgui"

LPUM :: 100

/*
*/

game_mode :: enum {
    PLAY,
    EDIT,
    LEVEL_VIEW,
}

rotation_dir :: enum {
    CLOCKWISE,
    COUNTER_CLOCKWISE,
}

game_state :: struct {

    levels        : map[string]level,
    curr_level    : string,
	is_initilized, is_edit : bool,
	time           : f32,

	mode           : game_mode,
	rot_dir        : rotation_dir,
	//selected_index : i32,
	pause          : bool,

	using interface : interface_state `json:"-"`,
}

game_init :: proc(game: ^game_state){


    game.levels = {}
    game.curr_level = "hello"
    game.levels[game.curr_level] = {}
    curr_level := &game.levels[game.curr_level]
    curr_level.curr_room = "room1"
    curr_level.rooms[curr_level.curr_room] = {}
    game.selected_index = -1

    curr_room := level_get_curr_room(game)

    //level_create_new(game, curr_room)
}

game_step :: proc(game: ^game_state){

    curr_level := &game.levels[game.curr_level]

    if curr_level == nil do return
    if !curr_level.initilized do return


    curr_room := level_get_curr_room(game)

    using curr_room

    if ion_is_pressed(.SPACE) do game.pause = !game.pause


    if !game.pause || ion_is_pressed(.ACTION_UP)
    {
        if game.selected_index >= 0{
            entity := &entities[game.selected_index]
            pos    := b2.Body_GetPosition(entity.body_id)
            points_add(&state.draw.points, pos, 20.0, b2.HexColor.Plum)

            if game.edit_mode == .VERTICES{
                def := &entity_defs[game.selected_index]

                if def.shape_type == .polygonShape || def.shape_type == .chainSegmentShape{
                    point := small_array.get(def.vertices, game.selected_vertex_index)
                    pos += point
                }else if def.shape_type == .capsuleShape{
                    pos += def.centers[game.selected_vertex_index]
                }
                circle_add(&state.draw.circles, pos, 0.5, b2.HexColor.Box2DYellow)
            }
        }

        if curr_room.rot_state != .None{
            player := &curr_room.entities[curr_room.player_index]
            entities_update_while_rotating(game, curr_room, player)
        }else{
            if game.mode == .PLAY{
                entities_update(game, curr_room)
                b2.World_Step(world_id, 0.016667,4)
            }

        }

    }
    state.draw.cam.zoom = curr_room.zoom
    b2.World_Draw(world_id, &state.draw.debug_draw)
}


game_editor :: proc(game: ^game_state) {
    curr_room := level_get_curr_room(game)
    using curr_room

    if im.BeginTabItem("Editor", nil, {.Leading}){

        if im.BeginCombo("Game mode", fmt.ctprint(game.mode)){

            for type in game_mode{
                if im.Selectable(fmt.ctprint(type), game.mode == type) do game.mode = type
            }
            im.EndCombo()
        }


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












