if(-not ('DaylightYouTubeServer' -as [type])) {Add-Type -Path (Join-Path $PSScriptRoot 'YouTubeHost.cs')}
$script:youtubeServer=$null; $script:youtubeHandle=[IntPtr]::Zero; $script:youtubeDiscovery=$null
$script:youtubeLastDiscovery=[DateTime]::MinValue; $script:youtubeDeadline=[DateTime]::MinValue
$script:youtubeLaunching=$false; $script:youtubePinned=$false; $script:youtubeGeometryStamp=''
$script:youtubeProfile=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Daylight\YouTubeProfile'
if(-not $state.youtube) {$state.youtube=@{url='';volume=70;geometry=$null}}
elseif($state.youtube -isnot [hashtable]) {$map=@{}; foreach($p in $state.youtube.PSObject.Properties) {$map[$p.Name]=$p.Value}; $state.youtube=$map}
$ui.YouTubeUrl.Text=[string]$state.youtube.url
$ui.YouTubeVolume.Value=[Math]::Max(0,[Math]::Min(100,[double]$state.youtube.volume))
$youtubeSettingsMarkup=@'
<Expander xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Header="YouTube · 계정과 재생" Foreground="#E9EDF5" FontSize="16" Margin="0,8,0,8"><StackPanel Margin="0,12,0,8" TextElement.Foreground="#E9EDF5">
 <TextBlock Text="1. 전용 브라우저에서 Premium 계정으로 로그인하세요.&#10;2. 위젯에 영상·재생목록 링크를 넣고 재생 창을 여세요." FontSize="12" TextWrapping="Wrap" Margin="0,0,0,12"/>
 <WrapPanel><Button x:Name="YouTubeSettingsLogin" Content="YouTube 로그인 ↗"/><Button x:Name="YouTubeSettingsShow" Content="위젯 표시"/></WrapPanel>
 <TextBlock Text="로그인은 이 PC의 전용 Edge 프로필에 유지됩니다. Daylight는 비밀번호나 쿠키를 읽지 않습니다. Premium은 YouTube가 로그인 계정을 인식할 때 적용되며, 영상에 포함된 협찬은 제거되지 않습니다." FontSize="12" TextWrapping="Wrap" Foreground="#B8C5D8" Margin="0,12,0,8"/>
 <TextBlock Text="광고가 나오면 재생 창의 YouTube 링크에서 계정을 확인하고, Edge의 쿠키 설정에서 이 재생 창의 YouTube 쿠키 허용 여부를 확인하세요. 내장 플레이어를 허용하지 않는 영상은 공식 사이트에서 재생하세요." FontSize="12" TextWrapping="Wrap" Foreground="#B8C5D8"/>
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
function Close-YouTubePlayer {
    if($script:youtubeHandle -ne [IntPtr]::Zero -and [DaylightYouTubeWindows]::IsWindow($script:youtubeHandle)) {
        $rect=[DaylightYouTubeWindows]::Position($script:youtubeHandle)
        $state.youtube.geometry=@{left=$rect.Left;top=$rect.Top;width=$rect.Right-$rect.Left;height=$rect.Bottom-$rect.Top}
        Send-YouTubeCommand 'pause'; [DaylightYouTubeWindows]::Close($script:youtubeHandle)
    }
    $script:youtubeHandle=[IntPtr]::Zero; $script:youtubeLaunching=$false
    $ui.YouTubeToggle.Content='▶'; foreach($name in @('YouTubeToggle','YouTubePrevious','YouTubeNext')) {$ui[$name].IsEnabled=$false}
}
function Open-YouTubePlayer {
    try {
        $link=Resolve-YouTubeLink $ui.YouTubeUrl.Text; $edge=Get-DaylightEdge
        if(-not $script:youtubeServer) {$script:youtubeServer=New-Object DaylightYouTubeServer ([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'YouTubePlayer.html')))}
        $state.youtube.url=$link.url; $ui.YouTubeUrl.Text=$link.url; Save-State
        $script:youtubeServer.Enqueue((@{action='load';video=$link.video;list=$link.list}|ConvertTo-Json -Compress))
        Send-YouTubeCommand 'volume' ([int]$ui.YouTubeVolume.Value)
        if($script:youtubeHandle -ne [IntPtr]::Zero -and [DaylightYouTubeWindows]::IsWindow($script:youtubeHandle)) {[DaylightYouTubeWindows]::Activate($script:youtubeHandle); return}
        [void][IO.Directory]::CreateDirectory($script:youtubeProfile)
        $arguments='--user-data-dir="'+$script:youtubeProfile+'" --no-first-run --no-default-browser-check --app="'+$script:youtubeServer.Url+'" --window-size=640,440'
        Start-Process -FilePath $edge -ArgumentList $arguments
        $script:youtubeLaunching=$true; $script:youtubeDeadline=[DateTime]::UtcNow.AddSeconds(40); $script:youtubeLastDiscovery=[DateTime]::MinValue
        $ui.YouTubeStatus.Text='재생 창 여는 중 · 처음에는 영상의 재생 버튼을 눌러주세요.'
    } catch {Write-DaylightDiagnostic 'youtube-open' $_; $ui.YouTubeStatus.Text=$_.Exception.Message}
}
function Update-YouTubePlayer {
    if($SelfTest) {return}
    if($script:youtubeHandle -ne [IntPtr]::Zero -and -not [DaylightYouTubeWindows]::IsWindow($script:youtubeHandle)) {Close-YouTubePlayer; $ui.YouTubeStatus.Text='재생 창을 닫았습니다. 링크는 저장되어 있습니다.'}

    if($script:youtubeDiscovery -and $script:youtubeDiscovery.State -ne 'Running') {
        try {
            $allowed=@(Receive-DaylightJob $script:youtubeDiscovery)
            if($script:youtubeServer -and $allowed.Count) {$found=[DaylightYouTubeWindows]::Find($script:youtubeServer.WindowTitle,[int[]]$allowed); if($found -ne [IntPtr]::Zero) {
                $script:youtubeHandle=$found; $script:youtubeLaunching=$false; [DaylightWindowHost]::HideFromSwitcher($found)
                $g=$state.youtube.geometry; if($g -and $g.width -ge 320 -and $g.height -ge 280) {$area=[Windows.SystemParameters]::WorkArea; $w=[Math]::Min($g.width,$area.Width); $h=[Math]::Min($g.height,$area.Height); $x=[Math]::Max($area.Left,[Math]::Min($g.left,$area.Right-$w)); $y=[Math]::Max($area.Top,[Math]::Min($g.top,$area.Bottom-$h)); [DaylightYouTubeWindows]::RestorePosition($found,$x,$y,$w,$h)}
                [DaylightYouTubeWindows]::Pin($found,[bool]$state.widgetPins.youtube); $script:youtubePinned=[bool]$state.widgetPins.youtube
            }}
        } catch {Write-DaylightDiagnostic 'youtube-window' $_} finally {Remove-DaylightJob $script:youtubeDiscovery; $script:youtubeDiscovery=$null}
    }
    if(-not $state.youtubeVisible -or -not $widgets.youtube.IsVisible) {if($script:youtubeHandle -ne [IntPtr]::Zero) {Close-YouTubePlayer}; if(-not $script:youtubeLaunching) {return}}
    if($script:youtubeLaunching) {
        if([DateTime]::UtcNow -gt $script:youtubeDeadline) {$script:youtubeLaunching=$false; $ui.YouTubeStatus.Text='재생 창을 찾지 못했습니다. Edge 창을 확인한 뒤 다시 열어주세요.'}
        elseif(-not $script:youtubeDiscovery -and ([DateTime]::UtcNow-$script:youtubeLastDiscovery).TotalSeconds -ge 3) {
            $script:youtubeLastDiscovery=[DateTime]::UtcNow
            $script:youtubeDiscovery=Start-DaylightJob -ScriptBlock {param($profile); Get-CimInstance Win32_Process -Filter "Name = 'msedge.exe'" | Where-Object {$_.CommandLine -and $_.CommandLine.IndexOf($profile,[StringComparison]::OrdinalIgnoreCase) -ge 0} | ForEach-Object {[int]$_.ProcessId}} -ArgumentList @($script:youtubeProfile)
        }
    }
    if($script:youtubeHandle -ne [IntPtr]::Zero) {
        if($script:youtubePinned -ne [bool]$state.widgetPins.youtube) {$script:youtubePinned=[bool]$state.widgetPins.youtube; [DaylightYouTubeWindows]::Pin($script:youtubeHandle,$script:youtubePinned)}
        $rect=[DaylightYouTubeWindows]::Position($script:youtubeHandle); $stamp="$($rect.Left),$($rect.Top),$($rect.Right),$($rect.Bottom)"
        if($stamp -ne $script:youtubeGeometryStamp) {$script:youtubeGeometryStamp=$stamp; $state.youtube.geometry=@{left=$rect.Left;top=$rect.Top;width=$rect.Right-$rect.Left;height=$rect.Bottom-$rect.Top}; Save-State}
        try {$info=$script:youtubeServer.StateJson|ConvertFrom-Json; foreach($name in @('YouTubeToggle','YouTubePrevious','YouTubeNext')) {$ui[$name].IsEnabled=[bool]$info.ready}; $ui.YouTubeToggle.Content='▶'; if($info.playing) {$ui.YouTubeToggle.Content='❚❚'}; if($info.error) {$ui.YouTubeStatus.Text=[string]$info.error} elseif($info.title) {$ui.YouTubeStatus.Text=[string]$info.title} elseif($info.ready) {$ui.YouTubeStatus.Text='재생 준비 완료 · 영상의 재생 버튼을 눌러주세요.'}} catch {Write-DaylightDiagnostic 'youtube-state' $_}
    }
}
function Stop-YouTubeWork {
    Close-YouTubePlayer
    if($script:youtubeDiscovery) {Remove-DaylightJob $script:youtubeDiscovery; $script:youtubeDiscovery=$null}
    if($script:youtubeServer) {$script:youtubeServer.Dispose(); $script:youtubeServer=$null}
}
$ui.YouTubeOpen.Add_Click({Open-YouTubePlayer})
$ui.YouTubeUrl.Add_KeyDown({if($_.Key -eq 'Enter') {Open-YouTubePlayer; $_.Handled=$true}})
$ui.YouTubeToggle.Add_Click({Send-YouTubeCommand 'toggle'})
$ui.YouTubePrevious.Add_Click({Send-YouTubeCommand 'previous'})
$ui.YouTubeNext.Add_Click({Send-YouTubeCommand 'next'})
$ui.YouTubeLogin.Add_Click({Open-YouTubeProfile})
$ui.YouTubeVolume.Add_ValueChanged({$state.youtube.volume=[int]$this.Value; Send-YouTubeCommand 'volume' ([int]$this.Value); Save-State})
$youtubeSettings.FindName('YouTubeSettingsLogin').Add_Click({Open-YouTubeProfile})
$youtubeSettings.FindName('YouTubeSettingsShow').Add_Click({Set-WidgetVisible 'youtube' $true})
$youtubeSettings.FindName('YouTubeOfficial').Add_Click({try {$link=Resolve-YouTubeLink $ui.YouTubeUrl.Text; Open-YouTubeProfile $link.url} catch {$ui.YouTubeStatus.Text=$_.Exception.Message; Set-WidgetVisible 'youtube' $true}})
foreach($name in @('YouTubeToggle','YouTubePrevious','YouTubeNext')) {$ui[$name].IsEnabled=$false}
