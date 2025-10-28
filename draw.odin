package main

import b2 "vendor:box2d"
import gl "vendor:OpenGL"
import "base:runtime"
import "vendor:glfw"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import im "shared:odin-imgui"


Camera :: struct {
	center        : b2.Vec2,
	width, height : i32,
	zoom          : f32,
	rotation      : f32,
}

RGBA8 :: [4]u8

make_rgba :: proc(color : b2.HexColor, alpha : f32) -> RGBA8 {
	c := i32(color)
	return {u8((c >> 16) & 0xFF), u8((c >> 8) & 0xFF), u8(c & 0xFF), u8(0xFF * alpha) }
}


camera_reset_view :: proc(using camera : ^Camera){
	center = {0, 0}
	zoom   = 1
}


camera_init  :: proc() -> Camera{
	c : Camera = { width = 1920, height = 1080, }
	camera_reset_view(&c)
	return c
}

//Takes in a vector that is screen's pixel coordinate and converts it to world's coordinate (according to the camera)
camera_convert_screen_to_world :: proc(using cam : ^Camera, ps : b2.Vec2) -> b2.Vec2{

	w := f32(width)
	h := f32(height)
	u := ps.x / w
	v := (h - ps.y) / h

	ratio   := w/h
	extents :b2.Vec2 = { zoom * ratio, zoom}

	lower := center - extents
	upper := center + extents

	pw :b2.Vec2= {(1.0 - u) * lower.x + u * upper.x, (1.0 - v) * lower.y + v * upper.y}
	return pw
}

camera_convert_world_to_screen :: proc(using cam : ^Camera, pw : b2.Vec2) -> b2.Vec2{
	w := f32(width)
	h := f32(height)
	ratio   := w/h

	extents :b2.Vec2 = { zoom * ratio, zoom}

	lower := center - extents
	upper := center + extents

	u := (pw.x - lower.x)/ (upper.x - lower.x)
	v := (pw.y - lower.y)/ (upper.y - lower.y)

	ps :b2.Vec2= {u * w, (1.0 - v) * h}
	return ps
}


//Convert from world coordinates to normalized device coordinates
// http://www.songho.ca/opengl/gl_projectionmatrix.html
camera_build_project_matrix :: proc(using cam: ^Camera, z_bias: f32) -> matrix[4,4]f32{

    m : matrix[4, 4]f32

	mat_rot := linalg.matrix4_rotate_f32(DEG2RAD * rotation, {0, 0, 1} )

	ratio   := f32(width) / f32(height)
	extents : b2.Vec2 = { zoom * ratio, zoom}
	lower   := center - extents
	upper   := center + extents

	w := upper.x - lower.x
	h := upper.y - lower.y

	m[0][0] = 2.0 / w
	m[1][1] = 2.0 / h
	m[2][2] = -1
	m[3][0] = -2.0 * center.x / w
	m[3][1] = -2.0 * center.y / h
	m[3][2] = z_bias
	m[3][3] = 1

	return m * mat_rot
}

camera_get_view_bounds :: proc(using cam: ^Camera)-> b2.AABB{
	return b2.AABB{
		lowerBound = camera_convert_screen_to_world(cam, {0, f32(height)}),
	    upperBound = camera_convert_screen_to_world(cam, {f32(width), 0})
	}
}



Background :: struct {
	vao, vbo, program : u32,
	uniforms : gl.Uniforms,
}

check_opengl :: proc(){
	err := gl.GetError()
	if err != gl.NO_ERROR{
		fmt.eprintf("OpenGL error = %d\n", err)
		assert(false)
	}
}


background_create :: proc(using back: ^Background){

	ok : bool
	program, ok = gl.load_shaders_file("shaders/background.vs", "shaders/background.fs")
	check_opengl()
	uniforms   = gl.get_uniforms_from_program(program)

	vertex_attribute : u32

	//Generate
	gl.GenVertexArrays(1, &vao)
	gl.GenBuffers(1, &vbo)

	gl.BindVertexArray(vao)
	gl.EnableVertexAttribArray(vertex_attribute)

	//Single quad
	vertices : [4]b2.Vec2 = {{-1.0,1.0}, {-1.0, -1.0}, {1.0, 1.0}, {1.0, -1}}
	gl.BindBuffer(gl.ARRAY_BUFFER, vbo)
	gl.BufferData(gl.ARRAY_BUFFER, size_of(vertices), &vertices[0], gl.STATIC_DRAW)
	gl.VertexAttribPointer(vertex_attribute, 2, gl.FLOAT, false, 0, 0)

	check_opengl()

	gl.BindBuffer(gl.ARRAY_BUFFER, 0)
	gl.BindVertexArray(0)
}

background_destroy :: proc(using back: ^Background){
	if bool(vao){
		gl.DeleteVertexArrays(1, &vao)
		gl.DeleteBuffers(1, &vbo)
		vao = 0
		vbo = 0
	}

	if bool(program){
		gl.DeleteProgram(program)
		program = 0
	}
}

