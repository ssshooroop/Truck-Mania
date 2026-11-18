$ErrorActionPreference = 'Stop'
$gameRoot = Split-Path $PSScriptRoot -Parent
$workspaceRoot = Split-Path $gameRoot -Parent
$godot = Join-Path $workspaceRoot 'tools/Godot_v4.5.2-stable_win64_console.exe'
$python = Join-Path $env:USERPROFILE '.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
& $python (Join-Path $PSScriptRoot 'build_ads_plugin.py')
if ($LASTEXITCODE -ne 0) { throw 'Ads plugin build failed' }
$androidTools = Join-Path $workspaceRoot 'tools/android'
$env:JAVA_HOME = (Get-ChildItem (Join-Path $androidTools 'java') -Directory -Filter 'jdk-*' | Select-Object -First 1).FullName
$env:ANDROID_HOME = Join-Path $androidTools 'sdk'
$env:ANDROID_SDK_ROOT = $env:ANDROID_HOME
$env:GRADLE_USER_HOME = Join-Path $androidTools 'gradle-cache'
& $python (Join-Path $PSScriptRoot 'prepare_android_export.py')
if ($LASTEXITCODE -ne 0) { throw 'Resource preparation failed' }
New-Item -ItemType Directory -Force -Path (Join-Path $gameRoot 'build/android') | Out-Null
& $godot --headless --path $gameRoot --export-debug Android build/android/truck-mania.apk
if ($LASTEXITCODE -ne 0) { throw 'APK export failed. Check Java/SDK paths and Android export template.' }
Get-Item (Join-Path $gameRoot 'build/android/truck-mania.apk') | Select-Object FullName,Length
