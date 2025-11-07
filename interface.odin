package main

import im "shared:odin-imgui"
import b2 "vendor:box2d"
import "base:runtime"
import "core:container/small_array"
import "core:fmt"

interface_edit_modes :: enum {
    ENTITY,      //For single entity
    VERTICES,    // For polygons edit
    INSERT,
    MULTI_ENTITY, //For multiple entities
}

interface_state :: struct {
    selected_index        : i32,
    edit_mode             : interface_edit_modes,
    selected_vertex_index : int,
    copied_def            : ^entity_def `json:"-"`,
    curr_static_index     : static_index_global,
}

saturate :: proc (f : f32)-> f32 {
    return (f < 0.0) ? 0.0 : (f > 1.0) ? 1.0 : f;
}

f32_to_u8_sat :: proc( val : f32)  -> u8{

    sat := saturate(val)
    sat *= 255
    sat += 0.5

    ret := cast(u8)sat
    return ret
}


float4_to_u32 :: proc(color : [4]f32) -> u32{
    out : u32
    out  =  u32(f32_to_u8_sat(color.a)) << 24
    out  |= u32(f32_to_u8_sat(color.r)) << 16
    out  |= u32(f32_to_u8_sat(color.g)) << 8
    out  |= u32(f32_to_u8_sat(color.b))
    return out
}


u32_to_float4 :: proc(color : u32) -> [4]f32{
    ret : [4]f32
    ret.a = f32((color >> 24) & 0xFF  ) / 255.0
    ret.r = f32((color >> 16) & 0xFF  ) / 255.0
    ret.g = f32((color >> 8)  & 0xFF  ) / 255.0
    ret.b = f32((color)       & 0xFF  ) / 255.0
    return ret
}


query_filter :: proc "c" (shape_id: b2.ShapeId, ctx : rawptr) -> bool{
    context = runtime.default_context()

    game := cast(^game_state)ctx

    index := i32(uintptr(b2.Shape_GetUserData(shape_id)))
    game.selected_index = index
    return true
}

interface_edit_entity :: proc(game: ^game_state, using curr_room : ^room){
    mpos :[2]f32= {f32(state.input.mouse_x), f32(state.input.mouse_y)}
    mpos = camera_convert_screen_to_world(&state.draw.cam, mpos)

    entity := &entities[game.selected_index]
    def    := &entity_defs[game.selected_index]

    #partial switch game.edit_mode{
    //Entity means we've selected a entity
    case .ENTITY:{
        if ion_is_down(.MOUSE_LEFT) && ion_is_down(.LEFT_ALT){
            def.body_def.position = mpos
            level_reload(game, curr_room)
        }else if ion_is_pressed(.DELETE){
            unordered_remove(&entity_defs, game.selected_index)
            game.selected_index = -1
            level_reload(game, curr_room)
        }else if ion_is_down(.LEFT_CTRL) && ion_is_pressed(.C){
            game.copied_def = def
        }else if ion_is_down(.LEFT_CTRL) && ion_is_pressed(.V){
            def := game.copied_def^
            def.body_def.position = mpos

            append(&entity_defs, def)
            level_reload(game, curr_room)
        }
    }
    case .VERTICES:{
        if def.shape_type == .capsuleShape{
            if ion_is_down(.LEFT_CTRL){
                mpos -= def.body_def.position
                def.centers[game.selected_vertex_index] = mpos
                level_reload(game, curr_room)
            }
        }else if def.shape_type == .polygonShape || def.shape_type == .chainSegmentShape{
            if ion_is_pressed(.MOUSE_RIGHT){
                mpos -= def.body_def.position

                small_array.push_back(&def.vertices, mpos)
                small_array.push_back(&def.vertices, mpos)
                level_reload(game, curr_room)
            }else if ion_is_down(.LEFT_CTRL){
                mpos -= def.body_def.position
                small_array.set(&def.vertices, game.selected_vertex_index, mpos)
                level_reload(game, curr_room)

            }else if ion_is_pressed(.DELETE){
                small_array.unordered_remove(&def.vertices, game.selected_vertex_index)

                if game.selected_vertex_index >= def.vertices.len{
                    game.selected_vertex_index -=1
                }
                level_reload(game, curr_room)
            }
        }
    }
    }
}

