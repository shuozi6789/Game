extends Node
## Procedural audio for the whole game: a soft looping ambience plus short,
## hand-drawn-feeling SFX for every action. No external audio files required.

const RATE := 22050
const SFX_POOL := 16

var _music: AudioStreamPlayer
var _music_stream: AudioStreamWAV
var _sfx: Dictionary = {}
var _music_tracks: Dictionary = {}
var _current_track: String = ""
var _pool: Array[AudioStreamPlayer] = []
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.seed = 7741
	_build_sfx()
	_music = AudioStreamPlayer.new()
	_music.name = "AmbientMusic"
	_music.volume_db = -18.0
	add_child(_music)
	_music_tracks["ambient"] = _make_music()
	_music_tracks["creek"] = _make_creek_music()
	_music_stream = _music_tracks["ambient"]
	_current_track = "ambient"
	_music.stream = _music_stream
	_music.play()
	for i in SFX_POOL:
		var player := AudioStreamPlayer.new()
		player.name = "Sfx_%d" % i
		add_child(player)
		_pool.append(player)

func play_music(track_id: String = "ambient") -> void:
	if _music == null or not _music_tracks.has(track_id):
		return
	if _current_track == track_id and _music.playing:
		return
	_current_track = track_id
	_music.stream = _music_tracks[track_id]
	_music.play()

func play_sfx(id: String, volume_db: float = -7.0, pitch: float = 1.0) -> void:
	if not _sfx.has(id):
		return
	var player: AudioStreamPlayer = null
	for candidate in _pool:
		if not candidate.playing:
			player = candidate
			break
	if player == null:
		player = _pool[0]
	player.stream = _sfx[id]
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.play()

func set_music_volume_db(value: float) -> void:
	if _music != null:
		_music.volume_db = value

func stop_music() -> void:
	if _music != null:
		_music.stop()

func start_music() -> void:
	if _music != null and not _music.playing:
		_music.play()

# =============================================================================
# SYNTHESIS HELPERS
# =============================================================================

func _wav(samples: PackedFloat32Array, looping: bool = false) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		var value := clampf(samples[i], -1.0, 1.0)
		data.encode_s16(i * 2, int(round(value * 32767.0)))
	stream.data = data
	if looping:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = samples.size()
	return stream

func _make_music() -> AudioStreamWAV:
	var duration := 24.0
	var count := int(duration * RATE)
	var out := PackedFloat32Array()
	out.resize(count)
	var chord_root := 110.0
	var fifth := 164.81
	var octave := 220.0
	var high := 329.63
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210
	var noise_state := 0.0
	for i in count:
		var t := float(i) / float(RATE)
		var slow := sin(TAU * t / 12.0) * 0.5 + 0.5
		var pad := sin(TAU * chord_root * t) * 0.045
		pad += sin(TAU * fifth * t + 0.4) * 0.030
		pad += sin(TAU * octave * t + 1.2) * 0.020
		pad *= 0.72 + 0.28 * slow
		# a sparse pentatonic bell every 3 seconds
		var bell_pos := fmod(t, 3.0)
		var bell := 0.0
		if bell_pos < 2.2:
			var env := exp(-bell_pos * 2.1)
			var note_freq: float = [261.63, 293.66, 329.63, 392.0, 440.0][int(floor(t / 3.0)) % 5]
			bell = sin(TAU * note_freq * 1.5 * t) * env * 0.028
			bell += sin(TAU * note_freq * 2.0 * t) * env * 0.012
		noise_state = noise_state * 0.985 + (rng.randf() * 2.0 - 1.0) * 0.015
		var wind := noise_state * 0.12
		var sample := pad + bell + wind
		var fade := 1.0
		if t < 1.2:
			fade = t / 1.2
		elif t > duration - 1.2:
			fade = (duration - t) / 1.2
		out[i] = sample * fade
	return _wav(out, true)

func _midi_hz(midi: float) -> float:
	return 440.0 * pow(2.0, (midi - 69.0) / 12.0)