background_draw :: proc( using back: ^Background, cam : ^Camera){
	gl.UseProgram(program)

	time := f32(glfw.GetTime())
	time = math.mod_f32(time, f32(100.0))

	gl.Uniform1f(uniforms["time"].location, time)
	gl.Uniform2f(uniforms["resolution"].location, f32(cam.width), f32(cam.height))

	gl.Uniform3f(uniforms["baseColor"].location, 0.2, 0.2, 0.2)

	gl.BindVertexArray(vao)
	gl.BindBuffer(gl.ARRAY_BUFFER, vbo)
	gl.DrawArrays(gl.TRIANGLE_STRIP, 0, 4)
	gl.BindBuffer(gl.ARRAY_BUFFER, 0)
	gl.BindVertexArray(0)
	gl.UseProgram(0)
}


PointData :: struct {
	pos  : b2.Vec2,
	size : f32,
	rgba : RGBA8,
}

Point :: struct{
	vao, vbo, program : u32,
	uniforms : gl.Uniforms,
	points : [dynamic]PointData,
}

points_create :: proc(using point : ^Point){

	vs : string = `
	#version 330
	uniform mat4 projectionMatrix;
	layout(location = 0) in vec2 v_position;
	layout(location = 1) in float v_size;
	layout(location = 2) in vec4 v_color;
	out vec4 f_color;
	void main(void) {
		f_color = v_color;
		gl_Position = projectionMatrix * vec4(v_position, 0.0f, 1.0f);
		gl_PointSize = v_size;
	}
	`

	fs : string = `
	#version 330
	in vec4 f_color;
	out vec4 color;
	void main(void){
		color = f_color;
	}
	`
	program, _ = gl.load_shaders_source(vs, fs)
	uniforms =   gl.get_uniforms_from_program(program)

	vertex_attribute : u32 = 0
	size_attribute   : u32 = 1
	color_attribute  : u32 = 2

	gl.GenVertexArrays(1, &vao)
	gl.GenBuffers(1, &vbo)

	gl.BindVertexArray(vao)
	gl.EnableVertexAttribArray(vertex_attribute)
	gl.EnableVertexAttribArray(size_attribute)
	gl.EnableVertexAttribArray(color_attribute)

	//Vertex buffer
	gl.BindBuffer(gl.ARRAY_BUFFER, vbo)
	gl.BufferData(gl.ARRAY_BUFFER, 2048 * size_of(PointData), nil, gl.DYNAMIC_DRAW)

	gl.VertexAttribPointer(vertex_attribute, 2, gl.FLOAT, gl.FALSE, size_of(PointData), offset_of(PointData, pos))

	gl.VertexAttribPointer(size_attribute, 1, gl.FLOAT, gl.FALSE, size_of(PointData), offset_of(PointData, size))

	gl.VertexAttribPointer(color_attribute, 4, gl.UNSIGNED_BYTE, gl.TRUE, size_of(PointData), offset_of(PointData, rgba))

	check_opengl()

	gl.BindBuffer(gl.ARRAY_BUFFER, 0)
	gl.BindVertexArray(0)

}

points_destroy :: proc(using point: ^Point){
	if vao != 0{
		gl.DeleteVertexArrays(1, &vao)
		gl.DeleteBuffers(1, &vbo)
		vao = 0
		vbo = 0
	}

	if program != 0{
		gl.DeleteProgram(program)
		program = 0
	}
}

points_add :: proc(using point: ^Point, v: b2.Vec2, size: f32, c: b2.HexColor) {
	rgba := make_rgba(c, 1.0)
	append(&points, PointData{v, size, rgba})
}

//Flush means draw
points_flush :: proc(using point: ^Point, cam: ^Camera){
	count := i32(len(points))
	if count == 0 do return

	gl.UseProgram(program)

	proj := camera_build_project_matrix(cam, 0)

	gl.UniformMatrix4fv(uniforms["projectionMatrix"].location, 1, gl.FALSE, &proj[0][0])

	gl.BindVertexArray(vao)

	gl.BindBuffer(gl.ARRAY_BUFFER, vbo)
	gl.Enable(gl.PROGRAM_POINT_SIZE)

	base := 0

	for count > 0{
		batch_count :i32= min(count, 2048)

		gl.BufferSubData(gl.ARRAY_BUFFER, 0, int(batch_count * size_of(PointData)), &points[base])
		gl.DrawArrays(gl.POINTS, 0, batch_count)

		check_opengl()

		count -= 2048
		base  += 2048
	}

	gl.Disable(gl.PROGRAM_POINT_SIZE)
	gl.BindBuffer(gl.ARRAY_BUFFER, 0)
	gl.BindVertexArray(0)
	gl.UseProgram(0)

	clear(&points)
}

VertexData :: struct {
	pos : b2.Vec2,
	rgba     : RGBA8,
}

Lines :: struct {
	points : [dynamic]VertexData,
	vao, vbo, program : u32,
	uniforms : gl.Uniforms,
}


