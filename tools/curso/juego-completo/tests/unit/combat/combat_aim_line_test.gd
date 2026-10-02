extends "res://tests/test_case.gd"
## AimLine: the projectile path must cross the crosshair.
## Regression: aim was measured from one point and bolts spawned 43 px above it,
## so every shot flew parallel to the aim and passed over the target.

const HAND := Vector2(200, 529)
const CROSSHAIR := Vector2(420, 600)
const MUZZLE := 34.0


func test_projectile_path_crosses_the_crosshair() -> void:
	var dir := AimLine.direction(HAND, CROSSHAIR)
	var spawn := AimLine.spawn_point(HAND, dir, MUZZLE)
	assert_near(AimLine.miss_distance(spawn, dir, CROSSHAIR), 0.0, 0.01)


func test_old_bug_aiming_from_another_point_misses() -> void:
	# The bug: direction from the chest (y 572), bolt spawned from the hand (y 529).
	var chest := HAND + Vector2(0, 43)
	var dir := AimLine.direction(chest, CROSSHAIR)
	var spawn := AimLine.spawn_point(HAND, dir, MUZZLE)
	assert_true(AimLine.miss_distance(spawn, dir, CROSSHAIR) > 30.0, "the old geometry misses by ~40 px")


func test_direction_falls_back_when_target_is_on_origin() -> void:
	assert_eq(AimLine.direction(HAND, HAND + Vector2(1, 1), Vector2.LEFT), Vector2.LEFT)
