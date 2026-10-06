if(-not ('DaylightYouTubeServer' -as [type])) {Add-Type -Path (Join-Path $PSScriptRoot 'YouTubeHost.cs')}
$script:youtubeServer=$null; $script:youtubeEmbedded=$null
$script:youtubeProfile=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Daylight\YouTubeProfile'
$script:youtubeEmbeddedProfile=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Daylight\YouTubeEmbeddedProfile'
if(-not $state.youtube) {$state.youtube=@{url='';volume=70;geometry=$null}}
elseif($state.youtube -isnot [hashtable]) {$map=@{}; foreach($p in $state.youtube.PSObject.Properties) {$map[$p.Name]=$p.Value}; $state.youtube=$map}
$ui.YouTubeUrl.Text=[string]$state.youtube.url
$ui.YouTubeVolume.Value=[Math]::Max(0,[Math]::Min(100,[double]$state.youtube.volume))
$script:youtubeSdkError=$null
try {
 $core=Join-Path $PSScriptRoot 'Microsoft.Web.WebView2.Core.dll'; $wpf=Join-Path $PSScriptRoot 'Microsoft.Web.WebView2.Wpf.dll'
 [void][Reflection.Assembly]::LoadFrom($core); [void][Reflection.Assembly]::LoadFrom($wpf)
 $refs=@($core,$wpf,[Windows.Window].Assembly.Location,[Windows.Media.Brush].Assembly.Location,[Windows.DependencyObject].Assembly.Location,'System.dll','System.Core.dll','System.Drawing.dll','System.Xaml.dll')
 if(-not ('DaylightEmbeddedYouTube' -as [type])) {Add-Type -Path (Join-Path $PSScriptRoot 'YouTubeEmbedded.cs') -ReferencedAssemblies $refs}
} catch {$script:youtubeSdkError='내장 플레이어 구성 요소가 없습니다. 패치를 다시 적용하세요.'; Write-DaylightDiagnostic 'youtube-sdk' $_}
$youtubeSettingsMarkup=@'
<Expander xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Header="YouTube · 계정과 재생" Foreground="#E9EDF5" FontSize="16" Margin="0,8,0,8"><StackPanel Margin="0,12,0,8" TextElement.Foreground="#E9EDF5">
 <TextBlock Text="영상·재생목록 링크를 넣으면 Daylight 안에서 바로 재생됩니다." FontSize="12" TextWrapping="Wrap" Margin="0,0,0,12"/>
 <WrapPanel><Button x:Name="YouTubeSettingsLogin" Content="Premium · 공식 사이트 ↗"/><Button x:Name="YouTubeSettingsShow" Content="위젯 표시"/></WrapPanel>
 <TextBlock Text="내장 플레이어는 브라우저 로그인 상태를 공유하지 않습니다. Premium 광고 제거가 필요하면 공식 사이트에서 재생하세요." FontSize="12" TextWrapping="Wrap" Foreground="#B8C5D8" Margin="0,12,0,8"/>
 <TextBlock Text="내장 재생을 허용하지 않는 영상은 공식 사이트 버튼을 사용하세요." FontSize="12" TextWrapping="Wrap" Foreground="#B8C5D8"/>
 <Button x:Name="YouTubeOfficial" Content="현재 링크를 공식 사이트에서 열기 ↗" HorizontalAlignment="Left" Margin="0,12,0,0"/>