lines_create :: proc(using line : ^Lines){

	vs : string = `
		#version 330
		uniform mat4 projectionMatrix;
		layout(location = 0) in vec2 v_position;
		layout(location = 1) in vec4 v_color;
		out vec4 f_color;

		void main(void){
			f_color = v_color;
			gl_Position = projectionMatrix * vec4(v_position , 0.0f, 1.0f);
		}
	`

	fs : string = `
		#version 330
		in vec4 f_color;
		out vec4 color;

		void main(void){
			color = f_color;
		}
	`

	ok := false
	program, ok = gl.load_shaders_source(vs, fs)
	check_opengl()
	uniforms   = gl.get_uniforms_from_program(program)

	vertex_attribute :u32= 0
	color_attribute  :u32= 1

	gl.GenVertexArrays(1, &vao)
	gl.GenBuffers(1, &vbo)

	gl.BindVertexArray(vao)
	gl.EnableVertexAttribArray(vertex_attribute)
	gl.EnableVertexAttribArray(color_attribute)

	//Vertex buffer
	gl.BindBuffer(gl.ARRAY_BUFFER, vbo)
	gl.BufferData(gl.ARRAY_BUFFER, 2048 * size_of(VertexData), nil, gl.DYNAMIC_DRAW)

	gl.VertexAttribPointer(vertex_attribute, 2, gl.FLOAT, gl.FALSE, size_of(VertexData), offset_of(VertexData, pos))
	gl.VertexAttribPointer(color_attribute, 4, gl.UNSIGNED_BYTE, gl.TRUE, size_of(VertexData), offset_of(VertexData, rgba))
	check_opengl()

	gl.BindBuffer(gl.ARRAY_BUFFER, 0)
	gl.BindVertexArray(0)
}

lines_destroy :: proc(using line: ^Lines){
	if vao != 0{
		gl.DeleteVertexArrays(1, &vao)
		gl.DeleteBuffers(1, &vbo)
		vao = 0
		vbo = 0
	}

	if program != 0{
		gl.DeleteProgram(program)
		program = 0
	}
}


lines_add :: proc(using line: ^Lines, p1, p2: b2.Vec2, c: b2.HexColor){
	rgba := make_rgba(c, 1.0)
	append(&points, VertexData{p1, rgba})
	append(&points, VertexData{p2, rgba})
}



lines_flush :: proc(using line: ^Lines, cam: ^Camera){
	count := i32(len(points))

	batch_size :i32= 2 * 2048

	if count ==0 do return

	gl.Enable(gl.BLEND)
	gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)

	gl.UseProgram(program)

	proj := camera_build_project_matrix(cam, 0.1)

	gl.UniformMatrix4fv(uniforms["projectionMatrix"].location, 1, gl.FALSE, &proj[0][0])
	gl.BindVertexArray(vao)

	gl.BindBuffer(gl.ARRAY_BUFFER, vbo)

	base :i32= 0

	for count > 0{
		batch_count := min(count, batch_size)
		size := int(batch_count * size_of(VertexData))
		gl.BufferSubData(gl.ARRAY_BUFFER, 0, size, &points[base])
		gl.DrawArrays(gl.LINES, 0, batch_count)
		check_opengl()

		count -= batch_size
		base  += batch_size
	}

	gl.BindBuffer(gl.ARRAY_BUFFER, 0)
	gl.BindVertexArray(0)
	gl.UseProgram(0)
	gl.Disable(gl.BLEND)
	clear(&points)
}



CircleData :: struct {
	pos : b2.Vec2,
	radius : f32,
	rgba : RGBA8,
}

Circles :: struct {
	circles : [dynamic]CircleData,

	vao, program : u32,
	vbos         : [2]u32,
	uniforms     : gl.Uniforms,
}


circle_create :: proc(using circle : ^Circles){

	batch_size := 2048

	program, _  = gl.load_shaders("shaders/circle.vs", "shaders/circle.fs")
	check_opengl()
	uniforms = gl.get_uniforms_from_program(program)

	vertex_attribute  :u32= 0
	position_instance :u32= 1;
	radiusInstance    :u32= 2;
	colorInstance     :u32= 3;

	gl.GenVertexArrays(1, &vao)
	gl.GenBuffers(2, &vbos[0])

	gl.BindVertexArray(vao)
	gl.EnableVertexAttribArray(vertex_attribute)
	gl.EnableVertexAttribArray(position_instance)
	gl.EnableVertexAttribArray(radiusInstance)
	gl.EnableVertexAttribArray(colorInstance)

	//vertex buffer for single quad
	a :f32= 1.1

	vertices : []b2.Vec2 = {
		{-a, -a}, {a, -a}, {-a, a}, {a, -a}, {a, a}, {-a, a}
	}

	gl.BindBuffer(gl.ARRAY_BUFFER, vbos[0])
	gl.BufferData(gl.ARRAY_BUFFER, size_of(b2.Vec2) * 6, &vertices[0], gl.STATIC_DRAW)
	gl.VertexAttribPointer(vertex_attribute, 2, gl.FLOAT, gl.FALSE, 0, 0)

	//
	gl.BindBuffer(gl.ARRAY_BUFFER, vbos[1])
	gl.BufferData(gl.ARRAY_BUFFER, batch_size * size_of(CircleData), nil, gl.DYNAMIC_DRAW )

	gl.VertexAttribPointer(position_instance, 2, gl.FLOAT, gl.FALSE, size_of(CircleData), offset_of(CircleData, pos))
	gl.VertexAttribPointer(radiusInstance,    1, gl.FLOAT, gl.FALSE, size_of(CircleData), offset_of(CircleData, radius))
	gl.VertexAttribPointer(colorInstance,     4, gl.UNSIGNED_BYTE, gl.TRUE, size_of(CircleData), offset_of(CircleData, rgba))

	gl.VertexAttribDivisor(position_instance, 1)
	gl.VertexAttribDivisor(radiusInstance,    1)
	gl.VertexAttribDivisor(colorInstance,     1)

	check_opengl()
	gl.BindBuffer(gl.ARRAY_BUFFER, 0)
	gl.BindVertexArray(0)
}

