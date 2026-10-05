# Meaningful state transitions; no real notifications or external API calls.
$initial=Get-LayoutSnapshot
Save-LayoutProfile '검증용 배치'; $profile=@($state.layoutProfiles | Where-Object {$_.name -eq '검증용 배치'})[0]
Assert-UI ($profile.snapshot -and $featureUI.Profiles.Items.Count -ge 1) 'Layout profile saved'
$state.widgetPins.clock=$false; $clockWindow.Width=500; Set-StylePreset 'clock' 'neon'
Restore-LayoutSnapshot $profile.snapshot
$expected=$profile.snapshot | ConvertFrom-Json
Assert-UI ($clockWindow.Width -eq $expected.geometry.clock.width -and $state.appearance.clock.theme -eq $expected.appearance.clock.theme -and $state.widgetPins.clock -eq $expected.widgetPins.clock) 'Profile restores appearance/size/pin'
Start-Focus 1 '테스트 집중'; Assert-UI ($script:focusSession -and $ui.Clock.Text -match '^00:|^01:') 'Focus countdown'
Pause-Focus; $remaining=$script:focusSession.remaining; $script:focusSession.end=[DateTime]::UtcNow.AddSeconds(-1); Update-Focus
Assert-UI ($script:focusSession.paused -and $script:focusSession.remaining -eq $remaining) 'Paused focus must not complete'
Pause-Focus; Assert-UI (-not $script:focusSession.paused -and $script:focusSession.end -gt [DateTime]::UtcNow) 'Focus resume'
$script:focusSession.end=[DateTime]::UtcNow.AddSeconds(-1); Update-Focus
Assert-UI (-not $script:focusSession -and @($state.notifications).Count -ge 1 -and $clockWindow.Width -eq $expected.geometry.clock.width) 'Focus completion restores layout and records notification'
Start-Focus 0 '無'; Assert-UI (-not $script:focusSession) 'Focus invalid duration'
$savedAgenda=$script:lastAgenda; $savedNotion=$script:lastNotionAgenda; $savedTasks=$state.tasks
$script:lastAgenda=@{events=@(@{id='today';date='2026-10-06';time='09:00–10:00';title='오늘 회의';allDay=$false},@{date='2026-10-07';time='09:00';title='내일 일정'})}
$script:lastNotionAgenda=@{tasks=@(@{text='마감 과제';done=$false;due='2026-10-06'},@{text='이미 완료';done=$true;due='2026-10-05'})}
$state.tasks=@(@{text='로컬 할 일';done=$false},@{text='완료된 로컬';done=$true})
$brief=Get-LocalBriefing ([DateTime]'2026-10-06 08:00')
Assert-UI ($brief.Contains('오늘 회의') -and $brief.Contains('마감 확인') -and $brief.Contains('로컬 할 일') -and -not $brief.Contains('내일 일정') -and -not $brief.Contains('이미 완료')) 'Briefing today/date/completion filtering'
Assert-UI ($brief.Contains('남은 할 일 · 2개')) 'Briefing count formatting'
$start=Get-EventStart $script:lastAgenda.events[0]; Assert-UI ($start -eq [DateTime]'2026-10-06 09:00') 'Event reminder time parsing'
Assert-UI (-not (Get-EventStart @{date='2026-10-06';time='종일';allDay=$true})) 'No timed notification for all-day'
$oldTray=$script:tray; $oldAlerts=$state.alertSettings.Clone(); $oldSelfTest=$SelfTest
$script:tray=New-Object PSObject; $script:balloonCalls=0
$tray | Add-Member -MemberType ScriptMethod -Name ShowBalloonTip -Value {param($a,$b,$c,$d) $script:balloonCalls++}
try {
    $SelfTest=$false; $script:featureStarted=[DateTime]::UtcNow.AddMinutes(-2)
    $state.alertSettings.time='08:00'; $state.alertSettings.lastDay=''; $state.alertSettings.briefing=$true; $state.alertSettings.events=$true
    Update-FeatureNotifications ([DateTime]'2026-10-06 08:55'); Update-FeatureNotifications ([DateTime]'2026-10-06 08:56')
    Assert-UI ($script:balloonCalls -eq 2 -and $state.alertSettings.lastDay -eq '2026-10-06' -and $state.alertSettings.eventKeys.Count -eq 1) 'Daily/event notifications deduplicate and persist'
    $script:eventNotified=@{}; foreach($key in $state.alertSettings.eventKeys) {$script:eventNotified[$key]=$true}
    Update-FeatureNotifications ([DateTime]'2026-10-06 08:57'); Assert-UI ($script:balloonCalls -eq 2) 'Notification dedup survives reload'
    $state.alertSettings.briefing=$false; $state.alertSettings.events=$false; Update-FeatureNotifications ([DateTime]'2026-10-07 09:00'); Assert-UI ($script:balloonCalls -eq 2) 'Disabled notifications stay silent'
} finally {$SelfTest=$oldSelfTest; $script:tray=$oldTray; $state.alertSettings=$oldAlerts}
Show-Briefing; Assert-UI ($briefingWindow.FindName('BriefingText').IsReadOnly -and -not $briefingWindow.ShowInTaskbar) 'Briefing window / taskbar'
$briefingWindow.Close(); $script:briefingWindow=$null
$oldTray=$script:tray; $script:tray=New-Object Windows.Forms.NotifyIcon; $tray.ContextMenuStrip=New-Object Windows.Forms.ContextMenuStrip
try {Initialize-FeatureTray; Initialize-FeatureTray; Assert-UI ($tray.ContextMenuStrip.Items.Count -eq 1) 'Tray briefing initialized once'; $tray.ContextMenuStrip.Items[0].PerformClick(); Assert-UI ($briefingWindow -and -not $briefingWindow.ShowInTaskbar) 'Tray briefing click'} finally {$tray.Dispose(); $script:tray=$oldTray; $script:featureTrayReady=$false; if($briefingWindow) {$briefingWindow.Close(); $script:briefingWindow=$null}}
$script:lastAgenda=$savedAgenda; $script:lastNotionAgenda=$savedNotion; $state.tasks=$savedTasks
Apply-DesktopStyle 'aurora'; Assert-UI ($state.appearance.main.theme -eq 'aurora' -and -not $state.chatVisible) 'Desktop style applied'
Assert-UI (@($state.layoutProfiles | Where-Object {$_.name -eq '추천 적용 전 배치'}).Count -eq 1) 'Desktop preset creates restore point'
Restore-LayoutSnapshot $initial; Save-State
$persisted=Get-Content -LiteralPath $DataPath -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-UI ($persisted.layoutProfiles.Count -ge 1 -and $persisted.alertSettings.time -eq '09:00') 'New settings persistence'
'PASS: focus pause/resume/completion, layout/style/pin restoration, profiles persistence, local briefing filtering, timed vs all-day reminder parsing, preset restore point'
