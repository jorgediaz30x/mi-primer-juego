extends RefCounted
## Minimal assertion base for the headless runner (stand-in until gdUnit4 is installed).

var failures: Array[String] = []
var current_test: String = ""


func assert_true(condition: bool, message: String = "") -> void:
	if not condition:
		failures.append("%s: expected true. %s" % [current_test, message])


func assert_false(condition: bool, message: String = "") -> void:
	assert_true(not condition, message)


func assert_eq(actual: Variant, expected: Variant, message: String = "") -> void:
	if actual != expected:
		failures.append("%s: expected <%s> got <%s>. %s" % [current_test, expected, actual, message])


func assert_near(actual: float, expected: float, tolerance: float = 0.0001, message: String = "") -> void:
	if absf(actual - expected) > tolerance:
		failures.append("%s: expected ~%f got %f. %s" % [current_test, expected, actual, message])
