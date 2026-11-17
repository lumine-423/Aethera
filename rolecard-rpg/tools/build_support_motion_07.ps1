param([string[]]$ActorIds=@('mingkong','ye'))
$ErrorActionPreference='Stop'
throw 'Retired 2026-10-28: use five-keyframe / external video workflow. See docs/video-art-strategy.md.'
$ProjectRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
foreach($ActorId in $ActorIds) {
  if($ActorId -notin @('mingkong','ye')){throw 'Unknown actor'}
  New-Item -ItemType Directory -Force -Path (Join-Path $ProjectRoot ('assets\characters\'+$ActorId+'-07')) | Out-Null
  $Arguments=@('--batch','--script-param',('actor='+$ActorId),'--script-param',('root='+$ProjectRoot.Replace('\','/')),'--script',(Join-Path $PSScriptRoot 'build_support_motion_07.lua'))
  $Run=Start-Process -FilePath 'D:\Aseprite\aseprite.exe' -ArgumentList $Arguments -WindowStyle Hidden -Wait -PassThru
  if($Run.ExitCode -ne 0){throw "Aseprite animation export failed: $ActorId"}
}
