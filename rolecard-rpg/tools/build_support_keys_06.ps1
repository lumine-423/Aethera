$ErrorActionPreference='Stop'
throw 'Retired 2026-10-28: use five-keyframe / external video workflow. See docs/video-art-strategy.md.'
$ProjectRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$SourceBase=Join-Path $ProjectRoot 'art-source\support-motion-06'
foreach($Actor in @('mingkong','ye')) {
  $Arguments=@('--batch','--script-param',('input='+ (Join-Path $SourceBase ($Actor+'-keys.png'))), '--script-param',('output='+ (Join-Path $SourceBase ($Actor+'-keys.generated'))), '--script',(Join-Path $PSScriptRoot 'build_support_keys_06.lua'))
  $Run=Start-Process -FilePath 'D:\Aseprite\aseprite.exe' -ArgumentList $Arguments -WindowStyle Hidden -Wait -PassThru
  if($Run.ExitCode -ne 0){throw "Aseprite key extraction failed: $Actor"}
}
