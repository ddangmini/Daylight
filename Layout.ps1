$pins=@{}
foreach($key in $widgets.Keys) {
    $value=$null; if($state.widgetPins) {if($state.widgetPins -is [hashtable]) {$value=$state.widgetPins[$key]} else {$value=$state.widgetPins.$key}}
    $pins[$key]=[bool]$state.pinned; if($extraCatalog.Contains($key)) {$pins[$key]=$false}; if($null -ne $value) {$pins[$key]=[bool]$value}
}
$state.widgetPins=$pins
function Toggle-WidgetPin([string]$Key) {if(-not $widgets.ContainsKey($Key)) {return}; $state.widgetPins[$Key]=-not $state.widgetPins[$Key]; if($state.widgetPins[$Key] -and $state.widgetDesktop) {$state.widgetDesktop[$Key]=$false}; Set-DaylightMode; Save-State}
$script:layoutReady=$false
$script:closingAll=$false
$script:quitRequested=$false
$script:pages=@{agenda=0;local=0;notion=0}
$script:taskSource='local'
$script:weatherJob=$null
$script:lastWeatherAttempt=[DateTime]::MinValue
$script:lastWeather=$null
$script:weatherChoosing=$false
$window.MinHeight=300; $tasksWindow.MinHeight=350; $memoWindow.MinHeight=300; $chatWindow.MinHeight=430
function Show-DaylightSettings { $settingsWindow.Topmost=$false; $settingsWindow.Show(); [void]$settingsWindow.Activate() }
function Set-WidgetVisible([string]$Key,[bool]$Visible) {
    $state[$Key+'Visible']=$Visible
    $ui['Show'+(Get-WidgetToggleName $Key)].IsChecked=$Visible
    if($Visible) {$widgets[$Key].Show(); [void]$widgets[$Key].Activate()} else {$widgets[$Key].Hide()}
    Save-State
}
function Get-WidgetToggleName([string]$Key) { if($Key -eq 'main') {return 'Main'}; return (Get-Culture).TextInfo.ToTitleCase($Key) }
function Get-PageCapacity([string]$Kind) {
    if(-not $state.autoLayout) { if($Kind -eq 'agenda') {return 2}; return 3 }
    if($Kind -eq 'agenda') {return [Math]::Max(1,[Math]::Floor(($window.Height-150)/125))}
    $rowHeight=70; if($Kind -eq 'notion') {$rowHeight=98}
    return [Math]::Max(1,[Math]::Floor(($tasksWindow.Height-215)/$rowHeight))
}
function Get-DaylightPage($Items,[string]$Kind) {
    $all=@($Items | Where-Object {$null -ne $_}); $capacity=Get-PageCapacity $Kind
    $count=[Math]::Max(1,[Math]::Ceiling($all.Count/$capacity))
    $script:pages[$Kind]=[Math]::Max(0,[Math]::Min($count-1,$script:pages[$Kind]))
    $prefix='Tasks'; if($Kind -eq 'agenda') {$prefix='Agenda'}
    if($Kind -eq 'agenda' -or $Kind -eq $script:taskSource) {
        $ui[$prefix+'Page'].Text="$($script:pages[$Kind]+1) / $count"
        $ui[$prefix+'Prev'].IsEnabled=$script:pages[$Kind] -gt 0
        $ui[$prefix+'Next'].IsEnabled=$script:pages[$Kind] -lt ($count-1)
    }
    return @($all | Select-Object -Skip ($script:pages[$Kind]*$capacity) -First $capacity)
}
function Update-DaylightLayout {
    if($script:layoutReady) {Render-Tasks; Render-Agenda $script:lastAgenda; Render-NotionTasks $script:lastNotionAgenda}
    if(-not $script:lastAgenda) {[void](Get-DaylightPage @() 'agenda')}
    if($script:taskSource -eq 'notion' -and -not $script:lastNotionAgenda) {[void](Get-DaylightPage @() 'notion')}
    $ui.TasksPanel.Visibility='Collapsed'; $ui.LocalPanel.Visibility='Visible'
    if($script:taskSource -eq 'notion') {$ui.TasksPanel.Visibility='Visible'; $ui.LocalPanel.Visibility='Collapsed'}
    $ui.TaskLocal.Opacity=0.5; $ui.TaskNotion.Opacity=0.5
    if($script:taskSource -eq 'local') {$ui.TaskLocal.Opacity=1} else {$ui.TaskNotion.Opacity=1}
    $ui.ClearDone.Visibility='Visible'; if($script:taskSource -eq 'notion') {$ui.ClearDone.Visibility='Collapsed'}
}
function Resize-DaylightWindow($Target,[double]$Width,[double]$Height,[double]$Ratio=0) {
    $area=[Windows.SystemParameters]::WorkArea
    $widthLimit=[Math]::Max($Target.MinWidth,$area.Width-12); $heightLimit=[Math]::Max($Target.MinHeight,$area.Height-12)
    $w=[Math]::Max($Target.MinWidth,[Math]::Min($widthLimit,$Width)); $h=[Math]::Max($Target.MinHeight,[Math]::Min($heightLimit,$Height))
    if($Ratio -gt 0) { $w=[Math]::Min([Math]::Min($widthLimit,$heightLimit*$Ratio),[Math]::Max([Math]::Max($Target.MinWidth,$Target.MinHeight*$Ratio),$w)); $h=$w/$Ratio }
    $Target.Width=$w; $Target.Height=$h
    Update-DaylightLayout
}
function Set-DaylightMode {
    foreach($key in $widgets.Keys) {
        $widgets[$key].Topmost=[bool]$state.widgetPins[$key]
        $button=$widgets[$key].FindName('WidgetPin'); $button.Content='◇'; if($state.widgetPins[$key]) {$button.Content='◆'}
        $button.ToolTip='항상 위: '+$(if($state.widgetPins[$key]) {'켜짐'} else {'꺼짐'})
        foreach($item in $widgets[$key].ContextMenu.Items) {if($item -is [Windows.Controls.MenuItem] -and $item.Header -eq '항상 위') {$item.IsChecked=[bool]$state.widgetPins[$key]}}
    }
    $ui.Pin.Content='선택한 창 항상 위'; if($ui.StyleTarget.SelectedItem -and $state.widgetPins[$ui.StyleTarget.SelectedItem.Tag]) {$ui.Pin.Content='선택한 창 항상 위 ✓'}
    Update-DaylightLayout
    if(Get-Command Update-DesktopWidgets -ErrorAction SilentlyContinue) {Update-DesktopWidgets}
}
function Capture-DaylightGeometry {
    $geometry=@{}
    foreach($key in $widgets.Keys) { $surface=$widgets[$key]; $left=$surface.Left; $top=$surface.Top; if([double]::IsNaN($left)) {$left=$null}; if([double]::IsNaN($top)) {$top=$null}; $geometry[$key]=@{width=$surface.Width;height=$surface.Height;left=$left;top=$top} }
    $state.geometry=$geometry
}
function Restore-DaylightGeometry {
    $area=[Windows.SystemParameters]::WorkArea
    $positions=@{main=@(40,65);tasks=@(440,65);memo=@(40,540);clock=@(($area.Width-360),65);weather=@(($area.Width-380),325);chat=@(440,480)}
    $offset=0; foreach($extraKey in $extraCatalog.Keys) {$positions[$extraKey]=@((80+$offset),(100+$offset)); $offset+=24}
    foreach($key in $widgets.Keys) {
        $surface=$widgets[$key]; $g=$null
        if($state.geometry) { if($state.geometry -is [hashtable]) {$g=$state.geometry[$key]} else {$g=$state.geometry.$key} }
        if($g -and $g.width -gt 0 -and $g.height -gt 0) {Resize-DaylightWindow $surface $g.width $g.height}
        $left=$area.Left+$positions[$key][0]; $top=$area.Top+$positions[$key][1]
        if($g -and $null -ne $g.left -and $null -ne $g.top) {$left=[double]$g.left; $top=[double]$g.top}
        $surface.WindowStartupLocation='Manual'; $surface.Left=[Math]::Max($area.Left,[Math]::Min($area.Right-$surface.Width,$left)); $surface.Top=[Math]::Max($area.Top,[Math]::Min($area.Bottom-$surface.Height,$top))
    }
}
function Update-DaylightSummaries {
    $ui.CalendarSummary.Text='설정에서 캘린더를 연결하세요'
    if($script:lastAgenda) {$ui.CalendarSummary.Text='앞으로 7일 · '+@($script:lastAgenda.events).Count+'개 일정'} elseif($script:calendarJob) {$ui.CalendarSummary.Text='갱신 중'} elseif(Test-Path -LiteralPath (Join-Path $PSScriptRoot 'calendar-token.dat')) {$ui.CalendarSummary.Text='구글 연결 저장됨 · 설정에서 새로고침'}
    $ui.NotionSummary.Text='설정에서 노션을 연결하세요'
    if($script:lastNotionAgenda) {$remaining=@($script:lastNotionAgenda.tasks | Where-Object {-not $_.done}).Count; $ui.NotionSummary.Text="$remaining 개 남음"} elseif($script:notionJob) {$ui.NotionSummary.Text='갱신 중'}
    $ui.CalendarSummary.ToolTip=$ui.CalendarStatus.Text; $ui.NotionSummary.ToolTip=$ui.NotionStatus.Text
}
function Set-WeatherIcon([int]$Code) {
    $icon='☁'; $color='#B9C9D8'
    if($Code -in @(0,1)) {$icon='☀';$color='#F9C866'} elseif($Code -eq 2) {$icon='⛅';$color='#F9C866'} elseif($Code -in @(45,48)) {$icon='≋';$color='#A5B8C6'} elseif($Code -in @(71,73,75,77,85,86)) {$icon='❄';$color='#78BEEA'} elseif($Code -in @(95,96,99)) {$icon='ϟ';$color='#C29BEF'} elseif($Code -in @(51,53,55,56,57,61,63,65,66,67,80,81,82)) {$icon='☂';$color='#73B8E7'}
    $ui.WeatherIcon.Text=$icon; $ui.WeatherIcon.Foreground=$color
}
. (Join-Path $PSScriptRoot 'WeatherUI.ps1')
$settingsWindow.Add_Closing({if(-not $script:closingAll) {$_.Cancel=$true; $settingsWindow.Hide()}})
foreach($key in $widgets.Keys) {
    $surface=$widgets[$key]
    $pinButton=$surface.FindName('WidgetPin'); $pinButton.Tag=$key; $pinButton.Add_Click({Toggle-WidgetPin $this.Tag})
    $surface.FindName('WidgetSettings').Add_Click({Show-DaylightSettings})
    $surface.FindName('WidgetClose').Tag=$key
    if($key -ne 'main') {$surface.FindName('WidgetClose').Add_Click({Set-WidgetVisible $this.Tag $false}); $surface.Add_Closing({if(-not $script:closingAll) {$_.Cancel=$true; Set-WidgetVisible $this.Tag $false}})}
    $surface.FindName('WidgetDrag').Add_MouseLeftButtonDown({
        if($_.Handled -or [Windows.Input.Mouse]::LeftButton -ne 'Pressed') {return}
        $target=[Windows.Window]::GetWindow($this)
        if($state.widgetLocks -and $state.widgetLocks[$target.Tag]) {return}
        if($_.OriginalSource -is [Windows.Controls.TextBlock] -or $_.OriginalSource -is [Windows.Controls.Border] -or $_.OriginalSource -eq $this) {
            $_.Handled=$true
            Invoke-DaylightSafe 'drag' {$target.DragMove(); Snap-DaylightWidget $target.Tag; Save-State}
        }
    })
    $handle=$surface.FindName('WidgetResize'); $handle.Tag=[pscustomobject]@{window=$surface;ratio=0}
    $handle.Add_DragStarted({$this.Tag.ratio=$this.Tag.window.Width/$this.Tag.window.Height})
    $handle.Add_DragDelta({$target=$this.Tag.window; if($state.widgetLocks -and $state.widgetLocks[$target.Tag]) {return}; $ratio=0; $width=$target.Width+$_.HorizontalChange; if($state.lockRatio) {$ratio=$this.Tag.ratio; if([Math]::Abs($_.VerticalChange*$ratio) -gt [Math]::Abs($_.HorizontalChange)) {$width=$target.Width+$_.VerticalChange*$ratio}}; Resize-DaylightWindow $target $width ($target.Height+$_.VerticalChange) $ratio})
    $handle.Add_DragCompleted({Snap-DaylightWidget $this.Tag.window.Tag; Save-State})
    $toggle=$ui['Show'+(Get-WidgetToggleName $key)]; $toggle.Tag=$key; $toggle.IsChecked=[bool]$state[$key+'Visible']; $toggle.Add_Click({Set-WidgetVisible $this.Tag ([bool]$this.IsChecked)})
    $surface.Add_SizeChanged({if($script:layoutReady -and $this.Tag -in @('main','tasks')) {Update-DaylightLayout}})
    $surface.ContextMenu=New-Object Windows.Controls.ContextMenu
    $settingsItem=New-Object Windows.Controls.MenuItem; $settingsItem.Header='설정'; $settingsItem.Add_Click({Show-DaylightSettings}); [void]$surface.ContextMenu.Items.Add($settingsItem)
    $styleItem=New-Object Windows.Controls.MenuItem; $styleItem.Header='이 창 꾸미기'; $styleItem.Tag=$key; $styleItem.Add_Click({Show-Appearance $this.Tag}); [void]$surface.ContextMenu.Items.Add($styleItem)
    $pinItem=New-Object Windows.Controls.MenuItem; $pinItem.Header='항상 위'; $pinItem.IsCheckable=$true; $pinItem.Tag=$key; $pinItem.Add_Click({Toggle-WidgetPin $this.Tag}); [void]$surface.ContextMenu.Items.Add($pinItem)
    $hideItem=New-Object Windows.Controls.MenuItem; $hideItem.Header='이 창 숨기기'; $hideItem.Tag=$key; $hideItem.Add_Click({Set-WidgetVisible $this.Tag $false}); [void]$surface.ContextMenu.Items.Add($hideItem)
    $quitItem=New-Object Windows.Controls.MenuItem; $quitItem.Header='Daylight 종료'; $quitItem.Add_Click({$script:quitRequested=$true; $window.Close()}); [void]$surface.ContextMenu.Items.Add($quitItem)
}
$ui.Quit.Add_Click({$script:quitRequested=$true; $window.Close()})
$ui.TaskLocal.Add_Click({$script:taskSource='local'; Update-DaylightLayout}); $ui.TaskNotion.Add_Click({$script:taskSource='notion'; Update-DaylightLayout})
$ui.AgendaPrev.Add_Click({$script:pages.agenda--; Render-Agenda $script:lastAgenda}); $ui.AgendaNext.Add_Click({$script:pages.agenda++; Render-Agenda $script:lastAgenda})
$ui.TasksPrev.Add_Click({$script:pages[$script:taskSource]--; Update-DaylightLayout}); $ui.TasksNext.Add_Click({$script:pages[$script:taskSource]++; Update-DaylightLayout})
$ui.AutoLayout.IsChecked=$state.autoLayout; $ui.LockRatio.IsChecked=$state.lockRatio
$ui.AutoLayout.Add_Click({$state.autoLayout=[bool]$this.IsChecked; Update-DaylightLayout; Save-State})
$ui.LockRatio.Add_Click({$state.lockRatio=[bool]$this.IsChecked; Save-State})
$ui.StyleTarget.SelectedIndex=0; $ui.StyleTarget.Add_SelectionChanged({Set-DaylightMode})
$ui.TextTone.Add_Click({Show-Appearance $ui.StyleTarget.SelectedItem.Tag})
$ui.Grow.Add_Click({$target=$widgets[$ui.StyleTarget.SelectedItem.Tag]; Resize-DaylightWindow $target ($target.Width*1.15) ($target.Height*1.15) ($target.Width/$target.Height); Save-State})
$ui.Shrink.Add_Click({$target=$widgets[$ui.StyleTarget.SelectedItem.Tag]; Resize-DaylightWindow $target ($target.Width/1.15) ($target.Height/1.15) ($target.Width/$target.Height); Save-State})
$ui.ResetLayout.Add_Click({
    $state.geometry=$null
    $defaults=@{main=@(370,440);tasks=@(390,470);memo=@(370,350);clock=@(320,225);weather=@(340,265);chat=@(470,560)}
    foreach($key in $widgets.Keys) {$widgets[$key].Width=$widgetDefaults[$key][0]; $widgets[$key].Height=$widgetDefaults[$key][1]}
    Restore-DaylightGeometry; Save-State
})
$ui.WeatherCredit.Add_MouseLeftButtonUp({Start-Process 'https://open-meteo.com/'})
$ui.WeatherSearch.Add_Click({Start-WeatherWork 'Search'}); $ui.WeatherRefresh.Add_Click({Start-WeatherWork})
$ui.WeatherChoice.Add_SelectionChanged({if($script:weatherChoosing -or -not $ui.WeatherChoice.SelectedItem) {return}; $location=$ui.WeatherChoice.SelectedItem.Tag; $state.weatherCity=[string]$location.name; $state.weatherLatitude=[double]$location.latitude; $state.weatherLongitude=[double]$location.longitude; $script:lastWeather=$null; $ui.Temperature.Text='—°'; $ui.Conditions.Text=$location.name+' · 조회 중'; Save-State; Start-WeatherWork})
$ui.WeatherCityInput.Text=$state.weatherCity; $ui.Conditions.Text=$state.weatherCity+' · 조회 중'
Restore-DaylightGeometry; $script:layoutReady=$true
$window.Add_Loaded({
    if($SelfTest) {return}
    foreach($key in $widgets.Keys) {if($key -ne 'main' -and $state[$key+'Visible']) {$widgets[$key].Show()}}
    if(-not $state.mainVisible) {$window.Hide()}
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing
    $script:tray=New-Object Windows.Forms.NotifyIcon; $tray.Icon=$script:daylightTrayIcon; $tray.Text='Daylight · 더블 클릭으로 설정'; $tray.Visible=$true
    $tray.Add_DoubleClick({Show-DaylightSettings})
    $trayMenu=New-Object Windows.Forms.ContextMenuStrip
    $item=$trayMenu.Items.Add('설정'); $item.Add_Click({Show-DaylightSettings})
    $item=$trayMenu.Items.Add('Daylight 종료'); $item.Add_Click({$script:quitRequested=$true; $window.Close()})
    $tray.ContextMenuStrip=$trayMenu
    Set-DaylightTextTone
})
