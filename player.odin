#+feature dynamic-literals
package main

/*
    Most of the function here are either callback functions declared by box2d
    or funtion that takes player as arguement
*/

import b2 "vendor:box2d"
import "core:fmt"
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
    0   = {-1.2,  -1.2},
    270 = { 1.2,  -1.2},
    180 = {-1.2,   1.2},
    90  = {-1.2,  -1.2},
}

ROT_RIGHT : map[f32]b2.Vec2 = {
    0   = {1.2,  -1.2},
    270 = {1.2,   1.2},
    180 = {1.2,   1.2},
    90  = {-1.2,  1.2},
}

bounding_box_filter := b2.DefaultQueryFilter()

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

/*
    This is the main function where game logic is defined
    What happens when player collides with which entity

    NOTE: maybe create different callback for different entity type,
          creating different callback
*/
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

/*
    Check if player is on edge and update player position according to it
    It also starts rotating the level
*/

player_update_rotation :: proc(game: ^game_state, curr_room: ^room, player: ^entity){
    if gaps & player.flags != {}{
        curr_room.rot_state = .ROTATING

        //Maybe set rotation to every room
        rot := state.draw.cam.rotation

        pos := b2.Body_GetPosition(player.body_id)

        if .GAP_RIGHT in player.flags{
            pos += ROT_RIGHT[rot]

            switch rot{
            case 0, 270:
                game.rot_dir = .COUNTER_CLOCKWISE
            case 180, 90:
                game.rot_dir = .CLOCKWISE
            }
        }else{
            pos += ROT_LEFT[rot]

            switch rot{
            case 0, 270:
                game.rot_dir = .CLOCKWISE
            case 180, 90:
                game.rot_dir = .COUNTER_CLOCKWISE
            }

        }

        b2.Body_SetTransform(player.body_id, pos, b2.Body_GetRotation(player.body_id))
        b2.Body_SetLinearVelocity(player.body_id, {})
    }
}

/*
    Gives which key to use as asdw according to the curr_room's rotation
*/
player_get_rotated_asdw :: proc(curr_room : ^room) -> (asdwjump : [5]ion_button){

    switch state.draw.cam.rotation{
    case 0:
        asdwjump = {.A, .S, .D, .W, .W}
    case 90:
        asdwjump = {.S, .D, .W, .A, .W}
    case 270:
        asdwjump = {.W, .A, .S, .D, .W}
    case 180:
        asdwjump = {.D, .W, .A, .S, .W}
    }
    return
}


/*
    Updates the jumping state of player and ground shape_id
    Gets all the collision of player and goes thru it to set the ground_id
    Also sets the gaps accodring to shape_id type
*/
player_update_jump :: proc(game: ^game_state, curr_room : ^room, using player: ^entity){
    normal  : b2.Vec2
    c_shape : b2.ShapeId

    rot           := state.draw.cam.rotation
    contacts_data : [20]b2.ContactData
    contacts      := b2.Body_GetContactData(body_id, contacts_data[:])

    for contact in contacts{
        normal = contact.manifold.normal
        c_shape = contact.shapeIdA

        if contact.shapeIdB != shape_id{
            normal *= 1
            c_shape = contact.shapeIdB
        }

        switch rot{
        case 0:
            if (abs(normal.y) > abs(normal.x)){
                if normal.y > 0{
                    curr_room.ground_id = c_shape
                    flags -= {.JUMPING}
                    break
                }
            }
        case 180:
            if (abs(normal.y) > abs(normal.x)){
                if normal.y < 0{
                    curr_room.ground_id = c_shape
                    flags -= {.JUMPING}
                    break
                }
            }
        case 90:
            if (abs(normal.x) > abs(normal.y)){
                if normal.x > 0{
                    curr_room.ground_id = c_shape
                    flags -= {.JUMPING}
                    break
                }
            }
        case 270:
            if (abs(normal.x) > abs(normal.y)){
                if normal.x < 0{
                    curr_room.ground_id = c_shape
                    flags -= {.JUMPING}
                    break
                }
            }
        }
    }

    //Basically if there is floor with no NO_FLIP in flags remote gap

    if .JUMPING not_in flags{
        flags += {.GAP_LEFT, .GAP_RIGHT }

        if curr_room.ground_id != b2.nullShapeId{
            floor_index := u32(uintptr(b2.Shape_GetUserData(curr_room.ground_id)))

            if floor_index > 0 && floor_index < u32(len(curr_room.entities)){
                floor := &curr_room.entities[floor_index]

                if .NO_FLIP in floor.flags{
                    flags -= {.GAP_LEFT, .GAP_RIGHT}
                }
            }
        }
    }
}