circle_destroy :: proc(using circle : ^Circles){
	if vao != 0{
		gl.DeleteVertexArrays(1, &vao)
		gl.DeleteBuffers(2, &vbos[0])
		vao = 0
		vbos[0] = 0
		vbos[1] = 0
	}

	if program != 0{
		gl.DeleteProgram(program)
		program = 0
	}
}

circle_add :: proc(using circle : ^Circles, center : b2.Vec2, radius : f32, color : b2.HexColor){
	rgba := make_rgba(color, 1.0)
	append(&circles, CircleData{center, radius, rgba})
}

circle_flush :: proc(using circle: ^Circles, cam: ^Camera){
	count := i32(len(circles))
	if count == 0 do return
	batch_size :i32= 2048

	gl.UseProgram(program)

	proj := camera_build_project_matrix(cam, 0.2)

	gl.UniformMatrix4fv(uniforms["projectionMatrix"].location, 1, gl.FALSE, &proj[0][0])
	gl.Uniform1f(uniforms["pixelScale"].location, f32(cam.height) / cam.zoom)

	gl.BindVertexArray(vao)

	gl.BindBuffer(gl.ARRAY_BUFFER, vbos[1])
	gl.Enable(gl.BLEND)
	gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)

	base :i32= 0

	for count > 0{
		batch_count := min(count, batch_size)

		gl.BufferSubData(gl.ARRAY_BUFFER, 0, int(batch_count * size_of(CircleData)), &circles[base])
		gl.DrawArraysInstanced(gl.TRIANGLES, 0, 6, batch_count)

		check_opengl()

		count -= batch_size
		base  += batch_size
	}

	gl.Disable(gl.BLEND)
	gl.BindBuffer(gl.ARRAY_BUFFER, 0)
	gl.BindVertexArray(0)
	gl.UseProgram(0)

	clear(&circles)
}


SolidCircleData :: struct {
	transform : b2.Transform,
	radius    : f32,
	rgba      : RGBA8,
}

SolidCircle :: struct {
	circles      : [dynamic]SolidCircleData,
	program, vao : u32,
	vbo          : [2]u32,
	uniforms     : gl.Uniforms,
}


solid_circle_create :: proc(using circle: ^SolidCircle){
	program,_ = gl.load_shaders("shaders/solid_circle.vs", "shaders/solid_circle.fs")
	uniforms  = gl.get_uniforms_from_program(program)

	gl.GenVertexArrays(1, &vao)
	gl.GenBuffers(2, &vbo[0])

	gl.BindVertexArray(vao)

	vertex_attribute   :u32= 0
	transform_instance :u32= 1
	radius_instance    :u32= 2
	color_instance     :u32= 3

	gl.EnableVertexAttribArray(vertex_attribute)
	gl.EnableVertexAttribArray(transform_instance)
	gl.EnableVertexAttribArray(radius_instance)
	gl.EnableVertexAttribArray(color_instance)

	batch_size : i32 = 2048

	//Vertex buffer for single quad
	a :f32= 1.1

	vertices : []b2.Vec2 = {
		{-a, -a}, {a, -a}, {-a, a}, {a, -a}, {a, a}, {-a, a}
	}

	gl.BindBuffer(gl.ARRAY_BUFFER, vbo[0])
	gl.BufferData(gl.ARRAY_BUFFER, size_of(b2.Vec2) * 6, &vertices[0], gl.STATIC_DRAW)
	gl.VertexAttribPointer(vertex_attribute, 2, gl.FLOAT, gl.FALSE, 0, 0)

	//
	gl.BindBuffer(gl.ARRAY_BUFFER, vbo[1])
	gl.BufferData(gl.ARRAY_BUFFER, int(batch_size * size_of(SolidCircleData)), nil, gl.DYNAMIC_DRAW )

	gl.VertexAttribPointer(transform_instance, 4, gl.FLOAT, gl.FALSE, size_of(SolidCircleData), offset_of(SolidCircleData, transform))
	gl.VertexAttribPointer(radius_instance,     1, gl.FLOAT, gl.FALSE, size_of(SolidCircleData), offset_of(SolidCircleData, radius))
	gl.VertexAttribPointer(color_instance,      4, gl.UNSIGNED_BYTE, gl.TRUE, size_of(SolidCircleData), offset_of(SolidCircleData, rgba))

	gl.VertexAttribDivisor(transform_instance, 1)
	gl.VertexAttribDivisor(radius_instance,    1)
	gl.VertexAttribDivisor(color_instance,     1)

	check_opengl()

	//Cleanup
	gl.BindBuffer(gl.ARRAY_BUFFER, 0)
	gl.BindVertexArray(0)
}

solid_circle_destroy :: proc(using circle: ^SolidCircle){
	if vao != 0{
		gl.DeleteVertexArrays(1, &vao)
		gl.DeleteBuffers(2, &vbo[0])
		vao = 0
		vbo[0] = 0
		vbo[1] = 0
	}

	if program != 0{
		gl.DeleteProgram(program)
		program = 0
	}
}

solid_circle_add :: proc(using circle : ^SolidCircle, transform : b2.Transform, radius : f32, color : b2.HexColor){
	rgba := make_rgba(color, 1.0)
	append(&circles, SolidCircleData{transform, radius, rgba})
}

