$script:updateJob=$null; $script:updateStage=$null; $script:updateMode=''; $script:startupChanging=$false
$script:installedVersion=(Get-Content (Join-Path $PSScriptRoot 'version.json') -Raw -Encoding UTF8|ConvertFrom-Json).version
function Get-StartupCommand([string]$Root=$PSScriptRoot) {return '"'+(Join-Path $Root 'Daylight.exe')+'"'}
function Set-DaylightStartup([bool]$Enabled) {
 $path='HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
 if($Enabled) {if(-not (Test-Path $path)) {[void](New-Item $path -Force)}; [void](New-ItemProperty $path -Name 'Daylight' -Value (Get-StartupCommand) -PropertyType String -Force)}
 else {Remove-ItemProperty $path -Name 'Daylight' -ErrorAction SilentlyContinue}
}
function Start-UpdateCheck([string]$Mode='check') {
 if($script:updateJob) {return}
 $script:updateMode=$Mode; $folder=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) ('Daylight\Updates\'+[guid]::NewGuid().ToString('N'))
 $script:updateJob=Start-DaylightJob -ScriptBlock {param($worker,$mode,$version,$folder); & $worker -Mode $mode -CurrentVersion $version -StageRoot $folder} -ArgumentList @((Join-Path $PSScriptRoot 'UpdateWorker.ps1'),$Mode,$script:installedVersion,$folder)
 $productUI.UpdateStatus.Text='업데이트 '+$(if($Mode -eq 'check'){'확인'}else{'다운로드·검증'})+' 중…'
}
function Receive-UpdateCheck {
 if(-not $script:updateJob -or $script:updateJob.State -eq 'Running') {return}
 try {
  $result=Receive-DaylightJob $script:updateJob
  if($script:updateMode -eq 'download') {$script:updateStage=$result.stage; $productUI.UpdateInstall.IsEnabled=$true; $productUI.UpdateStatus.Text='v'+$result.version+' 검증 완료 · 업데이트 후 재시작을 누르세요.'}
  elseif($result.available) {$productUI.UpdateStatus.Text='v'+$result.version+' 사용 가능'; $productUI.UpdateDownload.IsEnabled=$true}
  else {$productUI.UpdateStatus.Text='현재 v'+$script:installedVersion+' · 최신 버전입니다.'; $productUI.UpdateDownload.IsEnabled=$false}
 } catch {$productUI.UpdateStatus.Text='업데이트를 완료하지 못했습니다 · '+$_.Exception.Message}
 finally {Remove-DaylightJob $script:updateJob; $script:updateJob=$null}
}
function Start-DaylightHandoff([string]$Stage) {
 if($SelfTest) {throw '테스트에서는 실제 업데이트를 실행하지 않습니다.'}
 Sync-CurrentNote; Save-State
 $arguments='-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "'+(Join-Path $PSScriptRoot 'UpdateHandoff.ps1')+'" -TargetRoot "'+$PSScriptRoot+'" -StageRoot "'+$Stage+'" -AppProcessId '+$PID
 Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList $arguments -WindowStyle Hidden
 $script:quitRequested=$true; $window.Close()
}
function Get-DaylightBackups {
 $root=Join-Path $PSScriptRoot 'updates'; if(-not (Test-Path $root)) {return @()}
 return @(Get-ChildItem $root -Directory|Where-Object {Test-Path (Join-Path $_.FullName 'version.json')}|Sort-Object LastWriteTime -Descending|Select-Object -First 12)
}
function Prepare-DaylightRollback([string]$Backup) {
 $base=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'updates')).TrimEnd('\')+'\'; $resolved=[IO.Path]::GetFullPath($Backup)
 if(-not $resolved.StartsWith($base,[StringComparison]::OrdinalIgnoreCase)) {throw '앱 백업 폴더를 선택하세요.'}
 $manifest=Get-Content (Join-Path $resolved 'version.json') -Raw -Encoding UTF8|ConvertFrom-Json
 if([version]$manifest.version -lt [version]'0.10.0' -and (@($state.timetable).Count -or @($state.taskRules).Count -or @($state.activityHistory).Count)) {throw '이 백업은 시간표·반복 할 일 기록을 지원하지 않습니다. 데이터 보호를 위해 복원을 제한합니다.'}
 $stage=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) ('Daylight\Updates\rollback-'+[guid]::NewGuid().ToString('N')); [void][IO.Directory]::CreateDirectory($stage)
 foreach($file in $manifest.files) {
  if([IO.Path]::GetFileName($file.name) -ne $file.name -or $file.name -match '(data\.json|\.dat|\.bak|\.log)' -or $file.sha256 -notmatch '^[a-fA-F0-9]{64}$') {throw '백업 파일 목록이 올바르지 않습니다.'}
  $source=Join-Path $resolved $file.name; if(-not (Test-Path $source)) {$source=Join-Path $PSScriptRoot $file.name}
  if((Get-FileHash $source).Hash -ne $file.sha256) {throw '이 백업은 복원할 파일이 부족합니다. 다른 백업을 선택하세요.'}
  Copy-Item -LiteralPath $source -Destination (Join-Path $stage $file.name)
 }
 foreach($name in @('version.json','Update.ps1','Update.cmd')) {$source=Join-Path $resolved $name; if(-not (Test-Path $source)) {$source=Join-Path $PSScriptRoot $name}; Copy-Item -LiteralPath $source -Destination (Join-Path $stage $name)}
 return $stage
}
$productUI.UpdateCheck.Add_Click({Start-UpdateCheck})
$productUI.UpdateDownload.Add_Click({Start-UpdateCheck 'download'})
$productUI.UpdateInstall.Add_Click({if($script:updateStage) {Start-DaylightHandoff $script:updateStage}})
$productUI.Rollback.Add_Click({try {if(-not $productUI.Backups.SelectedItem) {throw '백업을 선택하세요.'}; $stage=Prepare-DaylightRollback $productUI.Backups.SelectedItem.Tag; Start-DaylightHandoff $stage} catch {$productUI.UpdateStatus.Text=$_.Exception.Message}})
$productUI.Startup.Add_Click({try {Set-DaylightStartup ([bool]$this.IsChecked); $productUI.StartupStatus.Text='적용됨 · 현재 사용자 계정'} catch {$this.IsChecked=-not $this.IsChecked; $productUI.StartupStatus.Text='자동 실행 설정을 변경하지 못했습니다.'}})
if(-not $SelfTest) {$productUI.Startup.IsChecked=[bool](Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name Daylight -ErrorAction SilentlyContinue).Daylight}
foreach($backup in @(Get-DaylightBackups)) {try {$version=(Get-Content (Join-Path $backup.FullName 'version.json') -Raw -Encoding UTF8|ConvertFrom-Json).version; $item=New-Object Windows.Controls.ComboBoxItem; $item.Content='v'+$version+' · '+$backup.LastWriteTime.ToString('MM-dd HH:mm'); $item.Tag=$backup.FullName; [void]$productUI.Backups.Items.Add($item)} catch {}}
if($productUI.Backups.Items.Count) {$productUI.Backups.SelectedIndex=0}