interface_handle_input :: proc(using game: ^game_state){
    if im.GetIO().WantCaptureMouse || im.GetIO().WantCaptureKeyboard do return

    curr_room := level_get_curr_room(game)

    if game.edit_mode == .VERTICES{

        if state.input.mouse_wheel_y != 0{
            def := curr_room.entity_defs[game.selected_index]

            v_len : i32

            if def.shape_type == .polygonShape || def.shape_type == .chainSegmentShape{
                v_len = i32(def.vertices.len)
            }else if def.shape_type == .capsuleShape{
                v_len =1
            }

            if state.input.mouse_wheel_y > 0{
                if game.selected_vertex_index >= int(v_len){
                    game.selected_vertex_index = 0
                }else{
                    game.selected_vertex_index += 1
                }
            }else if state.input.mouse_wheel_y < 0{
                if game.selected_vertex_index <= 0{
                    game.selected_vertex_index = int(v_len)
                }
                game.selected_vertex_index -= 1
            }
        }
    }else{
        state.draw.cam.zoom -= f32(state.input.mouse_wheel_y)/5.0
    }

    if ion_is_pressed(.MOUSE_LEFT){
        mpos :[2]f32= {f32(state.input.mouse_x), f32(state.input.mouse_y)}
        mpos = camera_convert_screen_to_world(&state.draw.cam, mpos)

        aabb : b2.AABB = {mpos, mpos + 1}

        r := b2.World_OverlapAABB(curr_room.world_id, aabb,  b2.DefaultQueryFilter(), query_filter, game)

        if r.leafVisits == 0{
            if !ion_is_down(.LEFT_ALT){
                game.selected_index = -1
                game.edit_mode = .INSERT
            }
        }else{
            game.edit_mode = .ENTITY
        }
    }

    if game.selected_index != -1{
        //Edit entity imgui
        interface_edit_entity(game, curr_room)
    }
}

PI :: 3.14159265358979323846
DEG2RAD :: PI/180.0
RAD2DEG :: 180.0/PI

interface_body_def_editor :: proc(game: ^game_state, curr_room: ^room){
    def_orig  :=  curr_room.entity_defs[game.selected_index]
    def       := &curr_room.entity_defs[game.selected_index]

    using def

    if im.BeginCombo("Body Type", fmt.ctprint(def.body_def.type)){
        for type in b2.BodyType{
            if im.Selectable(fmt.ctprint(type), def.body_def.type == type) do body_def.type = type
        }
        im.EndCombo()
    }

    im.SliderFloat2("Position", &body_def.position, -500, 500)
    im.InputFloat2("Position_", &body_def.position)

    angle := RAD2DEG * b2.Rot_GetAngle(def.body_def.rotation)

    if im.SliderFloat("Rotation", &angle, 0, 359){
        rad := DEG2RAD * angle
        body_def.rotation = b2.MakeRot(rad)
    }

    im.SliderFloat2("Linear velocity", &body_def.linearVelocity, 0, 500)
    im.SliderFloat("Angular velocity", &body_def.angularVelocity,0, 500)
    im.SliderFloat("Linear Damping",   &body_def.linearDamping,  0, 500)
    im.SliderFloat("Angular Damping",  &body_def.angularDamping, 0, 500)
    im.SliderFloat("Gravity Scale",    &body_def.gravityScale,   0, 100)

    im.Checkbox("Fixed rotation", &body_def.fixedRotation)

    if im.InputText("Body Name", cstring(&def.name_buf[0]), 255){
        def.body_def.name = cstring(&def.name_buf[0])
        level_reload(game, curr_room)
    }

}

