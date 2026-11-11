extends Node
## Процедурный звук: все эффекты синтезируются кодом (WAV-буферы в памяти).
##
## Разовые звуки — `play()` (без позиции) и `play_at()` (с позицией, тише с
## расстоянием до камеры). Зацикленные звуки-эмиттеры (гул вентиляции) —
## `loop_start()` / `loop_move()` / `loop_stop()`: эмиттеров может быть много,
## а звучат только LOOP_VOICES ближайших к камере, плееры не создаются и не
## удаляются после _ready (ADR-001, PR-M, issue #36).
##
## Новые звуки (vent_hum, turret_zap, swarm, doppel_whisper) не
## синтезируются в _ready: их «прогревает» _process по одному за кадр, а если
## звук попросили раньше — он синтезируется по требованию. Так _ready не
## дорожает (приёмка #36: рост не больше 20 %).

const RATE: int = 22050
## Частота для низких звуков: гулу и просадке хватает полосы до 5.5 кГц.
const RATE_LOW: int = 11025

## Разовые позиционные голоса (турель, рой) — отдельный пул, чтобы залп
## турелей не перебивал шаги и копку из основного пула.
const POS_VOICES: int = 6
## Сколько зацикленных эмиттеров звучат одновременно (ближайшие к камере).
const LOOP_VOICES: int = 4
## Больше эмиттеров не заводим: забытый loop_stop не должен копить записи.
const MAX_LOOPS: int = 64
## Дальше этого расстояния (пиксели мира, ~45 тайлов) позиционный звук не слышен.
const HEAR_DIST: float = 720.0
## Как часто пересчитываем, какие эмиттеры ближе всего к камере, с.
const LOOP_REFRESH: float = 0.25
## Минимальный промежуток между повторами одного звука, мс. Защищает пул
## от спама: стая фантомов, шёпот каждый кадр взгляда, дребезг просадки.
const GAP_MS: Dictionary = {
	"swarm": 120,
	"doppel_whisper": 1500,
	"cat_meow": 400,
}
## Новые звуки: имя → частота дискретизации. Синтез отложенный (см. выше).
const LAZY: Dictionary = {
	"vent_hum": RATE_LOW,
	"turret_zap": RATE,
	"swarm": RATE,
	"doppel_whisper": RATE,
	"siren": RATE,
	"cat_meow": RATE,
}
## Зацикленные звуки (петля по всей длине буфера).
const LOOPED: Dictionary = {"vent_hum": true}

var sounds: Dictionary = {}
var _pool: Array[AudioStreamPlayer] = []
var _next: int = 0
var enabled: bool = true

var _pos_pool: Array[AudioStreamPlayer2D] = []
var _pos_next: int = 0
## Ещё не синтезированные новые звуки (прогрев по одному за кадр).
var _pending: Array = []
## Имя → время последнего запуска (мс), для GAP_MS.
var _last_ms: Dictionary = {}

## Эмиттеры: ручка → {"name", "pos", "db", "pitch"}.
var _loops: Dictionary = {}
var _loop_seq: int = 0
var _loop_players: Array[AudioStreamPlayer2D] = []
## Какой ручке отдан голос (0 — свободен), по индексу голоса.
var _voice_owner: PackedInt32Array = PackedInt32Array()
var _refresh_t: float = 0.0


