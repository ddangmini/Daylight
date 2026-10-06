function New-DaylightWindow([string]$Markup) {
    [xml]$xml=$Markup.Replace('__THEME__',[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Theme.xaml')))
    $created=[Windows.Markup.XamlReader]::Load((New-Object Xml.XmlNodeReader $xml)); Register-DaylightToolWindow $created; if($script:daylightIcon) {$created.Icon=$script:daylightIcon}; return $created
}
function New-Widget([string]$Key,[string]$Title,[double]$Width,[double]$Height,[string]$Body) {
    $markup=@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="Daylight __TITLE__" Width="__WIDTH__" Height="__HEIGHT__" MinWidth="260" MinHeight="200" WindowStyle="None" ResizeMode="NoResize" AllowsTransparency="True" Background="Transparent" FontFamily="Malgun Gothic" FontSize="14" ShowInTaskbar="False">
 <Window.Resources>__THEME__</Window.Resources>
 <Border x:Name="Surface" Background="#A6192235" CornerRadius="20" Padding="20" BorderThickness="1" BorderBrush="#18FFFFFF"><Grid>
  <Grid.RowDefinitions><RowDefinition Height="36"/><RowDefinition/><RowDefinition Height="24"/></Grid.RowDefinitions>
  <Grid x:Name="WidgetDrag" Background="Transparent"><StackPanel x:Name="WidgetTitle" Orientation="Horizontal" VerticalAlignment="Center"><Border x:Name="Accent" Background="#A3E8D2" Width="4" Height="14" CornerRadius="2" Margin="0,0,9,0"/><TextBlock Text="__TITLE__" FontSize="12" FontWeight="SemiBold"/></StackPanel><StackPanel x:Name="WidgetTools" Style="{StaticResource QuietTools}" Orientation="Horizontal" HorizontalAlignment="Right"><Button x:Name="WidgetPin" Content="◇" ToolTip="이 창 항상 위" Padding="7,3"/><Button x:Name="Appearance" Content="◐" ToolTip="이 창 꾸미기" Padding="7,3"/><Button x:Name="WidgetSettings" Content="⚙" ToolTip="설정" Padding="7,3"/><Button x:Name="WidgetClose" Content="×" ToolTip="이 창 숨기기" Padding="7,3"/></StackPanel></Grid>
  <Grid Grid.Row="1" Margin="0,10,0,0">__BODY__</Grid>
  <TextBlock x:Name="WidgetHint" Grid.Row="2" Text="드래그로 이동 · 모서리로 크기 조절" FontSize="9" VerticalAlignment="Bottom" Style="{StaticResource QuietLabel}"/>
  <Thumb x:Name="WidgetResize" Grid.RowSpan="3" Style="{StaticResource ResizeHandle}" HorizontalAlignment="Right" VerticalAlignment="Bottom"/>
 </Grid></Border>
</Window>
'@
    $surface=New-DaylightWindow ($markup.Replace('__TITLE__',$Title).Replace('__WIDTH__',$Width.ToString([Globalization.CultureInfo]::InvariantCulture)).Replace('__HEIGHT__',$Height.ToString([Globalization.CultureInfo]::InvariantCulture)).Replace('__BODY__',$Body))
    $surface.Tag=$Key
    return $surface
}
$scheduleBody=@'
<Grid><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition/><RowDefinition Height="Auto"/></Grid.RowDefinitions><TextBlock x:Name="CalendarSummary" FontSize="11" Margin="0,0,0,8"/><StackPanel x:Name="Agenda" Grid.Row="1"/><StackPanel Grid.Row="2" Orientation="Horizontal" HorizontalAlignment="Right" Style="{StaticResource QuietTools}"><Button x:Name="AgendaPrev" Content="‹"/><TextBlock x:Name="AgendaPage" VerticalAlignment="Center" Margin="8,0" FontSize="11"/><Button x:Name="AgendaNext" Content="›"/></StackPanel></Grid>
'@
$taskBody=@'
<Grid><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition/><RowDefinition Height="Auto"/></Grid.RowDefinitions><StackPanel Orientation="Horizontal" Margin="0,0,0,14"><Button x:Name="TaskLocal" Content="내 할 일"/><Button x:Name="TaskNotion" Content="노션" Margin="6,0,0,0"/><TextBlock x:Name="Progress" VerticalAlignment="Center" FontSize="11" Margin="12,0,0,0"/></StackPanel><Grid Grid.Row="1"><StackPanel x:Name="TasksPanel"><TextBlock x:Name="NotionSummary" FontSize="11" Margin="0,0,0,8"/><StackPanel x:Name="NotionTasks"/></StackPanel><StackPanel x:Name="LocalPanel"><StackPanel x:Name="Tasks"/><Grid x:Name="TaskEntry" Style="{StaticResource QuietEntry}" Margin="0,10,0,0"><Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><TextBox x:Name="TaskInput" ToolTip="할 일 입력 · Enter로 추가" Padding="8,6"/><Button x:Name="AddTask" Content="+" Grid.Column="1" Margin="6,0,0,0"/></Grid></StackPanel></Grid><Grid Grid.Row="2"><Button x:Name="ClearDone" Content="완료 정리" Style="{StaticResource QuietAction}" HorizontalAlignment="Left"/><StackPanel Style="{StaticResource QuietTools}" Orientation="Horizontal" HorizontalAlignment="Right"><Button x:Name="TasksPrev" Content="‹"/><TextBlock x:Name="TasksPage" VerticalAlignment="Center" Margin="8,0" FontSize="11"/><Button x:Name="TasksNext" Content="›"/></StackPanel></Grid></Grid>
'@
$memoBody=@'
<Grid><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition/><RowDefinition Height="Auto"/></Grid.RowDefinitions><DockPanel Margin="0,0,0,12"><StackPanel DockPanel.Dock="Right" Orientation="Horizontal" Style="{StaticResource QuietTools}"><Button x:Name="NoteNew" Content="+" ToolTip="새 메모"/><Button x:Name="NoteDelete" Content="−" ToolTip="현재 메모 삭제"/></StackPanel><ComboBox x:Name="NoteChoice" Style="{StaticResource QuietSelect}" ToolTip="메모 전환"/></DockPanel><Grid Grid.Row="1"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition/></Grid.RowDefinitions><TextBox x:Name="NoteTitle" Background="Transparent" BorderBrush="Transparent" FontWeight="SemiBold" FontSize="18" Padding="0,6" ToolTip="메모 제목"/><TextBox x:Name="Note" Grid.Row="1" Background="Transparent" BorderBrush="Transparent" Padding="0,10" AcceptsReturn="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Hidden"/></Grid><Grid Grid.Row="2"><TextBlock x:Name="NoteCount" FontSize="10" VerticalAlignment="Center"/><Button x:Name="NoteExport" Content="텍스트로 저장 ↗" HorizontalAlignment="Right" Style="{StaticResource QuietAction}"/></Grid></Grid>
'@
$clockBody=@'
<Viewbox Stretch="Uniform" HorizontalAlignment="Left"><StackPanel><TextBlock x:Name="Clock" Text="17:31" FontSize="68" FontWeight="Light"/><TextBlock x:Name="Date" FontSize="13"/></StackPanel></Viewbox>
'@
$weatherBody=@'
<Viewbox Stretch="Uniform" HorizontalAlignment="Left"><StackPanel><StackPanel Orientation="Horizontal"><TextBlock x:Name="WeatherIcon" Text="☀" FontFamily="Segoe UI Emoji, Segoe UI Symbol" FontSize="50" Foreground="#F9C866" VerticalAlignment="Center" Margin="0,0,18,0"/><TextBlock x:Name="Temperature" Text="—°" FontSize="64" FontWeight="Light"/></StackPanel><TextBlock x:Name="Conditions" Text="서울 · 조회 중" FontSize="15" Margin="0,6,0,0"/><TextBlock x:Name="WeatherCredit" Text="Open-Meteo ↗" FontSize="9" Cursor="Hand" Margin="0,8,0,0"/></StackPanel></Viewbox>
'@
$chatBody=@'
<Grid><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions><Grid><TextBlock x:Name="ChatStatus" Text="설정에서 API 키를 연결하세요" FontSize="11" TextWrapping="Wrap"/><Button x:Name="ChatClear" Content="새 대화" HorizontalAlignment="Right" Style="{StaticResource QuietAction}"/></Grid><TextBox x:Name="ChatHistory" Grid.Row="1" Margin="0,14,0,12" IsReadOnly="True" AcceptsReturn="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Hidden" Background="Transparent" BorderBrush="Transparent" Padding="0"/><TextBox x:Name="ChatInput" Grid.Row="2" AcceptsReturn="True" Height="76" TextWrapping="Wrap" VerticalScrollBarVisibility="Hidden" ToolTip="질문 입력 · Ctrl+Enter로 전송"/><StackPanel Grid.Row="3" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,8,0,0"><Button x:Name="ChatCopy" Content="답변 복사"/><Button x:Name="ChatCancel" Content="취소" IsEnabled="False"/><Button x:Name="ChatSend" Content="전송 ↗"/></StackPanel></Grid>
'@
$script:window=New-Widget 'main' '일정' 370 440 $scheduleBody
$window.ShowInTaskbar=$false
$script:tasksWindow=New-Widget 'tasks' '할 일' 390 470 $taskBody
$script:memoWindow=New-Widget 'memo' '메모' 370 350 $memoBody
$script:clockWindow=New-Widget 'clock' '시계' 320 225 $clockBody
$script:weatherWindow=New-Widget 'weather' '날씨' 340 265 $weatherBody
$script:chatWindow=New-Widget 'chat' 'Gemini' 470 560 $chatBody
$settingsMarkup = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="Daylight 설정" Width="500" Height="730" MinWidth="420" MinHeight="430" Background="#192235" Foreground="#E9EDF5" FontFamily="Malgun Gothic" WindowStartupLocation="CenterOwner">
 <Window.Resources>__THEME__</Window.Resources>
 <ScrollViewer VerticalScrollBarVisibility="Auto"><StackPanel Margin="26">
  <TextBlock Text="설정" FontSize="24" FontWeight="SemiBold" Margin="0,0,0,24"/>
  <Border TextElement.Foreground="#E9EDF5" Background="#111A2B" CornerRadius="12" Padding="16" Margin="0,0,0,18"><StackPanel>
   <TextBlock Text="표시할 위젯" FontSize="17" FontWeight="SemiBold" Margin="0,0,0,6"/>
   <TextBlock Text="체크한 위젯만 바탕화면에 표시합니다." Foreground="#B8C5D8" FontSize="12" Margin="0,0,0,16"/>
   <TextBlock Text="기본 위젯" Foreground="#A3E8D2" FontSize="12" Margin="0,0,0,12"/>
   <CheckBox x:Name="ShowMain" Content="일정" Margin="0,0,0,12"/><CheckBox x:Name="ShowTasks" Content="할 일" Margin="0,0,0,12"/><CheckBox x:Name="ShowMemo" Content="메모" Margin="0,0,0,12"/><CheckBox x:Name="ShowChat" Content="Gemini 대화" Margin="0,0,0,12"/><CheckBox x:Name="ShowClock" Content="시계" Margin="0,0,0,12"/><CheckBox x:Name="ShowWeather" Content="날씨" Margin="0,0,0,12"/>
   <StackPanel x:Name="ExtraWidgetVisibility"/>
  </StackPanel></Border>
  <Border TextElement.Foreground="#E9EDF5" Background="#111A2B" CornerRadius="12" Padding="16" Margin="0,0,0,8"><StackPanel>
   <TextBlock Text="창 동작 · 잠금" FontSize="17" FontWeight="SemiBold" Margin="0,0,0,6"/>
   <TextBlock Text="전체 위젯의 크기와 이동 방식을 설정합니다." Foreground="#B8C5D8" FontSize="12" TextWrapping="Wrap" Margin="0,0,0,16"/>
   <CheckBox x:Name="AutoLayout" Content="창 크기에 맞춰 표시 개수 자동 조절" Margin="0,0,0,12"/><CheckBox x:Name="LockRatio" Content="크기 조절할 때 현재 화면비 유지" Margin="0,0,0,12"/><CheckBox x:Name="LockAllWidgets" Content="모든 창 이동·크기 잠금" Margin="0,0,0,12"/><CheckBox x:Name="DesktopAllWidgets" Content="모든 창 바탕화면에 붙이기" Margin="0,0,0,12"/>
  <WrapPanel><Button x:Name="Grow" Content="화면 확대 +"/><Button x:Name="Shrink" Content="화면 축소 −"/><Button x:Name="ResetLayout" Content="위치·크기 초기화"/></WrapPanel>
  <WrapPanel Margin="0,12,0,0"><Button x:Name="Pin" Content="선택한 창 항상 위"/><Button x:Name="TextTone" Content="선택한 창 꾸미기"/></WrapPanel>
  </StackPanel></Border>
 <TextBlock Text="창별 꾸미기" FontSize="16" FontWeight="SemiBold" Margin="0,24,0,12"/>
 <ComboBox x:Name="StyleTarget"><ComboBoxItem Content="일정" Tag="main"/><ComboBoxItem Content="할 일" Tag="tasks"/><ComboBoxItem Content="메모" Tag="memo"/><ComboBoxItem Content="시계" Tag="clock"/><ComboBoxItem Content="날씨" Tag="weather"/><ComboBoxItem Content="Gemini" Tag="chat"/></ComboBox>
 <TextBlock Text="위젯에 마우스를 올린 뒤 ◐ 버튼으로 배경 투명도·글자 색·강조 색을 바꿀 수 있습니다." TextWrapping="Wrap" FontSize="11" Margin="0,8,0,0"/>
 <TextBlock Text="Gemini · 무료 프로젝트" FontSize="16" FontWeight="SemiBold" Margin="0,24,0,12"/>
 <TextBlock Text="AI Studio에서 이 키의 프로젝트가 Free Tier인지 확인하세요. 유료 프로젝트 키는 과금될 수 있습니다. 앱은 결제 전환·자동 재시도 없이 전송한 대화만 보냅니다." TextWrapping="Wrap" FontSize="11" Margin="0,0,0,10"/>
 <PasswordBox x:Name="GPTKey" ToolTip="Gemini API 키 · 기존 키 유지 시 비워두세요" Padding="10" Background="#111A2B" Foreground="#E9EDF5"/>
 <TextBox x:Name="GPTModel" Text="gemini-3.5-flash-lite" Margin="0,8,0,0" ToolTip="권장: gemini-3.5-flash-lite · 이전 2.5 모델은 신규 계정에서 거절될 수 있습니다."/>
 <CheckBox x:Name="GeminiFreeTier" Content="AI Studio에서 이 프로젝트의 Free Tier를 확인했습니다" Margin="0,12,0,0"/><WrapPanel Margin="0,8,0,0"><Button x:Name="GPTSave" Content="연결 저장"/><Button x:Name="GPTDisconnect" Content="연결 해제"/><Button x:Name="GPTHelp" Content="키·무료 등급 확인 ↗"/></WrapPanel>
 <Button x:Name="GeminiQuota" Content="사용 한도 안내 ↗" HorizontalAlignment="Left" Margin="0,6,0,0"/><TextBlock x:Name="GPTStatus" Text="연결 안 됨" TextWrapping="Wrap" FontSize="11" Margin="0,8,0,0"/>
  <TextBlock Text="Google Calendar" FontSize="16" FontWeight="SemiBold" Margin="0,28,0,12"/>
  <WrapPanel><Button x:Name="CalendarConnect" Content="구글 연결"/><Button x:Name="CalendarRefresh" Content="새로고침"/><Button x:Name="CalendarDisconnect" Content="연결 해제"/><Button x:Name="CalendarCancel" Content="취소" Visibility="Collapsed"/></WrapPanel>
  <ComboBox x:Name="CalendarChoice" IsEnabled="False" Margin="0,12,0,0"/>
  <TextBlock x:Name="CalendarStatus" Text="연결 안 됨" Foreground="#99A7BE" FontSize="11" TextWrapping="Wrap" Margin="0,10,0,8"/>
  <WrapPanel><Button x:Name="CalendarHelp" Content="연결 안내 ↗"/><Button x:Name="CalendarSettings" Content="설정 파일 변경"/></WrapPanel>
  <TextBlock Text="Notion" FontSize="16" FontWeight="SemiBold" Margin="0,28,0,12"/>
  <WrapPanel><Button x:Name="NotionConnect" Content="연결 설정"/><Button x:Name="NotionRefresh" Content="새로고침"/><Button x:Name="NotionDisconnect" Content="연결 해제"/><Button x:Name="NotionHelp" Content="연결 안내 ↗"/></WrapPanel>
  <TextBlock x:Name="NotionStatus" Text="연결 안 됨" Foreground="#99A7BE" FontSize="11" TextWrapping="Wrap" Margin="0,10,0,0"/>
  <TextBlock Text="날씨 지역" FontSize="16" FontWeight="SemiBold" Margin="0,28,0,12"/>
  <Grid><Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><TextBox x:Name="WeatherCityInput" Text="서울"/><Button x:Name="WeatherSearch" Content="지역 검색" Grid.Column="1" Margin="8,0,0,0"/></Grid>
  <ComboBox x:Name="WeatherChoice" Margin="0,10,0,0" ToolTip="검색 결과에서 지역을 선택하세요"/>
  <TextBlock x:Name="WeatherStatus" Text="서울 · 15분마다 갱신" Foreground="#99A7BE" FontSize="11" TextWrapping="Wrap" Margin="0,10,0,8"/><Button x:Name="WeatherRefresh" Content="날씨 새로고침" HorizontalAlignment="Left"/>
  <TextBlock Text="서비스 열기" FontSize="16" FontWeight="SemiBold" Margin="0,28,0,12"/><WrapPanel><Button x:Name="GPT" Content="Gemini 대화 열기"/><Button x:Name="Calendar" Content="캘린더 ↗"/><Button x:Name="Notion" Content="Notion ↗"/></WrapPanel>
  <TextBlock Text="Daylight 0.10.0 · 바탕화면 위젯" Foreground="#8593AA" FontSize="10" Margin="0,28,0,0"/>
 <Button x:Name="Quit" Content="Daylight 종료" HorizontalAlignment="Left" Margin="0,16,0,0"/></StackPanel></ScrollViewer>
</Window>
'@
$script:settingsWindow=New-DaylightWindow $settingsMarkup
$script:widgets=@{ main=$window;tasks=$tasksWindow;memo=$memoWindow;clock=$clockWindow;weather=$weatherWindow;chat=$chatWindow }
. (Join-Path $PSScriptRoot 'ExtraShell.ps1')
$script:ui=@{}
foreach($surface in @($widgets.Values)+@($settingsWindow)) {
    $queue=New-Object 'Collections.Generic.Queue[Windows.DependencyObject]'; $queue.Enqueue($surface)
    while($queue.Count) { $element=$queue.Dequeue(); if($element -is [Windows.FrameworkElement] -and $element.Name) { $ui[$element.Name]=$element }; foreach($child in [Windows.LogicalTreeHelper]::GetChildren($element)) { if($child -is [Windows.DependencyObject]) {$queue.Enqueue($child)} } }
}
$ui.DragBar=$window.FindName('WidgetDrag'); $ui.MainTools=$window.FindName('WidgetTools'); $ui.Close=$window.FindName('WidgetClose'); $ui.Settings=$window.FindName('WidgetSettings'); $ui.ResizeMain=$window.FindName('WidgetResize')
$ui.Status=$memoWindow.FindName('WidgetHint'); $ui.Mode=New-Object Windows.Controls.Button; $ui.Expanded=$memoWindow.Content
