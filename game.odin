package main

import b2 "vendor:box2d"
import "core:fmt"
import "vendor:glfw"
import "core:math"
import "core:container/small_array"
import im "shared:odin-imgui"

LPUM :: 128

/*
*/

game_mode :: enum {
    PLAY,
    EDIT,
    LEVEL_VIEW,
    ZONE_VIEW,
}

rotation_dir :: enum {
    CLOCKWISE,
    COUNTER_CLOCKWISE,
}

game_state :: struct {

    zones         : map[string]zone,
    curr_zone     : string,
	is_initilized, is_edit : bool,
	time         : f32,

	mode           : game_mode,
	rot_dir        : rotation_dir,
	//selected_index : i32,
	pause          : bool,

	using interface : interface_state,
}

game_init :: proc(game: ^game_state){

    //b2.SetLengthUnitsPerMeter(LPUM)

    game.curr_zone = "one"
    game.zones[game.curr_zone] = {}
    curr_zone := &game.zones[game.curr_zone]

    curr_zone.curr_level = "apple"
    curr_zone.levels[curr_zone.curr_level] = {}

    curr_level := &curr_zone.levels[curr_zone.curr_level]
    curr_level.curr_room = "room1"
    curr_level.rooms[curr_level.curr_room] = {}

    curr_room := level_get_curr_room(game)

    level_create_new(game, curr_room)


    /*
    game.world_id = b2.CreateWorld(b2.DefaultWorldDef())

    body_def := b2.DefaultBodyDef()
    body_def.type = .kinematicBody
    body_def.position.x = 2.0 * 2.0


    game.body_id = b2.CreateBody(game.world_id, body_def)

    box      := b2.MakeBox(0.1, 1.0)
    shape_id := b2.CreatePolygonShape(game.body_id, b2.DefaultShapeDef(), box)
    game.time = 0
    */
}

game_step :: proc(game: ^game_state){
    curr_room := level_get_curr_room(game)

    using curr_room

    if ion_is_pressed(.SPACE) do game.pause = !game.pause

    if !game.pause || ion_is_pressed(.ACTION_UP)
    {

        for &entity, i in &entities{
            if i32(i) == game.selected_index{
                pos :=  b2.Body_GetPosition(entity.body_id)
                points_add(&state.draw.points, pos, 20.0, b2.HexColor.Plum)
                //circle_add(&state.draw.circles, pos, 40, b2.HexColor.Green)
            }
        }
        game.time += 1.0/60.0

        b2.World_Step(world_id, 0.016,10)
    }
    b2.World_Draw(world_id, &state.draw.debug_draw)

}
