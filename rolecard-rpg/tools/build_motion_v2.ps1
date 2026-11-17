$ErrorActionPreference='Stop'
throw 'Retired 2026-10-28: use five-keyframe / external video workflow. See docs/video-art-strategy.md.'
$ProjectRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$SourceBase=Join-Path $ProjectRoot 'art-source\rin-motion-v2'
$Runtime=Join-Path $ProjectRoot 'assets\characters\rin-motion-v2'
$Arguments=@('--batch','--script-param',('input='+ (Join-Path $SourceBase 'candidates\motion-grid-v2.png')),
 '--script-param',('components='+ (Join-Path $SourceBase 'component-analysis.json')),
 '--script-param',('output='+ (Join-Path $SourceBase 'rin-motion-v2.generated')),
 '--script-param',('runtime='+$Runtime),'--script',(Join-Path $PSScriptRoot 'build_rin_motion_v2.lua'))
$Run=Start-Process -FilePath 'D:\Aseprite\aseprite.exe' -ArgumentList $Arguments -WindowStyle Hidden -Wait -PassThru
if($Run.ExitCode -ne 0){throw 'Aseprite draft export failed'}
python (Join-Path $PSScriptRoot 'check_motion_v2.py')
if($LASTEXITCODE -ne 0){throw 'Motion structure validation failed'}
