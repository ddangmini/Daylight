foreach($option in @('hideWidgetTitles','snapWidgets')) {if(-not $state.ContainsKey($option)) {$state[$option]=$true}}
if(-not $state.ContainsKey('hideWidgetBorders')) {$state.hideWidgetBorders=$false}
function Set-WidgetChrome([string]$Key) {
 $surface=$widgets[$Key]; $style=$state.appearance[$Key]; $border=$surface.FindName('Surface')
 if($state.hideWidgetBorders -or $style.opacity -le 0.01) {$border.BorderBrush='Transparent'}
 $title=$surface.FindName('WidgetTitle')
 $title.ClearValue([Windows.UIElement]::OpacityProperty)
 if($state.hideWidgetTitles) {$title.Style=$surface.Resources['QuietTools']}
 else {$title.Style=$null; $title.Opacity=1; if($Key -eq 'clock' -and $script:stylePresets[$style.theme].minimal) {$title.Opacity=0}}
}
# Coordinates and threshold are device-independent pixels; only nearby overlapping edges attract.
function Get-SnappedBounds($Rect,$Others,$Area,[double]$Threshold=14) {
 $x=[double]$Rect.left; $y=[double]$Rect.top; $dx=$Threshold+1; $dy=$Threshold+1
 $xc=@([double]$Area.Left,[double]($Area.Right-$Rect.width)); $yc=@([double]$Area.Top,[double]($Area.Bottom-$Rect.height))
 foreach($other in $Others) {
  if($Rect.top -le $other.top+$other.height+$Threshold -and $Rect.top+$Rect.height -ge $other.top-$Threshold) {
   $xc+=@([double]($other.left-$Rect.width),[double]($other.left+$other.width),[double]$other.left,[double]($other.left+$other.width-$Rect.width))
  }
  if($Rect.left -le $other.left+$other.width+$Threshold -and $Rect.left+$Rect.width -ge $other.left-$Threshold) {
   $yc+=@([double]($other.top-$Rect.height),[double]($other.top+$other.height),[double]$other.top,[double]($other.top+$other.height-$Rect.height))
  }
 }
 foreach($candidate in $xc) {$distance=[Math]::Abs($candidate-$Rect.left); if($distance -le $Threshold -and $distance -lt $dx) {$x=$candidate; $dx=$distance}}
 foreach($candidate in $yc) {$distance=[Math]::Abs($candidate-$Rect.top); if($distance -le $Threshold -and $distance -lt $dy) {$y=$candidate; $dy=$distance}}
 return @{left=$x;top=$y;width=$Rect.width;height=$Rect.height}
}
function Get-WidgetWorkArea($Window) {
 $source=[Windows.PresentationSource]::FromVisual($Window)
 if(-not $source -or -not $source.CompositionTarget) {return [Windows.SystemParameters]::WorkArea}
 $handle=(New-Object Windows.Interop.WindowInteropHelper $Window).Handle
 $area=[Windows.Forms.Screen]::FromHandle($handle).WorkingArea
 $transform=$source.CompositionTarget.TransformFromDevice
 $origin=$transform.Transform((New-Object Windows.Point $area.Left,$area.Top))
 $end=$transform.Transform((New-Object Windows.Point $area.Right,$area.Bottom))
 return New-Object Windows.Rect $origin,$end
}
function Snap-DaylightWidget([string]$Key) {
 if(-not $state.snapWidgets -or $state.widgetLocks[$Key]) {return}
 $window=$widgets[$Key]; $others=@()
 foreach($peer in $widgets.Values) {if($peer.Tag -ne $Key -and $peer.IsVisible) {$others+=@{left=$peer.Left;top=$peer.Top;width=$peer.Width;height=$peer.Height}}}
 $position=Get-SnappedBounds @{left=$window.Left;top=$window.Top;width=$window.Width;height=$window.Height} $others (Get-WidgetWorkArea $window)
 $window.Left=$position.left; $window.Top=$position.top
}
function Get-CenteredBounds($Rects,$Area) {
 $left=($Rects|ForEach-Object {$_.left}|Measure-Object -Minimum).Minimum
 $top=($Rects|ForEach-Object {$_.top}|Measure-Object -Minimum).Minimum
 $right=($Rects|ForEach-Object {$_.left+$_.width}|Measure-Object -Maximum).Maximum
 $bottom=($Rects|ForEach-Object {$_.top+$_.height}|Measure-Object -Maximum).Maximum
 return @{dx=$Area.Left+($Area.Width-($right-$left))/2-$left;dy=$Area.Top+($Area.Height-($bottom-$top))/2-$top}
}
function Center-DaylightWidgets([string]$Key,[switch]$Group) {
 $targets=@($widgets[$Key]); if($Group) {$targets=@($widgets.Values|Where-Object {$_.IsVisible -and -not $state.widgetLocks[$_.Tag]})}
 $targets=@($targets|Where-Object {-not $state.widgetLocks[$_.Tag]})
 if(-not $targets.Count) {return}
 $rects=@($targets|ForEach-Object {@{left=$_.Left;top=$_.Top;width=$_.Width;height=$_.Height}})
 $delta=Get-CenteredBounds $rects (Get-WidgetWorkArea $targets[0])
 foreach($window in $targets) {$window.Left+=$delta.dx; $window.Top+=$delta.dy}
 Save-State
}
$alignmentMarkup=@'
<StackPanel xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Margin="0,14,0,0">
 <TextBlock Text="깔끔한 화면 · 정렬" Foreground="#A3E8D2" FontSize="12" Margin="0,0,0,12"/>
 <CheckBox x:Name="HideTitles" Content="제목은 마우스를 올릴 때만 표시" Margin="0,0,0,12"/>
 <CheckBox x:Name="HideBorders" Content="모든 위젯의 테두리 숨기기" Margin="0,0,0,12"/>
 <TextBlock Text="완전히 투명한 배경은 테두리도 자동으로 숨깁니다." Foreground="#B8C5D8" FontSize="11" TextWrapping="Wrap" Margin="0,0,0,12"/>
 <CheckBox x:Name="SnapWidgets" Content="가까운 창·화면 가장자리에 자동 정렬" Margin="0,0,0,12"/>
 <TextBlock Text="이동·크기 조절을 마치면 14px 안의 가장자리를 맞춥니다. 잠긴 창은 이동하지 않습니다." Foreground="#B8C5D8" FontSize="11" TextWrapping="Wrap" Margin="0,0,0,12"/>
 <WrapPanel><Button x:Name="CenterSelected" Content="선택한 창 가운데 정렬"/><Button x:Name="CenterGroup" Content="현재 배치 가운데 정렬" Margin="0,8,0,0"/></WrapPanel>
 <TextBlock Text="선택한 창: 아래 창별 꾸미기의 대상 · 현재 배치: 창 사이 간격을 유지하고 함께 이동" Foreground="#B8C5D8" FontSize="11" TextWrapping="Wrap" Margin="0,10,0,0"/>
