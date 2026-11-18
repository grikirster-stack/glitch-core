extends ScenarioBase
## Битый файл в реестре (#227, дыра приёмки #229).
##
## Раньше ветка «load() не инстанцируется → явный FAIL → следующий сценарий»
## проверялась файлом вне реестра. Здесь запись кладётся в реестр прогона на
## время двух шагов настоящего _next_scenario, файл — битый скрипт рядом.
## Оба убираются в finish: закоммиченный битый файл уронил бы --scenario=all
## (CI роняет шаг на любом SCRIPT ERROR, включая Parse Error при импорте).


const BROKEN_NAME: String = "load_guard_broken"
const BROKEN_FILE: String = "load_guard_broken.gd"
const NEXT_NAME: String = "load_guard_next"
const NEXT_FILE: String = "load_guard_next.gd"


var _broken_abs: String = ""
var _next_abs: String = ""
var _saved_queue: Array = []
var _saved_total: int = 0
var _saved_checks: int = 0
var _saved_fails: int = 0
var _banner: String = ""
var _probe_fails: int = -1
var _probe_checks: int = -1


func run() -> void:
	_plant()
	_saved_queue = runner._queue.duplicate()
	_saved_total = runner.scenarios_total
	_saved_checks = runner.checks
	_saved_fails = runner.fails
	runner.quiet_fail = true
	runner.skip_reset = true
	runner._queue = [BROKEN_NAME, NEXT_NAME]
	runner.scenarios_total = 2
	runner.checks = 0
	runner.fails = 0
	runner.quiet_banner = ""
	runner._next_scenario()
	var advanced: bool = await wait_until(func() -> bool:
		return runner._current != null and runner._current != self, 8.0)
	# Сосед — настоящий сценарий реестра: дождались его старта, значит очередь
	# после битого файла не встала.
	var neighbor: String = ""
	if runner._current != null:
		neighbor = runner._current.get_script().resource_path.get_file()
	_probe_fails = runner.fails
	_probe_checks = runner.checks
	_banner = runner.quiet_banner
	runner.quiet_fail = false
	runner.quiet_banner = ""
	runner.skip_reset = false
	# Чужой сценарий не гоняем до конца: проба про загрузку, не про его проверки.
	if runner._current != null and runner._current != self:
		runner._current.queue_free()
		runner._current = self
	runner._queue = _saved_queue
	runner.scenarios_total = _saved_total
	runner.checks = _saved_checks
	runner.fails = _saved_fails
	ok("битый файл в реестре — явный провал загрузки", _probe_fails == 1,
			"провалов пробы %d" % _probe_fails)
	ok("баннер «Сценарий не загрузился»", _banner.find(BROKEN_FILE) >= 0, _banner)
	ok("следующий сценарий продолжился", advanced and neighbor == NEXT_FILE, neighbor)
	ok("проба не повисла: очередь дошла до соседа", _probe_checks >= 1,
			"проверок пробы %d" % _probe_checks)
	_sweep()
	finish()


## Положить битый файл и две записи. Живой сосед — smoke.gd, он уже в реестре:
## второго файла не нужно, и --scenario=all его не увидит как новый сценарий.
func _plant() -> void:
	_broken_abs = ProjectSettings.globalize_path(ScenarioRunner.DIR + BROKEN_FILE)
	var f: FileAccess = FileAccess.open(_broken_abs, FileAccess.WRITE)
	if f == null:
		ok("временный битый файл записан", false, _broken_abs)
		return
	f.store_string("extends NotAType\nfunc run() -> void:\n\tpass\n")
	f.close()
	ScenarioRunner._probe_registry[BROKEN_NAME] = {"file": BROKEN_FILE, "title": "битый файл пробы"}
	# Сосед — существующий файл, но своё имя: иначе очередь не отличит его от
	# настоящего smoke, если тот ещё впереди в --scenario=all.
	ScenarioRunner._probe_registry[NEXT_NAME] = {"file": NEXT_FILE, "title": "живой сосед пробы"}
	_next_abs = ProjectSettings.globalize_path(ScenarioRunner.DIR + NEXT_FILE)
	var g: FileAccess = FileAccess.open(_next_abs, FileAccess.WRITE)
	if g != null:
		g.store_string("extends ScenarioBase\nfunc run() -> void:\n\tawait get_tree().process_frame\n\tfinish()\n")
		g.close()


func finish() -> void:
	_sweep()
	super()


func _sweep() -> void:
	ScenarioRunner._probe_registry.erase(BROKEN_NAME)
	ScenarioRunner._probe_registry.erase(NEXT_NAME)
	if _broken_abs != "" and FileAccess.file_exists(_broken_abs):
		DirAccess.remove_absolute(_broken_abs)
	if _broken_abs != "" and FileAccess.file_exists(_broken_abs + ".uid"):
		DirAccess.remove_absolute(_broken_abs + ".uid")
	if _next_abs != "" and FileAccess.file_exists(_next_abs):
		DirAccess.remove_absolute(_next_abs)
	if _next_abs != "" and FileAccess.file_exists(_next_abs + ".uid"):
		DirAccess.remove_absolute(_next_abs + ".uid")
	if runner != null:
		runner.quiet_fail = false
		runner.skip_reset = false
