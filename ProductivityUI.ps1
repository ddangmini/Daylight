$productMarkup=@'
<Expander xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Header="빠른 입력 · 나의 루틴" Margin="0,20,0,16"><StackPanel Margin="0,12,0,0">
 <TextBlock Text="빠른 입력" FontSize="17" Margin="0,0,0,10"/><CheckBox x:Name="HotkeyEnabled" Content="전역 단축키로 빠른 입력 열기"/><ComboBox x:Name="HotkeyChoice" Margin="0,8,0,0"><ComboBoxItem Content="Ctrl+Alt+Space" Tag="ctrlaltspace"/><ComboBoxItem Content="Ctrl+Alt+Q" Tag="ctrlaltq"/><ComboBoxItem Content="Ctrl+Shift+Space" Tag="ctrlshiftspace"/></ComboBox><Button x:Name="QuickOpen" Content="빠른 입력 열기" HorizontalAlignment="Left" Margin="0,10,0,0"/><TextBlock x:Name="HotkeyStatus" FontSize="11" TextWrapping="Wrap" Margin="0,8,0,18"/>
 <TextBlock Text="반복 할 일" FontSize="17" Margin="0,0,0,10"/><TextBox x:Name="RuleText" ToolTip="반복할 일"/><ComboBox x:Name="RuleFrequency" Margin="0,8,0,8"><ComboBoxItem Content="매일" Tag="daily"/><ComboBoxItem Content="평일" Tag="weekdays"/><ComboBoxItem Content="매주" Tag="weekly"/><ComboBoxItem Content="매월" Tag="monthly"/></ComboBox><TextBlock Text="매주는 요일을, 매월은 날짜를 정하세요." FontSize="11" TextWrapping="Wrap"/><ComboBox x:Name="RuleWeekDay" Visibility="Collapsed" Margin="0,8,0,8"><ComboBoxItem Content="월요일" Tag="1"/><ComboBoxItem Content="화요일" Tag="2"/><ComboBoxItem Content="수요일" Tag="3"/><ComboBoxItem Content="목요일" Tag="4"/><ComboBoxItem Content="금요일" Tag="5"/><ComboBoxItem Content="토요일" Tag="6"/><ComboBoxItem Content="일요일" Tag="0"/></ComboBox><TextBox x:Name="RuleDay" Visibility="Collapsed" Text="1" Width="80" HorizontalAlignment="Left" Margin="0,8,0,8"/><TextBlock Text="시작일 (YYYY-MM-DD)" FontSize="11"/><TextBox x:Name="RuleStart" Margin="0,8,0,8"/><Button x:Name="RuleAdd" Content="반복 할 일 추가" HorizontalAlignment="Left"/><ComboBox x:Name="RuleChoice" Margin="0,12,0,8"/><WrapPanel><Button x:Name="RuleToggle" Content="선택한 반복 켜기·끄기"/><Button x:Name="RuleDelete" Content="반복 삭제"/></WrapPanel><TextBlock x:Name="RuleStatus" FontSize="11" TextWrapping="Wrap" Margin="0,8,0,20"/>
 <TextBlock Text="상황별 배치" FontSize="17" Margin="0,0,0,10"/><ComboBox x:Name="SituationName" IsEditable="True"><ComboBoxItem Content="공부"/><ComboBoxItem Content="휴식"/><ComboBoxItem Content="수업"/></ComboBox><WrapPanel Margin="0,10,0,0"><Button x:Name="SituationSave" Content="현재 배치를 이 이름으로 저장"/><Button x:Name="SituationApply" Content="전환"/></WrapPanel><WrapPanel Margin="0,8,0,0"><Button x:Name="Study" Content="공부"/><Button x:Name="Rest" Content="휴식"/><Button x:Name="ClassMode" Content="수업"/><Button x:Name="SituationUndo" Content="직전 배치로"/></WrapPanel><TextBlock x:Name="SituationStatus" Text="각 상황의 배치를 먼저 저장하세요. 기존 나의 배치와 함께 관리됩니다." FontSize="11" TextWrapping="Wrap" Margin="0,8,0,20"/>
 <TextBlock Text="시간표와 돌아보기" FontSize="17" Margin="0,0,0,10"/><WrapPanel><Button x:Name="TimetableSetup" Content="시간표 만들기"/><Button x:Name="TimetableShow" Content="시간표 위젯 표시"/><Button x:Name="ReviewOpen" Content="주간 돌아보기"/></WrapPanel><TextBlock Text="매주 반복하는 직접 입력 시간표 · 주말은 수업이 있는 요일만 표시합니다." FontSize="11" TextWrapping="Wrap" Margin="0,8,0,20"/>
 <TextBlock Text="앱과 업데이트" FontSize="17" Margin="0,0,0,10"/><CheckBox x:Name="Startup" Content="컴퓨터 시작 시 Daylight 자동 실행"/><TextBlock x:Name="StartupStatus" Text="현재 사용자 계정 · 설정을 켜면 다음 로그인부터 적용" FontSize="11" TextWrapping="Wrap" Margin="0,8,0,14"/><WrapPanel><Button x:Name="UpdateCheck" Content="새 버전 확인"/><Button x:Name="UpdateDownload" Content="다운로드·검증" IsEnabled="False"/><Button x:Name="UpdateInstall" Content="업데이트 후 재시작" IsEnabled="False"/></WrapPanel><TextBlock x:Name="UpdateStatus" Text="수동 확인 · 설치 전 파일 검증 · 개인 데이터 유지" FontSize="11" TextWrapping="Wrap" Margin="0,8,0,12"/><ComboBox x:Name="Backups" ToolTip="복원할 이전 버전"/><Button x:Name="Rollback" Content="선택한 이전 버전으로 복원·재시작" HorizontalAlignment="Left" Margin="0,8,0,0"/>
