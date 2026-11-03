class_name TestEnv
extends RefCounted
## Тестовый прогон этого процесса (#132): --test, --scenario=, --mp-scenario= (хост и
## клиенты-процессы харнесса) или инструмент под --script (tools/*.gd).
##
## Зачем: на одной машине тесты гоняются параллельно (несколько worktree, сиды CI
## разом), а user:// у проекта один. В тестовом прогоне файлы сохранений получают
## суффикс процесса (Save.path_for: save_<слот>~t<pid>.sav), профиль по умолчанию —
## свой файл (Profile.default_path: profile~t<pid>.cfg) — прогоны не стирают файлы
## друг друга и не трогают (и не читают) сохранения и профиль игрока.
## Игра без этих флагов (меню, --seed=, --mp-host, --mp-join=) работает как раньше.
##
## От автозагрузок не зависит: Profile и Save зовут его и в режиме --script.

## Метка тестового файла: имя файла игрока её не содержит (слоты игры — «1» и
## mp_<буквы/цифры/_>_auto, см. Save.net_auto_slot).
const MARK: String = "~t"

## −1 — ещё не определяли; 0 / 1 — игра / тест. Тесты могут задать явно.
static var _active: int = -1


static func active() -> bool:
	if _active < 0:
		_active = 1 if _detect() else 0
	return _active == 1


static func _detect() -> bool:
	for a in OS.get_cmdline_user_args():
		if a == "--test" or a.begins_with("--scenario=") or a.begins_with("--mp-scenario="):
			return true
	var ml: MainLoop = Engine.get_main_loop()
	return ml != null and ml.get_script() != null   # инструмент: --script res://tools/…


## Суффикс имени файла этого процесса ("" — игра).
static func suffix() -> String:
	return "%s%d" % [MARK, OS.get_process_id()] if active() else ""


## Временный файл теста — свой у процесса: user://x/profile.cfg → user://x/profile~t<pid>.cfg.
static func file(path: String) -> String:
	return "%s%s%d.%s" % [path.get_basename(), MARK, OS.get_process_id(), path.get_extension()]
