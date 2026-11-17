param(
	[ValidateSet("debug", "release")]
	[string]$Mode = "release",
	[string]$Version = "",
	[switch]$SkipImportRefresh
)

$ErrorActionPreference = "Stop"

$ProjectDir = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$GodotExe = "D:\Godot\Godot_v4.7.2-stable_win64_console.exe"
$TpzPath = Join-Path $ProjectDir ".tools\godot-4.7.2\Godot_v4.7.2-stable_export_templates.tpz"
$DbgTpl = Join-Path $ProjectDir ".tools\godot-4.7.2\windows_debug_x86_64.exe"
$RelTpl = Join-Path $ProjectDir ".tools\godot-4.7.2\windows_release_x86_64.exe"

if (-not (Test-Path $GodotExe)) {
	throw "Godot console executable not found at $GodotExe"
}

if (-not (Test-Path $DbgTpl) -or -not (Test-Path $RelTpl)) {
	if (-not (Test-Path $TpzPath)) {
		throw "Missing export templates .tpz at $TpzPath"
	}
	Add-Type -AssemblyName System.IO.Compression.FileSystem
	$zip = [System.IO.Compression.ZipFile]::OpenRead($TpzPath)
	try {
		foreach ($pair in @(
			@{ Entry = "templates/windows_debug_x86_64.exe"; Out = $DbgTpl },
			@{ Entry = "templates/windows_release_x86_64.exe"; Out = $RelTpl }
		)) {
			$e = $zip.GetEntry($pair.Entry)
			if ($null -eq $e) { throw "Missing $($pair.Entry) in .tpz" }
			[System.IO.Compression.ZipFileExtensions]::ExtractToFile($e, $pair.Out, $true)
		}
	} finally {
		$zip.Dispose()
	}
}

if ($Version -eq "") {
	$manifestPath = Join-Path $ProjectDir "data\app_update.json"
	if (Test-Path $manifestPath) {
		$mj = Get-Content $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
		$Version = [string]$mj.version
	}
	if ($Version -eq "") { $Version = "1.0.0" }
}

$OutDir = Join-Path $ProjectDir "build\windows"
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }
$OutExe = Join-Path $OutDir ("Aethera-v{0}-win64.exe" -f $Version)

if (-not $SkipImportRefresh) {
	Write-Host "[1/2] Refreshing headless Godot resource imports..."
	& $GodotExe --headless --path $ProjectDir --quit
}

Write-Host "[2/2] Exporting Windows x86_64 standalone EXE ($Mode) -> $OutExe ..."
if ($Mode -eq "debug") {
	& $GodotExe --headless --path $ProjectDir --export-debug "Windows Desktop" $OutExe
} else {
	& $GodotExe --headless --path $ProjectDir --export-release "Windows Desktop" $OutExe
}
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $OutExe)) {
	throw "Godot Windows export failed with exit code $LASTEXITCODE"
}

$info = Get-Item $OutExe
$sha = (Get-FileHash $OutExe -Algorithm SHA256).Hash.ToLowerInvariant()
Write-Host ("SUCCESS: {0} ({1:N2} MB, SHA256={2})" -f $OutExe, ($info.Length / 1MB), $sha)
