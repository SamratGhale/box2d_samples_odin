#+feature dynamic-literals
package main

import b2 "vendor:box2d"
import array "core:container/small_array"
import "core:math"
import "core:fmt"

/*
	This file handles the things related to entity
	It doesn't/shouldn't depend on Other bigger structs like Level Room and Game
	This is done to create simplicity in the code
*/

static_index :: i32

entity_flags_enum :: enum u64{
    POLYGON_IS_BOX,
    JUMPING,
    NO_FLIP,
    GAP_LEFT,
    GAP_RIGHT,
    NO_ROTATION, //This means that the object will remain static
}
entity_flags :: bit_set[entity_flags_enum]


static_index_global :: struct {
	index  : i32,
	level, room : string,
	offset : b2.Vec2,
}

entity_type :: enum {
	PLAYER = 1 << 0,
	ENEMY  = 1 << 1,
	NPC    = 1 << 2,
	DOOR   = 1 << 3,
	PORTAL = 1 << 4,
	BOUNDING_BOX = 1 << 5,
	KEY    = 1 << 6,
	DOOR_OPENED = 1 << 7,
}

entity :: struct {
	type         : entity_type,
	flags        : entity_flags,
	body_id      : b2.BodyId,
	shape_id     : b2.ShapeId,
	index : ^static_index,
}

//I've not used box2d's structs to store the information to create shapes
//Because we can use the same data for multiple types of shapes
//i.e. we can use same radius value for creating circle or capsule
//instead of using b2.Capsule and b2.Circle

entity_def :: struct {
	body_def     : b2.BodyDef,
	shape_def    : b2.ShapeDef,
    shape_type   : b2.ShapeType,
    type         : entity_type,
    flags        : entity_flags,
    index        : static_index,

    //For circle and capsule
    radius       : f32,
    //For scale
    scale        : f32,
    //For capsule
    centers      : [2]b2.Vec2,
    //For box polygons
    size         : b2.Vec2,
    //For chain
    is_loop      : bool,

    //For polygons and chain
    vertices     : array.Small_Array(b2.MAX_POLYGON_VERTICES, b2.Vec2),
    name_buf     : [255]u8 `fmt:"-" json:"-"`,

}

gravity_map : map[f32]b2.Vec2 = {
    0   = {0, -9.8 * LPUM},
    90  = {-9.8    * LPUM, 0},
    180 = {0,  9.8 * LPUM},
    270 = {9.8     * LPUM, 0},
    360 = {0, -9.8 * LPUM},
}

//Returns a default entity def which contains default value for all the shapes
entity_get_default_def :: proc(pos : b2.Vec2) -> entity_def{
	ret : entity_def

	body_def := b2.DefaultBodyDef()
	body_def.position = pos
	body_def.type = .staticBody

	ret.shape_def = b2.DefaultShapeDef()
	ret.body_def  = body_def
	//For all
	ret.scale = 1.0

	//For circle
	ret.radius = 5
	ret.size = {2, 2}

	//for dynamic polygon
	vs : [4]b2.Vec2 = {{-10.0, -10.0}, {-10.0, 10.0}, {10.0, 10.0}, {10.0, -10.0}}

	for v in vs do array.push_back(&ret.vertices, v)

	ret.centers = {{-10, 0}, {10, 0}}
	return ret
}