func _ready() -> void:
	sounds["mine"] = _wav(_noise_hit(0.05, 320.0, 0.35, 0.6))
	sounds["break"] = _wav(_noise_hit(0.22, 180.0, 0.7, 0.9))
	sounds["place"] = _wav(_noise_hit(0.07, 420.0, 0.3, 0.5))
	sounds["pickup"] = _wav(_blip(520.0, 880.0, 0.10, 0.35))
	sounds["craft"] = _wav(_blip(440.0, 660.0, 0.16, 0.40))
	sounds["place_machine"] = _wav(_blip(180.0, 140.0, 0.18, 0.45))
	sounds["hit"] = _wav(_noise_hit(0.25, 120.0, 0.9, 1.0))
	sounds["alarm"] = _wav(_alarm())
	sounds["power"] = _wav(_blip(300.0, 1200.0, 0.22, 0.30))
	sounds["step"] = _wav(_noise_hit(0.04, 140.0, 0.25, 0.25))
	for i in 12:
		var p: AudioStreamPlayer = AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_pool.append(p)
	for i in POS_VOICES:
		_pos_pool.append(_new_player_2d())
	_voice_owner.resize(LOOP_VOICES)
	for i in LOOP_VOICES:
		_loop_players.append(_new_player_2d())
		_voice_owner[i] = 0
	_pending = LAZY.keys()
	set_process(true)


func _process(delta: float) -> void:
	if not _pending.is_empty():
		ensure(String(_pending.pop_front()))
	if not _loops.is_empty() or _voices_busy() > 0:
		_refresh_t -= delta
		if _refresh_t <= 0.0:
			_refresh_loops()
	elif _pending.is_empty():
		set_process(false)


# ------------------------------------------------------------------ публичный API

## Разовый звук без позиции. Возвращает false, если звук не запущен
## (звук выключен, имени нет, не прошёл промежуток GAP_MS).
func play(name: String, volume_db: float = 0.0, pitch: float = 1.0) -> bool:
	if not enabled or _pool.is_empty() or not ensure(name) or not _gap_ok(name):
		return false
	var p: AudioStreamPlayer = _pool[_next]
	_next = (_next + 1) % _pool.size()
	p.stream = sounds[name]
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()
	return true


## Разовый звук в точке мира: тише с расстоянием до камеры, дальше HEAR_DIST
## не запускается вовсе (голос не тратится).
func play_at(id: String, pos: Vector2, volume_db: float = 0.0, pitch: float = 1.0) -> bool:
	if not enabled or _pos_pool.is_empty() or not ensure(id):
		return false
	if _listener_pos().distance_to(pos) > HEAR_DIST or not _gap_ok(id):
		return false
	var p: AudioStreamPlayer2D = _pos_pool[_pos_next]
	_pos_next = (_pos_next + 1) % _pos_pool.size()
	p.stream = sounds[id]
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.global_position = pos
	p.play()
	return true


## Заводит зацикленный эмиттер в точке мира. Возвращает ручку (> 0) для
## loop_move/loop_stop или 0, если имя неизвестно, звук не зациклен или
## эмиттеров уже MAX_LOOPS. Звучат только LOOP_VOICES ближайших к камере.
func loop_start(id: String, pos: Vector2, volume_db: float = 0.0, pitch: float = 1.0) -> int:
	if not LOOPED.has(id) or _loops.size() >= MAX_LOOPS or not ensure(id):
		return 0
	_loop_seq += 1
	_loops[_loop_seq] = {"name": id, "pos": pos, "db": volume_db, "pitch": pitch}
	set_process(true)
	_refresh_loops()
	return _loop_seq


## Переносит эмиттер (движущийся источник). Голоса пересчитываются по таймеру.
func loop_move(handle: int, pos: Vector2) -> void:
	if not _loops.has(handle):
		return
	_loops[handle]["pos"] = pos
	var v: int = _voice_owner.find(handle)
	if v >= 0:
		_loop_players[v].global_position = pos


## Глушит эмиттер. Неизвестная или уже заглушённая ручка — без ошибки.
func loop_stop(handle: int) -> void:
	if not _loops.has(handle):
		return
	_loops.erase(handle)
	_refresh_loops()


## Глушит все эмиттеры (или только с этим именем).
func loop_stop_all(id: String = "") -> void:
	for h in _loops.keys():
		if id == "" or String(_loops[h]["name"]) == id:
			_loops.erase(h)
	_refresh_loops()


## Сколько эмиттеров заведено.
func loop_count() -> int:
	return _loops.size()


