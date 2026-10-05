$extrasBackup=$state.extras|ConvertTo-Json -Depth 12
$agendaBackup=$script:lastAgenda; $notionBackup=$script:lastNotionAgenda
try {
    Assert-UI ($extraCatalog.Count -eq 9 -and $widgets.Count -eq 15) 'Nine extra widgets registered'
    foreach($key in $extraCatalog.Keys) {Assert-UI ($ui['Show'+(Get-WidgetToggleName $key)] -and $widgets[$key].FindName('WidgetResize')) 'Extra visibility and resize controls'}
    foreach($key in $extraCatalog.Keys) {$helper=New-Object Windows.Interop.WindowInteropHelper $widgets[$key]; $handle=$helper.EnsureHandle(); $style=[DaylightWindowHost]::ExtendedStyle($handle); Assert-UI (($style -band 0x80) -ne 0 -and ($style -band 0x40000) -eq 0 -and -not $widgets[$key].ShowInTaskbar) 'Extra native task switcher flags'}
    $extras.ddays=@(); $extras.habits=@(); $extras.progress=@(); $extras.launchers=@(); $script:lastAgenda=$null; $script:lastNotionAgenda=$null; $extras.ddaySelected=''
    $extraUI.DdayNameInput.Text='시험'; $extraUI.DdayDateInput.SelectedDate=(Get-ExtraToday).AddDays(12); Click-UI $extraUI.DdayAdd
    Assert-UI ($extras.ddays.Count -eq 1 -and $ui.DdayNumber.Text -eq 'D−12') 'Manual countdown'
    $script:lastNotionAgenda=@{tasks=@(@{id='due';text='과제';done=$false;due=(Get-ExtraToday).AddDays(1).ToString('yyyy-MM-dd')},@{id='done';text='완료';done=$true;due=(Get-ExtraToday).ToString('yyyy-MM-dd')})}
    $script:lastAgenda=@{events=@(@{id='meeting';title='약속';date=(Get-ExtraToday).AddDays(2).ToString('yyyy-MM-dd')})}
    $candidates=@(Get-DdayCandidates)
    Assert-UI ($candidates.Count -eq 3 -and -not @($candidates|Where-Object {$_.id -eq 'notion:done'}).Count) 'Countdown source merge'
    $extras.ddaySelected='notion:due'; Render-Dday; Assert-UI ($ui.DdayNumber.Text -eq 'D−1') 'Countdown source selection'
    $extraUI.HabitNameInput.Text='독서'; Click-UI $extraUI.HabitAdd
    $check=$ui.HabitRows.Children[0].Children[0]; $check.IsChecked=$true; Click-UI $check
    Assert-UI ((Get-ExtraToday).ToString('yyyy-MM-dd') -in $extras.habits[0].dates) 'Habit completion persistence'
    $dates=@((Get-ExtraToday).AddDays(-1).ToString('yyyy-MM-dd'),(Get-ExtraToday).AddDays(-2).ToString('yyyy-MM-dd'))
    Assert-UI ((Get-HabitStreak $dates) -eq 2) 'Habit streak before checking today'
    Assert-UI ((Get-HabitStreak @($dates+(Get-ExtraToday).ToString('yyyy-MM-dd'))) -eq 3) 'Habit streak including today'
    $extraUI.ProgressNameInput.Text='강의'; $extraUI.ProgressCurrentInput.Text='2'; $extraUI.ProgressTotalInput.Text='8'; Click-UI $extraUI.ProgressAdd
    Assert-UI ($extras.progress.Count -eq 1 -and (Get-ProgressPercent 2 8) -eq 25) 'Progress normalization'
    Click-UI $ui.ProgressRows.Children[0].Children[0].Children[0]
    Assert-UI ($extras.progress[0].current -eq 3) 'Progress increment'
    $extraUI.ProgressTotalInput.Text='0'; Click-UI $extraUI.ProgressAdd
    Assert-UI ($extras.progress[0].total -eq 8) 'Invalid progress total accepted'
    Assert-UI ((Get-ProgressPercent 900 10) -eq 100 -and (Get-ProgressPercent 1 0) -eq 0) 'Progress bounds'
    Assert-UI (Test-LaunchTarget 'https://example.com') 'Web launcher validation'
    Assert-UI (-not (Test-LaunchTarget 'javascript:alert(1)') -and -not (Test-LaunchTarget 'powershell -Command anything')) 'Launcher command boundary'
    $extraUI.LaunchNameInput.Text='학습'; $extraUI.LaunchPathInput.Text='https://example.com'; Click-UI $extraUI.LaunchAdd
    Assert-UI ($extras.launchers.Count -eq 1 -and $ui.LaunchItems.Children.Count -eq 1) 'Launcher persistence/render'
    $extraUI.QuoteTextInput.Text='나의 문장'; $extraUI.QuoteAuthorInput.Text='나'; Click-UI $extraUI.QuoteAdd
    Assert-UI (@($extras.quotes|Where-Object {$_.text -eq '나의 문장'}).Count -eq 1) 'Quote add'
    $extras.quotes=@(@{text='첫 문장';author='A'},@{text='두 번째 문장';author='B'}); $extras.quoteOffset=0; Render-Quote; $before=$ui.QuoteText.Text; Click-UI $ui.QuoteNext
    Assert-UI ($ui.QuoteText.Text -ne $before) 'Quote rotation'
    $fixture=Join-Path (Split-Path $DataPath) ('photo-fixture-'+[guid]::NewGuid()+'.png')
    $bitmap=New-Object Drawing.Bitmap 120,80; try {$g=[Drawing.Graphics]::FromImage($bitmap); try {$g.Clear([Drawing.Color]::SteelBlue); $bitmap.Save($fixture,[Drawing.Imaging.ImageFormat]::Png)} finally {$g.Dispose()}} finally {$bitmap.Dispose()}
    Import-PhotoFiles @($fixture,'Z:\missing-photo.png'); Set-Photo
    Assert-UI ($ui.PhotoImage.Source -and $ui.PhotoPlaceholder.Visibility -eq 'Collapsed') 'Photo decode and missing-file handling'
    $stream=[IO.File]::Open($fixture,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None); $stream.Dispose()
    $extraUI.PhotoMinutesInput.Text='0'; Click-UI $extraUI.PhotoSave
    Assert-UI ($extras.photoMinutes -eq 0) 'Photo manual mode'
    $extraJobs.system=Start-DaylightJob {@{ok=$true;cpu=40;memory=50;totalGB=16;usedGB=8;battery=80;ac=1;diskGB=100;disk='C:\'}}
    [void](Wait-DaylightJob $extraJobs.system); Receive-ExtraWork system
    Assert-UI ($ui.SystemCpu.Text -eq 'CPU 40%' -and $ui.MemoryBar.Value -eq 50 -and $ui.CpuLine.Points.Count -ge 1) 'System render'
    $cover=[IO.File]::ReadAllBytes($fixture)
    $extraJobs.media=Start-DaylightJob {param($cover); @{ok=$true;active=$true;title='모의 곡';artist='모의 아티스트';playing=$true;cover=$cover;accepted=$true}} -ArgumentList (,$cover)
    [void](Wait-DaylightJob $extraJobs.media); Receive-ExtraWork media
    Assert-UI ($ui.MediaTitle.Text -eq '모의 곡' -and $ui.MediaArt.Source -and $ui.MediaToggle.Content -eq 'Ⅱ') 'Media text/art/playback render'
    $extraJobs.media=Start-DaylightJob {@{ok=$true;active=$false;title='음악을 재생해보세요';artist='';playing=$false;cover=$null}}
    [void](Wait-DaylightJob $extraJobs.media); Receive-ExtraWork media
    Assert-UI (-not $ui.MediaToggle.IsEnabled -and -not $ui.MediaArt.Source) 'Media session removal clears stale art'
    $state.ddayVisible=$true; $state.widgetDesktop.dday=$true; $state.widgetLocks.dday=$true; Update-DesktopWidgets
    $snapshot=Get-LayoutSnapshot; $state.ddayVisible=$false; $state.widgetDesktop.dday=$false; $state.widgetLocks.dday=$false; Restore-LayoutSnapshot $snapshot
    Assert-UI ($state.ddayVisible -and $state.widgetDesktop.dday -and $state.widgetLocks.dday) 'Extra layout/desktop/lock restoration'
    Save-State; $saved=[IO.File]::ReadAllText($DataPath)|ConvertFrom-Json
    Assert-UI ($saved.extras.habits.Count -eq 1 -and $saved.extras.progress.Count -eq 1 -and $saved.ddayVisible) 'Extra data persistence'
    $state.ddayVisible=$false; $state.widgetDesktop.dday=$false; $state.widgetLocks.dday=$false
    $photoImage=$ui.PhotoImage.Source; $ui.PhotoImage.Source=$null; Remove-Item -LiteralPath $fixture
    'PASS: eight extra widgets, source countdowns, habit history/streaks, progress editing, launcher validation, quote rotation, photo unlock/manual mode, media cover/state, system chart, profile restoration and persistence'
} finally {
    $copy=$extrasBackup|ConvertFrom-Json; foreach($property in $copy.PSObject.Properties) {$extras[$property.Name]=$property.Value}
    $script:lastAgenda=$agendaBackup; $script:lastNotionAgenda=$notionBackup
    Stop-ExtraWork; Commit-ExtraEdit
}

. (Join-Path $PSScriptRoot 'VerifyYouTube.ps1')
