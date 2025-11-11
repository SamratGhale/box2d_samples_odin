package main

import "core:container/small_array"
import "core:encoding/json"
import "core:fmt"
import b2 "vendor:box2d"
import "base:runtime"
import "core:os"
import "vendor:glfw"
import "core:path/filepath"
import "core:strings"

/*
This file contains code relating to levels in the game

In this game the hirarchy is level and room in that order
*/

level_flags_enum :: enum u64{
    COMPLETED,
    CONNECTOR
}

level_flags :: bit_set[level_flags_enum; u64]

level :: struct {
    rooms      : map[string]room,
    flags      : level_flags,
    name       : string,
    curr_room  : string,
    initilized : bool,
    new_room_buff : [255]u8`json:"-"`,
}

room_flags_enum :: enum u64{
    INITILIZED,
    COMPLETED,
    CONNECTOR,

    //Clockwise if set to true,
    //counter clockwise if set to false
    ROTATION_CLOCKWISE,
}

room_flags :: bit_set[room_flags_enum; u64]

rotation_state :: enum {
    None,
    ROTATING,
    ROTATION_COMPLETE,
}


room :: struct {
    //Position in the world
    pos            : [2]i32,
    world_id       : b2.WorldId `json:"-"`,
    flags          : room_flags,

    //This will be set to whichever shape the player is standing on
    ground_id      : b2.ShapeId `json:"-"`,

    entities       : [dynamic]entity `json:"-"`,
    entity_defs    : [dynamic]entity_def,

    //Represents whichever static_index the player has?
    player_index   : i32 `json:"-"`,

    //static_index -> array index on entities array
    //This will be filled when creating entities
    static_indexes : map[static_index]int `json:"-"`,

    //Represents the relation between different entities thruout the world
    relations      : map[^static_index][dynamic]static_index_global `json:"-"`,
    relations_serializeable  : map[static_index][dynamic]static_index_global,
    name           : string,
    name_buf       : [255]u8 `fmt:"-" json:"-"`,

    rot_state      : rotation_state,
    zoom           : f32,
    initilized     : bool,
}


/*
level_create_new :: proc(game: ^game_state, curr_room : ^room){
{
//Capsule
def := entity_get_default_def({12,0})
def.shape_type = .polygonShape
def.flags += {.POLYGON_IS_BOX}
def.size = {4, 8}
def.scale = 1.0

def.body_def.type = .kinematicBody
def.body_def.angularVelocity = .5
append(&curr_room.entity_defs, def)
}
{
//Capsule
def := entity_get_default_def({-12,0})
def.shape_type = .polygonShape
def.flags += {.POLYGON_IS_BOX}
def.size = {4, 8}
def.scale = 1.0

def.body_def.type = .kinematicBody
def.body_def.angularVelocity = .5
def.body_def.rotation = b2.MakeRot(DEG2RAD * 90)
append(&curr_room.entity_defs, def)
}
{
//Capsule
def := entity_get_default_def({0,0})
def.shape_type = .polygonShape
def.flags += {.POLYGON_IS_BOX, .NO_ROTATION}
def.size = {4, 4}
def.scale = 1.0

def.body_def.type = .kinematicBody
append(&curr_room.entity_defs, def)
}
{
//Capsule
def := entity_get_default_def({0,-12})
def.shape_type = .polygonShape
def.flags += {.POLYGON_IS_BOX}
def.body_def.angularVelocity = .5
def.body_def.rotation = b2.MakeRot(DEG2RAD * 90)
def.size = {8, 4}
def.scale = 1.0

def.body_def.type = .kinematicBody
append(&curr_room.entity_defs, def)
}
{
//Capsule
def := entity_get_default_def({0,12})
def.shape_type = .polygonShape
def.flags += {.POLYGON_IS_BOX}
def.size = {8, 4}
def.scale = 1.0

def.body_def.type = .kinematicBody
def.body_def.angularVelocity = .5
append(&curr_room.entity_defs, def)
}

{

//Player
def := entity_get_default_def({0,9})
def.shape_type = .polygonShape
def.flags += {.POLYGON_IS_BOX, .JUMPING}
def.size = {1, 1}
def.scale = .5
def.body_def.gravityScale = 0.1
def.type = .PLAYER

def.body_def.type = .dynamicBody
append(&curr_room.entity_defs, def)
}

curr_room.zoom = 20
curr_room.name = "first"

level_reload(game, curr_room)
}
*/

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

        if def.type == .PLAYER{
            curr_room.player_index = i32(i)
        }

        //Add to static indexes
        if new_entity.index != nil do curr_room.static_indexes[new_entity.index^] = i
    }

    /*
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
    */

    curr_room.initilized = true
}

level_get_curr_room :: proc "c" (game: ^game_state) -> ^room{
    curr_level := &game.levels[game.curr_level]
    if curr_level == nil || !curr_level.initilized do return nil

    room  := &curr_level.rooms[curr_level.curr_room]
    return room
}


level_get_all :: proc "c" (game:^game_state, index : ^static_index_global) -> (^level, ^room, ^entity){
    curr_level := &game.levels[index.level]
    curr_room  := &curr_level.rooms[index.room]

    entity_index := curr_room.static_indexes[index.index]
    entity       := &curr_room.entities[entity_index]

    return curr_level, curr_room, entity
}

//Handle level creations here?
level_drop_callback :: proc "c" (window: glfw.WindowHandle, count: i32, paths: [^]cstring){
    context = runtime.default_context()

    for i in 0..<count{
        path := string(paths[i])
        data, ok := os.read_entire_file_from_filename(path)

        if !ok{
            fmt.eprintln("Failed to load the file!")
            return
        }


        level_name := filepath.stem(path)

        level_name = strings.clone(level_name)

        game.levels[level_name] = {}

        curr_level := &game.levels[level_name]
        curr_level.name, _ = strings.clone(level_name)

        game.curr_level = strings.clone(level_name)

        if len(data) > 0{

            unmarshall_err := json.unmarshal(data, curr_level)

            if unmarshall_err != nil{
                fmt.eprintln("Failed to unmarshal the file!")
                return
            }else{

                for room_name in &curr_level.rooms{
                    curr_room := &curr_level.rooms[room_name]

                    level_reload(&game, curr_room)

                    for key, val in curr_room.relations_serializeable{
                        index  := curr_room.static_indexes[key]
                        entity := curr_room.entities[index]

                        curr_room.relations[entity.index] = {}
                        for v in val do append(&curr_room.relations[entity.index], v)
                    }


                }
            }
            delete(data)
        }else{
            //New level init
            //Don't create a new room?
        }

        curr_level.initilized = true
    }


}


level_save :: proc(game: ^game_state, curr_level: ^level){


    //relation serializeable

    for key, &curr_room in curr_level.rooms{
        clear(&curr_room.relations_serializeable)
        for key, val in curr_room.relations{

            if key != nil{
                curr_room.relations_serializeable[key^] = {}
                for v in val{
                    append(&curr_room.relations_serializeable[key^], v)
                }
            }
        }
    }



    err := os.make_directory("levels")


    level_path := fmt.tprintf("levels/%s.json", curr_level.name)

    data, json_err := json.marshal(curr_level^, {pretty = true ,use_enum_names = true})
    success := os.write_entire_file_or_err(level_path, data)
    fmt.println(success)
}









