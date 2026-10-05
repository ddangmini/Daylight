# Focus, layout profiles and local briefings. No AI or external writes.
$script:focusSession=$null
$script:briefingWindow=$null
$script:featureStarted=[DateTime]::UtcNow
$script:featureUIChanging=$false
$script:lastBriefingRefresh=[DateTime]::MinValue
$script:eventNotified=@{}
$script:featureMarkup=@'
<StackPanel xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
 <TextBlock Text="집중과 오늘" FontSize="18" FontWeight="SemiBold" Margin="0,0,0,12"/>
 <TextBlock Text="한 가지 일에 집중하기" Foreground="#A3E8D2"/>
 <ComboBox x:Name="FocusTask" Margin="0,8,0,8" ToolTip="집중할 할 일 선택"/>
 <WrapPanel><TextBox x:Name="FocusMinutes" Text="25" Width="60"/><TextBlock Text="분" VerticalAlignment="Center" Margin="8,0,12,0"/><Button x:Name="FocusStart" Content="집중 시작"/><Button x:Name="FocusPause" Content="일시정지"/><Button x:Name="FocusStop" Content="마치기"/></WrapPanel>
 <TextBlock x:Name="FocusStatus" Text="집중 중에는 시계만 남깁니다. 종료하면 배치가 돌아옵니다." TextWrapping="Wrap" FontSize="11" Margin="0,8,0,14"/>
 <Button x:Name="BriefingOpen" Content="오늘의 브리핑 열기" HorizontalAlignment="Left"/>
 <CheckBox x:Name="BriefingAlerts" Content="매일 브리핑 알림" Margin="0,12,0,8"/>
 <WrapPanel><TextBox x:Name="BriefingTime" Text="09:00" Width="80"/><Button x:Name="SaveAlertTime" Content="알림 시각 저장" Margin="8,0,0,0"/></WrapPanel>
 <CheckBox x:Name="EventAlerts" Content="일정 시작 10분 전 알림" Margin="0,12,0,8"/>
 <TextBlock x:Name="AlertStatus" Text="앱 실행 중 알림 · Windows 알림 설정에 따라 표시됩니다" FontSize="11" TextWrapping="Wrap" Margin="0,0,0,20"/>
 <TextBlock Text="나의 배치" FontSize="18" FontWeight="SemiBold" Margin="0,0,0,10"/>
 <TextBox x:Name="ProfileName" Text="나의 공부 공간" ToolTip="저장할 배치 이름"/>
 <WrapPanel Margin="0,8,0,8"><Button x:Name="ProfileSave" Content="현재 배치 저장"/><Button x:Name="ProfileApply" Content="선택한 배치 불러오기"/><Button x:Name="ProfileDelete" Content="삭제"/></WrapPanel>
 <ComboBox x:Name="Profiles"/><TextBlock x:Name="ProfileStatus" FontSize="11" TextWrapping="Wrap" Margin="0,8,0,22"/>
 <TextBlock Text="추천 데스크톱" FontSize="18" FontWeight="SemiBold" Margin="0,0,0,10"/>
 <ComboBox x:Name="DesktopStyle"><ComboBoxItem Content="에어 · 투명 타이포그래피" Tag="air"/><ComboBoxItem Content="모노 · 흑백" Tag="mono"/><ComboBoxItem Content="소프트 · 둥근 카드" Tag="soft"/><ComboBoxItem Content="보타닉 · 자연색" Tag="botanic"/><ComboBoxItem Content="오로라 · 은은한 그라데이션" Tag="aurora"/><ComboBoxItem Content="네온 · 야간" Tag="neon"/></ComboBox>
 <WrapPanel Margin="0,8,0,0"><Button x:Name="DesktopApply" Content="추천 디자인·배치 적용"/><Button x:Name="DesignGallery" Content="프리셋 미리보기 ↗"/></WrapPanel>
 <TextBlock Text="추천 배치는 Gemini 창을 숨기며, 현재 배치를 먼저 자동 저장합니다." FontSize="11" TextWrapping="Wrap" Margin="0,8,0,26"/>
