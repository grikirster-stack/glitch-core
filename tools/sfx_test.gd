extends SceneTree
class_name SfxTest
## Автотест процедурного звука (ADR-001, PR-M; issue #36).
##
## Проверяет звуки vent_hum, turret_zap, swarm, doppel_whisper.
## brownout остаётся в NetCodec.SOUNDS (append-only), синтеза больше нет (#170).
## есть в Sfx.sounds, длина > 0, в сигнале нет NaN/INF, пик в [-1, 1] и звук не
## тишина, синтез детерминирован (дважды — побайтно одно и то же), петля гула
## без щелчка на стыке. Плюс API: play/play_at, промежуток GAP_MS, зацикленные
## эмиттеры (лимит голосов, ближайшие к камере, стоп без утечек плееров).
## В конце — замер: время Sfx._ready() и прогрева новых звуков.
##
## Отдельный запуск:
##   godot --headless --path . --script res://tools/sfx_test.gd
## В составе общего прогона те же проверки вызывает tools/test_runner.gd
## (секция «== Звук ==») — общий код, без дублирования.
##
## Глобальное имя автозагрузки Sfx в режиме --script на этапе компиляции
## недоступно — узел берём через get_node(), типы не указываем.

# --------------------------------------------------------------- КОНСТАНТЫ
## Новые звуки зоны PR-M.
const NEW_SOUNDS: Array = ["vent_hum", "turret_zap", "swarm", "doppel_whisper"]
## Звуки, которые были до PR-M, — не должны пропасть.
const OLD_SOUNDS: Array = ["mine", "break", "place", "pickup", "craft", "place_machine",
		"hit", "alarm", "power", "step"]
## Сколько кадров ждём, пока прогрев синтезирует новые звуки сам.
const WARM_FRAMES: int = 120
## Ниже этого пика звук считаем тишиной (сломанный синтез).
const MIN_PEAK: float = 0.05
## Повторов замера (берём медиану).
const BENCH_RUNS: int = 5