## Ручки эмиттеров, которым сейчас отдан голос.
func loop_voiced() -> Array:
	var out: Array = []
	for h in _voice_owner:
		if h != 0:
			out.append(h)
	return out


## Синтезирует звук, если его ещё нет. false — имя неизвестно.
func ensure(id: String) -> bool:
	if sounds.has(id):
		return true
	if not LAZY.has(id):
		return false
	var s: AudioStreamWAV = _wav(synth(id), int(LAZY[id]))
	if LOOPED.has(id):
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = s.data.size() / 2   # 16 бит, моно: 2 байта на отсчёт
	sounds[id] = s
	_pending.erase(id)
	return true


## Синтезирует все отложенные звуки сразу (тесты, замер).
func warm_all() -> void:
	for id in LAZY:
		ensure(String(id))


## Сколько новых звуков ещё ждут прогрева.
func pending_count() -> int:
	return _pending.size()


## Сырой сигнал нового звука (float, без клиппинга) — для тестов и замера.
## Детерминирован: шум берётся из генераторов с постоянным сидом.
func synth(id: String) -> PackedFloat32Array:
	match id:
		"vent_hum":
			return _syn_vent_hum()
		"turret_zap":
			return _syn_turret_zap()
		"swarm":
			return _syn_swarm()
		"doppel_whisper":
			return _syn_doppel_whisper()
		"siren":
			return _syn_siren()
		"cat_meow":
			return _syn_cat_meow()
	return PackedFloat32Array()


# ------------------------------------------------------------------ голоса

func _new_player_2d() -> AudioStreamPlayer2D:
	var p: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
	p.bus = "Master"
	p.max_distance = HEAR_DIST
	add_child(p)
	return p


## Центр экрана в координатах мира — там «уши» 2D-звука.
func _listener_pos() -> Vector2:
	var vp: Viewport = get_viewport()
	if vp == null:
		return Vector2.ZERO
	var cam: Camera2D = vp.get_camera_2d()
	if cam != null:
		return cam.get_screen_center_position()
	return vp.get_canvas_transform().affine_inverse() * (vp.get_visible_rect().size * 0.5)


func _gap_ok(id: String) -> bool:
	if not GAP_MS.has(id):
		return true
	var now: int = Time.get_ticks_msec()
	if _last_ms.has(id) and now - int(_last_ms[id]) < int(GAP_MS[id]):
		return false
	_last_ms[id] = now
	return true


func _voices_busy() -> int:
	var n: int = 0
	for h in _voice_owner:
		if h != 0:
			n += 1
	return n


