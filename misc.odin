package main

import "core:math"
import "core:slice"
import b2 "vendor:box2d"


centroid :: proc(points: []b2.Vec2) -> b2.Vec2{
    center := b2.Vec2{0,0}
    for p in points do center += p
    center /= f32(len(points))
    return center
}


cross :: proc(o, a, b : b2.Vec2) -> f32{
    return (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
}

//For sorting
curr_center : b2.Vec2

sort_points_ccw :: proc(points : []b2.Vec2){
    if len(points) == 0 do return

    curr_center = centroid(points)
    slice.sort_by(points , proc(a, b: b2.Vec2) -> bool{
	c := cross(curr_center, a, b)

	if abs(c) < 1e-7{
	    return b2.Distance(curr_center, a) < b2.Distance(curr_center, b)
	}
	return c > 0
    })
}

FlipDirection :: enum {
    Horizontal,
    Vertical,
    Both,  // Flip both horizontally and vertically
}


flip_points :: proc(points: []b2.Vec2, direction : FlipDirection){
    for &vertex, i in points{
        switch direction {
        case .Horizontal:
            points[i] = b2.Vec2{-vertex.x, vertex.y}
        case .Vertical:
            points[i] = b2.Vec2{vertex.x, -vertex.y}
        case .Both:
            points[i] = b2.Vec2{-vertex.x, -vertex.y}
        }
    }
}