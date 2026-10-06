param([string]$TargetRoot,[string]$StageRoot,[int]$AppProcessId)
$ErrorActionPreference='Stop'
try {
 if(Get-Process -Id $AppProcessId -ErrorAction SilentlyContinue) {Wait-Process -Id $AppProcessId -Timeout 45 -ErrorAction Stop}
 $expected=(Get-Content (Join-Path $StageRoot 'version.json') -Raw -Encoding UTF8|ConvertFrom-Json).version
 & powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File (Join-Path $StageRoot 'Update.ps1') -TargetPath $TargetRoot
 $installed=(Get-Content (Join-Path $TargetRoot 'version.json') -Raw -Encoding UTF8|ConvertFrom-Json).version
 if($installed -ne $expected) {throw '설치 버전을 확인하지 못했습니다. 기존 앱을 다시 실행하세요.'}
 Start-Process -FilePath (Join-Path $TargetRoot 'Daylight.exe') -WindowStyle Hidden
} catch {Add-Type -AssemblyName PresentationFramework; [void][Windows.MessageBox]::Show($_.Exception.Message,'Daylight 업데이트')}