</StackPanel></Expander>
'@
[xml]$youtubeSettingsXml=$youtubeSettingsMarkup
$script:youtubeSettings=[Windows.Markup.XamlReader]::Load((New-Object Xml.XmlNodeReader $youtubeSettingsXml))
$extraSettings.Children.Insert(1,$youtubeSettings)
function Resolve-YouTubeLink([string]$Text) {
    $Text=$Text.Trim()
    if($Text -match '^[A-Za-z0-9_-]{11}$') {return @{video=$Text;list='';url='https://www.youtube.com/watch?v='+$Text}}
    $uri=$null; if(-not [Uri]::TryCreate($Text,[UriKind]::Absolute,[ref]$uri) -or $uri.Scheme -ne 'https' -or $uri.UserInfo -or -not $uri.IsDefaultPort) {throw 'https://로 시작하는 YouTube 영상·재생목록 링크를 넣어주세요.'}
    if($uri.DnsSafeHost -notin @('youtube.com','www.youtube.com','m.youtube.com','music.youtube.com','youtu.be')) {throw 'YouTube 링크만 사용할 수 있습니다.'}
    $video=''; $list=''; $query=@{}
    foreach($part in $uri.Query.TrimStart('?').Split('&')) {$pair=($part -split '=',2); if($pair.Length -eq 2) {$query[$pair[0]]=[Uri]::UnescapeDataString($pair[1])}}
    if($uri.DnsSafeHost -eq 'youtu.be') {$video=$uri.AbsolutePath.Trim('/')}
    elseif($uri.AbsolutePath -eq '/watch') {$video=[string]$query.v}
    elseif($uri.AbsolutePath -match '^/(shorts|live|embed)/([A-Za-z0-9_-]{11})/?$') {$video=$Matches[2]}
    elseif($uri.AbsolutePath -ne '/playlist') {throw '영상 또는 재생목록 링크를 넣어주세요.'}
    $list=[string]$query.list
    if(($video -and $video -notmatch '^[A-Za-z0-9_-]{11}$') -or ($list -and $list -notmatch '^[A-Za-z0-9_-]{10,150}$') -or (-not $video -and -not $list)) {throw '영상 ID 또는 재생목록 ID가 올바르지 않습니다.'}
    $url='https://www.youtube.com/playlist?list='+$list
    if($video) {$url='https://www.youtube.com/watch?v='+$video; if($list) {$url+='&list='+$list}}
    return @{video=$video;list=$list;url=$url}
}
function Get-DaylightEdge {
    foreach($folder in @(${env:ProgramFiles(x86)},$env:ProgramFiles,$env:LOCALAPPDATA)) {if($folder) {$path=Join-Path $folder 'Microsoft\Edge\Application\msedge.exe'; if(Test-Path -LiteralPath $path) {return $path}}}
    throw 'Microsoft Edge가 필요합니다. Edge를 설치한 뒤 다시 열어주세요.'
}
function Open-YouTubeProfile([string]$Url='https://www.youtube.com/') {
    try {
        $edge=Get-DaylightEdge; [void][IO.Directory]::CreateDirectory($script:youtubeProfile)
        $arguments='--user-data-dir="'+$script:youtubeProfile+'" --no-first-run --no-default-browser-check --new-window "'+$Url+'"'
        Start-Process -FilePath $edge -ArgumentList $arguments
    } catch {Write-DaylightDiagnostic 'youtube-login' $_; $ui.YouTubeStatus.Text='YouTube 브라우저를 열지 못했습니다. Edge 설치 상태를 확인하세요.'}
}
function Send-YouTubeCommand([string]$Action,$Value=$null) {
 if(-not $script:youtubeServer) {return}
 $command=@{action=$Action}; if($null -ne $Value) {$command.value=$Value}
 $script:youtubeServer.Enqueue(($command|ConvertTo-Json -Compress))
}
function Close-YouTubePlayer {Send-YouTubeCommand 'pause'}
function Open-YouTubePlayer([string]$QueueId='') {
 try {
  if($script:youtubeSdkError) {throw $script:youtubeSdkError}
  $link=Resolve-YouTubeLink $ui.YouTubeUrl.Text
  if($script:youtubeEmbedded -and $script:youtubeEmbedded.Error) {Stop-YouTubeWork}
  if(-not $script:youtubeServer) {$script:youtubeServer=New-Object DaylightYouTubeServer ([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'YouTubePlayer.html')))}
  if(-not $script:youtubeEmbedded) {
   $script:youtubeEmbedded=New-Object DaylightEmbeddedYouTube $PSScriptRoot
   [void]$ui.YouTubeViewHost.Children.Add($script:youtubeEmbedded.View)
   $ui.YouTubePlaceholder.Visibility='Collapsed'
   $script:youtubeEmbedded.Start($script:youtubeServer.Url,$script:youtubeEmbeddedProfile)
  }
  $state.youtube.url=$link.url; $ui.YouTubeUrl.Text=$link.url; Save-State
  $script:youtubeQueuePlaying=$QueueId; $script:youtubeLoadToken=[guid]::NewGuid().ToString('N'); $script:youtubeEndedToken=''
  $script:youtubeServer.Enqueue((@{action='load';video=$link.video;list=$link.list;token=$script:youtubeLoadToken}|ConvertTo-Json -Compress))
  Send-YouTubeCommand 'volume' ([int]$ui.YouTubeVolume.Value)
  $ui.YouTubeStatus.Text='영상 불러오는 중 · 처음에는 영상의 재생 버튼을 눌러주세요.'; Render-YouTubeQueue
 } catch {Write-DaylightDiagnostic 'youtube-embed' $_; $ui.YouTubeStatus.Text=$_.Exception.Message}
}
function Update-YouTubePlayer {
 if($SelfTest -or -not $script:youtubeEmbedded) {return}
 if(-not $state.youtubeVisible -or -not $widgets.youtube.IsVisible) {Close-YouTubePlayer; return}
 if($script:youtubeEmbedded.Error) {$ui.YouTubeStatus.Text=$script:youtubeEmbedded.Error; return}
 try {
  $info=$script:youtubeServer.StateJson|ConvertFrom-Json
  Receive-YouTubeQueueState $info
  foreach($name in @('YouTubeToggle','YouTubePrevious','YouTubeNext')) {$ui[$name].IsEnabled=[bool]$info.ready}
  $ui.YouTubeToggle.Content='▶'; if($info.playing) {$ui.YouTubeToggle.Content='❚❚'}
  if($info.error) {$ui.YouTubeStatus.Text=[string]$info.error} elseif($info.title) {$ui.YouTubeStatus.Text=[string]$info.title} elseif($info.ready) {$ui.YouTubeStatus.Text='재생 준비 완료 · 영상의 재생 버튼을 눌러주세요.'}
 } catch {Write-DaylightDiagnostic 'youtube-state' $_}
}
function Stop-YouTubeWork {
 if($script:youtubeQueueWindow -and $script:closingAll) {$script:youtubeQueueWindow.Close(); $script:youtubeQueueWindow=$null}
 $script:youtubeQueuePlaying=''; $script:youtubeLoadToken=''; $script:youtubeEndedToken=''
 if($script:youtubeEmbedded) {[void]$ui.YouTubeViewHost.Children.Remove($script:youtubeEmbedded.View); $script:youtubeEmbedded.Dispose(); $script:youtubeEmbedded=$null}
 if($script:youtubeServer) {$script:youtubeServer.Dispose(); $script:youtubeServer=$null}
 $ui.YouTubePlaceholder.Visibility='Visible'
}
$ui.YouTubeOpen.Add_Click({Open-YouTubePlayer})
$ui.YouTubeUrl.Add_KeyDown({if($_.Key -eq 'Enter') {Open-YouTubePlayer; $_.Handled=$true}})
$ui.YouTubeToggle.Add_Click({Send-YouTubeCommand 'toggle'})
$ui.YouTubePrevious.Add_Click({if($script:youtubeQueuePlaying) {Move-YouTubeQueuePlayback -1} else {Send-YouTubeCommand 'previous'}})
$ui.YouTubeNext.Add_Click({if($script:youtubeQueuePlaying) {Move-YouTubeQueuePlayback 1} else {Send-YouTubeCommand 'next'}})
$ui.YouTubeLogin.Add_Click({try {$link=Resolve-YouTubeLink $ui.YouTubeUrl.Text; Open-YouTubeProfile $link.url} catch {$ui.YouTubeStatus.Text=$_.Exception.Message}})
$ui.YouTubeVolume.Add_ValueChanged({$state.youtube.volume=[int]$this.Value; Send-YouTubeCommand 'volume' ([int]$this.Value); Save-State})
$youtubeSettings.FindName('YouTubeSettingsLogin').Add_Click({Open-YouTubeProfile})
$youtubeSettings.FindName('YouTubeSettingsShow').Add_Click({Set-WidgetVisible 'youtube' $true})
$youtubeSettings.FindName('YouTubeOfficial').Add_Click({try {$link=Resolve-YouTubeLink $ui.YouTubeUrl.Text; Open-YouTubeProfile $link.url} catch {$ui.YouTubeStatus.Text=$_.Exception.Message; Set-WidgetVisible 'youtube' $true}})
foreach($name in @('YouTubeToggle','YouTubePrevious','YouTubeNext')) {$ui[$name].IsEnabled=$false}
# Keep a 16:9 video viewport as the window is resized, without enlarging controls.
$ui.YouTubeFrame.Add_SizeChanged({$frame=$ui.YouTubeFrame; $w=[Math]::Max(200,$frame.ActualWidth); $h=[Math]::Max(200,$frame.ActualHeight); $viewWidth=[Math]::Min($w,$h*16/9); $viewHeight=[Math]::Max(200,$viewWidth*9/16); $ui.YouTubeViewHost.Width=$viewWidth; $ui.YouTubeViewHost.Height=$viewHeight; $ui.YouTubeViewHost.HorizontalAlignment='Center'; $ui.YouTubeViewHost.VerticalAlignment='Center'; $ui.YouTubeViewHost.Clip=New-Object Windows.Media.RectangleGeometry (New-Object Windows.Rect 0,0,$viewWidth,$viewHeight),14,14})
$state.youtube.queue=@($state.youtube.queue|Where-Object {$null -ne $_})
$script:youtubeQueuePlaying=''; $script:youtubeLoadToken=''; $script:youtubeEndedToken=''; $script:youtubeQueueWindow=$null
function Add-YouTubeQueue([string]$Text) {
 $new=@()
 foreach($line in @($Text -split '\r?\n'|Where-Object {$_.Trim()})) {
  $link=Resolve-YouTubeLink $line
  if(-not $link.video) {throw '대기열에는 개별 영상 링크를 넣어주세요. 재생목록은 위젯의 재생 버튼을 사용하세요.'}
  $new+=@{id=[guid]::NewGuid().ToString('N');video=$link.video;url=('https://www.youtube.com/watch?v='+$link.video);title=('영상 · '+$link.video)}
 }
 if(-not $new.Count) {throw '영상 링크를 한 줄에 하나씩 넣어주세요.'}
 if(@($state.youtube.queue).Count+$new.Count -gt 200) {throw '대기열은 최대 200개까지 추가할 수 있습니다.'}
 $state.youtube.queue=@($state.youtube.queue)+$new; Save-State; Render-YouTubeQueue
}
function Get-YouTubeQueueNext([string]$Id,[int]$Direction=1) {
 $items=@($state.youtube.queue)
 for($i=0;$i -lt $items.Count;$i++) {if($items[$i].id -eq $Id) {$next=$i+$Direction; if($next -ge 0 -and $next -lt $items.Count) {return $items[$next]}; return $null}}
 return $null
}
function Play-YouTubeQueue([string]$Id) {
 $item=$state.youtube.queue|Where-Object {$_.id -eq $Id}|Select-Object -First 1
 if(-not $item) {return}
 Set-WidgetVisible 'youtube' $true; $ui.YouTubeUrl.Text=$item.url; Open-YouTubePlayer $Id; Render-YouTubeQueue
}
function Move-YouTubeQueuePlayback([int]$Direction) {
 $next=Get-YouTubeQueueNext $script:youtubeQueuePlaying $Direction
 if($next) {Play-YouTubeQueue $next.id} elseif($Direction -gt 0) {$ui.YouTubeStatus.Text='대기열의 마지막 영상입니다.'}
}
function Receive-YouTubeQueueState($Info) {
 if(-not $script:youtubeQueuePlaying -or $Info.token -ne $script:youtubeLoadToken -or -not $script:youtubeLoadToken) {return}
 $item=$state.youtube.queue|Where-Object {$_.id -eq $script:youtubeQueuePlaying}|Select-Object -First 1
 if($Info.title -and $Info.url -and $item -and $Info.url -match ('[?&]v='+[regex]::Escape($item.video)+'(?:&|$)') -and $item.title -ne $Info.title) {Set-DaylightProperty $item 'title' ([string]$Info.title); Save-State; Render-YouTubeQueue}
 if($Info.endedToken -eq $script:youtubeLoadToken -and $script:youtubeEndedToken -ne $Info.endedToken) {
  $script:youtubeEndedToken=$Info.endedToken
  Move-YouTubeQueuePlayback 1
 }
}
function Edit-YouTubeQueue([string]$Id,[string]$Action) {
 $items=@($state.youtube.queue); $index=-1
 for($i=0;$i -lt $items.Count;$i++) {if($items[$i].id -eq $Id) {$index=$i; break}}
 if($index -lt 0) {return}
 if($Action -eq 'remove') {
  if($Id -eq $script:youtubeQueuePlaying) {Close-YouTubePlayer; $script:youtubeQueuePlaying=''; $script:youtubeLoadToken=''}
  $state.youtube.queue=@($items|Where-Object {$_.id -ne $Id})
 } else {
  $target=$index-1; if($Action -eq 'down') {$target=$index+1}
  if($target -lt 0 -or $target -ge $items.Count) {return}
  $swap=$items[$target]; $items[$target]=$items[$index]; $items[$index]=$swap; $state.youtube.queue=$items
 }
 Save-State; Render-YouTubeQueue
}
function Render-YouTubeQueue {
 $script:youtubeQueueButton.Content='☷ '+@($state.youtube.queue).Count
 if(-not $script:youtubeQueueWindow) {return}
 $panel=$script:youtubeQueueWindow.FindName('QueueRows'); $panel.Children.Clear(); $number=0
 foreach($item in @($state.youtube.queue)) {
  $number++; $row=New-Object Windows.Controls.StackPanel; $row.Margin='0,0,0,12'
  $title=New-Object Windows.Controls.TextBlock; $title.Text=[string]$number+'  '+$item.title; $title.TextWrapping='Wrap'; $title.Foreground='#E9EDF5'; $title.FontSize=13
  if($item.id -eq $script:youtubeQueuePlaying) {$title.Text='▶ '+$title.Text; $title.Foreground='#A3E8D2'}
  [void]$row.Children.Add($title); $tools=New-Object Windows.Controls.WrapPanel; $tools.Margin='0,5,0,0'
  foreach($spec in @(@('재생','play'),@('↑','up'),@('↓','down'),@('삭제','remove'))) {
   $b=New-Object Windows.Controls.Button; $b.Content=$spec[0]; $b.Tag=@{id=$item.id;action=$spec[1]}; $b.Padding='8,4'; $b.Margin='0,0,6,0'
   $b.Add_Click({if($this.Tag.action -eq 'play') {Play-YouTubeQueue $this.Tag.id} else {Edit-YouTubeQueue $this.Tag.id $this.Tag.action}}); [void]$tools.Children.Add($b)
  }
  [void]$row.Children.Add($tools); [void]$panel.Children.Add($row)
 }
 $script:youtubeQueueWindow.FindName('QueueStatus').Text='총 '+$number+'개 · 종료 시 다음 영상 · 마지막 영상에서 멈춤'
}
function Show-YouTubeQueue {
 if($script:youtubeQueueWindow) {$script:youtubeQueueWindow.Close()}
 $script:youtubeQueueWindow=New-DaylightWindow @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="YouTube 대기열" Width="470" Height="620" MinWidth="380" MinHeight="400" Background="#192235" Foreground="#E9EDF5" FontFamily="Malgun Gothic" ShowInTaskbar="False"><Window.Resources>__THEME__</Window.Resources><Grid Margin="24"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition/><RowDefinition Height="Auto"/></Grid.RowDefinitions><TextBlock Text="재생 대기열" FontSize="24" Margin="0,0,0,14"/><TextBox x:Name="QueueInput" Grid.Row="1" AcceptsReturn="True" Height="85" VerticalScrollBarVisibility="Auto" ToolTip="영상 링크를 한 줄에 하나씩 입력"/><WrapPanel Grid.Row="2" Margin="0,10,0,16"><Button x:Name="QueueAdd" Content="＋ 링크 추가"/><Button x:Name="QueueCurrent" Content="입력 중인 영상 추가"/></WrapPanel><ScrollViewer Grid.Row="3" VerticalScrollBarVisibility="Auto"><StackPanel x:Name="QueueRows"/></ScrollViewer><TextBlock Grid.Row="4" x:Name="QueueStatus" TextWrapping="Wrap" FontSize="11" Foreground="#B8C5D8" Margin="0,12,0,0"/></Grid></Window>
'@
 $e=$script:youtubeQueueWindow; $e.Resources.MergedDictionaries.Add($settingsWindow.Resources)
 $e.FindName('QueueAdd').Add_Click({try {Add-YouTubeQueue $script:youtubeQueueWindow.FindName('QueueInput').Text; $script:youtubeQueueWindow.FindName('QueueInput').Clear()} catch {$script:youtubeQueueWindow.FindName('QueueStatus').Text=$_.Exception.Message}})
 $e.FindName('QueueCurrent').Add_Click({try {Add-YouTubeQueue $ui.YouTubeUrl.Text} catch {$script:youtubeQueueWindow.FindName('QueueStatus').Text=$_.Exception.Message}})
 $e.Add_Closed({$script:youtubeQueueWindow=$null}); Render-YouTubeQueue
 if(-not $SelfTest) {$e.Show(); [void]$e.Activate()}
}
$script:youtubeQueueButton=New-Object Windows.Controls.Button; $youtubeQueueButton.ToolTip='재생 대기열'; $youtubeQueueButton.Padding='8,4'; $youtubeQueueButton.Add_Click({Show-YouTubeQueue})
$ui.YouTubeNext.Parent.Children.Add($youtubeQueueButton)|Out-Null
Render-YouTubeQueue