/*
    The bounding box is a way to determine if the player is one the edge of a entity or not
    It is basically two rectangle on both ends of the player, we do AABB collsion on the world
*/
player_get_bounding_box :: proc(rot: f32, p: b2.Vec2) -> (left, right : b2.AABB){

    //Get rotation of the player and rotate the aabbs

    right = {{0.7, -1}, {1, 1}}
    left = {{-1, -1}, {-0.7, 1}}

    switch (int(rot) % 360) {
    case 270, -90:
        right.lowerBound = swizzle(right.lowerBound, 1, 0)
        right.upperBound = swizzle(right.upperBound, 1, 0)
        left.lowerBound  = swizzle(left.lowerBound, 1, 0)
        left.upperBound  = swizzle(left.upperBound, 1, 0)
        right.lowerBound.x += 1
        right.upperBound.x += 1
        left.lowerBound.x  += 1
        left.upperBound.x  += 1
    case 90, -270:
        right.lowerBound = swizzle(right.lowerBound, 1, 0)
        left.lowerBound  = swizzle(left.lowerBound, 1, 0)
        right.upperBound = swizzle(right.upperBound, 1, 0)
        left.upperBound  = swizzle(left.upperBound, 1, 0)
    case 180, -180:
        right.lowerBound.y += 1
        left.lowerBound.y  += 1
        right.upperBound.y += 1
        left.upperBound.y  += 1
    }

    right.lowerBound  += p
    right.upperBound  += p
    left.lowerBound   += p
    left.upperBound   += p

    return
}

player_update_bounding_box :: proc(game: ^game_state, curr_room: ^room, player: ^entity){
    if curr_room.ground_id != b2.nullShapeId{
        pos := b2.Body_GetPosition(player.body_id)

        ground_index := u32(uintptr(b2.Shape_GetUserData(curr_room.ground_id)))
        ground       := &curr_room.entities[ground_index]

        aabb_left, aabb_right := player_get_bounding_box(state.draw.cam.rotation, pos)

        /*
        points_left  : [4]b2.Vec2
        points_left[0] = {aabb_left.lowerBound.x, aabb_left.upperBound.y}
        points_left[1] = {aabb_left.upperBound.x, aabb_left.upperBound.y}
        points_left[2] = {aabb_left.upperBound.x, aabb_left.lowerBound.y}
        points_left[3] = {aabb_left.lowerBound.x, aabb_left.lowerBound.y}


        DrawPolygonFcn(&points_left[0], 4, b2.HexColor.Black, &state.draw)

        points_right  : [4]b2.Vec2
        points_right[0] = {aabb_right.lowerBound.x, aabb_right.upperBound.y}
        points_right[1] = {aabb_right.upperBound.x, aabb_right.upperBound.y}
        points_right[2] = {aabb_right.upperBound.x, aabb_right.lowerBound.y}
        points_right[3] = {aabb_right.lowerBound.x, aabb_right.lowerBound.y}

        DrawPolygonFcn(&points_right[0], 4, b2.HexColor.Black, &state.draw)
        */

        result := b2.World_OverlapAABB(curr_room.world_id, aabb_right, bounding_box_filter, overlap_callback_right, game)
        result  = b2.World_OverlapAABB(curr_room.world_id, aabb_left,  bounding_box_filter, overlap_callback_left,  game)
    }
}

//Handles movement
player_handle_movement :: proc(curr_room : ^room, player: ^entity){
    rot := state.draw.cam.rotation
    velocity : b2.Vec2
    curr_vel := b2.Body_GetLinearVelocity(player.body_id)
    asdw     := player_get_rotated_asdw(curr_room)

    a, s, d, w, jump := asdw[0], asdw[1], asdw[2], asdw[3], asdw[4]

    //Basic movement
    if ion_is_down(d) do velocity.x += 10
    if ion_is_down(a) do velocity.x -= 10
    if ion_is_down(w) do velocity.y += 10
    if ion_is_down(s) do velocity.y -= 10

    //If we're jumping then increase the velocity
    if ion_is_down(jump) && .JUMPING not_in player.flags{
        if rot == 0 || rot == 180{
            velocity  *= {0, 3}
        }else{
            velocity  *= {3, 0}
        }

        player.flags += {.JUMPING}
    }else if ion_is_down(jump){
        velocity = {}
    }

    if velocity != {0, 0}{
        //This does the job of not being about to move linearly while jumping
        if velocity.x == 0{
            velocity.x = curr_vel.x
        }
        if velocity.y == 0{
            velocity.y = curr_vel.y
        }

        b2.Body_SetLinearVelocity(player.body_id, velocity)
    }
}


/*
    The main function of this file
    It is called on game.odin if the entity type is player

    1. updates the player jumping statestate
    2. update bounding box
    3. update player collision
    4. handle inputs for player movement
    5. update player rotation
*/
player_update :: proc(game : ^game_state, curr_room : ^room, player: ^entity){
    player_update_jump(game, curr_room, player)

    if .JUMPING not_in player.flags do player_update_bounding_box(game, curr_room, player)


    //Update collisions
    {
        pos := b2.Body_GetPosition(player.body_id)
        aabb : b2.AABB = {lowerBound = pos, upperBound = pos + 1}

        filter := b2.DefaultQueryFilter()
        filter.maskBits ~= u64(entity_type.BOUNDING_BOX)
        filter.maskBits ~= u64(entity_type.PLAYER)

        tree := b2.World_OverlapAABB(curr_room.world_id, aabb, filter, player_collision_callback, game)
    }
    player_handle_movement(curr_room, player)

    if .JUMPING not_in player.flags do player_update_rotation(game, curr_room, player)
}

