solid_circle_flush :: proc(using circle: ^SolidCircle, cam: ^Camera){
	count :i32= i32(len(circles))
	if count == 0 do return
	batch_size :i32= 2048

	gl.UseProgram(program)

	proj := camera_build_project_matrix(cam, 0.2)

	gl.UniformMatrix4fv(uniforms["projectionMatrix"].location, 1, gl.FALSE, &proj[0][0])
	gl.Uniform1f(uniforms["pixelScale"].location, f32(cam.height) / cam.zoom)

	gl.BindVertexArray(vao)

	gl.BindBuffer(gl.ARRAY_BUFFER, vbo[1])
	gl.Enable(gl.BLEND)
	gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)

	base :i32= 0

	for count > 0{
		batch_count := min(count, batch_size)

		gl.BufferSubData(gl.ARRAY_BUFFER, 0, int(batch_count * size_of(SolidCircleData)), &circles[base])
		gl.DrawArraysInstanced(gl.TRIANGLES, 0, 6, batch_count)

		check_opengl()

		count -= batch_size
		base  += batch_size
	}

	gl.Disable(gl.BLEND)
	gl.BindBuffer(gl.ARRAY_BUFFER, 0)
	gl.BindVertexArray(0)
	gl.UseProgram(0)

	clear(&circles)
}


CapsuleData :: struct {
	transform      : b2.Transform,
	radius, length : f32,
	rgba           : RGBA8,
}




SolidCapsules :: struct {
	capsules     : [dynamic]CapsuleData,
	vao, program : u32,
	vbo          : [2]u32,
	uniforms     : gl.Uniforms,
}


//Draw capsules using SDF-based shaders

solid_capsules_create :: proc(using capsule : ^SolidCapsules){
	program, _  = gl.load_shaders("shaders/solid_capsule.vs", "shaders/solid_capsule.fs")
	check_opengl()
	uniforms    = gl.get_uniforms_from_program(program)


	//batch_size := i32(len(capsules))
	batch_size : i32 = 512


	vertex_attribute   :u32= 0
	transform_instance :u32= 1
	radius_instance    :u32= 2
	length_instance    :u32= 3
	color_instance     :u32= 4

	gl.GenVertexArrays(1, &vao)
	gl.GenBuffers(2, &vbo[0])

	gl.BindVertexArray(vao)

	gl.EnableVertexAttribArray(vertex_attribute)
	gl.EnableVertexAttribArray(transform_instance)
	gl.EnableVertexAttribArray(radius_instance)
	gl.EnableVertexAttribArray(length_instance)
	gl.EnableVertexAttribArray(color_instance)

	//Vertex buffer for single quad
	a :f32= 1.1

	vertices : []b2.Vec2 = {
		{-a, -a}, {a, -a}, {-a, a}, {a, -a}, {a, a}, {-a, a}
	}

	gl.BindBuffer(gl.ARRAY_BUFFER, vbo[0])
	gl.BufferData(gl.ARRAY_BUFFER, size_of(b2.Vec2) * 6, &vertices[0], gl.STATIC_DRAW)
	gl.VertexAttribPointer(vertex_attribute, 2, gl.FLOAT, gl.FALSE, 0, 0)

	//
	gl.BindBuffer(gl.ARRAY_BUFFER, vbo[1])
	gl.BufferData(gl.ARRAY_BUFFER, int(batch_size * size_of(CapsuleData)), nil, gl.DYNAMIC_DRAW )

	gl.VertexAttribPointer(transform_instance, 4, gl.FLOAT, gl.FALSE, size_of(CapsuleData), offset_of(CapsuleData, transform))
	gl.VertexAttribPointer(radius_instance,     1, gl.FLOAT, gl.FALSE, size_of(CapsuleData), offset_of(CapsuleData, radius))
	gl.VertexAttribPointer(length_instance,     1, gl.FLOAT, gl.FALSE, size_of(CapsuleData), offset_of(CapsuleData, length))
	gl.VertexAttribPointer(color_instance,      4, gl.UNSIGNED_BYTE, gl.TRUE, size_of(CapsuleData), offset_of(CapsuleData, rgba))

	gl.VertexAttribDivisor(transform_instance, 1)
	gl.VertexAttribDivisor(radius_instance,    1)
	gl.VertexAttribDivisor(length_instance,    1)
	gl.VertexAttribDivisor(color_instance,     1)

	check_opengl()

	//Cleanup
	gl.BindBuffer(gl.ARRAY_BUFFER, 0)
	gl.BindVertexArray(0)
}

solid_capsules_destroy :: proc(using capsule : ^SolidCapsules){
	if vao != 0{
		gl.DeleteVertexArrays(1, &vao)
		gl.DeleteBuffers(2, &vbo[0])
		vao = 0
		vbo = {0, 0}
	}

	if program != 0{
		gl.DeleteProgram(program)
		program = 0
	}
}

solid_capsules_add :: proc(using capsule : ^SolidCapsules, p1, p2: b2.Vec2, radius : f32, c: b2.HexColor){
	d := p2 - p1

	length := b2.Length(d)
	if length < 0.001 do return

	axis := d/length

	transform : b2.Transform = {
		p = 0.5 * (p1 + p2),
		q = {
			c = axis.x,
			s = axis.y
		}
	}

	rgba := make_rgba(c, 1.0)

	append(&capsule.capsules, CapsuleData{transform, radius, length, rgba} )
}

