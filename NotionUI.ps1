$script:notionJob = $null
$script:lastNotionAttempt = [DateTime]::MinValue
$script:lastNotionAgenda = $null
function Set-NotionControls([bool]$Busy) {
    $connected = Test-Path -LiteralPath (Join-Path $PSScriptRoot 'notion-settings.dat')
    $ui.NotionConnect.IsEnabled = -not $Busy
    $ui.NotionRefresh.IsEnabled = -not $Busy -and $connected
    $ui.NotionDisconnect.IsEnabled = -not $Busy -and $connected
    foreach ($row in $ui.NotionTasks.Children) { if ($row -is [Windows.Controls.CheckBox]) { $row.IsEnabled = -not $Busy } }
}
function Render-NotionTasks($Agenda) {
    $ui.NotionTasks.Children.Clear()
    if ($null -eq $Agenda) { return }
    if (@($Agenda.tasks).Count -eq 0) {
        $empty = New-Object Windows.Controls.TextBlock; $empty.Text = '연결한 표에 할 일이 없습니다.'; $empty.Foreground = '#8593AA'; $empty.Margin = '0,8,0,0'; [void]$ui.NotionTasks.Children.Add($empty)
    }
    foreach ($task in (Get-DaylightPage $Agenda.tasks 'notion')) {
        $check = New-Object Windows.Controls.CheckBox; $check.Tag = $task.id; $check.IsChecked = [bool]$task.done; $check.Margin = '0,8,0,6'; $check.ToolTip = '체크하면 노션 완료 상태도 변경됩니다'
        $content = New-Object Windows.Controls.StackPanel
        $text = New-Object Windows.Controls.TextBlock; $text.Text = $task.text; $text.TextWrapping = 'Wrap'; $text.MaxWidth = [Math]::Max(120,$tasksWindow.Width-100); $text.MaxHeight=42; $text.TextTrimming='CharacterEllipsis'; $text.ToolTip=$task.text
        if ($task.done) { $text.Opacity = 0.5; $text.TextDecorations = [Windows.TextDecorations]::Strikethrough }
        [void]$content.Children.Add($text)
        if ($task.status) { $status = New-Object Windows.Controls.TextBlock; $status.Text = $task.status; $status.Foreground = '#A3E8D2'; $status.FontSize = 10; $status.Margin = '0,3,0,0'; [void]$content.Children.Add($status) }
        if ($task.due) { $due = New-Object Windows.Controls.TextBlock; $due.Text = '기한 · ' + $task.due; $due.Foreground = '#8593AA'; $due.FontSize = 10; $due.Margin = '0,3,0,0'; [void]$content.Children.Add($due) }
        $check.Content = $content
        $check.Add_Click({
            $id = [string]$this.Tag; $done = [bool]$this.IsChecked
            # Keep the last confirmed state visible until the remote write is confirmed.
            $this.IsChecked = -not $done
            Start-NotionWork 'Complete' $id $done
        })
        [void]$ui.NotionTasks.Children.Add($check)
    }
}
function Start-NotionWork([string]$Action = 'Refresh', [string]$PageId = '', [bool]$Done = $false) {
    if ($script:notionJob) { return }
    $script:lastNotionAttempt = [DateTime]::UtcNow
    $ui.NotionStatus.Text = '노션 할 일을 가져오는 중…'
    if ($Action -eq 'Complete') { $ui.NotionStatus.Text = '노션에 완료 상태를 반영하는 중…' }
    Set-NotionControls $true
    try {
        $script:notionJob = Start-DaylightJob -ScriptBlock {
            param($root, $action, $pageId, $done)
            . (Join-Path $root 'Calendar.ps1'); . (Join-Path $root 'Notion.ps1')
            Invoke-NotionWork $root $action $pageId $done
        } -ArgumentList $PSScriptRoot, $Action, $PageId, $Done
    } catch { $ui.NotionStatus.Text = '노션 조회를 시작하지 못했습니다. 앱을 다시 실행하세요.'; Set-NotionControls $false }
}
function Stop-NotionWork {
    if ($script:notionJob) { Stop-DaylightJob -Job $script:notionJob; Remove-DaylightJob -Job $script:notionJob -Force; $script:notionJob = $null }
}
function Receive-NotionWork {
    if (-not $script:notionJob -or $script:notionJob.State -in @('Running','NotStarted')) { return }
    $result = $null
    try { $result = @(Receive-DaylightJob -Job $script:notionJob -ErrorAction Stop) | Select-Object -Last 1 }
    catch { $result = [pscustomobject]@{ ok = $false; message = '노션 조회를 완료하지 못했습니다. 새로고침하세요.' } }
    Remove-DaylightJob -Job $script:notionJob -Force; $script:notionJob = $null
    if ($result -and $result.ok) {
        $script:lastNotionAgenda = $result.agenda; Render-NotionTasks $result.agenda
        $done = @($result.agenda.tasks | Where-Object { $_.done }).Count
        $zone = [TimeZoneInfo]::FindSystemTimeZoneById('Korea Standard Time')
        $stamp = [TimeZoneInfo]::ConvertTime([DateTimeOffset]::Parse($result.agenda.fetchedAt), $zone).ToString('HH:mm')
        $ui.NotionStatus.Text = "완료 $done / $(@($result.agenda.tasks).Count) · $stamp 갱신 · 5분마다 자동 갱신"
        if ($result.agenda.truncated) { $ui.NotionStatus.Text += ' · 최근 변경된 200개 표시' }
    } else {
        $ui.NotionStatus.Text = '노션 조회에 실패했습니다. 새로고침하세요.'
        if ($result -and $result.message) { $ui.NotionStatus.Text = $result.message }
        if ($result -and $result.writeSucceeded) { $script:lastNotionAgenda = $null; Render-NotionTasks $null }
        elseif ($script:lastNotionAgenda) { $ui.NotionStatus.Text += ' · 아래는 이전 조회 내용입니다.' }
    }
    Set-NotionControls $false
}
function New-NotionSettingsDialog {
    $markup = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="노션 연결 설정" Width="450" Height="650" ResizeMode="NoResize" Background="#192235" Foreground="#E9EDF5" FontFamily="Malgun Gothic" WindowStartupLocation="CenterOwner">
 <Window.Resources>__DAYLIGHT_THEME__</Window.Resources>
 <ScrollViewer VerticalScrollBarVisibility="Auto"><StackPanel Margin="26">
  <TextBlock Text="노션 할 일 연결" FontSize="20" FontWeight="Bold"/>
  <TextBlock Text="노션 표의 상태 이름을 그대로 입력해주세요. 토큰은 이 기기에 암호화해 저장됩니다." TextWrapping="Wrap" Foreground="#99A7BE" Margin="0,10,0,18"/>
  <TextBlock Text="노션 내부 연결 토큰" Margin="0,0,0,6"/><PasswordBox x:Name="Token"/>
  <TextBlock Text="할 일 데이터베이스 링크" Margin="0,14,0,6"/><TextBox x:Name="Database"/>
  <TextBlock Text="완료를 관리하는 속성 이름" Margin="0,14,0,6"/><TextBox x:Name="Property" Text="상태"/>
  <Grid Margin="0,14,0,0"><Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="12"/><ColumnDefinition/></Grid.ColumnDefinitions><StackPanel><TextBlock Text="완료 상태 이름" Margin="0,0,0,6"/><TextBox x:Name="Done" Text="완료"/></StackPanel><StackPanel Grid.Column="2"><TextBlock Text="체크 해제 시 상태" Margin="0,0,0,6"/><TextBox x:Name="Open" Text="할 일"/></StackPanel></Grid>
  <TextBlock Text="체크박스 속성을 쓰면 위 상태 이름은 사용하지 않습니다." Foreground="#8593AA" FontSize="10" Margin="0,8,0,0"/>
  <TextBlock Text="데이터 소스 ID (표가 여러 개일 때만)" Margin="0,14,0,6"/><TextBox x:Name="Source"/>
  <TextBlock x:Name="Validation" Foreground="#F2B8A8" TextWrapping="Wrap" Margin="0,12,0,0"/>
  <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,16,0,0"><Button x:Name="Cancel" Content="취소" IsCancel="True"/><Button x:Name="Save" Content="저장하고 연결" Background="#A3E8D2" Foreground="#152C28" IsDefault="True"/></StackPanel>
 </StackPanel></ScrollViewer>
</Window>
'@
    [xml]$xml = $markup.Replace('__DAYLIGHT_THEME__', [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Theme.xaml')))
    $reader = New-Object Xml.XmlNodeReader $xml
    $dialog = [Windows.Markup.XamlReader]::Load($reader)
    Register-DaylightToolWindow $dialog; $dialog.Icon=$script:daylightIcon
    if ($settingsWindow.IsLoaded) { $dialog.Owner = $settingsWindow } elseif ($window.IsLoaded) { $dialog.Owner = $window }
    $dialog.FindName('Save').Add_Click({
        $owner = [Windows.Window]::GetWindow($this)
        if (-not $owner.FindName('Token').Password.Trim() -or -not $owner.FindName('Database').Text.Trim() -or -not $owner.FindName('Property').Text.Trim()) {
            $owner.FindName('Validation').Text = '토큰, 데이터베이스 링크, 완료 속성 이름을 입력하세요.'; return
        }
        $owner.DialogResult = $true
    })
    return $dialog
}
$ui.NotionHelp.Add_Click({ Start-Process (Join-Path $PSScriptRoot 'NotionSetup.html') })
$ui.NotionConnect.Add_Click({
    try {
        $dialog = New-NotionSettingsDialog
        $old = Read-CalendarVault (Join-Path $PSScriptRoot 'notion-settings.dat')
        if ($old) {
            $dialog.FindName('Token').Password = $old.token; $dialog.FindName('Database').Text = $old.databaseId
            $dialog.FindName('Property').Text = $old.completionProperty; $dialog.FindName('Done').Text = $old.doneStatus
            $dialog.FindName('Open').Text = $old.openStatus; $dialog.FindName('Source').Text = [string]$old.sourceId
        }
        if (-not $dialog.ShowDialog()) { return }
        $settings = [pscustomobject]@{
            token = $dialog.FindName('Token').Password.Trim()
            databaseId = Get-NotionObjectId $dialog.FindName('Database').Text
            sourceId = ''; completionProperty = $dialog.FindName('Property').Text.Trim()
            doneStatus = $dialog.FindName('Done').Text.Trim(); openStatus = $dialog.FindName('Open').Text.Trim()
        }
        if ($dialog.FindName('Source').Text.Trim()) { $settings.sourceId = Get-NotionObjectId $dialog.FindName('Source').Text }
        Write-CalendarVault (Join-Path $PSScriptRoot 'notion-settings.dat') $settings
        $script:lastNotionAgenda = $null; Render-NotionTasks $null
        Start-NotionWork
    } catch { $ui.NotionStatus.Text = '노션 연결 설정을 저장하지 못했습니다. 링크 형식과 폴더 권한을 확인하세요.' }
})
$ui.NotionRefresh.Add_Click({ Start-NotionWork })
$ui.NotionDisconnect.Add_Click({
    try {
        foreach ($name in @('notion-settings.dat','notion-settings.dat.bak','notion-settings.dat.tmp')) { $path = Join-Path $PSScriptRoot $name; if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force } }
        $script:lastNotionAgenda = $null; Render-NotionTasks $null; Set-NotionControls $false
        $ui.NotionStatus.Text = '이 기기의 노션 연결 정보를 삭제했습니다.'
    } catch { $ui.NotionStatus.Text = '노션 연결 정보를 삭제하지 못했습니다. 폴더 권한을 확인하세요.' }
})
