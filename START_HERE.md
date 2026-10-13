# Truck Mania — исходники Godot

Репозиторий содержит рабочий проект из Bus Game. Его техническая папка —
`bus-bloom`, а текущее название в настройках Godot — **Cargo Yard / Грузовой двор**.
Названия сохранены, чтобы не менять существующие ресурсы и локальный запуск.

## Запуск

1. Установите **Godot 4.5.2 Standard** (GDScript).
2. Импортируйте `bus-bloom/project.godot` и дождитесь импорта ресурсов.
3. Нажмите **F5**.

Если Godot доступен в PATH, из корня репозитория можно выполнить:

```text
godot --path bus-bloom
```

Windows-ярлыки `Play Cargo Yard.cmd` и `Play Bus Bloom.cmd` используют локальный
`tools/Godot_v4.5.2-stable_win64.exe`. Сам движок в Git не хранится.

## Состав

- [bus-bloom/README.md](bus-bloom/README.md) — правила игры, структура и экспорт.
- `bus-bloom/scripts`, `scenes`, `main.tscn` — код и сцены.
- `bus-bloom/assets` — рисунки, звук и исходные PSD/Blender/FBX.
- `bus-bloom/tests` — существующие проверки игры.
- `bus-bloom/artifacts` — готовые снимки, GIF и отчёты; промежуточные кадры исключены.
- `level-design` — схемы уровней и инструменты их подготовки и проверки.
- [GITHUB_IMPORT_CHECK.md](GITHUB_IMPORT_CHECK.md) — результаты проверки этой версии
  и известные ограничения существующих тестов.

`.uid` и настройки импорта `.import` включены. Кэш `.godot`, сборки, журналы,
ключи подписи, локальные `.env`, старые ZIP и синхронизированная папка `sources`
исключены. Правила Godot сверены с
[официальной документацией 4.5](https://docs.godotengine.org/en/4.5/tutorials/best_practices/version_control_systems.html).

## Проверки

Из корня репозитория после установки движка:

```text
godot --headless --editor --path bus-bloom --import
godot --headless --path bus-bloom --script res://tests/model_test.gd
godot --headless --path bus-bloom --script res://tests/ui_test.gd
godot --headless --path bus-bloom -- --smoke-test
```

## Экспорт

`bus-bloom/export_presets.cfg` содержит профили Android, iOS и Web. Ключи подписи
и данные аккаунтов разработчика задаются локально. Подписанные мобильные сборки
в репозиторий не входят.

Для Web существующий профиль ожидает шаблон
`tools/web_nothreads_release.zip` и пишет результат в `sites/cargo-yard-preview/dist`.
Установите подходящие Export Templates Godot 4.5.2 и либо разместите этот шаблон
по указанному пути, либо очистите поле Custom Template / Release в редакторе,
чтобы использовать установленный стандартный шаблон. Создайте папку вывода при
необходимости. Локальные `tools` и `sites` в Git не включены.

## Работа с Git

Удалённый репозиторий: `https://github.com/ssshooroop/Truck-Mania.git`.
Основная ветка — `main`. Перед новой работой получайте изменения через
`git pull --ff-only`. Если Git сообщает о расхождении веток, сначала разберите
изменения; не используйте принудительную отправку.
