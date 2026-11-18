$ErrorActionPreference = 'Stop'
$gameRoot = Split-Path $PSScriptRoot -Parent
$workspaceRoot = Split-Path $gameRoot -Parent
$androidRoot = Join-Path $workspaceRoot 'tools/android'
$javaLog = Join-Path $gameRoot 'artifacts/android-java.log'
$deadline = (Get-Date).AddMinutes(12)
while (-not ((Get-Content $javaLog -Raw -ErrorAction SilentlyContinue) -match 'Java ready')) {
    if ((Get-Date) -gt $deadline) { throw 'Java installation did not complete' }
    Start-Sleep -Seconds 2
}
$javaDir = (Get-ChildItem (Join-Path $androidRoot 'java') -Directory | Select-Object -First 1).FullName
$sdkDir = Join-Path $androidRoot 'sdk'
$env:JAVA_HOME = $javaDir
$sdkManager = Join-Path $sdkDir 'cmdline-tools/latest/bin/sdkmanager.bat'
# User explicitly authorized SDK installation and license acceptance.
(1..100 | ForEach-Object { 'y' }) | & $sdkManager "--sdk_root=$sdkDir" --licenses
if ($LASTEXITCODE -ne 0) { throw 'SDK license setup failed' }
& $sdkManager "--sdk_root=$sdkDir" 'platform-tools' 'build-tools;35.0.0'
if ($LASTEXITCODE -ne 0) { throw 'Android SDK packages failed to install' }
$key = Join-Path $androidRoot 'debug.keystore'
if (-not (Test-Path -LiteralPath $key)) {
    & (Join-Path $javaDir 'bin/keytool.exe') -genkeypair -keystore $key -storepass android -alias androiddebugkey -keypass android -keyalg RSA -keysize 2048 -validity 10000 -dname 'CN=Android Debug,O=Android,C=US'
    if ($LASTEXITCODE -ne 0) { throw 'Debug signing key generation failed' }
}
$settingsPath = Join-Path $env:APPDATA 'Godot/editor_settings-4.5.tres'
$settings = Get-Content -LiteralPath $settingsPath -Raw
foreach ($item in @(@('java_sdk_path',$javaDir),@('android_sdk_path',$sdkDir),@('debug_keystore',$key))) {
    $line = 'export/android/' + $item[0] + ' = "' + $item[1].Replace('\','/') + '"'
    $pattern = '(?m)^export/android/' + $item[0] + ' = .*\r?$'
    if ($settings -match $pattern) { $settings = [regex]::Replace($settings,$pattern,$line) }
    else { $settings += "`n$line`n" }
}
Set-Content -LiteralPath $settingsPath -Value $settings -Encoding utf8
$presetPath = Join-Path $gameRoot 'export_presets.cfg'
$preset = Get-Content -LiteralPath $presetPath -Raw
$split = $preset.Split('[preset.1]',2,[StringSplitOptions]::None)
$template = (Join-Path $androidRoot 'android_release.apk').Replace('\','/')
if (-not (Test-Path -LiteralPath $template)) { throw 'Godot Android template missing' }
$androidPreset = $split[0].Replace('custom_template/debug=""','custom_template/debug="'+$template+'"').Replace('custom_template/release=""','custom_template/release="'+$template+'"')
Set-Content -LiteralPath $presetPath -Value ($androidPreset+'[preset.1]'+$split[1]) -Encoding utf8
Write-Output 'Android toolchain ready; building APK.'
& (Join-Path $PSScriptRoot 'build_android.ps1')