solid_capsules_flush :: proc(using capsule : ^SolidCapsules, cam : ^Camera){
	count := i32(len(capsules))

	if count == 0 do return

	//batch :i32= 2048

	gl.UseProgram(program)

	proj := camera_build_project_matrix(cam, 0.2)

	gl.UniformMatrix4fv(uniforms["projectionMatrix"].location, 1, gl.FALSE, &proj[0][0])
	gl.Uniform1f(uniforms["pixelScale"].location, f32(cam.height)/ cam.zoom)

	gl.BindVertexArray(vao)

	gl.BindBuffer(gl.ARRAY_BUFFER, vbo[1])
	gl.Enable(gl.BLEND)
	gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)

	base :i32= 0

	for count > 0{
		batch_count := min(count, 2048)
		//fmt.println(size_of(capsules[0]))

		gl.BufferSubData(gl.ARRAY_BUFFER, 0, int(batch_count * size_of(CapsuleData)), &capsule.capsules[base])
		gl.DrawArraysInstanced(gl.TRIANGLES, 0, 6, batch_count)

		check_opengl()

		count -= 2048
		base  += 2048
	}

	gl.Disable(gl.BLEND)
	gl.BindBuffer(gl.ARRAY_BUFFER, 0)
	gl.BindVertexArray(0)
	gl.UseProgram(0)

	clear(&capsules)
}




PolygonData :: struct #packed{
	transform : b2.Transform,
	p1, p2, p3, p4, p5, p6, p7, p8: b2.Vec2,
	count  : i32,
	radius : f32,

	//Keep color small
	color : RGBA8
}

SolidPolygon :: struct {
	polygons     : [dynamic]PolygonData,
	vao, program : u32,
	vbo          : [2]u32,
	uniforms     : gl.Uniforms,
}



solid_polygon_create :: proc(using polygon : ^SolidPolygon){
	program, _ = gl.load_shaders("shaders/solid_polygons.vs", "shaders/solid_polygons.fs")

	batch_size : i32 = 512

	uniforms = gl.get_uniforms_from_program(program)

	vertex_attribute     :u32= 0
	instance_transform   :u32= 1
	instance_point12     :u32= 2
	instance_point34     :u32= 3
	instance_point56     :u32= 4
	instance_point78     :u32= 5
	instance_point_count :u32= 6
	instance_radius      :u32= 7
	instance_color       :u32= 8


	gl.GenVertexArrays(1, &vao)
	gl.GenBuffers(2, &vbo[0])

	gl.BindVertexArray(vao)

	gl.EnableVertexAttribArray(vertex_attribute)
	gl.EnableVertexAttribArray(instance_transform)
	gl.EnableVertexAttribArray(instance_point12)
	gl.EnableVertexAttribArray(instance_point34)
	gl.EnableVertexAttribArray(instance_point56)
	gl.EnableVertexAttribArray(instance_point78)
	gl.EnableVertexAttribArray(instance_point_count)
	gl.EnableVertexAttribArray(instance_radius)
	gl.EnableVertexAttribArray(instance_color)

	a :f32= 1.1

	vertices : []b2.Vec2 = {
		{-a, -a}, {a, -a}, {-a, a}, {a, -a}, {a, a}, {-a, a}
	}

	gl.BindBuffer(gl.ARRAY_BUFFER, vbo[0])
	gl.BufferData(gl.ARRAY_BUFFER, size_of(b2.Vec2) * 6, &vertices[0], gl.STATIC_DRAW)
	gl.VertexAttribPointer(vertex_attribute, 2, gl.FLOAT, gl.FALSE, 0, 0)

	//
	gl.BindBuffer(gl.ARRAY_BUFFER, vbo[1])
	gl.BufferData(gl.ARRAY_BUFFER, int(batch_size * size_of(PolygonData)), nil, gl.DYNAMIC_DRAW)

	gl.VertexAttribPointer(instance_transform, 4, gl.FLOAT, false, size_of(PolygonData), offset_of(PolygonData, transform))
	gl.VertexAttribPointer(instance_point12,   4, gl.FLOAT, false, size_of(PolygonData), offset_of(PolygonData, p1))
	gl.VertexAttribPointer(instance_point34,   4, gl.FLOAT, false, size_of(PolygonData), offset_of(PolygonData, p3))
	gl.VertexAttribPointer(instance_point56,   4, gl.FLOAT, false, size_of(PolygonData), offset_of(PolygonData, p5))
	gl.VertexAttribPointer(instance_point78,   4, gl.FLOAT, false, size_of(PolygonData), offset_of(PolygonData, p7))
	gl.VertexAttribIPointer(instance_point_count, 1, gl.INT, size_of(PolygonData), offset_of(PolygonData, count))
	gl.VertexAttribPointer(instance_radius, 1, gl.FLOAT, false, size_of(PolygonData), offset_of(PolygonData, radius))
	gl.VertexAttribPointer(instance_color, 4, gl.UNSIGNED_BYTE, true, size_of(PolygonData), offset_of(PolygonData, color))


	gl.VertexAttribDivisor(instance_transform, 1)
	gl.VertexAttribDivisor(instance_point12, 1)
	gl.VertexAttribDivisor(instance_point34, 1)
	gl.VertexAttribDivisor(instance_point56, 1)
	gl.VertexAttribDivisor(instance_point78, 1)
	gl.VertexAttribDivisor(instance_point_count, 1)
	gl.VertexAttribDivisor(instance_radius, 1)
	gl.VertexAttribDivisor(instance_color, 1)

	check_opengl()

	gl.BindBuffer(gl.ARRAY_BUFFER, 0)
	gl.BindVertexArray(0)

}

