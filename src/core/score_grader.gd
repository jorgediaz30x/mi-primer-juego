class_name ScoreGrader
extends RefCounted
## End-of-run letter grade from points. Thresholds come from config "scoring.grades".

var _grades: Array[Dictionary] = []


func _init(grades: Array = []) -> void:
	for g: Variant in grades:
		if g is Dictionary:
			_grades.append(g)
	_grades.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("min_points", 0)) > int(b.get("min_points", 0)))


## Best grade whose threshold [param points] reaches, or "-" when none match.
func grade_for(points: int) -> String:
	for g in _grades:
		if points >= int(g.get("min_points", 0)):
			return str(g.get("grade", "-"))
	return "-"
