#+feature dynamic-literals
package main

import b2 "vendor:box2d"
import "base:runtime"

ROTATION_SPEED :: 3
ROT_RIGHT_0  : [2]f32 : {50, 40}
ROT_RIGHT_270: [2]f32 : {-40, 50}
ROT_RIGHT_180: [2]f32 : {50, -40}
ROT_RIGHT_90 : [2]f32 : {40, 50}

ROT_LEFT_0  : [2]f32 : {-50, 40}
ROT_LEFT_270: [2]f32 : {-40, -50}
ROT_LEFT_180: [2]f32 : {-50, -40}
ROT_LEFT_90 : [2]f32 : {40, -50}

ROT_LEFT : map[f32]b2.Vec2 = {
    0   = {-50,  -50},
    270 = {40, -50},
    180 = {-50, 50},
    90  = {-40,  -50},
}

ROT_RIGHT : map[f32]b2.Vec2 = {
    0   = {50,  -50},
    270 = {40, 50},
    180 = {50, 40},
    90  = {-40,  50},
}

overlap_callback_left :: proc "c" (shape_id: b2.ShapeId, ctx : rawptr) -> bool{
    game := cast(^game_state)ctx

    room := level_get_curr_room(game)

    if room != nil{
        player := &room.entities[room.player_index]
        player.flags -= {.GAP_LEFT}
    }
    return true
}

overlap_callback_right :: proc "c" (shape_id: b2.ShapeId, ctx : rawptr) -> bool{
    game := cast(^game_state)ctx

    room := level_get_curr_room(game)

    if room != nil{
        player := &room.entities[room.player_index]
        player.flags -= {.GAP_RIGHT}
    }
    return true
}

player_collision_callback :: proc "c" (shape_id: b2.ShapeId, ctx: rawptr) -> bool{
    context = runtime.default_context()
    game   := cast(^game_state)ctx


    curr_room := level_get_curr_room(game)

    if shape_id == b2.nullShapeId do return true

    index := u32(uintptr(b2.Shape_GetUserData(shape_id)))

    //Handle doors here

    if index >= u32(len(curr_room.entities)) do return true

    entity := &curr_room.entities[index]

    #partial switch entity.type{
    case .PLAYER, .BOUNDING_BOX:{
        //Ignore all
    }
    case .DOOR:{
        //Do the thing
        if entity.index == nil{
            break
        }

        indexes := &curr_room.relations[entity.index]

        for &index in indexes{
            new_zone, new_level, new_room, new_entity := level_get_all(game, &index)

            //Teleport
            if entity.type == .DOOR{
                game.selected_index = 0
                game.curr_zone = index.zone
                new_zone.curr_level = index.level
                new_level.curr_room = index.room

                player := &new_room.entities[new_room.player_index]

                new_pos := b2.Body_GetPosition(new_entity.body_id) + index.offset
                b2.Body_SetTransform(player.body_id, new_pos, b2.Body_GetRotation(player.body_id))
                b2.Body_SetLinearVelocity(player.body_id, {0, 0})
            }
        }
    }
    }
    return true
}

gaps := entity_flags{.GAP_LEFT, .GAP_RIGHT}

player_update_rotation :: proc(game: ^game_state, curr_room: ^room, player: ^entity){
    if gaps & player.flags != {}{
        curr_room.rot_state = .ROTATING

    }
}