/**
	Create entity from entity def
**/
entity_create_new :: proc(def : entity_def, world_id: b2.WorldId, entity_len : i32 = 0) -> entity{

	def    := def
	new_entity : entity

	def.shape_def.filter.categoryBits = u64(def.type)
	new_entity.body_id = b2.CreateBody(world_id, def.body_def)
	new_entity.type    = def.type
	new_entity.flags   = def.flags


	if def.index != 0{
		new_entity.index  = new(static_index)
		new_entity.index^ = def.index
	}

	if def.type == .PLAYER{
    	def.shape_def.filter.maskBits ~= u64(entity_type.DOOR_OPENED)
	}

	/*
		Prepare data structures for creating box2d shapes,
	*/

	switch def.shape_type{
		case .circleShape:{
			circle := b2.Circle{radius = def.radius}
			fmt.println(circle)
			new_entity.shape_id = b2.CreateCircleShape(new_entity.body_id, def.shape_def, circle)
		}
		case .capsuleShape:{
			capsule := b2.Capsule{center1 = def.centers[0], center2 = def.centers[1], radius = def.radius}
			new_entity.shape_id = b2.CreateCapsuleShape(new_entity.body_id, def.shape_def, capsule)
		}
		case .chainSegmentShape:{
			chain_def := b2.DefaultChainDef()
			verts :[dynamic]b2.Vec2

			for v in array.slice(&def.vertices){

				//if it's not a looped chain then it needs two defination
				if !def.is_loop do append(&verts, v)

				append(&verts, v)
			}

			slice := array.slice(&def.vertices)

			chain_def.points = &verts[0]
			chain_def.count  = i32(len(verts))
			chain_def.isLoop = def.is_loop

			c := b2.CreateChain(new_entity.body_id, chain_def)

			shapes_data : [10]b2.ShapeId
			shapes := b2.Body_GetShapes(new_entity.body_id, shapes_data[:])

			for shape in shapes{
				b2.Shape_SetUserData(shape, rawptr(uintptr(entity_len)))
			}
		}
		case .segmentShape:{

		}
		case .polygonShape:{
			poly : b2.Polygon
			if .POLYGON_IS_BOX in def.flags{
				def.size *= def.scale
				poly = b2.MakeBox(def.size.x, def.size.y)
			}else{
				points := make([dynamic]b2.Vec2, 0)

				for p, i in array.slice(&def.vertices){
					if i >= int(def.vertices.len) do break

					append_elem(&points, p * def.scale)
				}
				sort_points_ccw(points[:])

				hull := b2.ComputeHull(points[:])
				poly = b2.MakePolygon(hull, 0)
				delete(points)
			}

			new_entity.shape_id = b2.CreatePolygonShape(new_entity.body_id, def.shape_def, poly)
		}
	}

	b2.Shape_SetUserData(new_entity.shape_id, rawptr(uintptr(entity_len)))
	return new_entity
}

entities_update_while_rotating :: proc(game: ^game_state, curr_room : ^room, player: ^entity){
    if curr_room.rot_state == .ROTATION_COMPLETE{
        curr_room.rot_state = .None
        return
    }

    if game.rot_dir == .CLOCKWISE{
        state.draw.cam.rotation -= ROTATION_SPEED
    }else{
        state.draw.cam.rotation += ROTATION_SPEED
    }

    degree : f32 = -ROTATION_SPEED

    if game.rot_dir == .CLOCKWISE do degree = ROTATION_SPEED

    angle : f32 = DEG2RAD * degree

    rot := b2.MakeRot((360 - state.draw.cam.rotation) * DEG2RAD)

    for &entity in &curr_room.entities{
        if .NO_ROTATION in entity.flags{
       	    current_pos := b2.Body_GetPosition(entity.body_id)
            rotated_x := current_pos.x * math.cos(angle) - current_pos.y * math.sin(angle)
            rotated_y := current_pos.x * math.sin(angle) + current_pos.y * math.cos(angle)
            b2.Body_SetTransform(entity.body_id, {rotated_x, rotated_y}, rot)
        }
    }

    //Check if rotation complete
    curr_rot := state.draw.cam.rotation
    if int(abs(curr_rot)) % 90 == 0{
        if curr_rot < 0 do state.draw.cam.rotation = 360 + curr_rot

        curr_rot = state.draw.cam.rotation

        //Set gravity according to the rotation
        gravity := gravity_map[curr_rot]
        b2.World_SetGravity(curr_room.world_id, gravity)
        player.flags += {.JUMPING}
        curr_room.rot_state = .ROTATION_COMPLETE
        state.draw.cam.rotation = f32(int(abs(state.draw.cam.rotation)) % 360)
    }
}


entities_update :: proc(game: ^game_state, curr_room : ^room){
    for &entity in &curr_room.entities{
        if entity.type == .PLAYER{
            player_update(game, curr_room, &entity)
        }
    }
}











