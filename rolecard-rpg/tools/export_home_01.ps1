param([string]$Godot='D:\Godot\Godot_v4.7.2-stable_win64_console.exe')
$ErrorActionPreference='Stop'
$ProjectRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$OutputDir=Join-Path $ProjectRoot 'build\home'
$EvidenceDir=Join-Path $ProjectRoot 'evidence\home-build-01'
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
& $Godot --headless --path $ProjectRoot --editor --import --quit 2>&1 | Set-Content -LiteralPath (Join-Path $EvidenceDir 'import.log')
if($LASTEXITCODE -ne 0){throw 'Godot import failed'}
& $Godot --headless --path $ProjectRoot --export-release 'Web Home' (Join-Path $OutputDir 'index.html') 2>&1 | Set-Content -LiteralPath (Join-Path $EvidenceDir 'export.log')
if($LASTEXITCODE -ne 0 -or (Select-String -LiteralPath (Join-Path $EvidenceDir 'export.log') -Pattern 'SCRIPT ERROR|Parse Error|Failed to export' -Quiet)){throw 'Home export failed; inspect export.log'}
$IndexPath=Join-Path $OutputDir 'index.html'
$IndexHtml=Get-Content -LiteralPath $IndexPath -Raw
$IndexHtml=$IndexHtml -replace '<title>[^<]*</title>','<title>主页</title>'
[IO.File]::WriteAllText($IndexPath,$IndexHtml,[Text.UTF8Encoding]::new($false))
Get-ChildItem -LiteralPath $OutputDir -File | ForEach-Object { [pscustomobject]@{Name=$_.Name;Bytes=$_.Length;SHA256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash} } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $EvidenceDir 'web-build.json') -Encoding utf8
Write-Output $OutputDir