func _add_music_note(buffer: PackedFloat32Array, start: float, duration: float,
		midi: float, amplitude: float, decay: float, harmonics: float = 0.18) -> void:
	var start_index := int(start * RATE)
	var note_count := int(duration * RATE)
	for i in note_count:
		var index := start_index + i
		if index < 0 or index >= buffer.size():
			break
		var t := float(i) / float(RATE)
		var attack := minf(1.0, t / 0.035)
		var env := attack * exp(-decay * t)
		var f := _midi_hz(midi)
		var phase := TAU * f * t
		var value := sin(phase) * amplitude
		value += sin(phase * 2.0) * amplitude * harmonics
		value += sin(phase * 3.0) * amplitude * harmonics * 0.35
		buffer[index] += value * env

## A scene theme for 四·溪畔: slow D-major pads, harp-like chord arpeggios,
## a small pentatonic melody and a quiet water wash. Designed to loop for 32 s.
func _make_creek_music() -> AudioStreamWAV:
	var duration := 32.0
	var count := int(duration * RATE)
	var out := PackedFloat32Array()
	out.resize(count)
	var chords := [
		[62, 66, 69, 74], # D
		[59, 62, 66, 71], # Bm
		[55, 59, 62, 67], # G
		[57, 61, 64, 69], # A
	]
	# warm pad, one chord every 8 seconds
	for pass_i in 4:
		var start := float(pass_i) * 8.0
		var chord: Array = chords[pass_i]
		for note in chord:
			for k in 2:
				_add_music_note(out, start, 8.1, float(note) - 12.0 + float(k) * 0.02,
					0.035 if k == 0 else 0.018, 0.12, 0.22)
	# harp arpeggios, 16th-ish pattern
	for pass_i in 4:
		var chord: Array = chords[pass_i]
		for step in 16:
			var t := float(pass_i) * 8.0 + float(step) * 0.48
			var note: int = chord[step % chord.size()] + 12
			if step % 4 == 3:
				note += 12
			_add_music_note(out, t, 1.25, note, 0.040, 2.8, 0.22)
	# small glowing melody
	var melody := [
		[0.0, 81], [2.0, 78], [4.0, 74], [6.0, 76],
		[8.0, 78], [10.0, 74], [12.0, 71], [14.0, 74],
		[16.0, 76], [18.0, 78], [20.0, 81], [22.0, 78],
		[24.0, 76], [26.0, 74], [28.0, 71], [30.0, 74],
	]
	for event in melody:
		_add_music_note(out, float(event[0]) + 0.08, 2.1, float(event[1]), 0.028, 1.7, 0.15)
	# water wash: smooth filtered noise plus tiny high sparkles
	var rng := RandomNumberGenerator.new()
	rng.seed = 5521
	var noise_state := 0.0
	for i in count:
		var t := float(i) / float(RATE)
		noise_state = noise_state * 0.994 + (rng.randf() * 2.0 - 1.0) * 0.006
		out[i] += noise_state * 0.10
		if i % 18000 == 0:
			var z := float((i / 18000) % 7) * 0.17
			out[i] += sin(TAU * (1800.0 + z * 300.0) * t) * 0.006
	var fade := 1.5
	for i in count:
		var t := float(i) / float(RATE)
		var fade_in := clampf(t / fade, 0.0, 1.0)
		var fade_out := clampf((duration - t) / fade, 0.0, 1.0)
		out[i] *= minf(fade_in, fade_out)
	return _wav(out, true)

