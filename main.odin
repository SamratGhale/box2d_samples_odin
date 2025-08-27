package main

import gl "vendor:OpenGL"
import "core:fmt"
import "vendor:glfw"
import b2 "vendor:box2d"
import enki "shared:odin-enkiTS/enki"
import im "shared:odin-imgui"
import "shared:odin-imgui/imgui_impl_glfw"
import "shared:odin-imgui/imgui_impl_opengl3"

WIDTH  :: 1600
HEIGHT :: 900 

TITLE  :: "My Window!"

GL_MAJOR_VERSION :: 4
GL_MINOR_VERSION :: 5

sample_ctx :SampleContext


update_ui :: proc(){

	max_workers : i32 = 8


	menu_width :f32= 180.0

	if sample_ctx.draw.show_ui{
		//im.SetNextWindowPos({f32(sample_ctx.draw.cam.width) - menu_width - 10.0, 10.0})
		//im.SetNextWindowSize({menu_width, f32(sample_ctx.draw.cam.height) - 20.0})

		im.Begin("Tools", &sample_ctx.draw.show_ui)

		if im.BeginTabBar("Control Tabs"){
			if im.BeginTabItem("Controls"){
				im.PushItemWidth(100.0)
				//im.SliderInt("Sub-steps", &sample_ctx.subStepCount, 1, 50)
				//im.SliderFloat("Hertz", &hertz, 5.0, 120.0, "%.0f hz")


				im.PopItemWidth()
				im.Separator()

				//im.Checkbox("Sleep",         &sample_ctx.enableSleep)
				im.Checkbox("Warm Starting", &sample_ctx.enableWarmStarting)
				im.Checkbox("Continuous",    &sample_ctx.enableContinuous)

				im.Separator()

				debug_draw := &sample_ctx.draw.debug_draw

				im.Checkbox("Shapes",    &debug_draw.drawShapes)
				im.Checkbox("Joints",    &debug_draw.drawJoints)
				im.Checkbox("Joint Extras",    &debug_draw.drawJointExtras)
				im.Checkbox("Bounds",          &debug_draw.drawBounds)
				im.Checkbox("Contact Points",  &debug_draw.drawContacts)
				im.Checkbox("Contact Normals", &debug_draw.drawContactNormals)
				im.Checkbox("Contact Inpulses", &debug_draw.drawContactImpulses)
				im.Checkbox("Contact Features", &debug_draw.drawContactFeatures)
				im.Checkbox("Friction Inpulses", &debug_draw.drawFrictionImpulses)
				im.Checkbox("Mass ", &debug_draw.drawMass)
				im.Checkbox("Body Names", &debug_draw.drawBodyNames)
				im.Checkbox("Graph Colors", &debug_draw.drawGraphColors)
				im.Checkbox("Islands ", &debug_draw.drawIslands)
				//im.Checkbox("Counts ", &debug_draw.drawContacts)

				im.EndTabItem()
			}
			im.EndTabBar()
		}
		im.End()
	}



}

main :: proc (){

	if !glfw.Init(){
		fmt.eprintfln("GLFW has failed to load.")
		return
	}

	glfw.WindowHint(glfw.SCALE_TO_MONITOR, 1)

	sample_register("Bodies", "Kinematic", kinematic_create)

	sample_ctx.window = glfw.CreateWindow(WIDTH, HEIGHT, TITLE, nil, nil)
	sample_ctx.workerCount = 2

	defer glfw.Terminate()
	defer glfw.DestroyWindow(sample_ctx.window)


	if sample_ctx.window == nil{
		fmt.eprintln("GLFW has failed to load the window.")
		return
	}

	glfw.MakeContextCurrent(sample_ctx.window)
	glfw.SwapInterval(1)

	gl.load_up_to(GL_MAJOR_VERSION, GL_MINOR_VERSION, glfw.gl_set_proc_address)


	//Imgui
	im.CHECKVERSION()
	im.CreateContext()

	io := im.GetIO()
	io.ConfigFlags += {.NavEnableKeyboard, .NavEnableGamepad}

	im.FontAtlas_AddFontFromFileTTF(io.Fonts, "c:\\Windows\\Fonts\\Consola.ttf", 22)

	imgui_impl_glfw.InitForOpenGL(sample_ctx.window, true)
	defer imgui_impl_glfw.Shutdown()
	imgui_impl_opengl3.Init("#version 150")
	defer imgui_impl_opengl3.Shutdown()



	world_def := b2.DefaultWorldDef()
	world_def.gravity.y = 9.8 
	world_id := b2.CreateWorld(world_def)

	body_def := b2.DefaultBodyDef()
	body_def.type  = .kinematicBody
	body_def.position.x = 2.0 

	body_id := b2.CreateBody(world_id, body_def)

	box       := b2.MakeBox(0.1, 1.0)
	shape_def := b2.DefaultShapeDef()
	shape_id  := b2.CreatePolygonShape(body_id, shape_def, box)

	display_w, display_h := glfw.GetFramebufferSize(sample_ctx.window)
	sample_ctx.draw.cam.width  = display_w
	sample_ctx.draw.cam.height = display_h

	draw_create(&sample_ctx.draw, &sample_ctx.draw.cam)



	sample := sample_entries[0].create_fcn(&sample_ctx)


	sample.draw.show_ui = true


	fmt.println(sample_ctx.draw.cam)

	gl.ClearColor(0.2, 0.2, 0.2, 1.0)
	for !glfw.WindowShouldClose(sample_ctx.window){


		glfw.PollEvents()

		width, height := glfw.GetWindowSize(sample_ctx.window)
		sample_ctx.draw.cam.width  = width
		sample_ctx.draw.cam.height = height


		display_w, display_h := glfw.GetFramebufferSize(sample_ctx.window)
		gl.Viewport(0, 0, display_w, display_h)

		gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)


		imgui_impl_opengl3.NewFrame()
		imgui_impl_glfw.NewFrame()


		im.NewFrame()

		im.SetNextWindowPos({0, 0})
		im.SetNextWindowSize({f32(sample_ctx.draw.cam.width), f32(sample_ctx.draw.cam.height)})
		im.SetNextWindowBgAlpha(0)


		{
			kinematic_step(cast(^Kinematic)sample)

			draw_flush(&sample.draw)

			update_ui()
		}

		//im.ShowDemoWindow()


		im.Render()

		imgui_impl_opengl3.RenderDrawData(im.GetDrawData())

		glfw.SwapBuffers(sample_ctx.window)
	}
}














