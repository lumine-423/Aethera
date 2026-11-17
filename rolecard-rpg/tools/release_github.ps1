param(
	[string]$Version = "",
	[int]$VersionCode = 0,
	[string]$ReleaseNotes = "",
	[string]$Owner = "lumine-423",
	[string]$Repo = "Aethera",
	[string]$Token = $env:GITHUB_TOKEN,
	[switch]$SkipExport,
	[switch]$UploadRelease
)

$ErrorActionPreference = "Stop"

$ProjectDir = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$RootDir = (Resolve-Path (Join-Path $ProjectDir "..")).Path
$ManifestPath = Join-Path $ProjectDir "data\app_update.json"
$PresetsPath = Join-Path $ProjectDir "export_presets.cfg"

if (-not $Token) {
	$EnvFile = Join-Path $RootDir ".env"
	if (Test-Path $EnvFile) {
		foreach ($line in (Get-Content $EnvFile -Encoding UTF8)) {
			if ($line -match '^\s*GITHUB_TOKEN\s*=\s*(.+?)\s*$') {
				$Token = $Matches[1].Trim().Trim('"').Trim("'")
				break
			}
		}
	}
}

$mj = Get-Content $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($Version -eq "") { $Version = [string]$mj.version }
if ($VersionCode -le 0) { $VersionCode = [int]$mj.version_code }

# 1. Sync version, owner/repo & configured=true across app_update.json and export_presets.cfg
$mj.version = $Version
$mj.version_code = $VersionCode
$mj.github_owner = $Owner
$mj.github_repo = $Repo
$mj.configured = $true
if ($ReleaseNotes -ne "") { $mj.changelog = $ReleaseNotes }
[System.IO.File]::WriteAllText($ManifestPath, ($mj | ConvertTo-Json -Depth 8), (New-Object System.Text.UTF8Encoding($false)))

$presets = Get-Content $PresetsPath -Raw -Encoding UTF8
$presets = [regex]::Replace($presets, 'export_path="build/android/Aethera-v[^"]+\.apk"', "export_path=`"build/android/Aethera-v$Version.apk`"")
$presets = [regex]::Replace($presets, 'version/name="[^"]+"', "version/name=`"$Version`"")
$presets = [regex]::Replace($presets, 'version/code=\d+', "version/code=$VersionCode")
$presets = [regex]::Replace($presets, 'export_path="build/windows/Aethera-v[^"]+-win64\.exe"', "export_path=`"build/windows/Aethera-v$Version-win64.exe`"")
[System.IO.File]::WriteAllText($PresetsPath, $presets, (New-Object System.Text.UTF8Encoding($false)))

$ApkPath = Join-Path $ProjectDir ("build\android\Aethera-v{0}.apk" -f $Version)
$ExePath = Join-Path $ProjectDir ("build\windows\Aethera-v{0}-win64.exe" -f $Version)
$SumPath = Join-Path $ProjectDir "build\checksums.txt"

if (-not $SkipExport) {
	Write-Host "[1/3] Exporting Android APK v$Version ..."
	& powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "export_android.ps1")
	if ($LASTEXITCODE -ne 0) { throw "export_android.ps1 failed" }

	Write-Host "[2/3] Exporting Windows x64 EXE v$Version ..."
	& powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "export_windows.ps1") -Version $Version -SkipImportRefresh
	if ($LASTEXITCODE -ne 0) { throw "export_windows.ps1 failed" }
}

if (-not (Test-Path $ApkPath)) { throw "Missing APK: $ApkPath" }
if (-not (Test-Path $ExePath)) { throw "Missing EXE: $ExePath" }

$apkHash = (Get-FileHash $ApkPath -Algorithm SHA256).Hash.ToLowerInvariant()
$exeHash = (Get-FileHash $ExePath -Algorithm SHA256).Hash.ToLowerInvariant()
$sumLines = @(
	"$apkHash  $(Split-Path $ApkPath -Leaf)",
	"$exeHash  $(Split-Path $ExePath -Leaf)"
) -join "`n"
[System.IO.File]::WriteAllText($SumPath, $sumLines + "`n", (New-Object System.Text.UTF8Encoding($false)))
Write-Host "[checksums.txt]`n$sumLines"

if (-not $UploadRelease) {
	Write-Host "Local artifacts ready. Pass -UploadRelease (with gh CLI or GITHUB_TOKEN) to create/update GitHub Release v$Version."
	exit 0
}

$Tag = "v$Version"
$NotesBody = if ($ReleaseNotes -ne "") { $ReleaseNotes } else { [string]$mj.changelog }
$GhCmd = Get-Command gh -ErrorAction SilentlyContinue
if ($GhCmd) {
	$exists = $true
	& gh release view $Tag --repo "$Owner/$Repo" *> $null
	if ($LASTEXITCODE -ne 0) { $exists = $false }
	if (-not $exists) {
		& gh release create $Tag $ApkPath $ExePath $SumPath --repo "$Owner/$Repo" --title "艾瑟拉 Aethera $Tag" --notes $NotesBody
	} else {
		& gh release edit $Tag --repo "$Owner/$Repo" --title "艾瑟拉 Aethera $Tag" --notes $NotesBody
		& gh release upload $Tag $ApkPath $ExePath $SumPath --repo "$Owner/$Repo" --clobber
	}
	if ($LASTEXITCODE -ne 0) { throw "gh release upload failed" }
	exit 0
}

if (-not $Token) {
	throw "Neither gh CLI nor GITHUB_TOKEN is available for Release upload."
}

$hdr = @{
	Authorization = "Bearer $Token"
	Accept = "application/vnd.github+json"
	"User-Agent" = "Aethera-Release-Script/1.0"
}
$rel = $null
try {
	$rel = Invoke-RestMethod -Uri "https://api.github.com/repos/$Owner/$Repo/releases/tags/$Tag" -Headers $hdr -Method Get
} catch {
	$rel = $null
}
$payload = @{
	tag_name = $Tag
	target_commitish = [string]$mj.github_branch
	name = "艾瑟拉 Aethera $Tag"
	body = $NotesBody
	draft = $false
	prerelease = $false
} | ConvertTo-Json
if ($null -eq $rel) {
	$rel = Invoke-RestMethod -Uri "https://api.github.com/repos/$Owner/$Repo/releases" -Headers $hdr -Method Post -ContentType "application/json" -Body $payload
} else {
	$rel = Invoke-RestMethod -Uri "https://api.github.com/repos/$Owner/$Repo/releases/$($rel.id)" -Headers $hdr -Method Patch -ContentType "application/json" -Body $payload
}

$uploadBase = ([string]$rel.upload_url) -replace '\{\?name,label\}$', ''
foreach ($file in @($ApkPath, $ExePath, $SumPath)) {
	$fname = Split-Path $file -Leaf
	foreach ($existing in $rel.assets) {
		if ($existing.name -eq $fname) {
			Invoke-RestMethod -Uri "https://api.github.com/repos/$Owner/$Repo/releases/assets/$($existing.id)" -Headers $hdr -Method Delete | Out-Null
		}
	}
	$enc = [Uri]::EscapeDataString($fname)
	$u = "${uploadBase}?name=$enc"
	Write-Host "Uploading $fname -> $u ..."
	& curl.exe -f -L -sS --connect-timeout 30 --max-time 1800 --retry 2 -X POST -H "Authorization: Bearer $Token" -H "Accept: application/vnd.github+json" -H "Content-Type: application/octet-stream" -T "$file" $u
	if ($LASTEXITCODE -ne 0) { throw "Failed uploading $fname" }
}
Write-Host "GitHub Release $Tag published successfully to $Owner/$Repo !"
