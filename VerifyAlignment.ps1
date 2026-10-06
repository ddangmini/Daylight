$savedHideTitles=$state.hideWidgetTitles; $savedHideBorders=$state.hideWidgetBorders; $savedSnap=$state.snapWidgets
$savedClockStyle=$state.appearance.clock.Clone()
try {
 $state.appearance.clock.opacity=0; $state.appearance.clock.theme='adaptive'; Set-WidgetAppearance 'clock' 0.2
 Assert-UI ($widgets.clock.FindName('Surface').BorderBrush.Color.A -eq 0) 'Fully transparent background has no outline'
 $state.appearance.clock.opacity=0.8; $state.hideWidgetBorders=$true; Set-WidgetAppearance 'clock' 0.2
 Assert-UI ($widgets.clock.FindName('Surface').BorderBrush.Color.A -eq 0) 'Explicit border hiding'
 $state.hideWidgetBorders=$false; Set-WidgetAppearance 'clock' 0.2
 Assert-UI ($widgets.clock.FindName('Surface').BorderBrush.Color.A -gt 0) 'Border restores after option disabled'
 $state.hideWidgetTitles=$true; Set-WidgetAppearance 'clock' 0.2
 Assert-UI ($widgets.clock.FindName('WidgetTitle').Style -eq $widgets.clock.Resources['QuietTools']) 'Title shares hover and keyboard-focus visibility behavior'
 $state.hideWidgetTitles=$false; Set-WidgetAppearance 'clock' 0.2
 Assert-UI ($widgets.clock.FindName('WidgetTitle').Opacity -eq 1) 'Persistent titles option'
 $area=New-Object Windows.Rect 0,0,1920,1080
 $peer=@{left=500;top=100;width=300;height=250}
 $result=Get-SnappedBounds @{left=192;top=103;width=300;height=200} @($peer) $area
 Assert-UI ($result.left -eq 200 -and $result.top -eq 100) 'Adjacent edges join and top aligns'
 $result=Get-SnappedBounds @{left=180;top=103;width=300;height=200} @($peer) $area
 Assert-UI ($result.left -eq 180) 'Outside snap threshold stays unchanged'
 $result=Get-SnappedBounds @{left=192;top=800;width=300;height=200} @($peer) $area
 Assert-UI ($result.left -eq 192) 'Distant widgets do not attract'
 $result=Get-SnappedBounds @{left=7;top=8;width=300;height=200} @() $area
 Assert-UI ($result.left -eq 0 -and $result.top -eq 0) 'Screen edge snapping'
 $delta=Get-CenteredBounds @(@{left=50;top=50;width=300;height=200},@{left=350;top=50;width=300;height=200}) $area
 Assert-UI ($delta.dx -eq 610 -and $delta.dy -eq 390) 'Group centering preserves relative spacing'
 $before=$widgets.clock.Left; $state.widgetLocks.clock=$true; Center-DaylightWidgets 'clock'; Snap-DaylightWidget 'clock'
 Assert-UI ($widgets.clock.Left -eq $before) 'Locked widgets do not move'; $state.widgetLocks.clock=$false
 Save-State; $saved=Get-Content $DataPath -Raw -Encoding UTF8|ConvertFrom-Json
 Assert-UI ($null -ne $saved.hideWidgetTitles -and $null -ne $saved.snapWidgets) 'Alignment preferences persist'
 'PASS: transparent outlines, optional hover titles, edge snapping threshold and proximity, screen edges, group center and movement locks'
} finally {$state.hideWidgetTitles=$savedHideTitles; $state.hideWidgetBorders=$savedHideBorders; $state.snapWidgets=$savedSnap; $state.appearance.clock=$savedClockStyle; Set-DaylightTextTone}
