function Convert-ClassTime([string]$Text) {
 $value=[DateTime]::MinValue
 if(-not [DateTime]::TryParseExact($Text,'HH:mm',[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::None,[ref]$value)) {throw '시간은 09:00처럼 입력하세요.'}
 return $value.Hour*60+$value.Minute
}
function Add-TimetableClass([string]$Id,[string]$Title,[int]$Day,[string]$Start,[string]$End,[string]$Room,[string]$Link,[string]$Color,[string]$From,[string]$Until) {
 if(-not $Title.Trim()) {throw '수업 이름을 입력하세요.'}
 if($Day -lt 0 -or $Day -gt 6) {throw '요일을 선택하세요.'}
 $startMinute=Convert-ClassTime $Start; $endMinute=Convert-ClassTime $End
 if($endMinute -le $startMinute) {throw '종료 시각은 시작 시각보다 늦어야 합니다.'}
 $begin=[DateTime]::ParseExact($From,'yyyy-MM-dd',[Globalization.CultureInfo]::InvariantCulture)
 $finish=[DateTime]::ParseExact($Until,'yyyy-MM-dd',[Globalization.CultureInfo]::InvariantCulture)
 if($finish -lt $begin) {throw '학기 종료일을 확인하세요.'}
 if($Link) {$uri=$null; if(-not [Uri]::TryCreate($Link,[UriKind]::Absolute,[ref]$uri) -or $uri.Scheme -ne 'https' -or $uri.UserInfo) {throw '수업 링크는 https:// 주소를 사용하세요.'}}
 if($Color -notin @('#A3E8D2','#A5C8EF','#C8B9EC','#F3BA9C','#E8CF8E')) {$Color='#A3E8D2'}
 foreach($class in @($state.timetable)) {
  if($class.id -ne $Id -and $class.day -eq $Day -and $startMinute -lt $class.end -and $endMinute -gt $class.start -and $From -le $class.until -and $Until -ge $class.from) {throw '같은 요일·기간에 시간이 겹치는 수업이 있습니다.'}
 }
 if(-not $Id) {$Id=[guid]::NewGuid().ToString('N')}
 $state.timetable=@($state.timetable|Where-Object {$_.id -ne $Id})+@(@{id=$Id;title=$Title.Trim();day=$Day;start=$startMinute;end=$endMinute;room=$Room.Trim();link=$Link;color=$Color;from=$From;until=$Until})
 Save-State; Render-Timetable
}
function Get-TimetableDays($Classes=@($state.timetable)) {
 $days=@(1,2,3,4,5); if(@($Classes|Where-Object {$_.day -eq 6}).Count) {$days+=6}; if(@($Classes|Where-Object {$_.day -eq 0}).Count) {$days+=0}; return $days
}
function Get-NextClass([DateTime]$Now=(Get-FeatureNow)) {
 $candidates=@()
 for($offset=0;$offset -le 14;$offset++) {
  $date=$Now.Date.AddDays($offset); $stamp=$date.ToString('yyyy-MM-dd')
  foreach($class in @($state.timetable)) {
   if([int]$class.day -ne [int]$date.DayOfWeek -or $stamp -lt $class.from -or $stamp -gt $class.until) {continue}
   $begin=$date.AddMinutes($class.start); $end=$date.AddMinutes($class.end)
   if($end -gt $Now) {$candidates+=@{class=$class;start=$begin;end=$end;ongoing=($begin -le $Now);minutes=[Math]::Ceiling(($begin-$Now).TotalMinutes)}}
  }
 }
 return $candidates|Sort-Object {$_.start}|Select-Object -First 1
}
function Update-ClassCountdown {
 $next=Get-NextClass; $script:nextClass=$next
 $ui.NextClassLink.IsEnabled=[bool]($next -and $next.class.link)
 if(-not $next) {$ui.NextClass.Text='등록된 다음 수업이 없습니다'; return}
 $suffix=''; if($next.class.room) {$suffix=' · '+$next.class.room}
 if($next.ongoing) {$minutes=[Math]::Ceiling(($next.end-(Get-FeatureNow)).TotalMinutes); $ui.NextClass.Text=$next.class.title+' · 수업 중 · '+$minutes+'분 후 종료'+$suffix}
 else {$remaining=[string]$next.minutes+'분'; if($next.minutes -ge 60) {$remaining=[Math]::Floor($next.minutes/60).ToString()+'시간 '+($next.minutes%60)+'분'}; $ui.NextClass.Text=$next.class.title+' · '+$remaining+' 후 시작'+$suffix}
}
function Render-Timetable {
 $grid=$ui.TimetableGrid; $grid.Children.Clear(); $grid.ColumnDefinitions.Clear(); $grid.RowDefinitions.Clear()
 $now=Get-FeatureNow; $monday=$now.Date.AddDays(-(([int]$now.DayOfWeek+6)%7)); $classes=@($state.timetable|Where-Object {$_.from -le $monday.AddDays(6).ToString('yyyy-MM-dd') -and $_.until -ge $monday.ToString('yyyy-MM-dd')})
 $days=@(Get-TimetableDays $classes); $start=8*60; $end=19*60
 if($classes.Count) {$start=[Math]::Min($start,[Math]::Floor(($classes|ForEach-Object {$_.start}|Measure-Object -Minimum).Minimum/60)*60); $end=[Math]::Max($end,[Math]::Ceiling(($classes|ForEach-Object {$_.end}|Measure-Object -Maximum).Maximum/60)*60)}
 $hours=($end-$start)/60; $rowHeight=38
 $col=New-Object Windows.Controls.ColumnDefinition; $col.Width=[Windows.GridLength]40; [void]$grid.ColumnDefinitions.Add($col)
 foreach($day in $days) {[void]$grid.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition))}
 $row=New-Object Windows.Controls.RowDefinition; $row.Height=[Windows.GridLength]30; [void]$grid.RowDefinitions.Add($row)
 $row=New-Object Windows.Controls.RowDefinition; $row.Height=[Windows.GridLength]($hours*$rowHeight); [void]$grid.RowDefinitions.Add($row)
 $names=@('일','월','화','수','목','금','토')
 for($i=0;$i -lt $days.Count;$i++) {
  $day=$days[$i]; $label=New-Object Windows.Controls.TextBlock; $label.Text=$names[$day]; $label.HorizontalAlignment='Center'; $label.Foreground='#E9EDF5'; if($day -eq [int]$now.DayOfWeek) {$label.Foreground='#A3E8D2'}
  [Windows.Controls.Grid]::SetColumn($label,$i+1); [void]$grid.Children.Add($label)
  $canvas=New-Object Windows.Controls.Canvas; $canvas.ClipToBounds=$true; $canvas.Background='#08192235'; [Windows.Controls.Grid]::SetRow($canvas,1); [Windows.Controls.Grid]::SetColumn($canvas,$i+1)
  [void]$grid.Children.Add($canvas)
  for($hour=0;$hour -le $hours;$hour++) {$line=New-Object Windows.Controls.Border; $line.BorderBrush='#18344056'; $line.BorderThickness='0,1,0,0'; $line.Height=$rowHeight; $line.Width=500; [Windows.Controls.Canvas]::SetTop($line,$hour*$rowHeight); [void]$canvas.Children.Add($line)}
  foreach($class in @($classes|Where-Object {$_.day -eq $day})) {
   $button=New-Object Windows.Controls.Button; $button.Name='TimetableClassCard'; $button.Tag=$class.id; $button.Background=$class.color; $button.Foreground='#172131'; $button.Padding='5,4'; $button.Margin=0; $button.HorizontalContentAlignment='Left'; $button.VerticalContentAlignment='Top'
   $text=New-Object Windows.Controls.TextBlock; $text.Name='TimetableClassText'; $text.Text=$class.title+"`n"+$class.room; $text.TextWrapping='Wrap'; $text.FontSize=11; $text.Foreground='#172131'; $button.Content=$text
   $button.Height=[Math]::Max(16,($class.end-$class.start)/60*$rowHeight-2); $button.ToolTip=$class.title+' · '+([TimeSpan]::FromMinutes($class.start).ToString('hh\:mm'))+'–'+([TimeSpan]::FromMinutes($class.end).ToString('hh\:mm'))+' · '+$class.room
   [Windows.Controls.Canvas]::SetTop($button,($class.start-$start)/60*$rowHeight+1); [Windows.Controls.Canvas]::SetLeft($button,3)
   $button.SetBinding([Windows.FrameworkElement]::WidthProperty,(New-Object Windows.Data.Binding 'ActualWidth' -Property @{Source=$canvas;Converter=$script:classWidthConverter}))|Out-Null
   $button.Add_Click({Show-TimetableEditor $this.Tag}); [void]$canvas.Children.Add($button)
  }
 }
 $times=New-Object Windows.Controls.Canvas; [Windows.Controls.Grid]::SetRow($times,1); [void]$grid.Children.Add($times)
 for($hour=0;$hour -lt $hours;$hour++) {$label=New-Object Windows.Controls.TextBlock; $label.Text=[string](($start/60)+$hour); $label.FontSize=10; $label.Foreground='#A9B6CA'; [Windows.Controls.Canvas]::SetTop($label,$hour*$rowHeight); [void]$times.Children.Add($label)}
 Update-ClassCountdown
}
Add-Type -ReferencedAssemblies @([Windows.Data.IValueConverter].Assembly.Location,'System.dll') -TypeDefinition @'
using System; using System.Globalization; using System.Windows.Data;
public class DaylightClassWidth : IValueConverter {
 public object Convert(object value,Type t,object p,CultureInfo c){return Math.Max(16,System.Convert.ToDouble(value)-6);}
 public object ConvertBack(object v,Type t,object p,CultureInfo c){throw new NotSupportedException();}
}
'@
$script:classWidthConverter=New-Object DaylightClassWidth
function Show-TimetableEditor([string]$Id='') {
 if($script:timetableEditor) {$script:timetableEditor.Close()}
 $script:timetableEditor=New-DaylightWindow @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="나의 시간표" Width="460" Height="730" MinWidth="400" MinHeight="400" Background="#192235" Foreground="#E9EDF5" FontFamily="Malgun Gothic" ShowInTaskbar="False"><Window.Resources>__THEME__</Window.Resources><ScrollViewer VerticalScrollBarVisibility="Auto"><StackPanel Margin="24"><TextBlock Text="나의 시간표" FontSize="24" Margin="0,0,0,18"/><ComboBox x:Name="ClassChoice" ToolTip="새 수업 또는 수정할 수업"/><TextBlock Text="수업 이름" Margin="0,14,0,6"/><TextBox x:Name="ClassTitle"/><TextBlock Text="요일" Margin="0,12,0,6"/><ComboBox x:Name="ClassDay"/><TextBlock Text="시작 · 종료 (24시간)" Margin="0,12,0,6"/><StackPanel Orientation="Horizontal"><TextBox x:Name="ClassStart" Text="09:00" Width="120"/><TextBox x:Name="ClassEnd" Text="10:30" Width="120" Margin="10,0"/></StackPanel><TextBlock Text="강의실 · 장소" Margin="0,12,0,6"/><TextBox x:Name="ClassRoom"/><TextBlock Text="수업 링크 (선택)" Margin="0,12,0,6"/><TextBox x:Name="ClassLink"/><TextBlock Text="학기 시작 · 종료 (YYYY-MM-DD)" Margin="0,12,0,6"/><StackPanel Orientation="Horizontal"><TextBox x:Name="ClassFrom" Width="150"/><TextBox x:Name="ClassUntil" Width="150" Margin="10,0"/></StackPanel><TextBlock Text="수업 색" Margin="0,12,0,6"/><ComboBox x:Name="ClassColor"/><WrapPanel Margin="0,18,0,0"><Button x:Name="ClassSave" Content="저장"/><Button x:Name="ClassDelete" Content="삭제"/><Button x:Name="ClassNew" Content="새 수업"/></WrapPanel><TextBlock x:Name="ClassStatus" Text="매주 반복 · 시간표의 수업을 누르면 수정합니다." TextWrapping="Wrap" FontSize="11" Margin="0,12,0,0"/></StackPanel></ScrollViewer></Window>
'@
 $editor=$script:timetableEditor; $editor.Resources.MergedDictionaries.Add($settingsWindow.Resources)
 $choice=$editor.FindName('ClassChoice'); $item=New-Object Windows.Controls.ComboBoxItem; $item.Content='새 수업'; $item.Tag=''; [void]$choice.Items.Add($item)
 foreach($class in @($state.timetable)) {$item=New-Object Windows.Controls.ComboBoxItem; $item.Content=$class.title; $item.Tag=$class.id; [void]$choice.Items.Add($item)}
 $names=@('일','월','화','수','목','금','토'); for($i=0;$i -lt 7;$i++) {$item=New-Object Windows.Controls.ComboBoxItem; $item.Content=$names[$i]; $item.Tag=$i; [void]$editor.FindName('ClassDay').Items.Add($item)}
 foreach($color in @('#A3E8D2','#A5C8EF','#C8B9EC','#F3BA9C','#E8CF8E')) {$item=New-Object Windows.Controls.ComboBoxItem; $item.Content=$color; $item.Tag=$color; $item.Foreground=$color; [void]$editor.FindName('ClassColor').Items.Add($item)}
 $choice.Add_SelectionChanged({
  $e=$script:timetableEditor; $id=$e.FindName('ClassChoice').SelectedItem.Tag; $class=$state.timetable|Where-Object {$_.id -eq $id}|Select-Object -First 1
  foreach($pair in @(@('ClassTitle','title'),@('ClassRoom','room'),@('ClassLink','link'))) {$e.FindName($pair[0]).Text=[string]$class.($pair[1])}
  $e.FindName('ClassDay').SelectedIndex=1; $e.FindName('ClassColor').SelectedIndex=0; $e.FindName('ClassFrom').Text=(Get-FeatureNow).ToString('yyyy-MM-dd'); $e.FindName('ClassUntil').Text=(Get-FeatureNow).AddMonths(4).ToString('yyyy-MM-dd')
  if($class) {$e.FindName('ClassDay').SelectedIndex=$class.day; $e.FindName('ClassStart').Text=[TimeSpan]::FromMinutes($class.start).ToString('hh\:mm'); $e.FindName('ClassEnd').Text=[TimeSpan]::FromMinutes($class.end).ToString('hh\:mm'); $e.FindName('ClassFrom').Text=$class.from; $e.FindName('ClassUntil').Text=$class.until; foreach($item in $e.FindName('ClassColor').Items) {if($item.Tag -eq $class.color) {$e.FindName('ClassColor').SelectedItem=$item}}}
 })
 $choice.SelectedIndex=0; foreach($item in $choice.Items) {if($item.Tag -eq $Id) {$choice.SelectedItem=$item}}
 $editor.FindName('ClassSave').Add_Click({try {$e=$script:timetableEditor; Add-TimetableClass $e.FindName('ClassChoice').SelectedItem.Tag $e.FindName('ClassTitle').Text $e.FindName('ClassDay').SelectedItem.Tag $e.FindName('ClassStart').Text $e.FindName('ClassEnd').Text $e.FindName('ClassRoom').Text $e.FindName('ClassLink').Text $e.FindName('ClassColor').SelectedItem.Tag $e.FindName('ClassFrom').Text $e.FindName('ClassUntil').Text; $e.Close(); $script:timetableEditor=$null; Set-WidgetVisible 'timetable' $true} catch {$script:timetableEditor.FindName('ClassStatus').Text=$_.Exception.Message}})
 $editor.FindName('ClassDelete').Add_Click({$id=$script:timetableEditor.FindName('ClassChoice').SelectedItem.Tag; $state.timetable=@($state.timetable|Where-Object {$_.id -ne $id}); Save-State; Render-Timetable; $script:timetableEditor.Close(); $script:timetableEditor=$null})
 $editor.FindName('ClassNew').Add_Click({$script:timetableEditor.FindName('ClassChoice').SelectedIndex=0})
 if(-not $SelfTest) {$editor.Show(); [void]$editor.Activate()}
}
$ui.TimetableEdit.Add_Click({Show-TimetableEditor})
$ui.NextClassLink.Add_Click({if($script:nextClass.class.link) {Start-Process $script:nextClass.class.link}})
Render-Timetable
