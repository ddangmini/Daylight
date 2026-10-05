param([string]$TargetPath, [switch]$SelfTest)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework, System.Windows.Forms
$script:allowedFiles = @('Daylight.ps1','Calendar.ps1','Notion.ps1','NotionUI.ps1','Theme.xaml','Start.cmd','GoogleSetup.html','NotionSetup.html','사용안내.md','Shell.ps1','Layout.ps1','Weather.ps1','VerifyUI.ps1','Memo.ps1','Appearance.ps1','GPT.ps1','GPTUI.ps1','WeatherUI.ps1','WindowHost.ps1','Diagnostics.ps1','BackgroundWork.ps1','Desktop.ps1','ExtraShell.ps1','Extras.ps1','ExtraBackend.ps1','VerifyExtras.ps1','Daylight.exe','Features.ps1','VerifyFeatures.ps1','DesignGallery.html','Styles.ps1','Icons.ps1','Daylight.ico','Daylight.png','YouTube.ps1','YouTubeHost.cs','YouTubePlayer.html','VerifyYouTube.ps1','README.md','CHANGELOG.md','version.json')
function Get-UpdateTarget([string]$Root, [string]$Name) {
    if ($Name -notin $script:allowedFiles) { throw '업데이트 파일 목록이 올바르지 않습니다.' }
    $base = [IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
    $path = [IO.Path]::GetFullPath((Join-Path $base $Name))
    if (-not $path.StartsWith($base, [StringComparison]::OrdinalIgnoreCase)) { throw '업데이트 경로가 앱 폴더 밖을 가리킵니다.' }
    return $path
}
function Install-DaylightPatch([string]$Root, [bool]$CheckRunning = $true) {
    $target = [IO.Path]::GetFullPath($Root)
    if ($target.TrimEnd('\') -eq [IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\')) { throw '패치를 별도 폴더에 풀고 기존 앱 폴더를 대상으로 선택하세요.' }
    if (-not (Test-Path -LiteralPath (Join-Path $target 'Daylight.ps1')) -or -not (Test-Path -LiteralPath (Join-Path $target 'Calendar.ps1'))) { throw '기존 Daylight.ps1과 Calendar.ps1이 있는 앱 폴더를 선택하세요.' }
    if ($CheckRunning) {
        $appPath = Join-Path $target 'Daylight.ps1'
        $running = @(Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe' OR Name = 'pwsh.exe'" | Where-Object { $_.CommandLine -and $_.CommandLine.IndexOf($appPath, [StringComparison]::OrdinalIgnoreCase) -ge 0 })
        if ($running.Count) { throw 'Daylight가 실행 중입니다. 위젯을 종료한 뒤 업데이트를 다시 실행하세요.' }
    }
    $manifest = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'version.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($manifest.files.Count -ne ($script:allowedFiles.Count - 1)) { throw '업데이트 파일이 누락되었습니다. 패치 압축을 다시 풀어주세요.' }
    foreach ($item in $manifest.files) {
        $source = Get-UpdateTarget $PSScriptRoot $item.name
        if ((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -ne $item.sha256) { throw '업데이트 파일이 손상되었습니다. 패치를 다시 내려받으세요.' }
    }
    $backupRoot = Join-Path $target ('updates\backup-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8))
    $targetBase = $target.TrimEnd('\') + '\'
    $resolvedBackup = [IO.Path]::GetFullPath($backupRoot)
    if (-not $resolvedBackup.StartsWith($targetBase, [StringComparison]::OrdinalIgnoreCase)) { throw '백업 경로가 앱 폴더 밖을 가리킵니다.' }
    [void][IO.Directory]::CreateDirectory($resolvedBackup)
    $changed = @()
    try {
        foreach ($name in $script:allowedFiles) {
            $source = Get-UpdateTarget $PSScriptRoot $name; $destination = Get-UpdateTarget $target $name
            $existed = Test-Path -LiteralPath $destination
            if ($existed) { Copy-Item -LiteralPath $destination -Destination (Join-Path $resolvedBackup $name) -Force }
            $changed += [pscustomobject]@{ name = $name; existed = $existed }
            Copy-Item -LiteralPath $source -Destination $destination -Force
        }
    } catch {
        foreach ($item in $changed) {
            $destination = Get-UpdateTarget $target $item.name
            if ($item.existed) { Copy-Item -LiteralPath (Join-Path $resolvedBackup $item.name) -Destination $destination -Force }
            elseif (Test-Path -LiteralPath $destination) { Remove-Item -LiteralPath $destination -Force }
        }
        throw '패치를 적용하지 못해 이전 앱 파일로 되돌렸습니다. 폴더 권한을 확인하세요.'
    }
    return $resolvedBackup
}
if ($SelfTest) {
    if (-not $TargetPath) { throw 'Test target required' }
    $before = @{}
    foreach ($name in @('data.json','data.json.bak','calendar-client.dat','calendar-token.dat','calendar-token.dat.bak','notion-settings.dat','gpt-settings.dat','gpt-settings.dat.bak','gemini-settings.dat','gemini-settings.dat.bak')) { $before[$name] = (Get-FileHash -LiteralPath (Join-Path $TargetPath $name)).Hash }
    [void](Install-DaylightPatch $TargetPath $false)
    foreach ($name in $before.Keys) { if ((Get-FileHash -LiteralPath (Join-Path $TargetPath $name)).Hash -ne $before[$name]) { throw "User data changed: $name" } }
    if (-not (Test-Path -LiteralPath (Join-Path $TargetPath 'NotionUI.ps1'))) { throw 'Patch files missing' }
    'PASS: patch manifest, source integrity, code backup, update application, Google/Notion/GPT credentials and local data unchanged'; exit 0
}
try {
    if (-not $TargetPath) {
        $picker = New-Object Windows.Forms.FolderBrowserDialog
        $picker.Description = '지금 사용 중인 Daylight 앱 폴더를 선택하세요. 로그인 정보와 메모를 그대로 보존합니다.'
        $picker.ShowNewFolderButton = $false
        if ($picker.ShowDialog() -ne [Windows.Forms.DialogResult]::OK) { exit 0 }
        $TargetPath = $picker.SelectedPath
    }
    [void](Install-DaylightPatch $TargetPath)
    [void][Windows.MessageBox]::Show('Daylight 0.9 업데이트이 적용되었습니다. 기존 앱 폴더의 Start.cmd를 실행하세요. 로그인 정보와 메모는 그대로 유지됩니다.', 'Daylight 업데이트')
} catch { [void][Windows.MessageBox]::Show($_.Exception.Message, '업데이트를 완료하지 못했습니다') }
