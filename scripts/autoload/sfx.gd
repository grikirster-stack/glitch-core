extends Node
## Процедурный звук: все эффекты синтезируются кодом (WAV-буферы в памяти).

const RATE: int = 22050

var sounds: Dictionary = {}
var _pool: Array[AudioStreamPlayer] = []
var _next: int = 0
var enabled: bool = true


func _ready() -> void:
	sounds["mine"] = _noise_hit(0.05, 320.0, 0.35, 0.6)
	sounds["break"] = _noise_hit(0.22, 180.0, 0.7, 0.9)
	sounds["place"] = _noise_hit(0.07, 420.0, 0.3, 0.5)
	sounds["pickup"] = _blip(520.0, 880.0, 0.10, 0.35)
	sounds["craft"] = _blip(440.0, 660.0, 0.16, 0.40)
	sounds["place_machine"] = _blip(180.0, 140.0, 0.18, 0.45)
	sounds["hit"] = _noise_hit(0.25, 120.0, 0.9, 1.0)
	sounds["alarm"] = _alarm()
	sounds["power"] = _blip(300.0, 1200.0, 0.22, 0.30)
	sounds["step"] = _noise_hit(0.04, 140.0, 0.25, 0.25)
	for i in 12:
		var p: AudioStreamPlayer = AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_pool.append(p)


func play(name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if not enabled or not sounds.has(name) or _pool.is_empty():
		return
	var p: AudioStreamPlayer = _pool[_next]
	_next = (_next + 1) % _pool.size()
	p.stream = sounds[name]
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()


func _noise_hit(dur: float, freq: float, decay: float, vol: float) -> AudioStreamWAV:
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
	return _to_wav(data)


func _blip(f0: float, f1: float, dur: float, vol: float) -> AudioStreamWAV:
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
	return _to_wav(data)


func _alarm() -> AudioStreamWAV:
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
	return _to_wav(data)


func _to_wav(data: PackedFloat32Array) -> AudioStreamWAV:
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(data.size() * 2)
	for i in data.size():
		bytes.encode_s16(i * 2, int(clampf(data[i], -1.0, 1.0) * 32000.0))
	var s: AudioStreamWAV = AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = bytes
	return s