solid_polygon_add :: proc(using polygon: ^SolidPolygon, transform : b2.Transform, points : [^]b2.Vec2, count : i32, radius : f32, color : b2.HexColor){

	data : PolygonData

	data.transform = transform

	n := min(count, 8)

	ps := cast([^]b2.Vec2)&data.p1

	for i in 0..<count{
    	//fmt.print(points[i])
		ps[i] = points[i]
	}

	data.count = n
	data.radius = f32(radius)
	data.color = make_rgba(color, 1.0)

	append(&polygons, data)
}



solid_polygon_flush :: proc(using polygon : ^SolidPolygon, cam : ^Camera){
	count := i32(len(polygons))

	if count == 0 do return

	batch_size :i32= 512

	gl.UseProgram(program)

	proj := camera_build_project_matrix(cam, 0.2)

	gl.UniformMatrix4fv(uniforms["projectionMatrix"].location, 1, gl.FALSE, &proj[0][0])
	gl.Uniform1f(uniforms["pixelScale"].location, f32(cam.height)/ cam.zoom)

	gl.BindVertexArray(vao)

	gl.BindBuffer(gl.ARRAY_BUFFER, vbo[1])
	gl.Enable(gl.BLEND)
	gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)

	base :i32= 0

	for count > 0{
		batch_count := min(count, batch_size)

		gl.BufferSubData(gl.ARRAY_BUFFER, 0, int(batch_count * size_of(PolygonData)), &polygons[base])
		gl.DrawArraysInstanced(gl.TRIANGLES, 0, 6, batch_count)

		check_opengl()

		count -= batch_size
		base  += batch_size
	}

	gl.Disable(gl.BLEND)
	gl.BindBuffer(gl.ARRAY_BUFFER, 0)
	gl.BindVertexArray(0)
	gl.UseProgram(0)

	clear(&polygons)

}


Draw :: struct {
	show_ui : bool,
	debug_draw : b2.DebugDraw,

	cam        : Camera,
	background : Background,
	points     : Point,
	lines      : Lines,
	circles    : Circles,
	solid_circles : SolidCircle,
	solid_capsules : SolidCapsules,
	polygons   : SolidPolygon,

	drawCounters : bool,

	regular_font : im.Font,

	frame_buffer : u32,

}

draw_aabb :: proc(using draw : ^Draw, aabb : b2.AABB, c : b2.HexColor){
	p1 := aabb.lowerBound
	p2 :[2]f32= {aabb.upperBound.x, aabb.lowerBound.y}

	p3 := aabb.upperBound
	p4 :[2]f32= {aabb.lowerBound.x, aabb.upperBound.y}

	lines_add(&lines, p1, p2, c)
	lines_add(&lines, p2, p3, c)
	lines_add(&lines, p3, p4, c)
	lines_add(&lines, p4, p1, c)
}

DrawPolygonFcn ::proc "c" (vertices: [^]b2.Vec2, vertexCount : i32, color: b2.HexColor, ctx : rawptr){

	context = runtime.default_context()
	draw : ^Draw = cast(^Draw)ctx

	p1 := vertices[vertexCount - 1]
	for i in 0..<vertexCount {
		p2 := vertices[i]
		lines_add(&draw.lines, p1, vertices[i], color)
		p1 = p2
	}
}

DrawSolidPolygonFcn :: proc "c" (transform : b2.Transform, vertices: [^]b2.Vec2, vertexCount: i32, radius: f32, color: b2.HexColor, ctx: rawptr){


    context = runtime.default_context()

	draw    : ^Draw = cast(^Draw)ctx
	solid_polygon_add(&draw.polygons, transform, vertices, vertexCount, radius, color)
}


DrawCircleFcn :: proc "c" (center: b2.Vec2, radius : f32, color: b2.HexColor, ctx : rawptr){
	context = runtime.default_context()
	draw : ^Draw = cast(^Draw)ctx
	circle_add(&draw.circles, center, radius, color)
}

DrawSolidCircle :: proc(using circle : ^SolidCircle, transform : b2.Transform, center : b2.Vec2, radius : f32, color : b2.HexColor){
	context = runtime.default_context()

	transform := transform

	transform.p = b2.TransformPoint(transform, center)
	solid_circle_add(circle, transform, radius, color)
}

DrawTransform :: proc "c" (using lines: ^Lines, transform : b2.Transform){
	context = runtime.default_context()
	k_axis_scale :f32= 0.2
	p1           := transform.p

	p2 := p1 +  k_axis_scale * b2.Rot_GetXAxis(transform.q)
	lines_add(lines, p1, p2, b2.HexColor.Red)

	p2 = p1 +  k_axis_scale * b2.Rot_GetYAxis(transform.q)
	lines_add(lines, p1, p2, b2.HexColor.Green)
}

