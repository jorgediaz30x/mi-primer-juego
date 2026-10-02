extends SceneTree
## Headless unit test runner.
##
##   godot --headless --path . -s res://tests/run_unit_tests.gd
##
## Finds every *_test.gd under res://tests/unit, runs each test_* method on a
## fresh instance, prints results and exits 1 on any failure.

const ROOT := "res://tests/unit"


func _initialize() -> void:
	var files: Array[String] = []
	_collect(ROOT, files)
	var passed: int = 0
	var failed: int = 0
	for path in files:
		var script: GDScript = load(path)
		for method: Dictionary in script.get_script_method_list():
			var method_name: String = method["name"]
			if not method_name.begins_with("test_"):
				continue
			var suite: Object = script.new()
			suite.current_test = "%s::%s" % [path.get_file(), method_name]
			suite.call(method_name)
			if suite.failures.is_empty():
				passed += 1
				print("  PASS ", suite.current_test)
			else:
				failed += 1
				for f: String in suite.failures:
					print("  FAIL ", f)
	print("\n%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)


func _collect(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_collect(dir_path.path_join(sub), out)
	for file in dir.get_files():
		if file.ends_with("_test.gd"):
			out.append(dir_path.path_join(file))
