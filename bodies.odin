package main
import b2 "vendor:box2d"
import "core:math"

/*

Kinematic :: struct {
	using sample : Sample,

	body_id         : b2.BodyId,
	amplitude, time : f32,
}



kinematic_create :: proc(ctx : ^SampleContext)->^Sample{

	kinematic := new(Kinematic)
	sample_create(&kinematic.sample, ctx)

	if ctx.restart == false{
		kinematic.draw.cam.center = {0, 0}
		kinematic.draw.cam.zoom   = 4
	}

	kinematic.amplitude = 2.0

	{
		body_def := b2.DefaultBodyDef()

		body_def.type = .kinematicBody
		body_def.position.x = 2.0 * kinematic.amplitude
		kinematic.body_id = b2.CreateBody(kinematic.world_id, body_def)

		box := b2.MakeBox(0.1, 1.0)
		shape_def := b2.DefaultShapeDef()
		_ = b2.CreatePolygonShape(kinematic.body_id, shape_def, box)
	}

	kinematic.time = 0

	return &kinematic.sample
}

kinematic_step :: proc(using kinematic : ^Kinematic){
	time_step := hertz > 0  ? 1.0 / hertz : 0


	if kinematic.pause && kinematic.singleStep == false{
		time_step = 0
	}

	if time_step > 0{
		point :b2.Vec2= {
			 2.0 * amplitude * math.cos_f32(time),
			amplitude * math.sin_f32(2.0 * time)
		}

		rotation := b2.MakeRot(2.0 * time)

		axis := b2.RotateVector(rotation, {0.0, 1.0})


		lines_add(&kinematic.draw.lines, point - 0.5 * axis, point + 0.5 * axis, b2.HexColor.Plum)
		points_add(&kinematic.draw.points, point, 10.0, b2.HexColor.Plum)

		b2.Body_SetTargetTransform(body_id, {point, rotation}, time_step)
	}
	sample_step(&kinematic.sample)
	time += time_step
}
*/