interface_shape_def_editor :: proc(game: ^game_state, curr_room : ^room){
    def_orig  :=  curr_room.entity_defs[game.selected_index]
    def       := &curr_room.entity_defs[game.selected_index]

    using def.shape_def

    if im.BeginCombo("Shape Type", fmt.ctprint(def.shape_type)){
        for type in b2.ShapeType{
            if im.Selectable(fmt.ctprint(type), def.shape_type == type) do def.shape_type = type
        }
        im.EndCombo()
    }

    if def.shape_type == .circleShape{
        im.SliderFloat("radius", &def.radius, 0, 359)
    }else if def.shape_type == .polygonShape{

        if .POLYGON_IS_BOX in def.flags{
            im.SliderFloat2("Size", &def.size, 0, 100)
        }else{

        }
    }else if def.shape_type == .capsuleShape{
        im.SliderFloat2("Center 1", &def.centers[0], -500, 500)
        im.SliderFloat2("Center 2", &def.centers[1], -500, 500)
        im.SliderFloat("Radius", &def.radius, 0, 359)

    }else if def.shape_type == .chainSegmentShape{
        im.Checkbox("is loop", &def.is_loop)
    }

    im.SliderFloat("Density", &def.shape_def.density, 0, 100)

    if im.Button("Flip horizontally") do flip_points(small_array.slice(&def.vertices), .Horizontal)
    if im.Button("Flip vertically")   do flip_points(small_array.slice(&def.vertices), .Vertical)

    if im.TreeNode("Events and contacts"){

        im.Checkbox("Is sensor",               &isSensor)
       	im.Checkbox("Enable Sensor Events",    &enableSensorEvents)
        im.Checkbox("Enable Contact Events",   &enableContactEvents)
        im.Checkbox("Enable Hit Events",       &enableHitEvents)
        im.Checkbox("Enable Presolve Events",  &enablePreSolveEvents)
        im.Checkbox("Invoke contact Creation", &invokeContactCreation)
        im.Checkbox("Update body mass ",       &updateBodyMass)
        im.TreePop()
    }

    //Surface material
    if im.TreeNode("Material") {
        im.Separator()
        using def.shape_def.material
        im.SliderFloat("Friction",           &friction,          0, 1)
        im.SliderFloat("Restitution",        &restitution,       0, 1)
        im.SliderFloat("Rolling Resistance", &rollingResistance, 0, 1)
        im.SliderFloat("Tangent Speed",      &tangentSpeed,      0, 1)
        im.InputInt("User material id",      &userMaterialId)

        //Colorpicker

        if im.TreeNode("Color"){
            color_f32 := u32_to_float4(customColor)
            if im.ColorPicker4("Custom Color", &color_f32, {.Uint8, .InputRGB}){
                customColor = float4_to_u32(color_f32)
            }
            im.TreePop()
        }

        im.Separator()
        im.TreePop()
    }

    //Filter
    if im.TreeNode("Filter"){
        im.Separator()
        using def.shape_def.filter
        //Category bits
        im.Text("Category Bits")
        for type in entity_type{
            contains := bool(u64(type) & categoryBits)
            if im.Checkbox(fmt.ctprint(type), &contains) do categoryBits ~= u64(type)
        }

        im.Text("Mask Bits")
        for type in entity_type{
            contains := bool(u64(type) & maskBits)
            if im.Checkbox(fmt.ctprint(" ",type), &contains) {
                maskBits ~= u64(type)
                level_reload(game, curr_room)
            }
        }

        im.InputInt("Group index", &groupIndex)
        im.Separator()
        im.TreePop()
    }
}


interface_edit_levels :: proc(game : ^game_state){
    if im.BeginTabItem("Game"){


        if im.Button("Save level"){
            curr_room := level_get_curr_room(game)
            level_save(game, curr_room)
        }

        im.EndTabItem()
    }

}










