$ErrorActionPreference='Stop'
throw 'Retired 2026-10-28: use five-keyframe / external video workflow. See docs/video-art-strategy.md.'
$ProjectRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$Aseprite='D:\Aseprite\aseprite.exe'
$SourceBase=Join-Path $ProjectRoot 'art-source\rin-cast-study'
$Runtime=Join-Path $ProjectRoot 'assets\characters\rin-study'
$Arguments=@('--batch','--script-param',('input='+ (Join-Path $SourceBase 'candidates\keyposes-alpha-v2.png')),
 '--script-param',('output='+ (Join-Path $SourceBase 'rin-cast-study')),
 '--script-param',('runtime='+$Runtime),'--script',(Join-Path $PSScriptRoot 'build_rin_study.lua'))
$Run=Start-Process -FilePath $Aseprite -ArgumentList $Arguments -WindowStyle Hidden -Wait -PassThru
if($Run.ExitCode -ne 0){throw 'Aseprite source build failed'}
$Metadata=Get-Content -LiteralPath (Join-Path $SourceBase 'rin-cast-study-normalization.json') -Raw | ConvertFrom-Json
if($Metadata.frames[2].front_leg_correction -ne -14 -or $Metadata.frames[3].front_leg_correction -ne -17){throw 'Expected source revision was not produced'}
$Run=Start-Process -FilePath $Aseprite -ArgumentList @('--batch',(Join-Path $Runtime 'cast-study.png'),'--scale','3','--save-as',(Join-Path $SourceBase 'contact-3x.png')) -WindowStyle Hidden -Wait -PassThru
if($Run.ExitCode -ne 0){throw 'Aseprite contact sheet failed'}
python (Join-Path $PSScriptRoot 'check_art_assets.py')
if($LASTEXITCODE -ne 0){throw 'Art structural validation failed'}
