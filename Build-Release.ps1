param([string]$OutputDirectory,[switch]$RebuildLauncher)
$ErrorActionPreference='Stop'
if(-not $OutputDirectory) {$OutputDirectory=Join-Path $PSScriptRoot 'dist'}
[void][IO.Directory]::CreateDirectory($OutputDirectory)
if($RebuildLauncher -or -not (Test-Path (Join-Path $PSScriptRoot 'Daylight.exe'))) {
 $compiler=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
 & $compiler /nologo /target:winexe /reference:System.Windows.Forms.dll (('/win32icon:')+(Join-Path $PSScriptRoot 'Daylight.ico')) (('/out:')+(Join-Path $PSScriptRoot 'Daylight.exe')) (Join-Path $PSScriptRoot 'Launcher.cs')
 if($LASTEXITCODE -ne 0) {throw 'Launcher compilation failed'}
}
$update=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Update.ps1'))
$match=[regex]::Match($update,'allowedFiles\s*=\s*@\((.*?)\)')
if(-not $match.Success) {throw 'Release file list missing'}
$names=@([regex]::Matches($match.Groups[1].Value,"'([^']+)'")|ForEach-Object {$_.Groups[1].Value}|Where-Object {$_ -ne 'version.json'})
foreach($name in $names) {
 if([IO.Path]::GetFileName($name) -ne $name -or $name -match '(data\.json|\.dat|\.bak|\.log)$') {throw 'Unexpected release file'}
 $path=Join-Path $PSScriptRoot $name
 if(-not (Test-Path -LiteralPath $path -PathType Leaf)) {throw "Required file missing: $name"}
 if($name.EndsWith('.ps1')) {[IO.File]::WriteAllText($path,[IO.File]::ReadAllText($path),(New-Object Text.UTF8Encoding $true))}
}
$files=@($names|ForEach-Object {[pscustomobject]@{name=$_;sha256=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $_) -Algorithm SHA256).Hash}})
$manifest=@{version='0.9.1';files=$files}|ConvertTo-Json -Depth 5
[IO.File]::WriteAllText((Join-Path $PSScriptRoot 'version.json'),$manifest,(New-Object Text.UTF8Encoding $false))
$archive=Join-Path $OutputDirectory 'Daylight-0.9.1.zip'
$paths=@(($names+@('version.json','Update.cmd','Update.ps1'))|ForEach-Object {Join-Path $PSScriptRoot $_})
Compress-Archive -LiteralPath $paths -DestinationPath $archive -Force
$checksum=(Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()+'  Daylight-0.9.1.zip'
[IO.File]::WriteAllText((Join-Path $OutputDirectory 'SHA256SUMS.txt'),$checksum+"`n",(New-Object Text.UTF8Encoding $false))
"PASS: release ZIP contains only allowlisted application files ($($paths.Count) files)"
