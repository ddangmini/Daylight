function Assert-UI($Value,[string]$Message) {if(-not $Value) {throw $Message}}
function Click-UI($Button) {$Button.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Primitives.ButtonBase]::ClickEvent)))}
$savedAppearance=$state.appearance
try {
 $state.appearance=@{}; $values=@(0,0.07,0.22,0.37,0.5,0.58,0.74,0.86,1); $expectedOpacity=@{}; $index=0
 foreach($key in $widgets.Keys) {$expectedOpacity[$key]=[double]$values[$index%$values.Count]; $index++; $state.appearance[$key]=$savedAppearance[$key].Clone(); $state.appearance[$key].opacity=$expectedOpacity[$key]}
 Save-State
 $state.appearance=(Get-Content -LiteralPath $DataPath -Raw -Encoding UTF8|ConvertFrom-Json).appearance
 Initialize-WidgetAppearance; Set-DaylightTextTone
 foreach($key in $widgets.Keys) {
  Assert-UI ([Math]::Abs($state.appearance[$key].opacity-$expectedOpacity[$key]) -lt 0.000001) 'Restart preserves each fractional opacity'
  $brush=$widgets[$key].FindName('Surface').Background; $alphas=@()
  if($brush -is [Windows.Media.SolidColorBrush]) {$alphas=@($brush.Color.A)} else {$alphas=@($brush.GradientStops|ForEach-Object {$_.Color.A})}
  foreach($alpha in $alphas) {Assert-UI ($alpha -eq [Math]::Max(1,[Math]::Round($expectedOpacity[$key]*255))) 'Restored opacity reaches solid and gradient backgrounds'}
 }
 Initialize-WidgetAppearance
 foreach($key in $widgets.Keys) {Assert-UI ($state.appearance[$key].opacity -eq $expectedOpacity[$key]) 'Hashtable reinitialization preserves opacity'}
 'PASS: fractional opacity survives saved JSON reload and background rendering for all widgets'
} finally {$state.appearance=$savedAppearance; Set-DaylightTextTone; Save-State}
if($state.note -eq '기존 버전의 메모') {Assert-UI ($state.notes[0].body -eq $state.note) 'Legacy note migration'}
Assert-UI ([Windows.Window]::GetWindow($ui.CalendarConnect) -eq $settingsWindow) 'Calendar settings separation'
Assert-UI ([Windows.Window]::GetWindow($ui.Tasks) -eq $tasksWindow -and [Windows.Window]::GetWindow($ui.Note) -eq $memoWindow) 'Task memo independence'
Assert-UI ([Windows.Window]::GetWindow($ui.Agenda) -eq $window -and [Windows.Window]::GetWindow($ui.ChatInput) -eq $chatWindow) 'Agenda chat independence'
foreach($surface in $widgets.Values) {Assert-UI ($surface.AllowsTransparency -and $surface.FindName('WidgetTools').Opacity -eq 0) 'Transparent windows / hidden tools'}
$originalCount=$state.tasks.Count
$ui.TaskInput.Text='한글 저장 검증'; Add-Task
Assert-UI ($state.tasks.Count -eq $originalCount+1) 'Task add'
$script:pages.local=0; Render-Tasks
$check=$ui.Tasks.Children[$ui.Tasks.Children.Count-1].Children[1]
$check.IsChecked=$true; Click-UI $check
Assert-UI (@($state.tasks | Where-Object {$_.done}).Count -ge 1) 'Task completion'
$ui.Note.Text='저장 직전에 전환해도 보존'; $ui.NoteTitle.Text='첫 메모'; $first=$state.selectedNote
Click-UI $ui.NoteNew
Assert-UI (($state.notes | Where-Object {$_.id -eq $first}).body -eq '저장 직전에 전환해도 보존') 'Memo switch lost debounce text'
$ui.Note.Text='두 번째 메모'; Sync-CurrentNote; $second=$state.selectedNote; Select-DaylightNote $first
Assert-UI ($ui.Note.Text -eq '저장 직전에 전환해도 보존' -and ($state.notes | Where-Object {$_.id -eq $second}).body -eq '두 번째 메모') 'Multiple notes lost'
Save-State
$saved=Get-Content -LiteralPath $DataPath -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-UI ($saved.notes.Count -ge 2 -and $saved.note -eq $ui.Note.Text -and $saved.geometry.memo.width -gt 0) 'Memo / geometry persistence'
$state.appearance.main.opacity=0.7; $state.appearance.weather.opacity=0.3; $state.appearance.main.tone='auto'
Set-WidgetAppearance 'main' 0.9; Set-WidgetAppearance 'weather' 0.1
Assert-UI ([Math]::Abs($window.FindName('Surface').Background.Color.A-179) -le 1 -and [Math]::Abs($weatherWindow.FindName('Surface').Background.Color.A-76) -le 1) 'Per-widget background opacity'
Assert-UI ($ui.CalendarSummary.Foreground.Color.R -eq 25) 'Automatic dark text on light wallpaper'
Set-WidgetAppearance 'main' 0.1
Assert-UI ($ui.CalendarSummary.Foreground.Color.R -eq 246) 'Automatic white text on dark wallpaper'
$state.appearance.main.opacity=0; Set-WidgetAppearance 'main' 0.1
Assert-UI ($window.FindName('Surface').Background.Color.A -eq 1 -and $ui.CalendarSummary.Opacity -eq 1) 'Fully transparent surface must remain draggable with opaque text'
$black=New-Object Drawing.Bitmap 40,40; $white=New-Object Drawing.Bitmap 40,40
$g=[Drawing.Graphics]::FromImage($white); $g.Clear([Drawing.Color]::White); $g.Dispose()
try {Assert-UI ((Get-WallpaperBrightness $window $black '2') -lt 0.01 -and (Get-WallpaperBrightness $window $white '2') -gt 0.99) 'Wallpaper luminance sampler'} finally {$black.Dispose();$white.Dispose()}
$dialog=New-AppearanceDialog; Assert-UI ($dialog.FindName('OpacitySlider').Maximum -eq 100 -and $dialog.FindName('ToneChoice').Items.Count -eq 3) 'Appearance controls'
$state.tasks=@(1..18 | ForEach-Object {[pscustomobject]@{id=[string]$_;text="테스트 할 일 $_";done=$false}})
$script:pages.local=0; Update-DaylightLayout
$capacity=Get-PageCapacity 'local'; Assert-UI ($ui.Tasks.Children.Count -eq $capacity -and $state.tasks.Count -eq 18 -and $ui.TasksNext.IsEnabled) 'Task paging loses records'
$script:pages.local=999; Update-DaylightLayout
Assert-UI (-not $ui.TasksNext.IsEnabled -and $ui.TasksPrev.IsEnabled) 'Task last page clamp'
$script:pages.local=0
Resize-DaylightWindow $clockWindow 400 250 1.6
Assert-UI ([Math]::Abs($clockWindow.Width/$clockWindow.Height-1.6) -lt 0.01) 'Resize aspect ratio'
Resize-DaylightWindow $tasksWindow 1 1
Assert-UI ($tasksWindow.Width -ge 260 -and $tasksWindow.Height -ge 350) 'Minimum constraints'
$events=@(1..20 | ForEach-Object {[pscustomobject]@{date='2026-10-05';time='14:00–15:00';title="일정 $_";location=''}})
$script:lastAgenda=[pscustomobject]@{rangeStart='2026-10-05';events=$events}; Render-Agenda $script:lastAgenda
Assert-UI ($ui.Agenda.Children.Count -le (Get-PageCapacity 'agenda')+1 -and $ui.AgendaNext.IsEnabled) 'Agenda pagination'
Set-WeatherIcon 95; Assert-UI ($ui.WeatherIcon.Text -eq 'ϟ') 'Weather thunder icon'; Set-WeatherIcon 75; Assert-UI ($ui.WeatherIcon.Text -eq '❄') 'Weather snow icon'
$request=New-GPTRequest 'gemini-3.5-flash-lite' @([pscustomobject]@{role='user';content='안녕'})
Assert-UI ($request.contents[0].parts[0].text -eq '안녕' -and $request.generationConfig.maxOutputTokens -eq 2048) 'Gemini request'; Assert-UI ($request.generationConfig.thinkingConfig.thinkingLevel -eq 'minimal') 'New model thinking config'
$answer=Convert-GPTResponse ([pscustomobject]@{candidates=@([pscustomobject]@{finishReason='STOP';content=@{parts=@(@{text='한글 답변'})}})})
Assert-UI ($answer.text -eq '한글 답변') 'GPT output parsing'
$script:pendingPrompt='질문'; $script:gptJob=Start-DaylightJob { [pscustomobject]@{ok=$true;text='모의 답변';incomplete=$false} }
[void](Wait-DaylightJob $script:gptJob -Timeout 15); Receive-GPTWork
Assert-UI ($script:chatMessages.Count -eq 2 -and $ui.ChatHistory.Text.Contains('모의 답변') -and $ui.ChatSend.IsEnabled) 'GPT async receive'
$script:pendingPrompt='실패 후 복원'; $script:gptJob=Start-DaylightJob {[pscustomobject]@{ok=$false;message='테스트 오류'}}
[void](Wait-DaylightJob $script:gptJob -Timeout 15); Receive-GPTWork
Assert-UI ($ui.ChatInput.Text -eq '실패 후 복원' -and $script:chatMessages.Count -eq 2) 'GPT failure retry restoration'
foreach($surface in @($widgets.Values)+@($settingsWindow)) {Assert-UI (-not $surface.ShowInTaskbar -and $surface.Icon) 'Taskbar hidden / custom icon'}
$notionDialog=New-NotionSettingsDialog; Assert-UI (-not $notionDialog.ShowInTaskbar -and $notionDialog.Icon) 'Notion dialog taskbar / icon'; $notionDialog.Close()
$oldClock=$state.widgetPins.clock; $oldTasks=$state.widgetPins.tasks; Toggle-WidgetPin 'clock'
Assert-UI ($clockWindow.Topmost -ne $oldClock -and $tasksWindow.Topmost -eq $oldTasks -and $clockWindow.FindName('WidgetPin').Content -eq $(if($clockWindow.Topmost){'◆'}else{'◇'})) 'Independent pin toggle'
Save-State; $saved=Get-Content -LiteralPath $DataPath -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-UI ($saved.widgetPins.clock -eq $clockWindow.Topmost) 'Per-widget pin persistence'
foreach($name in $script:stylePresets.Keys) {Set-StylePreset 'memo' $name; Assert-UI ($state.appearance.memo.theme -eq $name -and $memoWindow.FindName('Surface').CornerRadius.TopLeft -eq $script:stylePresets[$name].radius) 'Theme application'}
$state.appearance.memo.textScale=1.1; Set-WidgetAppearance 'memo'; $fontSize=$ui.Note.FontSize; Set-WidgetAppearance 'memo'; Assert-UI ($ui.Note.FontSize -eq $fontSize) 'Font scaling accumulation'
Set-StylePreset 'memo' 'adaptive'
Set-StylePreset 'main' 'paper'; $state.appearance.main.tone='auto'; Set-WidgetAppearance 'main' 0.05
Assert-UI ($ui.CalendarSummary.Foreground.Color.R -eq 25) 'Auto contrast accounts for opaque preset background'
Set-StylePreset 'main' 'adaptive'
$script:pendingPrompt='한도 오류 질문'; $script:gptJob=Start-DaylightJob {[pscustomobject]@{ok=$false;message='한도 도달';quotaExceeded=$true}}
[void](Wait-DaylightJob $script:gptJob -Timeout 15); Receive-GPTWork
Assert-UI (-not $ui.ChatSend.IsEnabled -and $ui.ChatInput.Text -eq '한도 오류 질문' -and -not $script:gptJob) 'Quota stops without auto retry'
$script:geminiCooldown=[DateTime]::UtcNow.AddSeconds(-1); Receive-GPTWork; Assert-UI ($ui.ChatSend.IsEnabled -and -not $script:gptJob) 'Cooldown permits manual retry only'
Show-Appearance 'memo' -NoShow
Assert-UI ($appearanceWindow.FindName('PresetChoice').Items.Count -eq 13 -and -not $appearanceWindow.ShowInTaskbar) 'Preset dialog controls'
$appearanceWindow.FindName('PresetChoice').SelectedIndex=1
Assert-UI ($state.appearance.memo.theme -eq 'paper' -and $appearanceWindow.FindName('ToneChoice').SelectedItem.Tag -eq 'dark') 'Preset dialog change updates dependent controls'
$appearanceWindow.FindName('TextScaleSlider').Value=115
Assert-UI ($state.appearance.memo.textScale -eq 1.15) 'Text size control'
Click-UI $appearanceWindow.FindName('ApplyAllStyle')
Assert-UI ($state.appearance.clock.theme -eq 'paper') 'Apply style to all'
$state.appearance.clock.opacity=0.25; Assert-UI ($state.appearance.memo.opacity -eq 0.92) 'Style copies must remain independent'
$scroll=$appearanceWindow.FindName('AppearanceScroll')
Assert-UI ($scroll -and $scroll.VerticalScrollBarVisibility -eq 'Auto' -and $appearanceWindow.Height -le $appearanceWindow.MaxHeight) 'Appearance dialog scrolling / work area'
$appearanceWindow.Content.Measure((New-Object Windows.Size 360,320)); $appearanceWindow.Content.Arrange((New-Object Windows.Rect 0,0,360,320)); $appearanceWindow.Content.UpdateLayout()
$scroll.ScrollToEnd(); $appearanceWindow.Content.UpdateLayout()
Assert-UI ($scroll.ScrollableHeight -gt 0 -and $scroll.VerticalOffset -eq $scroll.ScrollableHeight) 'Appearance bottom controls reachable at small height'
Close-Appearance
foreach($key in $widgets.Keys) {Set-StylePreset $key 'adaptive'}
. (Join-Path $PSScriptRoot 'VerifyFeatures.ps1')
if($PreviewPath) {
    $script:state.tasks=@([pscustomobject]@{id='a';text='기업가 정신 과제 제출';done=$false},[pscustomobject]@{id='b';text='리빙랩 독후감';done=$false},[pscustomobject]@{id='c';text='일본어 발표 준비';done=$false},[pscustomobject]@{id='d';text='오늘의 작은 목표';done=$true})
    $window.Width=370; $window.Height=450; $tasksWindow.Width=430; $tasksWindow.Height=450; $memoWindow.Width=370; $memoWindow.Height=350; $clockWindow.Width=400; $clockWindow.Height=225; $weatherWindow.Width=400; $weatherWindow.Height=275; $chatWindow.Width=430; $chatWindow.Height=450
    $script:lastAgenda=[pscustomobject]@{rangeStart='2026-10-05';events=@([pscustomobject]@{date='2026-10-05';time='14:00–15:00';title='팀 프로젝트 회의';location='도서관 2층'},[pscustomobject]@{date='2026-10-06';time='09:00–10:30';title='내일의 첫 수업';location=''})}
    $ui.NoteTitle.Text='오늘의 생각'; $ui.Note.Text="해야 할 일은 작게 나누기.`r`n`r`n발표 초안은 오늘 20분만.`r`n좋은 아이디어는 여기 남겨두기."; Sync-CurrentNote
    $script:pages.local=0; $script:taskSource='local'; Update-DaylightLayout
    $ui.CalendarSummary.Text='앞으로 7일 · 2개 일정 (예시)'; $ui.Clock.Text='17:31'; $ui.Date.Text='10월 5일 월요일'; $ui.Temperature.Text='18°'; $ui.Conditions.Text='서울 · 대체로 맑음 (예시)'; Set-WeatherIcon 1
    $script:chatMessages=@([pscustomobject]@{role='user';content='발표 준비를 작게 나눠줘.'},[pscustomobject]@{role='assistant';content="오늘은 세 가지만 해보세요.`r`n`r`n1. 전달할 핵심 한 문장 쓰기`r`n2. 슬라이드 제목 세 개 정하기`r`n3. 첫 1분을 소리 내어 연습하기"}); Render-Chat; $ui.ChatInput.Clear(); $ui.ChatStatus.Text='Gemini · 예시 대화'
    $previewThemes=@{main='linen';tasks='cloud';memo='linen';clock='air';weather='aurora';chat='neon'}; foreach($key in $widgets.Keys) {Set-StylePreset $key $previewThemes[$key]};
    foreach($key in $widgets.Keys) { $state.appearance[$key].opacity=0.8;  if($key -eq 'clock') {$state.appearance[$key].opacity=0.15}; $brightness=0.8; if($key -in @('clock','weather')) {$brightness=0.2}; Set-WidgetAppearance $key $brightness; $surface=$widgets[$key]; $surface.Content.Measure((New-Object Windows.Size $surface.Width,$surface.Height)); $surface.Content.Arrange((New-Object Windows.Rect 0,0,$surface.Width,$surface.Height)); $surface.Content.UpdateLayout() }
    $visual=New-Object Windows.Media.DrawingVisual; $drawing=$visual.RenderOpen()
    $gradient=New-Object Windows.Media.LinearGradientBrush ([Windows.Media.ColorConverter]::ConvertFromString('#D9D5C9')),([Windows.Media.ColorConverter]::ConvertFromString('#32464B')),0
    $drawing.DrawRectangle($gradient,$null,(New-Object Windows.Rect 0,0,1400,1100))
    $positions=@{main=@(40,90);tasks=@(440,90);memo=@(40,580);clock=@(950,100);weather=@(950,390);chat=@(440,580)}
    foreach($key in $widgets.Keys) {$surface=$widgets[$key]; $brush=New-Object Windows.Media.VisualBrush $surface.Content; $drawing.DrawRectangle($brush,$null,(New-Object Windows.Rect $positions[$key][0],$positions[$key][1],$surface.Width,$surface.Height))}
    $caption=New-Object Windows.Media.FormattedText 'DAYLIGHT 0.7   /   예시 화면 · 일정, 날씨, 대화는 예시 데이터',([Globalization.CultureInfo]::GetCultureInfo('ko-KR')),([Windows.FlowDirection]::LeftToRight),(New-Object Windows.Media.Typeface 'Malgun Gothic'),12,([Windows.Media.Brushes]::Black)
    $drawing.DrawText($caption,(New-Object Windows.Point 56,36)); $drawing.Close()
    $bitmap=New-Object Windows.Media.Imaging.RenderTargetBitmap 1400,1100,96,96,([Windows.Media.PixelFormats]::Pbgra32); $bitmap.Render($visual)
    $encoder=New-Object Windows.Media.Imaging.PngBitmapEncoder; [void]$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap)); $stream=[IO.File]::Create($PreviewPath); try {$encoder.Save($stream)} finally {$stream.Dispose()}
}
$noteTimer.Stop(); Clear-WallpaperCache
'PASS: widgets, hidden controls, memo/pagination/resize, contrast, thirteen themes and customization, independent pin persistence, taskbar hidden/custom icon, Gemini parser/async/quota cooldown'

. (Join-Path $PSScriptRoot 'VerifyExtras.ps1')

. (Join-Path $PSScriptRoot 'VerifyAlignment.ps1')

. (Join-Path $PSScriptRoot 'VerifyProductivity.ps1')