</StackPanel>
'@
[xml]$featureXML=$featureMarkup
$script:featurePanel=[Windows.Markup.XamlReader]::Load((New-Object Xml.XmlNodeReader $featureXML))
$settingsWindow.Content.Content.Children.Insert(2,$featurePanel)
$script:featureUI=@{}
foreach($name in @('FocusTask','FocusMinutes','FocusStart','FocusPause','FocusStop','FocusStatus','BriefingOpen','BriefingAlerts','BriefingTime','SaveAlertTime','EventAlerts','AlertStatus','ProfileName','ProfileSave','ProfileApply','ProfileDelete','Profiles','ProfileStatus','DesktopStyle','DesktopApply','DesignGallery')) {$featureUI[$name]=$featurePanel.FindName($name)}
if(-not $state.layoutProfiles) {$state.layoutProfiles=@()}
if(-not $state.alertSettings) {$state.alertSettings=@{briefing=$true;time='09:00';events=$true;lastDay=''}}
if($state.alertSettings -isnot [hashtable]) {$copy=@{}; foreach($p in $state.alertSettings.PSObject.Properties) {$copy[$p.Name]=$p.Value}; $state.alertSettings=$copy}
if(-not $state.notifications) {$state.notifications=@()}
foreach($key in @($state.alertSettings.eventKeys)) {if($key) {$script:eventNotified[[string]$key]=$true}}
$featureUI.BriefingAlerts.IsChecked=[bool]$state.alertSettings.briefing; $featureUI.EventAlerts.IsChecked=[bool]$state.alertSettings.events; $featureUI.BriefingTime.Text=[string]$state.alertSettings.time
$featureUI.DesktopStyle.SelectedIndex=0
function Get-FeatureNow {return [TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([DateTimeOffset]::UtcNow,'Korea Standard Time').DateTime}
function Get-LayoutSnapshot {
    Capture-DaylightGeometry
    $snapshot=@{geometry=$state.geometry;appearance=$state.appearance;widgetPins=$state.widgetPins;widgetDesktop=$state.widgetDesktop;widgetLocks=$state.widgetLocks;autoLayout=$state.autoLayout;lockRatio=$state.lockRatio}
    foreach($key in $widgets.Keys) {$snapshot[$key+'Visible']=[bool]$state[$key+'Visible']}
    return ($snapshot | ConvertTo-Json -Depth 12 -Compress)
}
function Restore-LayoutSnapshot([string]$Json) {
    $snap=$Json | ConvertFrom-Json
    foreach($mapName in @('widgetDesktop','widgetLocks')) {if($snap.$mapName) {foreach($key in $widgets.Keys) {$state[$mapName][$key]=[bool]$snap.$mapName.$key}}}
    $state.geometry=$snap.geometry; $state.autoLayout=[bool]$snap.autoLayout; $state.lockRatio=[bool]$snap.lockRatio
    foreach($key in $widgets.Keys) {
        if($snap.appearance.$key) {$style=@{}; foreach($p in $snap.appearance.$key.PSObject.Properties) {$style[$p.Name]=$p.Value}; $state.appearance[$key]=$style}
        if($null -ne $snap.widgetPins.$key) {$state.widgetPins[$key]=[bool]$snap.widgetPins.$key}
        $state[$key+'Visible']=[bool]$snap.($key+'Visible'); $ui['Show'+(Get-WidgetToggleName $key)].IsChecked=$state[$key+'Visible']
        if(-not $SelfTest -and -not $script:closingAll) {if($state[$key+'Visible']) {$widgets[$key].Show()} else {$widgets[$key].Hide()}}
    }
    Restore-DaylightGeometry; $ui.AutoLayout.IsChecked=$state.autoLayout; $ui.LockRatio.IsChecked=$state.lockRatio
    Set-DaylightMode; Set-DaylightTextTone; Save-State
}
function Refresh-ProfileChoice {
    $featureUI.Profiles.Items.Clear()
    foreach($profile in @($state.layoutProfiles)) {$item=New-Object Windows.Controls.ComboBoxItem; $item.Content=$profile.name; $item.Tag=$profile; [void]$featureUI.Profiles.Items.Add($item)}
    if($featureUI.Profiles.Items.Count) {$featureUI.Profiles.SelectedIndex=$featureUI.Profiles.Items.Count-1}
}
function Save-LayoutProfile([string]$Name) {
    if($script:focusSession) {$featureUI.ProfileStatus.Text='집중을 마친 뒤 배치를 저장하세요.'; return}
    $Name=$Name.Trim(); if(-not $Name) {$featureUI.ProfileStatus.Text='배치 이름을 입력하세요.'; return}
    $Name=$Name.Substring(0,[Math]::Min(40,$Name.Length))
    $state.layoutProfiles=@($state.layoutProfiles | Where-Object {$_.name -ne $Name})+@(@{id=[guid]::NewGuid().ToString('N');name=$Name;snapshot=(Get-LayoutSnapshot)})
    if($state.layoutProfiles.Count -gt 20) {$state.layoutProfiles=@($state.layoutProfiles | Select-Object -Last 20)}
    Refresh-ProfileChoice; Save-State; $featureUI.ProfileStatus.Text='저장됨 · '+$Name
}
function Refresh-FocusTasks {
    $selected=''; if($featureUI.FocusTask.SelectedItem) {$selected=[string]$featureUI.FocusTask.SelectedItem.Tag}
    $featureUI.FocusTask.Items.Clear(); $item=New-Object Windows.Controls.ComboBoxItem; $item.Content='자유 집중'; $item.Tag=''; [void]$featureUI.FocusTask.Items.Add($item)
    foreach($task in @($state.tasks)+@($script:lastNotionAgenda.tasks)) {if($task -and -not $task.done) {$item=New-Object Windows.Controls.ComboBoxItem; $item.Content=[string]$task.text; $item.Tag=[string]$task.id; [void]$featureUI.FocusTask.Items.Add($item)}}
    $featureUI.FocusTask.SelectedIndex=0
    foreach($item in $featureUI.FocusTask.Items) {if($item.Tag -eq $selected) {$featureUI.FocusTask.SelectedItem=$item; break}}
}
function Start-Focus([int]$Minutes=25,[string]$Title='자유 집중') {
    if($script:focusSession) {return}
    if($Minutes -lt 1 -or $Minutes -gt 180) {$featureUI.FocusStatus.Text='1~180분 사이로 입력하세요.'; return}
    $script:focusSession=@{snapshot=(Get-LayoutSnapshot);remaining=$Minutes*60;duration=$Minutes*60;end=[DateTime]::UtcNow.AddMinutes($Minutes);paused=$false;title=$Title}
    foreach($key in $widgets.Keys) {if($key -ne 'clock' -and -not $SelfTest) {$widgets[$key].Hide()}}
    if(-not $SelfTest) {$clockWindow.Show()}; Update-Focus
}
function Pause-Focus {
    if(-not $script:focusSession) {return}
    if($script:focusSession.paused) {$script:focusSession.end=[DateTime]::UtcNow.AddSeconds($script:focusSession.remaining); $script:focusSession.paused=$false}
    else {$script:focusSession.remaining=[Math]::Max(0,[Math]::Ceiling(($script:focusSession.end-[DateTime]::UtcNow).TotalSeconds)); $script:focusSession.paused=$true}
    Update-Focus
}
function Show-DaylightNotification([string]$Title,[string]$Text) {
    $state.notifications=@($state.notifications)+@(@{time=(Get-FeatureNow).ToString('yyyy-MM-dd HH:mm');title=$Title;text=$Text})
    $state.notifications=@($state.notifications | Select-Object -Last 30); Save-State
    if(-not $SelfTest -and $script:tray) {$tray.ShowBalloonTip(7000,$Title,$Text.Substring(0,[Math]::Min(240,$Text.Length)),[Windows.Forms.ToolTipIcon]::Info)}
}
function Stop-Focus([bool]$Completed=$false) {
    if(-not $script:focusSession) {return}
    $snapshot=$script:focusSession.snapshot; $title=$script:focusSession.title; $script:focusSession=$null
    Restore-LayoutSnapshot $snapshot; Update-Clock
    $featureUI.FocusStatus.Text='배치를 복원했습니다.'; $featureUI.FocusPause.Content='일시정지'
    if($Completed) {Show-DaylightNotification '집중 완료 · 잠깐 쉬어가세요' $title}
}
function Update-Focus {
    if(-not $script:focusSession) {return}
    if(-not $script:focusSession.paused) {$script:focusSession.remaining=[Math]::Max(0,[Math]::Ceiling(($script:focusSession.end-[DateTime]::UtcNow).TotalSeconds))}
    if($script:focusSession.remaining -le 0) {Stop-Focus $true; return}
    $seconds=[int]$script:focusSession.remaining; $ui.Clock.Text=('{0:00}:{1:00}' -f [Math]::Floor($seconds/60),($seconds%60))
    $title=[string]$script:focusSession.title; if($title.Length -gt 22) {$title=$title.Substring(0,22)+'…'}
    $ui.Date.Text='집중 · '+$title
    $featureUI.FocusStatus.Text=$ui.Clock.Text+' 남음 · '+$script:focusSession.title
    $featureUI.FocusPause.Content='일시정지'; if($script:focusSession.paused) {$featureUI.FocusPause.Content='계속하기'; $ui.Date.Text='일시정지 · '+$title}
}
function Get-LocalBriefing([DateTime]$Now=(Get-FeatureNow)) {
    $today=$Now.ToString('yyyy-MM-dd'); $lines=@($Now.ToString('M월 d일 dddd',[Globalization.CultureInfo]::GetCultureInfo('ko-KR')),'','오늘의 일정')
    $events=@($script:lastAgenda.events | Where-Object {$_.date -eq $today})
    if(-not $script:lastAgenda) {$lines+='캘린더 조회 결과가 없습니다. 설정에서 연결 상태를 확인하세요.'}
    elseif(-not $events.Count) {$lines+='오늘 등록된 일정이 없습니다.'}
    foreach($event in $events) {$lines+=([string]$event.time+'  '+$event.title)}
    $local=@($state.tasks | Where-Object {-not $_.done}); $notion=@($script:lastNotionAgenda.tasks | Where-Object {-not $_.done})
    $lines+=@('',('남은 할 일 · '+($local.Count+$notion.Count)+'개'))
    foreach($task in @($local)+@($notion | Sort-Object due)) {$line='• '+$task.text; if($task.due) {$line+=' · '+$task.due.Substring(0,[Math]::Min(10,$task.due.Length)); if($task.due.Substring(0,[Math]::Min(10,$task.due.Length)) -le $today) {$line+=' · 마감 확인'}}; $lines+=$line}
    if(-not $local.Count -and -not $notion.Count) {$lines+='남은 할 일이 없습니다.'}
    if(-not $script:lastNotionAgenda) {$lines+=@('','노션 조회 결과 없음 · 연결 상태를 설정에서 확인하세요.')}
    $lines+=@('','조회한 목록 기준 · 연결되지 않거나 조회에 실패한 항목은 포함되지 않을 수 있습니다.')
    return ($lines -join "`r`n")
}
function Show-Briefing {
    if($script:briefingWindow) {$briefingWindow.Close()}
    $script:briefingWindow=New-DaylightWindow @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="Daylight · 오늘" Width="460" Height="610" MinWidth="340" MinHeight="300" Background="#192235" Foreground="#E9EDF5" FontFamily="Malgun Gothic" WindowStartupLocation="CenterScreen"><Window.Resources>__THEME__</Window.Resources><Grid Margin="24"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition/><RowDefinition Height="Auto"/></Grid.RowDefinitions><DockPanel><TextBlock Text="오늘의 브리핑" FontSize="24" FontWeight="SemiBold"/><Button x:Name="RefreshBriefing" Content="새로 보기" HorizontalAlignment="Right"/></DockPanel><TextBox x:Name="BriefingText" Grid.Row="1" Margin="0,18,0,12" Background="Transparent" BorderThickness="0" IsReadOnly="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto"/><TextBlock Grid.Row="2" Text="일정·할 일에서 직접 정리 · AI 호출 없음" FontSize="11"/></Grid></Window>
'@
    $briefingWindow.MaxHeight=[Math]::Max(300,[Windows.SystemParameters]::WorkArea.Height-24)
    $briefingWindow.FindName('BriefingText').Text=Get-LocalBriefing
    $briefingWindow.FindName('RefreshBriefing').Add_Click({$briefingWindow.FindName('BriefingText').Text=Get-LocalBriefing})
    if(-not $SelfTest) {$briefingWindow.Show(); [void]$briefingWindow.Activate()}
}
function Get-EventStart($Event) {
    if($Event.allDay -or -not $Event.date) {return $null}
    $match=[regex]::Match([string]$Event.time,'(?:^|\s)(\d{2}:\d{2})')
    if(-not $match.Success) {return $null}
    try {return [DateTime]::ParseExact(($Event.date+' '+$match.Groups[1].Value),'yyyy-MM-dd HH:mm',[Globalization.CultureInfo]::InvariantCulture)} catch {return $null}
}
function Update-FeatureNotifications([DateTime]$Now=(Get-FeatureNow)) {
    if($SelfTest -or -not $script:tray -or $script:focusSession) {return}
    if(([DateTime]::UtcNow-$script:featureStarted).TotalSeconds -lt 30 -or $script:calendarJob -or $script:notionJob) {return}
    $day=$Now.ToString('yyyy-MM-dd'); $target=[DateTime]::MinValue
    if($state.alertSettings.briefing -and [DateTime]::TryParseExact(($day+' '+$state.alertSettings.time),'yyyy-MM-dd HH:mm',[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::None,[ref]$target) -and $Now -ge $target -and $state.alertSettings.lastDay -ne $day) {
        $state.alertSettings.lastDay=$day
        $brief=Get-LocalBriefing $Now; Show-DaylightNotification '오늘의 브리핑' ($brief -replace "`r`n",' · ')
    }
    if($state.alertSettings.events) {foreach($event in @($script:lastAgenda.events)) {
        $start=Get-EventStart $event; if(-not $start) {continue}
        $minutes=($start-$Now).TotalMinutes; $key=$event.id+'|'+$start.ToString('o')
        if($minutes -gt 0 -and $minutes -le 10 -and -not $script:eventNotified.ContainsKey($key)) {$script:eventNotified[$key]=$true; $state.alertSettings.eventKeys=@(@($state.alertSettings.eventKeys)+@($key) | Select-Object -Last 100); Show-DaylightNotification '곧 시작하는 일정' ($event.time+' · '+$event.title)}
    }}
}
function Update-Features {
    Update-Focus; Update-FeatureNotifications
    if(([DateTime]::UtcNow-$script:lastBriefingRefresh).TotalSeconds -ge 15) {Refresh-FocusTasks; $script:lastBriefingRefresh=[DateTime]::UtcNow}
}
function Apply-DesktopStyle([string]$Name) {
    if($script:focusSession) {$featureUI.ProfileStatus.Text='집중을 마친 뒤 배치를 바꾸세요.'; return}
    Save-LayoutProfile '추천 적용 전 배치'
    $themes=@{air='air';mono='mono';soft='cloud';botanic='linen';aurora='aurora';neon='neon'}
    if(-not $themes.ContainsKey($Name)) {return}
    $area=[Windows.SystemParameters]::WorkArea; $small=$area.Width -lt 1250
    $left=$area.Left+24; $right=$area.Right-350; $center=$area.Left+[Math]::Max(24,($area.Width-360)/2)
    $geometry=@{main=@($left,$area.Top+24,330,390);tasks=@($right,$area.Top+24,330,390);memo=@($right,$area.Top+430,330,300);clock=@($center,$area.Top+28,360,230);weather=@($center,$area.Top+280,340,270);chat=@($left,$area.Top+430,440,470)}
    if($small) {$geometry.memo=@($left,$area.Top+430,330,300)}
    Capture-DaylightGeometry
    foreach($key in $geometry.Keys) {
        $state.geometry[$key]=@{left=$geometry[$key][0];top=$geometry[$key][1];width=$geometry[$key][2];height=$geometry[$key][3]}
        $state[$key+'Visible']=($key -ne 'chat'); $ui['Show'+(Get-WidgetToggleName $key)].IsChecked=$state[$key+'Visible']; $state.widgetPins[$key]=$false
        $preset=$script:stylePresets[$themes[$Name]]; $state.appearance[$key]=@{theme=$themes[$Name];opacity=$preset.opacity;tone=$preset.tone;accent=$preset.accent;radius=$preset.radius;textScale=1.0;font='Malgun Gothic'}
        if($key -eq 'clock' -and $preset.clockFont) {$state.appearance[$key].font=$preset.clockFont}
        if($key -eq 'clock' -and $Name -in @('air','mono')) {$state.appearance[$key].opacity=0.02; $state.appearance[$key].tone='auto'}
    }
    Restore-DaylightGeometry; Set-DaylightMode; Set-DaylightTextTone
    if(-not $SelfTest) {foreach($key in $widgets.Keys) {if($state[$key+'Visible']) {$widgets[$key].Show()} else {$widgets[$key].Hide()}}}
    Save-State; $featureUI.ProfileStatus.Text='추천 디자인 적용 · 이전 배치를 목록에서 복원할 수 있습니다.'
}
$featureUI.FocusStart.Add_Click({$minutes=0; if(-not [int]::TryParse($featureUI.FocusMinutes.Text,[ref]$minutes)) {$featureUI.FocusStatus.Text='집중 시간을 숫자로 입력하세요.'; return}; Start-Focus $minutes ([string]$featureUI.FocusTask.SelectedItem.Content)})
$featureUI.FocusPause.Add_Click({Pause-Focus}); $featureUI.FocusStop.Add_Click({Stop-Focus})
$featureUI.BriefingOpen.Add_Click({Show-Briefing})
$featureUI.BriefingAlerts.Add_Click({$state.alertSettings.briefing=[bool]$this.IsChecked; Save-State})
$featureUI.EventAlerts.Add_Click({$state.alertSettings.events=[bool]$this.IsChecked; Save-State})
$featureUI.SaveAlertTime.Add_Click({$parsed=[DateTime]::MinValue; if(-not [DateTime]::TryParseExact($featureUI.BriefingTime.Text.Trim(),'HH:mm',[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::None,[ref]$parsed)) {$featureUI.AlertStatus.Text='24시간 형식으로 입력하세요. 예: 09:00'; return}; $state.alertSettings.time=$parsed.ToString('HH:mm'); Save-State; $featureUI.AlertStatus.Text='브리핑 알림 · '+$state.alertSettings.time+' · 한국 시간'})
$featureUI.ProfileSave.Add_Click({Save-LayoutProfile $featureUI.ProfileName.Text})
$featureUI.ProfileApply.Add_Click({if($script:focusSession) {$featureUI.ProfileStatus.Text='집중을 마친 뒤 배치를 불러오세요.'; return}; if($featureUI.Profiles.SelectedItem) {Restore-LayoutSnapshot $featureUI.Profiles.SelectedItem.Tag.snapshot; $featureUI.ProfileStatus.Text='배치를 불러왔습니다.'}})
$featureUI.ProfileDelete.Add_Click({if($featureUI.Profiles.SelectedItem) {$id=$featureUI.Profiles.SelectedItem.Tag.id; $state.layoutProfiles=@($state.layoutProfiles | Where-Object {$_.id -ne $id}); Refresh-ProfileChoice; Save-State}})
$featureUI.DesktopApply.Add_Click({Apply-DesktopStyle $featureUI.DesktopStyle.SelectedItem.Tag})
$featureUI.DesignGallery.Add_Click({Start-Process (Join-Path $PSScriptRoot 'DesignGallery.html')})
$focusButton=New-Object Windows.Controls.Button; $focusButton.Content='▶'; $focusButton.ToolTip='집중 설정'; $focusButton.Padding='7,3'; $focusButton.Add_Click({Show-DaylightSettings; $featurePanel.BringIntoView()}); $clockWindow.FindName('WidgetTools').Children.Insert(0,$focusButton)
$briefButton=New-Object Windows.Controls.Button; $briefButton.Content='☷'; $briefButton.ToolTip='오늘의 브리핑'; $briefButton.Padding='7,3'; $briefButton.Add_Click({Show-Briefing}); $window.FindName('WidgetTools').Children.Insert(0,$briefButton)
function Initialize-FeatureTray {
    if(-not $script:tray -or $script:featureTrayReady) {return}
    $tray.Add_BalloonTipClicked({Show-Briefing})
    $item=New-Object Windows.Forms.ToolStripMenuItem '오늘의 브리핑'; $item.Add_Click({Show-Briefing})
    $tray.ContextMenuStrip.Items.Insert(0,$item); $script:featureTrayReady=$true
}
$window.Add_Loaded({Initialize-FeatureTray})
Refresh-FocusTasks; Refresh-ProfileChoice
