param(
	[string]$Godot = 'D:\Godot\Godot_v4.7.2-stable_win64_console.exe',
	[string]$AndroidSdk = 'D:\AI\klcx_work\tools\sdk',
	[string]$PlatformTools = 'D:\AI\klcx_work\tools\platform-tools',
	[string]$JavaHome = 'D:\AI\klcx_work\tools\jdk-17.0.21.0.2+1',
	[switch]$DebugBuild
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$OutDir = Join-Path $ProjectRoot 'build\android'
$EvidenceDir = Join-Path $ProjectRoot 'evidence'
$ToolsAndroid = Join-Path $ProjectRoot '.tools\android'
$KeystorePath = Join-Path $ToolsAndroid 'aethera-test.keystore'
$AppDataSandbox = Join-Path $ToolsAndroid 'godot_appdata'
$GodotAppDataDir = Join-Path $AppDataSandbox 'Godot'
$SdkView = Join-Path $ToolsAndroid 'sdk_view'

if (!(Test-Path -LiteralPath $Godot)) { throw "Godot executable missing: $Godot" }
if (!(Test-Path -LiteralPath $AndroidSdk)) { throw "Android SDK missing: $AndroidSdk" }
if (!(Test-Path -LiteralPath $PlatformTools)) { throw "Android platform-tools missing: $PlatformTools" }
if (!(Test-Path -LiteralPath $JavaHome)) { throw "JDK missing: $JavaHome" }
if (!(Test-Path -LiteralPath $KeystorePath)) { throw "Keystore missing: $KeystorePath" }

New-Item -ItemType Directory -Path $OutDir, $EvidenceDir, $GodotAppDataDir, $SdkView -Force | Out-Null

# Assemble clean SDK directory view combining sdk/* and sibling platform-tools/
$Links = @{
	'build-tools'    = Join-Path $AndroidSdk 'build-tools'
	'platforms'      = Join-Path $AndroidSdk 'platforms'
	'cmdline-tools'  = Join-Path $AndroidSdk 'cmdline-tools'
	'platform-tools' = $PlatformTools
}
foreach ($kv in $Links.GetEnumerator()) {
	$dst = Join-Path $SdkView $kv.Key
	if (!(Test-Path -LiteralPath $dst) -and (Test-Path -LiteralPath $kv.Value)) {
		New-Item -ItemType Junction -Path $dst -Target $kv.Value | Out-Null
	}
}

# Prepare isolated Godot editor_settings with verified SDK / JDK / keystore paths
$RealSettings = Join-Path $env:APPDATA 'Godot\editor_settings-4.7.tres'
$SandboxSettings = Join-Path $GodotAppDataDir 'editor_settings-4.7.tres'
$SdkFwd = $SdkView.Replace('\', '/')
$JdkFwd = $JavaHome.Replace('\', '/')
$KsFwd = $KeystorePath.Replace('\', '/')

if (Test-Path -LiteralPath $RealSettings) {
	$lines = Get-Content -LiteralPath $RealSettings -Encoding UTF8 | Where-Object {
		$_ -notmatch '^export/android/(android_sdk_path|java_sdk_path|debug_keystore|debug_keystore_user|debug_keystore_pass)\s*='
	}
} else {
	$lines = @('[gd_resource type="EditorSettings" format=3]', '', '[resource]')
}
$lines += @(
	"export/android/android_sdk_path = `"$SdkFwd`"",
	"export/android/java_sdk_path = `"$JdkFwd`"",
	"export/android/debug_keystore = `"$KsFwd`"",
	'export/android/debug_keystore_user = "aethera"',
	'export/android/debug_keystore_pass = "aethera_test"'
)
[IO.File]::WriteAllText($SandboxSettings, ($lines -join "`r`n") + "`r`n", (New-Object System.Text.UTF8Encoding($false)))

$ApkName = if ($DebugBuild) { 'Aethera-v1.0.0-debug.apk' } else { 'Aethera-v1.0.0.apk' }
$ApkPath = Join-Path $OutDir $ApkName
$ExportLog = Join-Path $EvidenceDir 'latest-android-export.txt'

$env:APPDATA = $AppDataSandbox
$env:ANDROID_HOME = $SdkView
$env:ANDROID_SDK_ROOT = $SdkView
$env:JAVA_HOME = $JavaHome
$env:PATH = "$JavaHome\bin;$env:PATH"

$ExportFlag = if ($DebugBuild) { '--export-debug' } else { '--export-release' }
Write-Host "Exporting Android APK ($ExportFlag) -> $ApkPath ..."

# Run via cmd /c so native stderr does not prematurely trigger PowerShell ErrorAction Stop
$prevPref = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
& cmd /c "`"$Godot`" --headless --path `"$ProjectRoot`" $ExportFlag Android `"$ApkPath`" > `"$ExportLog`" 2>&1"
$ec = $LASTEXITCODE
$ErrorActionPreference = $prevPref

Get-Content -LiteralPath $ExportLog -Tail 40 | ForEach-Object { Write-Host $_ }
if ($ec -ne 0 -or !(Test-Path -LiteralPath $ApkPath)) {
	throw "Android export failed (exit=$ec); inspect $ExportLog"
}

$ApkSigner = Join-Path $AndroidSdk 'build-tools\34.0.0\apksigner.bat'
Write-Host "Verifying APK signature with apksigner..."
$ErrorActionPreference = 'Continue'
& $ApkSigner verify --print-certs $ApkPath
$sc = $LASTEXITCODE
$ErrorActionPreference = 'Stop'
if ($sc -ne 0) {
	throw "apksigner verification failed (exit=$sc)"
}

$Aapt2 = Join-Path $AndroidSdk 'build-tools\34.0.0\aapt2.exe'
$Badging = & $Aapt2 dump badging $ApkPath | Select-Object -First 12
$Badging | ForEach-Object { Write-Host $_ }

$Info = Get-Item -LiteralPath $ApkPath
$Hash = (Get-FileHash -LiteralPath $ApkPath -Algorithm SHA256).Hash
[pscustomobject]@{
	Name = $Info.Name
	Path = $Info.FullName
	Bytes = $Info.Length
	MB = [math]::Round($Info.Length / 1MB, 2)
	SHA256 = $Hash
	Mode = if ($DebugBuild) { 'debug' } else { 'release' }
} | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $EvidenceDir 'latest-android-build.json') -Encoding utf8

Write-Host ("APK_READY: {0} ({1} MB, SHA256={2})" -f $Info.FullName, [math]::Round($Info.Length / 1MB, 2), $Hash)