</StackPanel>
'@
[xml]$alignmentXml=$alignmentMarkup
$script:alignmentSettings=[Windows.Markup.XamlReader]::Load((New-Object Xml.XmlNodeReader $alignmentXml))
[void]$ui.LockAllWidgets.Parent.Children.Add($alignmentSettings)
foreach($pair in @(@('HideTitles','hideWidgetTitles'),@('HideBorders','hideWidgetBorders'),@('SnapWidgets','snapWidgets'))) {
 $control=$alignmentSettings.FindName($pair[0]); $control.Tag=$pair[1]; $control.IsChecked=[bool]$state[$pair[1]]
 $control.Add_Click({$state[$this.Tag]=[bool]$this.IsChecked; Set-DaylightTextTone; Save-State})
}
$alignmentSettings.FindName('CenterSelected').Add_Click({Center-DaylightWidgets ([string]$ui.StyleTarget.SelectedItem.Tag)})
$alignmentSettings.FindName('CenterGroup').Add_Click({Center-DaylightWidgets 'main' -Group})
foreach($key in $widgets.Keys) {
 $item=New-Object Windows.Controls.MenuItem; $item.Header='이 창 가운데 정렬'; $item.Tag=$key
 $item.Add_Click({Center-DaylightWidgets $this.Tag}); [void]$widgets[$key].ContextMenu.Items.Insert(2,$item)
}
Set-DaylightTextTone
