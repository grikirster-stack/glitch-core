extends "res://tools/scenarios/campaign_common.gd"
## Прямой запуск старого файла. Реестр зовёт campaign_light.gd (главы 1–2)
## и campaign_light_late.gd (главы 3–4). «Тёмная станция» и главы фабрики
## сняты (#170): этот файл их не поднимает.


func run() -> void:
	ok("главы «Свет» на месте", Campaign.CHAPTERS == ["dig", "fire", "mirror", "colors"])
	ok("фабрика и «Тёмная станция» не в списке", not Campaign.has("dark_station")
			and not Campaign.has("mine") and not Campaign.has("conveyor")
			and not Campaign.has("siege") and not Campaign.has("signal"))
	finish()
