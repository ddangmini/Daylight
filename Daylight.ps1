param([switch]$SelfTest, [string]$DataPath, [string]$PreviewPath)
$ErrorActionPreference = 'Stop'
if (-not $DataPath) { $DataPath = Join-Path $PSScriptRoot 'data.json' }
. (Join-Path $PSScriptRoot 'Diagnostics.ps1')
. (Join-Path $PSScriptRoot 'BackgroundWork.ps1')
trap {Write-DaylightDiagnostic 'fatal' $_; break}
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
. (Join-Path $PSScriptRoot 'WindowHost.ps1')
. (Join-Path $PSScriptRoot 'Calendar.ps1')
. (Join-Path $PSScriptRoot 'Notion.ps1')
if (-not $DataPath) { $DataPath = Join-Path $PSScriptRoot 'data.json' }
$script:state = @{ tasks = @(); note = ''; compact = $false; pinned = $true; calendarId = 'primary'; autoLayout = $true; lockRatio = $false; clockVisible = $true; weatherVisible = $true; darkText = $false; geometry = $null; mainVisible = $true; tasksVisible = $true; memoVisible = $true; chatVisible = $false; appearance = $null; widgetPins = $null; notes = @(); selectedNote = ''; weatherCity = '서울'; weatherLatitude = 37.5665; weatherLongitude = 126.9780 }
$script:loadWarning = ''
if (Test-Path -LiteralPath $DataPath) {
    try {
        $saved = Get-Content -LiteralPath $DataPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $script:state.tasks = @($saved.tasks | Where-Object { $null -ne $_ })
        $script:state.note = [string]$saved.note
        $script:state.compact = [bool]$saved.compact
        $script:state.pinned = [bool]$saved.pinned
        if ($saved.calendarId) { $script:state.calendarId = [string]$saved.calendarId }
        foreach ($key in @('hideWidgetTitles','hideWidgetBorders','snapWidgets','youtube','youtubeVisible','extras','ddayVisible','habitsVisible','mediaVisible','launcherVisible','progressVisible','systemVisible','photoVisible','quoteVisible','widgetDesktop','widgetLocks','autoLayout','lockRatio','clockVisible','weatherVisible','darkText','geometry','weatherCity','weatherLatitude','weatherLongitude','mainVisible','tasksVisible','memoVisible','chatVisible','appearance','widgetPins','layoutProfiles','alertSettings','notifications','notes','selectedNote')) {
            if ($null -ne $saved.PSObject.Properties[$key]) { $script:state[$key] = $saved.$key }
        }
    } catch { $script:loadWarning = '저장 파일을 읽지 못했습니다. 기존 파일을 보존합니다.' }
}
. (Join-Path $PSScriptRoot 'Shell.ps1')
. (Join-Path $PSScriptRoot 'Icons.ps1')
function Save-State {
    if ($script:loadWarning) { $ui.Status.Text = $script:loadWarning; return }
    try {
        if ($script:layoutReady) { Capture-DaylightGeometry }
        $json = $script:state | ConvertTo-Json -Depth 8
        $temporary = "$DataPath.tmp"
        [IO.File]::WriteAllText($temporary, $json, (New-Object Text.UTF8Encoding $false))
        if (Test-Path -LiteralPath $DataPath) { [IO.File]::Replace($temporary, $DataPath, "$DataPath.bak") } else { [IO.File]::Move($temporary, $DataPath) }
        $ui.Status.Text = '이 기기에 자동 저장'
    } catch { $ui.Status.Text = '저장 실패 · 폴더 쓰기 권한을 확인하세요' }
}
function Render-Tasks {
    $ui.Tasks.Children.Clear()
    $done = @($script:state.tasks | Where-Object { $_.done }).Count
    $ui.Progress.Text = "완료 $done / $($script:state.tasks.Count)"
    if ($script:state.tasks.Count -eq 0) {
        $empty = New-Object Windows.Controls.TextBlock
        $empty.Text = '오늘 하고 싶은 일을 적어보세요.'; $empty.Foreground = '#8593AA'; $empty.Margin = '0,10,0,0'
        [void]$ui.Tasks.Children.Add($empty)
    }
    foreach ($task in (Get-DaylightPage $script:state.tasks 'local')) {
        $row = New-Object Windows.Controls.DockPanel; $row.Margin = '0,0,0,8'
        $delete = New-Object Windows.Controls.Button; $delete.Content = '×'; $delete.Padding = '8,4'; $delete.Margin = '8,0,0,0'; $delete.Tag = $task.id; $delete.Opacity = 0
        $row.Add_MouseEnter({ $this.Children[0].Opacity = 1 }); $row.Add_MouseLeave({ $this.Children[0].Opacity = 0 })
        [Windows.Controls.DockPanel]::SetDock($delete, [Windows.Controls.Dock]::Right)
        $delete.Add_Click({ $id = $this.Tag; $script:state.tasks = @($script:state.tasks | Where-Object { $_.id -ne $id }); Save-State; Render-Tasks })
        [void]$row.Children.Add($delete)
        $check = New-Object Windows.Controls.CheckBox; $check.IsChecked = [bool]$task.done; $check.Tag = $task.id; $check.Foreground = '#E9EDF5'; $check.VerticalContentAlignment = 'Center'; $check.Padding = '4,5,0,5'
        $label = New-Object Windows.Controls.TextBlock; $label.Text = [string]$task.text; $label.TextWrapping = 'Wrap'; $label.MaxWidth = [Math]::Max(120,$tasksWindow.Width-115); $label.MaxHeight = 42; $label.TextTrimming = 'CharacterEllipsis'; $label.ToolTip=$task.text
        if ($task.done) { $label.Opacity = 0.5; $label.TextDecorations = [Windows.TextDecorations]::Strikethrough }
        $check.Content = $label
        $check.Add_Click({ foreach ($item in $script:state.tasks) { if ($item.id -eq $this.Tag) { $item.done = [bool]$this.IsChecked } }; Save-State; Render-Tasks })
        [void]$row.Children.Add($check); [void]$ui.Tasks.Children.Add($row)
    }
}
function Add-Task {
    $value = $ui.TaskInput.Text.Trim()
    if (-not $value) { return }
    $script:state.tasks += [pscustomobject]@{ id = [guid]::NewGuid().ToString(); text = $value; done = $false }
    $ui.TaskInput.Clear(); Save-State; Render-Tasks
}
function Apply-Mode { Set-DaylightMode }
function Update-Clock {
    $now = [TimeZoneInfo]::ConvertTime([DateTimeOffset]::UtcNow, [TimeZoneInfo]::FindSystemTimeZoneById('Korea Standard Time'))
    $ui.Clock.Text = $now.ToString('HH:mm')
    $ui.Date.Text = $now.ToString('M월 d일 dddd', [Globalization.CultureInfo]::GetCultureInfo('ko-KR'))
}
$script:calendarJob = $null
$script:calendarUpdatingChoice = $false
$script:lastCalendarAttempt = [DateTime]::MinValue
$script:lastAgenda = $null
function Set-CalendarControls([bool]$Busy) {
    $connected = Test-Path -LiteralPath (Join-Path $PSScriptRoot 'calendar-token.dat')
    $ui.CalendarConnect.IsEnabled = -not $Busy -and (-not $connected -or $script:calendarReconnectRequired)
    $ui.CalendarConnect.Content='구글 연결'; if($script:calendarReconnectRequired) {$ui.CalendarConnect.Content='다시 로그인'}
    $ui.CalendarSettings.IsEnabled = -not $Busy -and -not $connected
    $ui.CalendarRefresh.IsEnabled = -not $Busy -and $connected
    $ui.CalendarDisconnect.IsEnabled = -not $Busy -and $connected
    $ui.CalendarChoice.IsEnabled = -not $Busy -and $connected
    if ($Busy) { $ui.CalendarCancel.Visibility = 'Visible' } else { $ui.CalendarCancel.Visibility = 'Collapsed' }
}
function Render-Agenda($Agenda) {
    $ui.Agenda.Children.Clear()
    if ($null -eq $Agenda) { return }
    if (@($Agenda.events).Count -eq 0) {
        $empty = New-Object Windows.Controls.TextBlock
        $empty.Text = '이 기간에 등록된 일정이 없습니다.'; $empty.Foreground = '#8593AA'; $empty.Margin = '0,8,0,0'
        [void]$ui.Agenda.Children.Add($empty)
    }
    $previousDate = ''
    foreach ($event in (Get-DaylightPage $Agenda.events 'agenda')) {
        $displayDate = $event.date
        # Ongoing multi-day events are grouped under today, while retaining the original time range.
        if ($displayDate -lt $Agenda.rangeStart) { $displayDate = $Agenda.rangeStart }
        if ($displayDate -ne $previousDate) {
            $heading = New-Object Windows.Controls.TextBlock
            $label = [DateTime]::ParseExact($displayDate, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture).ToString('M월 d일 ddd', [Globalization.CultureInfo]::GetCultureInfo('ko-KR'))
            if ($displayDate -eq $Agenda.rangeStart) { $label = '오늘 · ' + $label }
            $heading.Text = $label; $heading.Foreground = '#A3E8D2'; $heading.FontSize = 12; $heading.Margin = '0,12,0,8'
            [void]$ui.Agenda.Children.Add($heading); $previousDate = $displayDate
        }
        $card = New-Object Windows.Controls.Border; $card.Background = 'Transparent'; $card.CornerRadius = 0; $card.Padding = 0; $card.Margin = '0,0,0,8'
        $content = New-Object Windows.Controls.StackPanel
        $time = New-Object Windows.Controls.TextBlock; $time.Text = $event.time; $time.Foreground = '#A3E8D2'; $time.FontSize = 11
        $title = New-Object Windows.Controls.TextBlock; $title.Text = $event.title; $title.Foreground = '#F1F5FA'; $title.TextWrapping = 'Wrap'; $title.MaxHeight=42; $title.TextTrimming='CharacterEllipsis'; $title.ToolTip=$event.title; $title.Margin = '0,4,0,0'
        [void]$content.Children.Add($time); [void]$content.Children.Add($title)
        if ($event.location) { $location = New-Object Windows.Controls.TextBlock; $location.Text = $event.location; $location.Foreground = '#8593AA'; $location.FontSize = 10; $location.TextWrapping = 'Wrap'; $location.MaxHeight=28; $location.TextTrimming='CharacterEllipsis'; $location.ToolTip=$event.location; $location.Margin = '0,4,0,0'; [void]$content.Children.Add($location) }
        $card.Child = $content; [void]$ui.Agenda.Children.Add($card)
    }
}
function Start-CalendarWork([string]$Action = 'Refresh') {
    if ($script:calendarJob) { return }
    $script:lastCalendarAttempt = [DateTime]::UtcNow
    $ui.CalendarStatus.Text = '일정을 가져오는 중…'
    if ($Action -eq 'Connect') { $ui.CalendarStatus.Text = '브라우저에서 구글 로그인을 완료하세요. 최대 3분간 기다립니다.' }
    Set-CalendarControls $true
    try {
        $script:calendarJob = Start-DaylightJob -ScriptBlock {
            param($root, $action, $calendarId)
            . (Join-Path $root 'Calendar.ps1')
            Invoke-CalendarWork $action $root $calendarId
        } -ArgumentList $PSScriptRoot, $Action, $script:state.calendarId
    } catch { $ui.CalendarStatus.Text = '일정 조회를 시작하지 못했습니다. 앱을 다시 실행하세요.'; Set-CalendarControls $false }
}
function Stop-CalendarWork {
    if ($script:calendarJob) { Stop-DaylightJob -Job $script:calendarJob; Remove-DaylightJob -Job $script:calendarJob -Force; $script:calendarJob = $null }
    Set-CalendarControls $false
}
function Receive-CalendarWork {
    if (-not $script:calendarJob -or $script:calendarJob.State -in @('Running','NotStarted')) { return }
    $result = $null
    try { $result = @(Receive-DaylightJob -Job $script:calendarJob -ErrorAction Stop) | Select-Object -Last 1 }
    catch { $result = [pscustomobject]@{ ok = $false; message = '일정 조회를 완료하지 못했습니다. 새로고침으로 다시 시도하세요.' } }
    Remove-DaylightJob -Job $script:calendarJob -Force; $script:calendarJob = $null
    Set-CalendarControls $false
    if ($result -and $result.ok) {
        $script:calendarReconnectRequired=$false; Set-CalendarControls $false
        if ($script:state.calendarId -ne $result.calendarId) { $script:state.calendarId = [string]$result.calendarId; Save-State }
        $script:calendarUpdatingChoice = $true
        try {
            $ui.CalendarChoice.Items.Clear()
            foreach ($calendar in $result.calendars) {
                $entry = New-Object Windows.Controls.ComboBoxItem; $entry.Content = [string]$calendar.name; $entry.Tag = [string]$calendar.id
                [void]$ui.CalendarChoice.Items.Add($entry)
                if ($calendar.id -eq $script:state.calendarId -or ($script:state.calendarId -eq 'primary' -and $calendar.primary)) { $ui.CalendarChoice.SelectedItem = $entry }
            }
        } finally { $script:calendarUpdatingChoice = $false }
        $script:lastAgenda = $result.agenda
        Render-Agenda $result.agenda
        $stamp = [DateTimeOffset]::Parse($result.agenda.fetchedAt).ToString('HH:mm')
        $ui.CalendarStatus.Text = "한국 시간 · 오늘부터 7일 · $stamp 갱신 · 5분마다 자동 갱신"
        if ($result.agenda.truncated) { $ui.CalendarStatus.Text += ' · 앞선 100개 표시' }
    } else {
        $script:calendarReconnectRequired=[bool]$result.requiresReconnect; Set-CalendarControls $false
        $message = '조회하지 못했습니다. 새로고침으로 다시 시도하세요.'
        if ($result -and $result.message) { $message = $result.message }
        if ($script:lastAgenda) { $stamp = [DateTimeOffset]::Parse($script:lastAgenda.fetchedAt).ToString('M/d HH:mm'); $message += " · 아래는 $stamp 조회 내용입니다." }
        $ui.CalendarStatus.Text = $message
    }
}
$ui.CalendarHelp.Add_Click({ Start-Process (Join-Path $PSScriptRoot 'GoogleSetup.html') })
function Select-CalendarClient {
    $picker = New-Object Microsoft.Win32.OpenFileDialog
    $picker.Title = '구글에서 내려받은 데스크톱 앱 연결 설정(JSON)을 선택하세요'
    $picker.Filter = 'Google OAuth 설정 (*.json)|*.json'
    if (-not $picker.ShowDialog($window)) { $ui.CalendarStatus.Text = '설정 파일이 없다면 「처음 연결하는 방법」을 참고하세요.'; return $false }
    Import-CalendarClient $picker.FileName $PSScriptRoot
    return $true
}
$ui.CalendarSettings.Add_Click({
    try { if (Select-CalendarClient) { $ui.CalendarStatus.Text = '설정 파일을 변경했습니다. 구글 연결을 눌러 로그인하세요.' } }
    catch { $ui.CalendarStatus.Text = '데스크톱 앱용 구글 JSON 파일인지 확인하세요.' }
})
$ui.CalendarConnect.Add_Click({
    try {
        if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'calendar-client.dat'))) {
            if (-not (Select-CalendarClient)) { return }
        }
        Start-CalendarWork 'Connect'
    } catch { $ui.CalendarStatus.Text = '연결 설정 파일을 읽지 못했습니다. 데스크톱 앱용 구글 JSON 파일인지 확인하세요.' }
})
$ui.CalendarRefresh.Add_Click({ Start-CalendarWork })
$ui.CalendarCancel.Add_Click({ Stop-CalendarWork; $ui.CalendarStatus.Text = '작업을 취소했습니다.' })
$ui.CalendarDisconnect.Add_Click({
    try {
        foreach ($name in @('calendar-token.dat','calendar-token.dat.bak','calendar-token.dat.tmp')) {
            $path = Join-Path $PSScriptRoot $name
            if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
        }
        $script:calendarUpdatingChoice = $true; $ui.CalendarChoice.Items.Clear(); $script:calendarUpdatingChoice = $false
        $script:lastAgenda = $null; Render-Agenda $null
        $script:state.calendarId = 'primary'; Save-State; Set-CalendarControls $false
        $ui.CalendarStatus.Text = '이 기기의 연결을 해제했습니다. 구글 계정의 접근 권한은 연결 안내에서 해제할 수 있습니다.'
    } catch { $script:calendarUpdatingChoice = $false; $ui.CalendarStatus.Text = '연결 정보를 삭제하지 못했습니다. 폴더 권한을 확인하세요.' }
})
$ui.CalendarChoice.Add_SelectionChanged({
    if ($script:calendarUpdatingChoice -or -not $ui.CalendarChoice.SelectedItem) { return }
    $newId = [string]$ui.CalendarChoice.SelectedItem.Tag
    if ($newId -ne $script:state.calendarId) {
        $script:state.calendarId = $newId; Save-State
        $script:lastAgenda = $null; Render-Agenda $null
        Start-CalendarWork
    }
})
. (Join-Path $PSScriptRoot 'Memo.ps1')
$ui.AddTask.Add_Click({ Add-Task })
$ui.TaskInput.Add_KeyDown({ if ($_.Key -eq 'Return') { Add-Task; $_.Handled = $true } })
$ui.ClearDone.Add_Click({ $script:state.tasks = @($script:state.tasks | Where-Object { -not $_.done }); Save-State; Render-Tasks })
$ui.Mode.Add_Click({ $script:state.compact = -not $script:state.compact; Apply-Mode; Save-State })
$ui.Pin.Add_Click({Toggle-WidgetPin $ui.StyleTarget.SelectedItem.Tag})
$ui.Close.Add_Click({ $window.Close() })
# Widget drag handlers are registered once in Layout.ps1.

