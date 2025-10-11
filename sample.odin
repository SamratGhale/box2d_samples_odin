package main
import b2 "vendor:box2d"
import glfw "vendor:glfw"
import "core:fmt"
import im "shared:odin-imgui"

/*

max_tasks :i32: 64
max_threads :i32: 64
is_debug    :: true
hertz :f32: 60.0


SampleContext :: struct {
	window : glfw.WindowHandle,
	draw : Draw,
	restart, pause, singleStep : bool,
	workerCount, subStepCount  : u32,
	sampleIndex : i32,

	tasks : [max_threads]SampleTask,
	enableWarmStarting: bool,
	enableSLeep : bool,
	enableContinuous : bool,
}


Sample :: struct {
	using ctx : ^SampleContext,
	task_count, thread_count : u32,

	ground_body_id : b2.BodyId,
	world_id : b2.WorldId,
	mouse_joint_id : b2.JointId,
	step_count : i32,
	max_profile, total_profile : b2.Profile,

	text_line, text_increment: i32,

	task_scheduler : ^enki.TaskScheduler,
}

SampleCreateFnc :: proc(ctx: ^SampleContext) -> ^Sample


SampleEntry :: struct {
	category, name : string,
	create_fcn     : SampleCreateFnc
}

MAX_SAMPLES :: 256
sample_entries: [MAX_SAMPLES]SampleEntry
sample_count : i32



SampleTask :: struct {
	using task_set : enki.TaskSet,
	task           : b2.TaskCallback,
	task_ctx       : rawptr,
}

task_enqueue :: proc "c" (task: b2.TaskCallback, item_count : i32, min_range: i32, task_ctx, user_ctx : rawptr) -> rawptr{
	sample := cast(^Sample)user_ctx

	if sample.task_count < MAX_SAMPLES{
		sample_task := &sample.tasks[sample.task_count]

		enki.SetParamsTaskSet(&sample_task.task_set, {
			setSize = u32(item_count),
			minRange = u32(min_range),
		})
		sample_task.task = task
		sample_task.task_ctx = task_ctx
		enki.AddTaskSet(sample.task_scheduler, &sample_task.task_set)
		sample.task_count += 1
		return sample_task
	}else{
		//assert(false)
		task(0, item_count, 0, task_ctx)
		return nil
	}
}

task_finish :: proc(task_ptr, user_ctx: rawptr){
	if task_ptr != nil{
		sample_task := cast(^SampleTask)task_ptr
		sample      := cast(^Sample)user_ctx
		enki.WaitForTaskSet(sample.task_scheduler, &sample_task.task_set)
	}
}


sample_create :: proc(using sample: ^Sample, sample_ctx : ^SampleContext){
	sample.ctx = sample_ctx

	task_scheduler = enki.NewTaskScheduler()
	enki.InitTaskSchedulerNumThreads(task_scheduler, sample_ctx.workerCount)

	task_count = 0

	thread_count = 1 + ctx.workerCount

	world_id = b2.nullWorldId

	text_line = 30
	text_increment = 22

	mouse_joint_id = b2.nullJointId

	step_count = 0

	ground_body_id = b2.nullBodyId

	max_profile = {}
	total_profile = {}

	sample_create_world(sample)

}

sample_create_world :: proc(using sample: ^Sample){
	if b2.IS_NON_NULL(world_id){
		b2.DestroyWorld(world_id)
		world_id = b2.nullWorldId
	}

	world_def := b2.DefaultWorldDef()
	world_def.workerCount = i32(workerCount)
	world_def.enqueueTask = task_enqueue
	world_def.userTaskContext = rawptr(sample)
	world_def.enableSleep = sample.enableSLeep
	world_id = b2.CreateWorld(world_def)
}

sample_draw_text_line :: proc (using sample: ^Sample,  text : cstring, args : ..any){

	im.Begin("Overlay", nil, {.NoTitleBar, .NoNavInputs, .AlwaysAutoResize, .NoScrollbar})
	//im.PushFont(&ctx.draw.regular_font)

	//im.SetCursorPos({5.0, f32(text_line)})

	im.TextColored(im.Vec4{230.0/255.0, 153.0/255.0, 153.0/255.0, 255/255}, text, args)

	//im.PopFont()
	im.End()

	text_line += text_increment
}


sample_step :: proc(using sample: ^Sample){
	time_step := hertz > 0 ? 1.0 /hertz : 0

	text_line = 30

	if (ctx.pause){
		if ctx.singleStep{
			ctx.singleStep = false
		}else{
			time_step = 0
		}

		if ctx.draw.show_ui{
			sample_draw_text_line(sample, "****PAUSED****")
			text_line += text_increment
		}
	}

	draw.debug_draw.drawingBounds = camera_get_view_bounds(&draw.cam)
	draw.debug_draw.useDrawingBounds = true

	b2.World_EnableSleeping(world_id,     enableSLeep)
	b2.World_EnableWarmStarting(world_id, enableWarmStarting)
	b2.World_EnableContinuous(world_id,   enableContinuous)

	b2.World_Step(world_id, time_step, i32(subStepCount))
	task_count = 0

	b2.World_Draw(world_id, &draw.debug_draw)

	if time_step > 0.0{
		step_count += 1
	}

	if draw.drawCounters{
		s := b2.World_GetCounters(world_id)

		sample_draw_text_line(sample, fmt.ctprintf("bodies/shapes/contacts/joints = %d/%d/%d/%d", s.bodyCount, s.shapeCount, s.contactCount, s.jointCount))

		sample_draw_text_line(sample, fmt.ctprintf("islands/tasks = %d/%d", s.islandCount, s.taskCount))
		sample_draw_text_line(sample, fmt.ctprintf("tree height static/movable = %d/%d", s.staticTreeHeight, s.treeHeight))


		sample_draw_text_line(sample, fmt.ctprintf("stack allocator size = %d K", s.stackUsed/1024))
		sample_draw_text_line(sample, fmt.ctprintf("stack allocation = %d K",     s.byteCount/1024))
	}

	//just show the profile for now
	{
		p := b2.World_GetProfile(world_id)

		sample_draw_text_line(sample, fmt.ctprintf("step %5.2f", p.step))
		sample_draw_text_line(sample, fmt.ctprintf("pairs %5.2f", p.pairs))
		sample_draw_text_line(sample, fmt.ctprintf("collide %5.2f", p.collide))
		sample_draw_text_line(sample, fmt.ctprintf("solve %5.2f", p.solve))
		sample_draw_text_line(sample, fmt.ctprintf("> merge islands %5.2f", p.mergeIslands))
		sample_draw_text_line(sample, fmt.ctprintf("> prepare tasks %5.2f", p.prepareStages))
		sample_draw_text_line(sample, fmt.ctprintf("> solve constraints %5.2f", p.solveConstraints))
		sample_draw_text_line(sample, fmt.ctprintf(">> prepare constraints %5.2f", p.prepareConstraints))
		sample_draw_text_line(sample, fmt.ctprintf(">> intregate velocity %5.2f", p.integrateVelocities))
		sample_draw_text_line(sample, fmt.ctprintf(">> warm start %5.2f", p.warmStart))
		sample_draw_text_line(sample, fmt.ctprintf(">> solve impulses %5.2f", p.solveImpulses))
		sample_draw_text_line(sample, fmt.ctprintf(">> integrate positions %5.2f", p.integratePositions))
		sample_draw_text_line(sample, fmt.ctprintf(">> relax impulses positions %5.2f", p.relaxImpulses))
		sample_draw_text_line(sample, fmt.ctprintf(">> apply restitution %5.2f", p.applyRestitution))
		sample_draw_text_line(sample, fmt.ctprintf(">> store impulses %5.2f", p.storeImpulses))
		sample_draw_text_line(sample, fmt.ctprintf("> update transforms %5.2f", p.transforms))
		sample_draw_text_line(sample, fmt.ctprintf("> hit events %5.2f", p.hitEvents))
		sample_draw_text_line(sample, fmt.ctprintf("> refit BVH %5.2f", p.refit))
		sample_draw_text_line(sample, fmt.ctprintf("> sleep ilands %5.2f", p.sleepIslands))
		sample_draw_text_line(sample, fmt.ctprintf("> bullets %5.2f", p.bullets))
		sample_draw_text_line(sample, fmt.ctprintf("sensors %5.2f", p.sensors))
	}
}

sample_register :: proc(category, name : string, fcn : SampleCreateFnc) -> i32{
	index := sample_count

	if index < MAX_SAMPLES{
		sample_entries[index] = {category, name, fcn}
		sample_count += 1
		return index
	}
	return -1
}


*/