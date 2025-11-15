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


    game.selected_index = -1
    game.mode = .EDIT

    bounding_box_filter.maskBits ~= u64(entity_type.DOOR_OPENED)
    bounding_box_filter.maskBits ~= u64(entity_type.KEY)
    bounding_box_filter.maskBits ~= u64(entity_type.PLAYER)

    //level_create_new(game, curr_room)
}

game_step :: proc(game: ^game_state){

    curr_level := &game.levels[game.curr_level]

    curr_room := level_get_curr_room(game)

    if curr_room == nil || !curr_room.initilized do return

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