$ui.Calendar.Add_Click({ Start-Process 'https://calendar.google.com/' })
$ui.Notion.Add_Click({ Start-Process 'https://www.notion.so/' })
. (Join-Path $PSScriptRoot 'NotionUI.ps1')
. (Join-Path $PSScriptRoot 'Layout.ps1')
. (Join-Path $PSScriptRoot 'Styles.ps1')
. (Join-Path $PSScriptRoot 'Appearance.ps1')
. (Join-Path $PSScriptRoot 'GPTUI.ps1')
. (Join-Path $PSScriptRoot 'Features.ps1')
. (Join-Path $PSScriptRoot 'Desktop.ps1')
. (Join-Path $PSScriptRoot 'Extras.ps1')
. (Join-Path $PSScriptRoot 'YouTube.ps1')
. (Join-Path $PSScriptRoot 'Alignment.ps1')
$script:timer = New-Object Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds(1); $timer.Add_Tick({
    Invoke-DaylightSafe 'clock' {Update-Clock}
    Invoke-DaylightSafe 'calendar' {Receive-CalendarWork}
    Invoke-DaylightSafe 'notion' {Receive-NotionWork}
    Invoke-DaylightSafe 'weather' {Receive-WeatherWork}
    Invoke-DaylightSafe 'gemini' {Receive-GPTWork}
    Invoke-DaylightSafe 'appearance' {Update-DaylightSummaries; Set-DaylightTextTone}
    Invoke-DaylightSafe 'features' {Update-Features}
    Invoke-DaylightSafe 'desktop' {Update-DesktopWidgets}
    Invoke-DaylightSafe 'extras' {Update-ExtraWidgets}
    Invoke-DaylightSafe 'youtube' {Update-YouTubePlayer}
    if (-not $SelfTest -and -not $script:calendarJob -and (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'calendar-token.dat')) -and ([DateTime]::UtcNow - $script:lastCalendarAttempt).TotalMinutes -ge 5) { Start-CalendarWork }
    if (-not $SelfTest -and -not $script:notionJob -and (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'notion-settings.dat')) -and ([DateTime]::UtcNow - $script:lastNotionAttempt).TotalMinutes -ge 5) { Start-NotionWork }
    if (-not $SelfTest -and $script:state.weatherVisible -and -not $script:weatherJob -and ([DateTime]::UtcNow - $script:lastWeatherAttempt).TotalMinutes -ge 15) { Start-WeatherWork }
})
$window.Add_Closing({
 if(-not $script:quitRequested) { $_.Cancel=$true; Set-WidgetVisible 'main' $false; return }
 $script:closingAll=$true; Stop-YouTubeWork; Stop-ExtraWork; Stop-Focus; if($script:briefingWindow) {$briefingWindow.Close()}; $timer.Stop(); $noteTimer.Stop(); Stop-CalendarWork; Stop-NotionWork; Stop-WeatherWork; Stop-GPTWork; Sync-CurrentNote; Save-State
 $settingsWindow.Close(); foreach($key in $widgets.Keys) { if($key -ne 'main') {$widgets[$key].Close()} }
 Close-Appearance; Clear-WallpaperCache
 if($script:tray) { $script:tray.Visible=$false; $script:tray.Dispose() }
 if($script:daylightTrayIcon) {$script:daylightTrayIcon.Dispose()}
})
Render-Tasks; Apply-Mode; Update-Clock; Set-CalendarControls $false; Set-NotionControls $false
if ($script:loadWarning) { $ui.Status.Text = $script:loadWarning }
if ($SelfTest) {
    . (Join-Path $PSScriptRoot 'VerifyUI.ps1')
    exit 0
}
$timer.Start()
$script:application=New-Object Windows.Application
$application.ShutdownMode=[Windows.ShutdownMode]::OnExplicitShutdown
$application.Add_DispatcherUnhandledException({
    Write-DaylightDiagnostic 'ui' $_.Exception
    if($_.Exception -isnot [OutOfMemoryException] -and $_.Exception -isnot [AccessViolationException]) {$_.Handled=$true}
})
$window.Add_Closed({$application.Shutdown()})
[void]$application.Run($window)