## Отдаёт голоса LOOP_VOICES ближайшим слышимым эмиттерам. Уже звучащие
## эмиттеры не перезапускаются — петля не щёлкает при пересчёте.
func _refresh_loops() -> void:
	_refresh_t = LOOP_REFRESH
	var want: Dictionary = {}
	if enabled and not _loops.is_empty():
		var lp: Vector2 = _listener_pos()
		var cand: Array = []
		for h in _loops:
			var d: float = lp.distance_to(_loops[h]["pos"])
			if d <= HEAR_DIST:
				cand.append([d, int(h)])
		cand.sort_custom(func(a: Array, b: Array) -> bool:
			return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
		for i in mini(LOOP_VOICES, cand.size()):
			want[int(cand[i][1])] = true
	for v in LOOP_VOICES:
		var h: int = _voice_owner[v]
		if h != 0 and not want.has(h):
			_loop_players[v].stop()
			_loop_players[v].stream = null
			_voice_owner[v] = 0
		elif h != 0:
			_loop_players[v].global_position = _loops[h]["pos"]
			want.erase(h)
	for h in want:
		var v: int = _voice_owner.find(0)
		if v < 0:
			break
		var e: Dictionary = _loops[h]
		var p: AudioStreamPlayer2D = _loop_players[v]
		var s: AudioStreamWAV = sounds[e["name"]]
		p.stream = s
		p.volume_db = float(e["db"])
		# Лёгкая расстройка и сдвиг фазы по ручке: две вентиляции рядом
		# не сливаются в один громкий гул.
		p.pitch_scale = float(e["pitch"]) * (1.0 + float(int(h) % 5 - 2) * 0.012)
		p.global_position = e["pos"]
		_voice_owner[v] = int(h)
		p.play(fmod(float(h) * 0.37, maxf(0.01, s.get_length())))


# ------------------------------------------------------------------ синтез: старые

func _noise_hit(dur: float, freq: float, decay: float, vol: float) -> PackedFloat32Array:
	var n: int = int(dur * RATE)
	var data: PackedFloat32Array = PackedFloat32Array()
	data.resize(n)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = int(freq) * 31 + n
	var last: float = 0.0
	for i in n:
		var t: float = float(i) / float(n)
		var env: float = pow(1.0 - t, 1.0 + decay * 4.0)
		var raw: float = rng.randf_range(-1.0, 1.0)
		# Простой однополюсный фильтр — звук получается «каменным».
		last = last * 0.72 + raw * 0.28
		data[i] = last * env * vol
	return data


func _blip(f0: float, f1: float, dur: float, vol: float) -> PackedFloat32Array:
	var n: int = int(dur * RATE)
	var data: PackedFloat32Array = PackedFloat32Array()
	data.resize(n)
	var phase: float = 0.0
	for i in n:
		var t: float = float(i) / float(n)
		var f: float = lerpf(f0, f1, t)
		phase += TAU * f / float(RATE)
		var env: float = sin(PI * t) * vol
		data[i] = sin(phase) * env
	return data


func _alarm() -> PackedFloat32Array:
	var dur: float = 0.9
	var n: int = int(dur * RATE)
	var data: PackedFloat32Array = PackedFloat32Array()
	data.resize(n)
	for i in n:
		var t: float = float(i) / float(n)
		var f: float = 420.0 + sin(t * TAU * 5.0) * 180.0
		var phase: float = f * float(i) / float(RATE) * TAU
		var env: float = minf(1.0, t * 8.0) * (1.0 - t * 0.4)
		data[i] = signf(sin(phase)) * 0.28 * env
	return data


# ------------------------------------------------------------------ синтез: новые
#
# Медленные модуляторы (лопасти, слоги, огибающие) считаем раз в CTRL отсчётов,
# а не на каждом: синтез в разы дешевле, на слух разницы нет.

## Шаг управляющих сигналов, отсчётов. 49 делит 11025 нацело — у петли гула
## последний блок кончается ровно на стыке.
const CTRL: int = 49


## Гул вентиляции: ровно 1 с, все частоты целые — петля без щелчка на стыке.
## Низкий гудящий тон, «воп-воп» лопастей и шум воздуха в шахте.
func _syn_vent_hum() -> PackedFloat32Array:
	var rate: int = RATE_LOW
	var n: int = rate
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 9101
	var noise: PackedFloat32Array = PackedFloat32Array()
	noise.resize(n)
	for i in n:
		noise[i] = rng.randf_range(-1.0, 1.0)
	# Фильтр шума прогреваем хвостом петли: к началу он в том же состоянии,
	# что и в конце, — стык петли непрерывен.
	var lp: float = 0.0
	for i in range(n - 256, n):
		lp = lp * 0.9 + noise[i] * 0.1
	var data: PackedFloat32Array = PackedFloat32Array()
	data.resize(n)
	var w: float = TAU * 50.0 / float(rate)
	var k_hum: float = 0.0
	var k_air: float = 0.0
	for i in n:
		if i % CTRL == 0:
			var t: float = float(i) / float(rate)
			var throb: float = (0.85 + 0.15 * sin(TAU * t)) * 0.4
			k_hum = throb * 0.55
			k_air = throb * 1.6 * (0.65 + 0.35 * sin(TAU * 6.0 * t))
		lp = lp * 0.9 + noise[i] * 0.1
		# 50 Гц и гармоники 100 и 150 Гц из одного синуса:
		# 1 − 2s² = cos 2x, 3s − 4s³ = sin 3x.
		var s: float = sin(w * float(i))
		var s2: float = s * s
		var hum: float = s * 0.5 + (1.0 - 2.0 * s2) * 0.25 + s * (3.0 - 4.0 * s2) * 0.12
		data[i] = hum * k_hum + lp * k_air
	return data


## Сирена (#172): два тона, вверх-вниз, как тревога у базы. Короткий, не петля.
func _syn_siren() -> PackedFloat32Array:
	var n: int = int(0.7 * RATE)
	var data: PackedFloat32Array = PackedFloat32Array()
	data.resize(n)
	var phase: float = 0.0
	for i in n:
		var t: float = float(i) / float(n)
		var wob: float = 0.5 + 0.5 * sin(t * TAU * 3.0)
		var f: float = lerpf(520.0, 880.0, wob)
		phase += TAU * f / float(RATE)
		var env: float = minf(1.0, t * 12.0) * (1.0 - t * 0.35)
		data[i] = sin(phase) * 0.42 * env
	return data


## Мяу кота: два коротких глиссандо вверх, без шума. Сид фиксирован.
func _syn_cat_meow() -> PackedFloat32Array:
	var n: int = int(0.28 * RATE)
	var data: PackedFloat32Array = PackedFloat32Array()
	data.resize(n)
	var phase: float = 0.0
	for i in n:
		var t: float = float(i) / float(n)
		var syllable: float = fmod(t * 2.0, 1.0)
		var f: float = lerpf(520.0, 880.0, syllable)
		phase += TAU * f / float(RATE)
		var env: float = sin(PI * syllable) * (1.0 - t * 0.35)
		data[i] = sin(phase) * env * 0.55
	return data


## Разряд турели: писк, быстро падающий вниз, и треск искр.
func _syn_turret_zap() -> PackedFloat32Array:
	var n: int = int(0.16 * RATE)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 7303
	var data: PackedFloat32Array = PackedFloat32Array()
	data.resize(n)
	var phase: float = 0.0
	var crack: float = 0.0
	for i in n:
		var t: float = float(i) / float(n)
		phase += TAU * lerpf(2400.0, 260.0, sqrt(t)) / float(RATE)
		if rng.randf() < 0.08:
			crack = rng.randf_range(-1.0, 1.0)
		crack *= 0.6
		var u: float = 1.0 - t
		var env: float = u * u * u * minf(1.0, t * 80.0)
		data[i] = (signf(sin(phase)) * 0.45 + crack * 0.5) * env * 0.9
	return data


## Стрёкот стаи: три «насекомых» с разной частотой и ритмом щелчков.
## Щелчок — верхушка синуса ритма в 6-й степени; несущую считаем только
## внутри щелчка.
func _syn_swarm() -> PackedFloat32Array:
	var n: int = int(0.4 * RATE)
	var data: PackedFloat32Array = PackedFloat32Array()
	data.resize(n)
	var c1: float = TAU * 3100.0 / float(RATE)
	var c2: float = TAU * 3900.0 / float(RATE)
	var c3: float = TAU * 4700.0 / float(RATE)
	var g1: float = 0.0
	var g2: float = 1.7
	var g3: float = 3.9
	var d1: float = 0.0
	var d2: float = 0.0
	var d3: float = 0.0
	var env: float = 0.0
	for i in n:
		if i % CTRL == 0:
			var sec: float = float(i) / float(RATE)
			# Ритм каждого «плывёт» — стая не звучит метрономом.
			d1 = TAU * 34.0 * (1.0 + 0.08 * sin(TAU * 1.3 * sec)) / float(RATE)
			d2 = TAU * 41.0 * (1.0 + 0.08 * sin(TAU * 2.0 * sec)) / float(RATE)
			d3 = TAU * 29.0 * (1.0 + 0.08 * sin(TAU * 2.7 * sec)) / float(RATE)
			env = sin(PI * float(i) / float(n)) * 0.3
		g1 += d1
		g2 += d2
		g3 += d3
		var s: float = 0.0
		var fi: float = float(i)
		var a: float = sin(g1)
		if a > 0.0:
			a = a * a * a
			s += sin(c1 * fi) * a * a
		a = sin(g2)
		if a > 0.0:
			a = a * a * a
			s += sin(c2 * fi) * a * a
		a = sin(g3)
		if a > 0.0:
			a = a * a * a
			s += sin(c3 * fi) * a * a
		data[i] = s * env
	return data


## Шёпот двойника: полосовой шум «слогами» и еле слышный сползающий тон.
func _syn_doppel_whisper() -> PackedFloat32Array:
	var n: int = int(0.9 * RATE)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 6661
	var data: PackedFloat32Array = PackedFloat32Array()
	data.resize(n)
	var lp1: float = 0.0
	var lp2: float = 0.0
	var phase: float = 0.0
	var k_band: float = 0.0
	var k_hiss: float = 0.0
	var k_tone: float = 0.0
	var dp: float = 0.0
	for i in n:
		if i % CTRL == 0:
			var t: float = float(i) / float(n)
			# Слоги: неровный ритм ~3.6 в секунду; «с» — только на пике слога.
			var syl: float = 0.5 + 0.5 * sin(TAU * (3.6 * t + 0.15 * sin(TAU * 1.4 * t)))
			var s2: float = syl * syl
			var env: float = minf(1.0, t / 0.15) * minf(1.0, (1.0 - t) / 0.3)
			k_band = 0.55 * syl * env
			k_hiss = 0.18 * s2 * s2 * env
			k_tone = 0.05 * env
			dp = TAU * lerpf(170.0, 140.0, t) / float(RATE)
		var raw: float = rng.randf_range(-1.0, 1.0)
		lp1 = lp1 * 0.55 + raw * 0.45
		lp2 = lp2 * 0.93 + raw * 0.07
		phase += dp
		data[i] = (lp1 - lp2) * k_band + (raw - lp1) * k_hiss + sin(phase) * k_tone
	return data





# ------------------------------------------------------------------ кодирование

## Float-сигнал → 16-битный WAV. Перевод в 16 бит делает движок (WAV-файл с
## float-данными через load_from_buffer) — в разы быстрее цикла в GDScript.
func _wav(data: PackedFloat32Array, rate: int = RATE) -> AudioStreamWAV:
	var raw: PackedByteArray = data.to_byte_array()
	var buf: PackedByteArray = PackedByteArray()
	buf.resize(44)
	buf.encode_u32(0, 0x46464952)   # "RIFF"
	buf.encode_u32(4, 36 + raw.size())
	buf.encode_u32(8, 0x45564157)   # "WAVE"
	buf.encode_u32(12, 0x20746d66)  # "fmt "
	buf.encode_u32(16, 16)
	buf.encode_u16(20, 3)           # IEEE float
	buf.encode_u16(22, 1)           # моно
	buf.encode_u32(24, rate)
	buf.encode_u32(28, rate * 4)
	buf.encode_u16(32, 4)
	buf.encode_u16(34, 32)
	buf.encode_u32(36, 0x61746164)  # "data"
	buf.encode_u32(40, raw.size())
	buf.append_array(raw)
	var s: AudioStreamWAV = AudioStreamWAV.load_from_buffer(buf, {"compress/mode": 0})
	if s == null or s.format != AudioStreamWAV.FORMAT_16_BITS:
		return _to_wav(data, rate)
	return s


## Запасной путь: кодирование циклом (если движок не принял буфер).
func _to_wav(data: PackedFloat32Array, rate: int = RATE) -> AudioStreamWAV:
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(data.size() * 2)
	for i in data.size():
		bytes.encode_s16(i * 2, int(clampf(data[i], -1.0, 1.0) * 32000.0))
	var s: AudioStreamWAV = AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = rate
	s.stereo = false
	s.data = bytes
	return s