func _make_tone(duration: float, start_freq: float, end_freq: float,
		volume: float, decay: float, noise: float = 0.0, seed: int = 1) -> AudioStreamWAV:
	var count := int(duration * RATE)
	var out := PackedFloat32Array()
	out.resize(count)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var phase := 0.0
	var smooth_noise := 0.0
	for i in count:
		var t := float(i) / float(RATE)
		var f := lerpf(start_freq, end_freq, t / maxf(duration, 0.001))
		phase += TAU * f / float(RATE)
		var env := exp(-decay * t) * (1.0 - smoothstep(duration * 0.78, duration, t))
		smooth_noise = smooth_noise * 0.82 + (rng.randf() * 2.0 - 1.0) * 0.18
		var s := sin(phase) * volume + smooth_noise * noise
		out[i] = s * env
	return _wav(out)

func _make_noise(duration: float, volume: float, lowpass: float, seed: int) -> AudioStreamWAV:
	var count := int(duration * RATE)
	var out := PackedFloat32Array()
	out.resize(count)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var state := 0.0
	for i in count:
		var t := float(i) / float(RATE)
		state = state * lowpass + (rng.randf() * 2.0 - 1.0) * (1.0 - lowpass)
		var env := exp(-(float(i) / float(count)) * 8.0)
		out[i] = state * volume * env
	return _wav(out)

func _build_sfx() -> void:
	_sfx["footstep_a"] = _make_tone(0.095, 150.0, 70.0, 0.30, 18.0, 0.12, 1)
	_sfx["footstep_b"] = _make_tone(0.085, 138.0, 64.0, 0.26, 20.0, 0.13, 2)
	_sfx["footstep_water"] = _make_noise(0.16, 0.24, 0.55, 3)
	_sfx["jump"] = _make_tone(0.18, 190.0, 390.0, 0.16, 10.0, 0.02, 4)
	_sfx["land"] = _make_tone(0.16, 110.0, 55.0, 0.32, 16.0, 0.16, 5)
	_sfx["ui_move"] = _make_tone(0.045, 620.0, 620.0, 0.12, 32.0, 0.0, 6)
	_sfx["ui_click"] = _make_tone(0.11, 520.0, 760.0, 0.17, 18.0, 0.0, 7)
	_sfx["dialogue_open"] = _make_tone(0.23, 440.0, 620.0, 0.12, 9.0, 0.02, 8)
	_sfx["dialogue"] = _make_tone(0.055, 880.0, 880.0, 0.075, 28.0, 0.0, 9)
	_sfx["type"] = _make_tone(0.022, 1250.0, 1150.0, 0.045, 55.0, 0.0, 10)
	_sfx["choice"] = _make_tone(0.12, 660.0, 880.0, 0.13, 15.0, 0.0, 11)
	_sfx["talk"] = _make_tone(0.30, 659.25, 880.0, 0.10, 7.0, 0.01, 12)
	_sfx["color"] = _make_tone(0.55, 440.0, 987.77, 0.12, 4.2, 0.02, 13)
	_sfx["pickup"] = _make_tone(0.32, 880.0, 1318.5, 0.16, 7.0, 0.01, 14)
	_sfx["puzzle_step"] = _make_tone(0.28, 523.25, 783.99, 0.16, 8.0, 0.02, 15)
	_sfx["puzzle_ok"] = _make_tone(0.85, 659.25, 1046.5, 0.16, 2.8, 0.01, 16)
	_sfx["puzzle_wrong"] = _make_tone(0.35, 146.83, 92.5, 0.22, 8.0, 0.08, 17)
	_sfx["transition"] = _make_noise(0.55, 0.22, 0.93, 18)
	_sfx["splash"] = _make_noise(0.24, 0.20, 0.45, 19)
	_sfx["pause_open"] = _make_tone(0.16, 330.0, 220.0, 0.11, 12.0, 0.0, 20)
	_sfx["pause_close"] = _make_tone(0.16, 220.0, 330.0, 0.11, 12.0, 0.0, 21)
	_sfx["backpack"] = _make_tone(0.18, 390.0, 294.0, 0.10, 11.0, 0.02, 22)
	_sfx["camera"] = _make_noise(0.18, 0.08, 0.82, 23)
	_sfx["ending"] = _make_tone(2.2, 261.63, 523.25, 0.12, 1.2, 0.01, 24)
