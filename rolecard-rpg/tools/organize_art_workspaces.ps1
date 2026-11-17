param([string]$Inventory='')
$ErrorActionPreference='Stop'
$ProjectRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$WorkspaceRoot=[IO.Path]::GetFullPath((Join-Path $ProjectRoot 'workspaces'))
if(-not $Inventory){$Inventory=Join-Path $WorkspaceRoot 'organization-records\2026-10-29\migration-inventory.json'}
$Record=Get-Content -LiteralPath $Inventory -Raw | ConvertFrom-Json
$Results=@()
foreach($Batch in $Record.batches){
    $SourcePath=[IO.Path]::GetFullPath($Batch.source)
    $TargetPath=[IO.Path]::GetFullPath($Batch.target)
    # Check exact absolute boundaries before any move. No recursive shell deletion.
    if(-not $SourcePath.StartsWith((Join-Path $ProjectRoot 'art-source')+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw "Source outside art-source: $SourcePath"}
    if(-not $TargetPath.StartsWith($WorkspaceRoot+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw "Target outside workspaces: $TargetPath"}
    if(Test-Path -LiteralPath $TargetPath){
        $Existing=Get-Item -LiteralPath $SourcePath
        if($Existing.LinkType -ne 'Junction'){throw "Target exists without matching old junction: $TargetPath"}
        if([IO.Path]::GetFullPath([string]$Existing.Target) -ne $TargetPath){throw "Unexpected junction: $SourcePath"}
    }else{
        $SourceItem=Get-Item -LiteralPath $SourcePath
        if($SourceItem.Attributes -band [IO.FileAttributes]::ReparsePoint){throw "Source already redirects elsewhere: $SourcePath"}
        New-Item -ItemType Directory -Path (Split-Path -Parent $TargetPath) -Force | Out-Null
        Move-Item -LiteralPath $SourcePath -Destination $TargetPath
        try{
            New-Item -ItemType Junction -Path $SourcePath -Value $TargetPath | Out-Null
        }catch{
            if(-not (Test-Path -LiteralPath $SourcePath)){Move-Item -LiteralPath $TargetPath -Destination $SourcePath}
            throw
        }
    }
    foreach($File in $Batch.files){
        $MovedPath=Join-Path $TargetPath $File.path
        $OldAliasPath=Join-Path $SourcePath $File.path
        if(-not (Test-Path -LiteralPath $MovedPath) -or -not (Test-Path -LiteralPath $OldAliasPath)){throw "Missing moved file or alias: $MovedPath"}
        if((Get-FileHash -LiteralPath $MovedPath -Algorithm SHA256).Hash -ne $File.sha256){throw "Content changed during move: $MovedPath"}
    }
    $Results += [pscustomobject]@{batch=$Batch.batch;area=$Batch.area;source=$SourcePath;target=$TargetPath;files=$Batch.files.Count;hashVerified=$true;oldPathJunction=$true}
}
$OutputPath=Join-Path (Split-Path -Parent $Inventory) 'migration-result.json'
$Results | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $OutputPath -Encoding utf8
Write-Output "Moved/verified $($Results.Count) batches. Receipt: $OutputPath"
