# Truck Mania — Huawei AppGallery

Ветка содержит текущий код игры, 150 уровней, Unity Ads, Huawei IAP и диагностику
недоступности магазина и рекламы. Целевая версия Huawei: **0.1.4 (9)**.

## Параметры приложения

- Package name: `org.truckmania.game.hw`.
- Huawei App ID: `119855549`.
- Экспорт Godot: `Android Huawei`, feature `huawei_appgallery`.
- Unity Game ID: `800430064`; обычная сборка использует `test_mode=false`.
- Публичный ключ IAP и восемь Product ID: `config/huawei_iap.json`.
- Содержимое товаров: `config/store_catalog.json`; реальные цены приходят из Huawei IAP.

Профили Google Play используют `org.truckmania.game`. Скрипт сборки Huawei временно
подставляет свои build metadata и после экспорта восстанавливает исходные файлы.

## Сборка

Текущие Windows-скрипты используют Godot 4.5.2 и Android-инструменты из соседнего
с проектом каталога `tools`: `Godot_v4.5.2-stable_win64_console.exe` и `android/`
(JDK 17, Android SDK, Gradle cache, Android source template и signing).
Сгенерированный Gradle-проект Godot находится в `android/build/` и не входит в Git.
Для подготовки окружения в репозитории есть `tools/setup_android.py`,
`tools/configure_android.ps1` и `tools/prepare_aab_template.py`.

Для подписания локально нужны `tools/android/signing/truck-mania-upload.jks`
и `upload-credentials.json` в соседнем каталоге инструментов. Эти файлы не входят
в репозиторий. Для обновления существующей установки используется тот же ключ.

```powershell
python tools/build_huawei.py --check-config
python tools/build_huawei.py
```

Скрипт собирает оба native-модуля, экспортирует подписанный APK и проверяет
его подпись, пакет, App ID, SDK, public key, товары, уровни и соответствие
игровых ресурсов текущим исходникам. Результат находится в `build/android/`.
Сборка не загружает приложение в AppGallery.

## Диагностика на планшете

В версии 8 владелец сообщил, что магазин и реклама недоступны. Причина пока
не установлена по журналу устройства; переименование пакета само по себе
не подтверждено причиной.

В версии 9 добавлено: **меню игры → Поддержка → Скопировать диагностику**.
После запуска подождать 30–60 секунд, открыть магазин, затем скопировать отчёт.
Он содержит наличие SDK, статусы инициализации, доступные товары и ошибки
по рекламным позициям. Числовые ошибки Unity сохраняются как `sdk_<code>`,
ошибки Huawei — как `huawei_<code>`. Отчёт не включает ключи, квитанции,
токены покупки, данные аккаунта и идентификаторы игрока/устройства.

Для USB-диагностики:

```powershell
adb logcat -s TruckManiaAds TruckManiaIap godot AndroidRuntime
```

Перед публикацией остаётся проверить реальные показы, покупку, отмену и
восстановление на устройстве с подходящим тестовым аккаунтом Huawei.
В AppGallery Connect должны быть активны IAP и товары для нового App ID,
выбранные регионы и правильный отпечаток сертификата подписи.

SHA-256 сертификата текущей локальной сборки:

```text
6C:95:73:B6:34:97:E0:31:2E:CC:6E:99:6C:6C:CE:7D:F0:28:4E:E1:6E:17:88:60:DA:12:B2:6C:10:32:1D:E6
```

## Проверки

Локально пройдены тесты store service, сохранения/восстановления покупок,
магазина, рекламы, диагностики и локализации. `tools/build_huawei_iap_plugin.py`
запускает проверки подписей квитанций перед сборкой native-модуля.

```powershell
python -m unittest discover -s tests -p test_verify_store_builds.py
godot --headless --path . --script tests/service_diagnostics_test.gd
godot --headless --path . --script tests/store_service_test.gd
godot --headless --path . --script tests/store_game_flow_test.gd
godot --headless --path . --script tests/unity_ads_test.gd
```

Полный `agconnect-services.json`, приватные ключи, пароли подписи, APK/AAB,
кэши и локальные журналы не нужны в Git. Текущий IAP-модуль получает App ID
из Android manifest metadata; OAuth/client-secret из AGC-файла не использует.