DrawSolidCircleFcn :: proc "c"(transform : b2.Transform, radius: f32, color: b2.HexColor, ctx: rawptr){
	context = runtime.default_context()
	draw : ^Draw = cast(^Draw)ctx
	DrawSolidCircle(&draw.solid_circles, transform, b2.Vec2_zero, radius, color)
}

DrawSolidCapsuleFcn :: proc "c" (p1, p2: b2.Vec2, radius: f32, color : b2.HexColor, ctx : rawptr){
	context = runtime.default_context()
	draw : ^Draw = cast(^Draw)ctx
	solid_capsules_add(&draw.solid_capsules, p1, p2, radius, color)
}

DrawSegmentFcn :: proc "c" (p1, p2 : b2.Vec2, color: b2.HexColor, ctx : rawptr){
	context = runtime.default_context()
	draw : ^Draw = cast(^Draw)ctx
	lines_add(&draw.lines, p1, p2, color)
}

DrawTransformFcn :: proc "c" (transform : b2.Transform, ctx : rawptr){
	context = runtime.default_context()
	draw : ^Draw = cast(^Draw)ctx
	DrawTransform(&draw.lines, transform)
}

DrawPointFcn :: proc "c" (p : b2.Vec2, size: f32, color: b2.HexColor, ctx: rawptr){
	context = runtime.default_context()
	draw : ^Draw = cast(^Draw)ctx
	points_add(&draw.points, p, size, color)
}

DrawString :: proc (draw : ^Draw,  x, y: int, fmt : cstring, args : ..any){
	//@(link_name="ImGui_TextColored")     TextColored     :: proc(col: Vec4, fmt: cstring, #c_vararg args: ..any)      --- // shortcut for PushStyleColor(ImGuiCol_Text, col); Text(fmt, ...); PopStyleColor();

	im.Begin("Overlay", nil, {.NoTitleBar, .NoNavInputs, .AlwaysAutoResize, .NoScrollbar, .NoMouseInputs, .NoFocusOnAppearing})

	//im.PushFont(&draw.regular_font)
	im.SetCursorPos(b2.Vec2{f32(x), f32(y)})
	im.TextColored(im.Vec4{230, 153, 153, 255}, fmt, args)
	//im.PopFont()
	im.End()

}

DrawStringVec :: proc (draw : ^Draw, p : b2.Vec2, fmt : cstring, args : ..any){
	ps := camera_convert_world_to_screen(&draw.cam , p)

	im.Begin("Overlay", nil, {.NoTitleBar, .NoNavInputs, .AlwaysAutoResize, .NoScrollbar, .NoMouseInputs, .NoFocusOnAppearing})

	//im.PushFont(&draw.regular_font)
	im.SetCursorPos(ps)
	im.TextColored(im.Vec4{230, 153, 153, 255}, fmt, args)
	//im.PopFont()
	im.End()
}

DrawStringFcn :: proc "c" (p: b2.Vec2, s : cstring, color : b2.HexColor, ctx : rawptr){
	context = runtime.default_context()
	draw : ^Draw = cast(^Draw)ctx
	DrawStringVec(draw, p, s)
}

draw_flush :: proc(using draw: ^Draw){



    solid_circle_flush(&solid_circles, &cam)
	solid_polygon_flush(&polygons, &cam)
	solid_capsules_flush(&solid_capsules, &cam)
	circle_flush(&circles, &cam)
	lines_flush(&lines, &cam)
	points_flush(&points, &cam)


	check_opengl()
}

draw_create :: proc(using draw: ^Draw, camera : ^Camera){
	draw.cam = cam


	background_create(&background)
	points_create(&points)
	solid_capsules_create(&solid_capsules)
	lines_create(&lines)
	circle_create(&circles)
	solid_circle_create(&solid_circles)
	solid_polygon_create(&polygons)


	bounds : b2.AABB = {{-max(f32), -max(f32)}, {max(f32), max(f32)}}

	debug_draw.DrawPolygonFcn      = DrawPolygonFcn
	debug_draw.DrawSolidPolygonFcn = DrawSolidPolygonFcn
	debug_draw.DrawCircleFcn      = DrawCircleFcn
	debug_draw.DrawSolidCircleFcn = DrawSolidCircleFcn
	debug_draw.DrawSolidCapsuleFcn = DrawSolidCapsuleFcn
	debug_draw.DrawSegmentFcn     = DrawSegmentFcn
	debug_draw.DrawTransformFcn   = DrawTransformFcn
	debug_draw.DrawPointFcn       = DrawPointFcn
	debug_draw.DrawStringFcn      = DrawStringFcn
	debug_draw.drawingBounds      = bounds

	debug_draw.useDrawingBounds     = false
	debug_draw.drawShapes           = true
	debug_draw.drawJoints           = true
	debug_draw.drawJointExtras      = false
	debug_draw.drawBounds           = false
	debug_draw.drawMass             = false
	debug_draw.drawContacts         = false
	debug_draw.drawGraphColors      = false
	debug_draw.drawContactNormals   = false
	debug_draw.drawContactImpulses  = false
	debug_draw.drawContactFeatures  = false
	debug_draw.drawFrictionImpulses = false
	debug_draw.drawIslands          = false

	drawCounters = true

	debug_draw.userContext = rawptr(draw)

}





