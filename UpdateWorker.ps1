param([string]$Mode,[string]$CurrentVersion,[string]$StageRoot)
$ErrorActionPreference='Stop'; $ProgressPreference='SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
$headers=@{'User-Agent'='Daylight-Updater'}
$release=Invoke-RestMethod 'https://api.github.com/repos/ddangmini/Daylight/releases/latest' -Headers $headers -TimeoutSec 20
if($release.tag_name -notmatch '^v(\d+\.\d+\.\d+)$' -or $release.draft -or $release.prerelease) {throw '정식 업데이트 버전을 확인할 수 없습니다.'}
$version=$Matches[1]; $available=[version]$version -gt [version]$CurrentVersion
if($Mode -eq 'check') {return [pscustomobject]@{version=$version;available=$available;url=$release.html_url}}
if(-not $available) {throw '이미 최신 버전입니다.'}
$zipName='Daylight-'+$version+'.zip'
$zipAsset=@($release.assets|Where-Object {$_.name -eq $zipName}); $shaAsset=@($release.assets|Where-Object {$_.name -eq 'SHA256SUMS.txt'})
if($zipAsset.Count -ne 1 -or $shaAsset.Count -ne 1 -or $zipAsset[0].size -gt 100MB) {throw '정상적인 업데이트 파일이 없습니다.'}
foreach($asset in @($zipAsset[0],$shaAsset[0])) {if(-not $asset.browser_download_url.StartsWith('https://github.com/ddangmini/Daylight/releases/download/'+$release.tag_name+'/')) {throw '업데이트 주소가 올바르지 않습니다.'}}
[void][IO.Directory]::CreateDirectory($StageRoot)
$zipPath=Join-Path $StageRoot $zipName; $shaPath=Join-Path $StageRoot 'SHA256SUMS.txt'
Invoke-WebRequest $zipAsset[0].browser_download_url -Headers $headers -UseBasicParsing -OutFile $zipPath -TimeoutSec 60
Invoke-WebRequest $shaAsset[0].browser_download_url -Headers $headers -UseBasicParsing -OutFile $shaPath -TimeoutSec 20
$line=[IO.File]::ReadAllText($shaPath).Trim()
if($line -notmatch ('^([a-fA-F0-9]{64})\s+\*?'+[regex]::Escape($zipName)+'$')) {throw '업데이트 체크섬을 확인할 수 없습니다.'}
if((Get-FileHash $zipPath -Algorithm SHA256).Hash -ne $Matches[1]) {throw '다운로드 파일이 손상되었습니다.'}
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip=[IO.Compression.ZipFile]::OpenRead($zipPath); $folder=Join-Path $StageRoot 'app'; [void][IO.Directory]::CreateDirectory($folder)
try {
 if($zip.Entries.Count -gt 100) {throw '업데이트 파일 목록이 올바르지 않습니다.'}
 $names=@{}
 foreach($entry in $zip.Entries) {
  $name=$entry.FullName
  if([IO.Path]::GetFileName($name) -ne $name -or $name -match '[\\/]' -or $name -match '(data\.json|\.dat|\.bak|\.log)' -or $name -notmatch '\.(ps1|cs|xaml|html|md|ico|png|dll|exe|json|cmd|txt)$' -or $entry.Length -gt 30MB -or $names.ContainsKey($name)) {throw '안전하지 않은 업데이트 파일을 발견했습니다.'}
  $names[$name]=$true; [IO.Compression.ZipFileExtensions]::ExtractToFile($entry,(Join-Path $folder $name),$false)
 }
} finally {$zip.Dispose()}
$manifest=Get-Content (Join-Path $folder 'version.json') -Raw -Encoding UTF8|ConvertFrom-Json
if($manifest.version -ne $version -or $manifest.files.Count+3 -ne $names.Count) {throw '업데이트 목록이 일치하지 않습니다.'}
foreach($file in $manifest.files) {if(-not $names.ContainsKey($file.name) -or $file.sha256 -notmatch '^[A-Fa-f0-9]{64}$' -or (Get-FileHash (Join-Path $folder $file.name)).Hash -ne $file.sha256) {throw '업데이트 구성 요소가 손상되었습니다.'}}
foreach($name in @('Daylight.exe','Daylight.ps1','Update.ps1','Update.cmd')) {if(-not $names.ContainsKey($name)) {throw '앱 파일이 누락되었습니다.'}}
return [pscustomobject]@{version=$version;stage=$folder;available=$true}
