param([string]$Godot = 'D:\Godot\Godot_v4.7.2-stable_win64_console.exe',[ValidateSet('Probe','Game')][string]$Target='Probe')
$ErrorActionPreference = 'Stop'
$ProjectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$OutputDir = Join-Path $ProjectRoot $(if($Target -eq 'Game'){'build\game'}else{'build\web'})
$EvidenceDir = Join-Path $ProjectRoot 'evidence'
if (!(Test-Path -LiteralPath $Godot)) { throw 'Godot executable missing' }
if (!(Test-Path -LiteralPath (Join-Path $ProjectRoot '.tools\godot-4.7.2\receipt.json'))) {
    throw 'Project-local official templates have not been verified'
}
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
New-Item -ItemType Directory -Path $EvidenceDir -Force | Out-Null
$ImportLog = Join-Path $EvidenceDir ('latest-'+$Target.ToLower()+'-import.txt')
$ExportLog = Join-Path $EvidenceDir ('latest-'+$Target.ToLower()+'-export.txt')
& $Godot --headless --path $ProjectRoot --editor --import 2>&1 | Tee-Object -FilePath $ImportLog
if ($LASTEXITCODE -ne 0 -or (Select-String -LiteralPath $ImportLog -Pattern 'SCRIPT ERROR|Parse Error|Failed to load' -Quiet)) {
    throw 'Import or script validation failed; inspect latest-import.txt'
}
& $Godot --headless --path $ProjectRoot --export-release ('Web '+$Target) (Join-Path $OutputDir 'index.html') 2>&1 | Tee-Object -FilePath $ExportLog
if ($LASTEXITCODE -ne 0 -or (Select-String -LiteralPath $ExportLog -Pattern 'SCRIPT ERROR|Parse Error|Failed to export' -Quiet)) {
    throw 'Web export failed; inspect latest-export.txt'
}
if($Target -eq 'Probe'){Copy-Item -LiteralPath (Join-Path $ProjectRoot 'web\game-bridge.js') -Destination (Join-Path $OutputDir 'game-bridge.js')}
if($Target -eq 'Game'){foreach($ModuleName in @('game-platform.mjs','writer-lease.mjs')){Copy-Item -LiteralPath (Join-Path $ProjectRoot ('web\'+$ModuleName)) -Destination (Join-Path $OutputDir $ModuleName)}}
$Files = Get-ChildItem -LiteralPath $OutputDir -File | ForEach-Object {
    [pscustomobject]@{ Name=$_.Name; Bytes=$_.Length; SHA256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }
}
[pscustomobject]@{ Engine=(& $Godot --version); Build=('rolecard-'+$Target.ToLower()+'-10'); Files=@($Files) } |
    ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $EvidenceDir ('latest-'+$Target.ToLower()+'-build.json')) -Encoding utf8