## --------------------------------------------------------------------- исполнитель
class Runner extends Node:
	var host: Node = null          ## кто-то снаружи (test_runner)
	var sfx = null                 ## узел автозагрузки Sfx

	var checks: int = 0
	var fails: int = 0
	var done: bool = false

	var _frames: int = 0
	var _waiting: bool = false


	func _init(p_host: Node = null) -> void:
		host = p_host


	func start(_main_scene: Node) -> void:
		print("== Звук ==")
		sfx = get_tree().root.get_node_or_null("Sfx")
		_ok("автозагрузка Sfx на месте", sfx != null)
		if sfx == null:
			done = true
			return
		var missing: Array = []
		for id in OLD_SOUNDS:
			if not sfx.sounds.has(id):
				missing.append(id)
		_ok("прежние звуки на месте (%d)" % OLD_SOUNDS.size(), missing.is_empty(), str(missing))
		_waiting = true


	func _process(_delta: float) -> void:
		if not _waiting:
			return
		_frames += 1
		if int(sfx.pending_count()) > 0 and _frames < WARM_FRAMES:
			return
		_waiting = false
		_ok("прогрев синтезировал новые звуки сам (за %d кадров)" % _frames,
				int(sfx.pending_count()) == 0, "осталось %d" % int(sfx.pending_count()))
		sfx.warm_all()
		_check_sounds()
		_check_play()
		_check_loops()
		_bench()
		done = true


	func _ok(label: String, cond: bool, extra: String = "") -> void:
		checks += 1
		if cond:
			print("  OK   %s %s" % [label, extra])
		else:
			fails += 1
			print("  FAIL %s %s" % [label, extra])


	# ------------------------------------------------------------ сигналы

	func _check_sounds() -> void:
		for id in NEW_SOUNDS:
			var s = sfx.sounds.get(id, null)
			var a: PackedFloat32Array = sfx.synth(id)
			var b: PackedFloat32Array = sfx.synth(id)
			var bad: int = 0
			var peak: float = 0.0
			for x in a:
				if is_nan(x) or is_inf(x):
					bad += 1
				else:
					peak = maxf(peak, absf(x))
			var len_s: float = s.get_length() if s != null else 0.0
			_ok("%s: есть в Sfx.sounds, длина > 0" % id, s != null and len_s > 0.0 and a.size() > 0,
					"%.3f с, %d отсчётов" % [len_s, a.size()])
			_ok("%s: без NaN/INF, пик в [-1, 1] и не тишина" % id,
					bad == 0 and peak <= 1.0 and peak >= MIN_PEAK, "пик %.3f, плохих %d" % [peak, bad])
			var same_stream: bool = s != null and s.data == sfx._wav(a, int(sfx.LAZY[id])).data
			_ok("%s: синтез детерминирован" % id, a == b and same_stream)
		# Петля гула: зациклена по всей длине, стык не громче обычного шага сигнала.
		var hum = sfx.sounds.get("vent_hum", null)
		var h: PackedFloat32Array = sfx.synth("vent_hum")
		var max_step: float = 0.0
		for i in range(1, h.size()):
			max_step = maxf(max_step, absf(h[i] - h[i - 1]))
		var seam: float = absf(h[0] - h[h.size() - 1]) if h.size() > 1 else 1.0
		_ok("vent_hum: петля по всему буферу", hum != null
				and hum.loop_mode == AudioStreamWAV.LOOP_FORWARD and hum.loop_begin == 0
				and hum.loop_end == h.size(), "loop_end %d" % (hum.loop_end if hum != null else -1))
		_ok("vent_hum: стык петли без щелчка", seam <= max_step,
				"стык %.4f, наибольший шаг %.4f" % [seam, max_step])
		_ok("разовые звуки не зациклены", _no_loop(["turret_zap", "swarm", "doppel_whisper"]))


	func _no_loop(ids: Array) -> bool:
		for id in ids:
			var s = sfx.sounds.get(id, null)
			if s == null or s.loop_mode != AudioStreamWAV.LOOP_DISABLED:
				return false
		return true


	# ------------------------------------------------------------ API

	func _check_play() -> void:
		var en0: bool = bool(sfx.enabled)
		sfx.enabled = true
		var lp: Vector2 = sfx._listener_pos()
		_ok("play: новый звук запускается", bool(sfx.play("turret_zap", -40.0)))
		_ok("play: неизвестное имя — без ошибки, false", not bool(sfx.play("нет_такого")))
		_ok("play_at: рядом с камерой — звучит", bool(sfx.play_at("turret_zap", lp + Vector2(32, 0), -40.0)))
		_ok("play_at: дальше HEAR_DIST — голос не тратится",
				not bool(sfx.play_at("turret_zap", lp + Vector2(sfx.HEAR_DIST + 100.0, 0), -40.0)))
		# Промежуток GAP_MS: второй запуск подряд глушится. brownout снят (#170).
		sfx._last_ms.erase("doppel_whisper")
		var first: bool = bool(sfx.play("doppel_whisper", -40.0))
		var second: bool = bool(sfx.play("doppel_whisper", -40.0))
		_ok("doppel_whisper: повтор раньше GAP_MS не звучит", first and not second)
		sfx.enabled = false
		_ok("enabled = false: тишина", not bool(sfx.play("swarm")) and not bool(sfx.play_at("swarm", lp)))
		sfx.enabled = en0


	func _check_loops() -> void:
		var en0: bool = bool(sfx.enabled)
		sfx.enabled = true
		var kids0: int = sfx.get_child_count()
		var loops0: int = int(sfx.loop_count())
		var lp: Vector2 = sfx._listener_pos()
		var voices: int = int(sfx.LOOP_VOICES)

		_ok("loop_start: неизвестное имя — 0", int(sfx.loop_start("нет_такого", lp)) == 0)
		_ok("loop_start: разовый звук не зацикливается — 0", int(sfx.loop_start("turret_zap", lp)) == 0)

		# 10 вентиляций: ручка i на расстоянии 10·i от камеры, 11-я — за пределом слышимости.
		var hs: Array = []
		for i in 10:
			hs.append(int(sfx.loop_start("vent_hum", lp + Vector2(10.0 * float(i + 1), 0.0), -30.0)))
		var far: int = int(sfx.loop_start("vent_hum", lp + Vector2(sfx.HEAR_DIST * 2.0, 0.0), -30.0))
		var all_ok: bool = far > 0
		for h in hs:
			if h <= 0:
				all_ok = false
		_ok("loop_start: 11 эмиттеров заведены", all_ok and int(sfx.loop_count()) == loops0 + 11)
		var voiced: Array = sfx.loop_voiced()
		var nearest: bool = true
		for i in voices:
			if not voiced.has(hs[i]):
				nearest = false
		_ok("звучат не больше %d голосов" % voices, voiced.size() <= voices, "звучит %d" % voiced.size())
		_ok("голоса у ближайших к камере", nearest and not voiced.has(far), str(voiced))
		var playing: int = 0
		for p in sfx._loop_players:
			if p.playing:
				playing += 1
		_ok("плееры петель играют", playing == voiced.size(), "играет %d" % playing)

		# Стоп ближайшего — голос переходит к следующему по расстоянию.
		sfx.loop_stop(hs[0])
		voiced = sfx.loop_voiced()
		_ok("loop_stop: голос переходит к следующему", not voiced.has(hs[0]) and voiced.has(hs[voices]),
				str(voiced))
		sfx.loop_stop(hs[0])
		sfx.loop_stop(-5)
		_ok("loop_stop: повтор и чужая ручка — без ошибки", int(sfx.loop_count()) == loops0 + 10)

		# Перенос: дальний эмиттер подвинулся к камере — получил голос.
		sfx.loop_move(far, lp)
		sfx._refresh_loops()
		_ok("loop_move: подвинутый к камере эмиттер зазвучал", sfx.loop_voiced().has(far))

		# Лимит эмиттеров: сверх MAX_LOOPS — 0, записи не копятся.
		var extra: Array = []
		for i in int(sfx.MAX_LOOPS) + 5:
			var h: int = int(sfx.loop_start("vent_hum", lp + Vector2(0.0, 2000.0 + float(i)), -30.0))
			if h > 0:
				extra.append(h)
		_ok("эмиттеров не больше MAX_LOOPS", int(sfx.loop_count()) == int(sfx.MAX_LOOPS),
				"%d" % int(sfx.loop_count()))

		for h in hs + extra + [far]:
			sfx.loop_stop(h)
		var silent: bool = true
		for p in sfx._loop_players:
			if p.playing or p.stream != null:
				silent = false
		_ok("после стопа: эмиттеров как до теста, плееры молчат",
				int(sfx.loop_count()) == loops0 and silent)
		_ok("плееры не создаются и не теряются (утечек нет)", sfx.get_child_count() == kids0,
				"узлов %d → %d" % [kids0, sfx.get_child_count()])
		sfx.enabled = en0


	# ------------------------------------------------------------ замер

	## Свежий экземпляр sfx.gd: время _ready() (прежние звуки + пулы) и прогрева
	## новых звуков. Медиана BENCH_RUNS повторов.
	func _bench() -> void:
		var scr: Script = load("res://scripts/autoload/sfx.gd")
		var ready_ms: Array = []
		var warm_ms: Array = []
		var per: Dictionary = {}
		for id in NEW_SOUNDS:
			per[id] = []
		for r in BENCH_RUNS:
			var inst: Node = scr.new()
			var t0: int = Time.get_ticks_usec()
			inst._ready()
			var t1: int = Time.get_ticks_usec()
			for id in NEW_SOUNDS:
				var ta: int = Time.get_ticks_usec()
				inst.ensure(id)
				per[id].append(float(Time.get_ticks_usec() - ta) / 1000.0)
			var t2: int = Time.get_ticks_usec()
			ready_ms.append(float(t1 - t0) / 1000.0)
			warm_ms.append(float(t2 - t1) / 1000.0)
			inst.free()
		var parts: PackedStringArray = PackedStringArray()
		for id in NEW_SOUNDS:
			parts.append("%s %.2f" % [id, _median(per[id])])
		print("  ЗАМЕР  Sfx._ready(): медиана %.2f мс; прогрев 5 новых звуков: %.2f мс (%s); всего %.2f мс"
				% [_median(ready_ms), _median(warm_ms), ", ".join(parts), _median(ready_ms) + _median(warm_ms)])


	func _median(a: Array) -> float:
		var s: Array = a.duplicate()
		s.sort()
		return float(s[s.size() / 2]) if not s.is_empty() else 0.0


# ------------------------------------------------------------- отдельный запуск

var _runner: Node = null
var _started: bool = false


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_runner = Runner.new(null)
		root.add_child(_runner)
		_runner.start(null)
		return false
	if _runner == null:
		return false
	if _runner.done:
		print("")
		print("ИТОГ: проверок %d, провалов %d" % [_runner.checks, _runner.fails])
		quit(1 if _runner.fails > 0 else 0)
		return true
	return false