</StackPanel></Expander>
'@
[xml]$productXml=$productMarkup
$script:productPanel=[Windows.Markup.XamlReader]::Load((New-Object Xml.XmlNodeReader $productXml))
$settingsWindow.Content.Content.Children.Insert(2,$productPanel)
$script:productUI=@{}; foreach($name in @('HotkeyChoice','HotkeyEnabled','QuickOpen','HotkeyStatus','RuleText','RuleFrequency','RuleWeekDay','RuleDay','RuleStart','RuleAdd','RuleChoice','RuleToggle','RuleDelete','RuleStatus','SituationName','SituationSave','SituationApply','Study','Rest','ClassMode','SituationUndo','SituationStatus','TimetableSetup','TimetableShow','ReviewOpen','Startup','StartupStatus','UpdateCheck','UpdateDownload','UpdateInstall','UpdateStatus','Backups','Rollback')) {$productUI[$name]=$productPanel.FindName($name)}
function Refresh-TaskRules {
 $productUI.RuleChoice.Items.Clear()
 foreach($rule in @($state.taskRules)) {$item=New-Object Windows.Controls.ComboBoxItem; $prefix='진행 · '; if(-not $rule.enabled) {$prefix='중지 · '}; $item.Content=$prefix+$rule.text; $item.Tag=$rule.id; [void]$productUI.RuleChoice.Items.Add($item)}
 if($productUI.RuleChoice.Items.Count) {$productUI.RuleChoice.SelectedIndex=0}
}
$productUI.RuleWeekDay.SelectedIndex=0
$productUI.RuleFrequency.Add_SelectionChanged({$productUI.RuleWeekDay.Visibility='Collapsed'; $productUI.RuleDay.Visibility='Collapsed'; if($this.SelectedItem.Tag -eq 'weekly') {$productUI.RuleWeekDay.Visibility='Visible'}; if($this.SelectedItem.Tag -eq 'monthly') {$productUI.RuleDay.Visibility='Visible'}})
$productUI.RuleFrequency.SelectedIndex=0; $productUI.RuleStart.Text=(Get-FeatureNow).ToString('yyyy-MM-dd')
$productUI.RuleAdd.Add_Click({try {$day=0; if(-not [int]::TryParse($productUI.RuleDay.Text,[ref]$day)) {throw '요일 또는 날짜를 숫자로 입력하세요.'}; if($productUI.RuleFrequency.SelectedItem.Tag -eq 'weekly') {$day=[int]$productUI.RuleWeekDay.SelectedItem.Tag}; Add-TaskRule $productUI.RuleText.Text $productUI.RuleFrequency.SelectedItem.Tag $day $productUI.RuleStart.Text; Refresh-TaskRules; $productUI.RuleText.Clear(); $productUI.RuleStatus.Text='추가됨 · 앱 실행 시 오늘의 할 일을 생성합니다.'} catch {$productUI.RuleStatus.Text=$_.Exception.Message}})
$productUI.RuleToggle.Add_Click({if($productUI.RuleChoice.SelectedItem) {$id=$productUI.RuleChoice.SelectedItem.Tag; foreach($rule in $state.taskRules) {if($rule.id -eq $id) {$rule.enabled=-not $rule.enabled}}; Save-State; Update-RecurringTasks; Refresh-TaskRules}})
$productUI.RuleDelete.Add_Click({if($productUI.RuleChoice.SelectedItem) {$id=$productUI.RuleChoice.SelectedItem.Tag; $state.taskRules=@($state.taskRules|Where-Object {$_.id -ne $id}); Save-State; Refresh-TaskRules}})
$productUI.SituationName.SelectedIndex=0
$productUI.SituationSave.Add_Click({Save-LayoutProfile $productUI.SituationName.Text; $productUI.SituationStatus.Text=$featureUI.ProfileStatus.Text})
$productUI.SituationApply.Add_Click({try {Apply-Situation $productUI.SituationName.Text; $productUI.SituationStatus.Text='현재 · '+$state.activeSituation} catch {$productUI.SituationStatus.Text=$_.Exception.Message}})
foreach($pair in @(@('Study','공부'),@('Rest','휴식'),@('ClassMode','수업'))) {$productUI[$pair[0]].Tag=$pair[1]; $productUI[$pair[0]].Add_Click({try {Apply-Situation $this.Tag; $productUI.SituationStatus.Text='현재 · '+$state.activeSituation} catch {$productUI.SituationStatus.Text=$_.Exception.Message}})}
$productUI.SituationUndo.Add_Click({if($script:focusSession) {$productUI.SituationStatus.Text='집중을 마친 뒤 전환하세요.'; return}; if($state.situationRestore) {$current=Get-LayoutSnapshot; Restore-LayoutSnapshot $state.situationRestore; $state.situationRestore=$current; $state.activeSituation='직전 배치'; Save-State}})
$productUI.TimetableSetup.Add_Click({Show-TimetableEditor})
$productUI.TimetableShow.Add_Click({Set-WidgetVisible 'timetable' $true})
$script:quickWindow=$null; $script:reviewWindow=$null; $script:quickHotkey=$null
if(-not $state.ContainsKey('hotkeyEnabled')) {$state.hotkeyEnabled=$true}
function Show-QuickEntry {
 if($script:quickWindow) {$quickWindow.Show(); [void]$quickWindow.Activate(); return}
 $script:quickWindow=New-DaylightWindow @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="Daylight 빠른 입력" Width="440" Height="300" MinWidth="360" MinHeight="260" Background="#192235" Foreground="#E9EDF5" FontFamily="Malgun Gothic" ShowInTaskbar="False" WindowStartupLocation="CenterScreen"><Window.Resources>__THEME__</Window.Resources><Grid Margin="24"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition/><RowDefinition Height="Auto"/></Grid.RowDefinitions><ComboBox x:Name="QuickKind" SelectedIndex="0"><ComboBoxItem Content="할 일" Tag="task"/><ComboBoxItem Content="메모" Tag="memo"/></ComboBox><TextBox x:Name="QuickText" Grid.Row="1" Margin="0,14,0,12" AcceptsReturn="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto"/><Grid Grid.Row="2"><TextBlock x:Name="QuickStatus" Text="Ctrl+Enter 저장 · Esc 닫기" FontSize="11" VerticalAlignment="Center"/><Button x:Name="QuickSave" Content="저장" HorizontalAlignment="Right"/></Grid></Grid></Window>
'@
 $quickWindow.FindName('QuickSave').Add_Click({try {Save-QuickEntry $script:quickWindow.FindName('QuickText').Text $script:quickWindow.FindName('QuickKind').SelectedItem.Tag; $script:quickWindow.FindName('QuickText').Clear(); $script:quickWindow.Hide()} catch {$script:quickWindow.FindName('QuickStatus').Text=$_.Exception.Message}})
 $quickWindow.Add_PreviewKeyDown({if($_.Key -eq 'Escape') {$script:quickWindow.Hide(); $_.Handled=$true} elseif($_.Key -eq 'Enter' -and [Windows.Input.Keyboard]::Modifiers -band [Windows.Input.ModifierKeys]::Control) {$button=$script:quickWindow.FindName('QuickSave'); $button.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Button]::ClickEvent))); $_.Handled=$true}})
 $quickWindow.Add_Closing({if(-not $script:closingAll) {$_.Cancel=$true; $script:quickWindow.Hide()}})
 if(-not $SelfTest) {$quickWindow.Show(); [void]$quickWindow.Activate(); [void]$quickWindow.FindName('QuickText').Focus()}
}
if(-not $state.hotkeyChoice) {$state.hotkeyChoice='ctrlaltspace'}
$script:hotkeyChanging=$false
function Set-QuickHotkey {
 if($script:quickHotkey) {$script:quickHotkey.Dispose(); $script:quickHotkey=$null}
 if(-not $state.hotkeyEnabled -or $SelfTest) {$productUI.HotkeyStatus.Text='빠른 입력 버튼으로도 열 수 있습니다.'; return}
 if(-not ('DaylightQuickHotkey' -as [type])) {Add-Type -Path (Join-Path $PSScriptRoot 'QuickInput.cs') -ReferencedAssemblies @([Windows.Interop.HwndSource].Assembly.Location,[Windows.DependencyObject].Assembly.Location,'System.dll')}
 $handle=(New-Object Windows.Interop.WindowInteropHelper $window).EnsureHandle()
  $modifiers=0x4003; $key=0x20; if($state.hotkeyChoice -eq 'ctrlaltq') {$key=0x51}; if($state.hotkeyChoice -eq 'ctrlshiftspace') {$modifiers=0x4006}
 $script:quickHotkey=New-Object DaylightQuickHotkey $handle,([uint32]$modifiers),([uint32]$key)
 if(-not $quickHotkey.Registered -and $state.hotkeyChoice -eq 'ctrlaltspace') {
  $quickHotkey.Dispose(); $script:quickHotkey=New-Object DaylightQuickHotkey $handle,([uint32]0x4003),([uint32]0x51)
  if($quickHotkey.Registered) {$state.hotkeyChoice='ctrlaltq'; $script:hotkeyChanging=$true; try {$productUI.HotkeyChoice.SelectedIndex=1} finally {$script:hotkeyChanging=$false}; Save-State}
 }
 $quickHotkey.Add_Triggered({Invoke-DaylightSafe 'quick-input' {Show-QuickEntry}})
 $productUI.HotkeyStatus.Text=[string]$productUI.HotkeyChoice.SelectedItem.Content+' · 할 일·메모 빠르게 저장'; if(-not $quickHotkey.Registered) {$productUI.HotkeyStatus.Text='단축키가 다른 앱에서 사용 중입니다. 빠른 입력 버튼을 이용하세요.'}
}
foreach($item in $productUI.HotkeyChoice.Items) {if($item.Tag -eq $state.hotkeyChoice) {$productUI.HotkeyChoice.SelectedItem=$item}}
$productUI.HotkeyChoice.Add_SelectionChanged({if(-not $script:hotkeyChanging -and $this.SelectedItem) {$state.hotkeyChoice=$this.SelectedItem.Tag; Set-QuickHotkey; Save-State}})
$productUI.HotkeyEnabled.IsChecked=[bool]$state.hotkeyEnabled
$productUI.HotkeyEnabled.Add_Click({$state.hotkeyEnabled=[bool]$this.IsChecked; Set-QuickHotkey; Save-State})
$productUI.QuickOpen.Add_Click({Show-QuickEntry})
function Render-WeeklyReview {
 $review=Get-WeeklyReview (Get-FeatureNow) $script:reviewOffset
 $reviewWindow.FindName('ReviewTitle').Text=$review.start.ToString('M월 d일')+'–'+$review.end.AddDays(-1).ToString('M월 d일')
 $reviewWindow.FindName('ReviewSummary').Text='완료한 할 일 '+$review.completed+'개'+"`n집중 "+$review.minutes+'분 · '+$review.sessions+'회'+"`n습관 체크 "+$review.habits+'회'
 $rows=$reviewWindow.FindName('ReviewRows'); $rows.Children.Clear()
 for($i=0;$i -lt 7;$i++) {$date=$review.start.AddDays($i); $count=@($review.tasks|Where-Object {([DateTime]::Parse($_.at)).Date -eq $date}).Count; $text=New-Object Windows.Controls.TextBlock; $text.Text=$date.ToString('ddd M/d',[Globalization.CultureInfo]::GetCultureInfo('ko-KR'))+' · 완료 '+$count+'개'; $text.Margin='0,6,0,6'; [void]$rows.Children.Add($text)}
 $foot=$reviewWindow.FindName('ReviewFoot'); $foot.Text='업데이트 이후 기록부터 집계합니다. 완료를 취소하면 기록에서도 제외됩니다.'
}
function Show-WeeklyReview {
 if($script:reviewWindow) {$script:reviewWindow.Close()}
 $script:reviewOffset=0
 $script:reviewWindow=New-DaylightWindow @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="주간 돌아보기" Width="430" Height="580" MinWidth="340" MinHeight="380" Background="#192235" Foreground="#E9EDF5" FontFamily="Malgun Gothic" ShowInTaskbar="False"><Window.Resources>__THEME__</Window.Resources><ScrollViewer VerticalScrollBarVisibility="Auto"><StackPanel Margin="24"><TextBlock Text="주간 돌아보기" FontSize="24"/><TextBlock x:Name="ReviewTitle" Margin="0,14,0,10"/><WrapPanel><Button x:Name="ReviewPrev" Content="이전 주"/><Button x:Name="ReviewNext" Content="다음 주"/></WrapPanel><TextBlock x:Name="ReviewSummary" FontSize="21" Margin="0,20,0,16"/><StackPanel x:Name="ReviewRows"/><TextBlock x:Name="ReviewFoot" TextWrapping="Wrap" FontSize="11" Margin="0,20,0,0"/></StackPanel></ScrollViewer></Window>
'@
 $reviewWindow.FindName('ReviewPrev').Add_Click({$script:reviewOffset--; Render-WeeklyReview})
 $reviewWindow.FindName('ReviewNext').Add_Click({if($script:reviewOffset -lt 0) {$script:reviewOffset++; Render-WeeklyReview}})
 Render-WeeklyReview; if(-not $SelfTest) {$reviewWindow.Show()}
}
$productUI.ReviewOpen.Add_Click({Show-WeeklyReview})
$script:lastProductivityDay=''
function Update-Productivity {
 $day=(Get-FeatureNow).ToString('yyyy-MM-dd')
 if($day -ne $script:lastProductivityDay) {Update-RecurringTasks; Render-Timetable; $script:lastProductivityDay=$day}
 Update-ClassCountdown; Receive-UpdateCheck
}
function Stop-Productivity {
 if($script:quickHotkey) {$script:quickHotkey.Dispose()}
 if($script:updateJob) {Remove-DaylightJob $script:updateJob; $script:updateJob=$null}
 foreach($window in @($script:quickWindow,$script:reviewWindow,$script:timetableEditor)) {if($window) {$window.Close()}}
}
Refresh-TaskRules; Set-QuickHotkey
