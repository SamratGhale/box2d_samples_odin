package main

import b2 "vendor:box2d"
import "core:container/small_array"
import "core:fmt"
import "core:os"
import "core:strings"

/*
	This file contains code relating to levels in the game

	In this game the hirarchy is zone, level and room in that order
*/


//Zone def start
zone_flags_enum :: enum u64{
	COMPLETED,
}

zone_flags :: bit_set[zone_flags_enum; u64]

zone :: struct {
	levels     : map[string]level,
	flags      : zone_flags,
	name       : string,
	curr_level : string,
}

//Zone def end


level_flags_enum :: enum u64{
	COMPLETED,
	CONNECTOR
}

level_flags :: bit_set[level_flags_enum; u64]

level :: struct {
	rooms     : map[string]room,
	flags     : level_flags,
	name      : string,
	curr_room : string,
	name_buf  : [255]u8,
}


room_flags_enum :: enum u64{
	INITILIZED,
	COMPLETED,
	CONNECTOR,

	//Clockwise if set to true,
	//counter clockwise if set to false
	ROTATION_CLOCKWISE,

	//Rotation state
	ROTATING,

	//Only check this if ROTATING is true
	ROTATION_COMPLETE,
}

room_flags :: bit_set[room_flags_enum; u64]


room :: struct {
	//Position in the world
	pos            : [2]i32,
	world_id       : b2.WorldId,
	flags          : room_flags,

	//This will be set to whichever shape the player is standing on
	ground_id      : b2.ShapeId,

	entities       : [dynamic]entity,
	entity_defs    : [dynamic]entity_def,

	//Represents whichever static_index the player has?
	player_index   : i32,

	//static_index -> array index on entities array
	static_indexes : map[static_index]int,

	//Represents the relation between different entities thruout the world
	relations      : map[^static_index][dynamic]static_index_global,
	relations_serializeable  : map[static_index][dynamic]static_index_global,
	name           : string,
	name_buf       : [255]u8,
}


level_create_new :: proc(game: ^game_state, curr_room : ^room){
    //curr_room.world_id = b2.CreateWorld(b2.DefaultWorldDef())

    def := entity_get_default_def({0,0})
    def.shape_type = .capsuleShape
    def.flags += {.POLYGON_IS_BOX}
    def.size = {0.4, 4.0}
    def.scale = 1.0

    def.body_def.type = .kinematicBody
    def.body_def.position.x = 2.0 * 2.0

    append(&curr_room.entity_defs, def)

    level_reload(game, curr_room)
}

level_reload :: proc(game: ^game_state, using curr_room : ^room){

    clear(&entities)

    if world_id != b2.nullWorldId{
        b2.DestroyWorld(world_id)
    }

    {
        world_def := b2.DefaultWorldDef()
        world_def.gravity = {0, -9.8 * LPUM}
        world_def.enableSleep = false
        world_id = b2.CreateWorld(world_def)
    }

    clear(&static_indexes)

    for def, i in entity_defs{
        new_entity := entity_create_new(def, world_id, i32(i))
        append(&entities, new_entity)
    }

    clear(&relations_serializeable)

    for key, val in relations{
        if val != nil{
            relations_serializeable[key^] = {}

            for v in val{
                append(&relations_serializeable[key^], v)
            }
        }
    }

    clear(&relations)

    for key, val in relations_serializeable{
        index := static_indexes[key]
        entity := &entities[index]

        relations[entity.index] = {}

        for v in val do append(&relations[entity.index], v)
    }

}

level_get_curr_room :: proc(game: ^game_state) -> ^room{
    zone  := &game.zones[game.curr_zone]
    level := &zone.levels[zone.curr_level]
    room  := &level.rooms[level.curr_room]
    return room
}
