class_name AimLine
extends RefCounted
## Aiming geometry. Aim is measured from ONE origin and projectiles spawn on the
## line from that origin toward the target, so every shot crosses the crosshair.
##
## Usage:
##   var dir := AimLine.direction(hand, mouse, dir)
##   var spawn := AimLine.spawn_point(hand, dir, muzzle_offset)


## Unit direction from [param origin] to [param target]; [param fallback] when they coincide.
static func direction(origin: Vector2, target: Vector2, fallback: Vector2 = Vector2.RIGHT) -> Vector2:
	var to_target := target - origin
	return to_target.normalized() if to_target.length() > 4.0 else fallback


## Where a projectile appears: [param offset] pixels along the aim line.
static func spawn_point(origin: Vector2, dir: Vector2, offset: float) -> Vector2:
	return origin + dir * offset


## Distance from [param point] to the ray that starts at [param start] going [param dir].
static func miss_distance(start: Vector2, dir: Vector2, point: Vector2) -> float:
	var along: float = (point - start).dot(dir)
	return (start + dir * along).distance_to(point)
