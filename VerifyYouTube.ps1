$savedYouTube=$state.youtube|ConvertTo-Json -Depth 8
$server=$null
try {
    foreach($link in @('https://youtu.be/M7lc1UVf-VE','https://www.youtube.com/watch?v=M7lc1UVf-VE','https://www.youtube.com/shorts/M7lc1UVf-VE','M7lc1UVf-VE')) {Assert-UI ((Resolve-YouTubeLink $link).video -eq 'M7lc1UVf-VE') 'YouTube video URL normalization'}
    Assert-UI ((Resolve-YouTubeLink 'https://www.youtube.com/playlist?list=PLabcdefghijk123').list -eq 'PLabcdefghijk123') 'YouTube playlist parsing'
    foreach($link in @('http://www.youtube.com/watch?v=M7lc1UVf-VE','https://youtube.com.evil.example/watch?v=M7lc1UVf-VE','https://www.youtube.com:9443/watch?v=M7lc1UVf-VE','https://user@www.youtube.com/watch?v=M7lc1UVf-VE','https://www.youtube.com/watch?v=bad','javascript:alert(1)')) {$blocked=$false; try {Resolve-YouTubeLink $link | Out-Null} catch {$blocked=$true}; Assert-UI $blocked 'Invalid or non-YouTube link rejected'}
    Assert-UI ($ui.ShowYoutube -and $ui.YouTubeUrl -and $youtubeSettings.FindName('YouTubeSettingsLogin')) 'YouTube widget and settings wired'
    Assert-UI ((-not $script:youtubeSdkError) -and ('DaylightEmbeddedYouTube' -as [type]) -and $ui.YouTubeViewHost) 'Embedded SDK and in-widget host loaded'
    $server=New-Object DaylightYouTubeServer ([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'YouTubePlayer.html')))
    $page=Invoke-WebRequest -Uri $server.Url -UseBasicParsing -TimeoutSec 5
    Assert-UI ($page.Content.Contains('https://www.youtube.com/iframe_api') -and -not $page.Content.Contains('__ORIGIN__')) 'Official player served on per-session loopback origin'
    $server.Enqueue('{"action":"toggle"}')
    $batch=Invoke-RestMethod -Uri ($server.Url+'commands') -TimeoutSec 5
    Assert-UI ($batch.Count -eq 1 -and $batch[0].action -eq 'toggle') 'Player command delivery'
    $batch=Invoke-RestMethod -Uri ($server.Url+'commands') -TimeoutSec 5
    Assert-UI ($batch.Count -eq 0) 'Player commands delivered once'
    Invoke-WebRequest -Uri ($server.Url+'state') -Method Post -ContentType 'application/json' -Headers @{Origin=$server.Origin} -Body '{"ready":true,"title":"test"}' -UseBasicParsing -TimeoutSec 5|Out-Null
    Assert-UI (($server.StateJson|ConvertFrom-Json).title -eq 'test') 'Player state bridge'
    foreach($uri in @(($server.Origin+'/commands'),($server.Url+'state'))) {$blocked=$false; try {Invoke-WebRequest -Uri $uri -Method Post -Headers @{Origin='https://untrusted.example'} -Body '{}' -UseBasicParsing -TimeoutSec 5|Out-Null} catch {$blocked=$_.Exception.Response.StatusCode.value__ -eq 403}; Assert-UI $blocked 'Untrusted origin and wrong session route rejected'}
    $state.youtube.url='https://www.youtube.com/watch?v=M7lc1UVf-VE'; Save-State
    $state.youtube.queue=@()
    Add-YouTubeQueue "https://youtu.be/M7lc1UVf-VE`nhttps://www.youtube.com/watch?v=dQw4w9WgXcQ"
    Assert-UI ($state.youtube.queue.Count -eq 2) 'Multiple video queue input'
    $first=$state.youtube.queue[0].id; $second=$state.youtube.queue[1].id
    $blocked=$false; try {Add-YouTubeQueue "M7lc1UVf-VE`nhttps://example.com/unsafe"} catch {$blocked=$true}
    Assert-UI ($blocked -and $state.youtube.queue.Count -eq 2) 'Invalid batch leaves queue unchanged'
    $blocked=$false; try {Add-YouTubeQueue 'https://www.youtube.com/playlist?list=PLabcdefghijk123'} catch {$blocked=$true}; Assert-UI $blocked 'Queue requires individual videos'
    Edit-YouTubeQueue $second 'up'; Assert-UI ($state.youtube.queue[0].id -eq $second) 'Queue reorder'
    Edit-YouTubeQueue $second 'down'; Assert-UI ((Get-YouTubeQueueNext $first).id -eq $second -and -not (Get-YouTubeQueueNext $second)) 'Queue boundaries'
    Show-YouTubeQueue; Assert-UI ($script:youtubeQueueWindow.FindName('QueueRows').Children.Count -eq 2) 'Queue dialog renders saved items'
    $playFunction=${function:Play-YouTubeQueue}
    try {
     $script:queueTestPlays=0
     function Play-YouTubeQueue([string]$Id) {$script:queueTestPlays++; $script:youtubeQueuePlaying=$Id; $script:youtubeLoadToken='next-token'; $script:youtubeEndedToken=''}
     $script:youtubeQueuePlaying=$first; $script:youtubeLoadToken='first-token'; $script:youtubeEndedToken=''
     Receive-YouTubeQueueState @{token='old-token';endedToken='old-token'}
     Assert-UI ($script:queueTestPlays -eq 0) 'Stale ended event ignored'
     Receive-YouTubeQueueState @{token='first-token';endedToken='first-token'}
     Receive-YouTubeQueueState @{token='first-token';endedToken='first-token'}
     Assert-UI ($script:queueTestPlays -eq 1 -and $script:youtubeQueuePlaying -eq $second) 'Ended event advances once'
     Receive-YouTubeQueueState @{token='next-token';endedToken='next-token'}
     Assert-UI ($script:queueTestPlays -eq 1) 'Queue stops at last video'
    } finally {Set-Item Function:Play-YouTubeQueue $playFunction}
    Edit-YouTubeQueue $second 'remove'; Assert-UI ($state.youtube.queue.Count -eq 1 -and -not $script:youtubeQueuePlaying) 'Deleting current item stops queue'
    Save-State
    $saved=Get-Content -LiteralPath $DataPath -Raw -Encoding UTF8|ConvertFrom-Json
    Assert-UI ($saved.youtube.url -eq $state.youtube.url -and $saved.youtube.queue.Count -eq 1 -and $saved.youtube.queue[0].id -eq $first) 'YouTube settings and queue persistence'
    $native=New-Object Windows.Window; $native.Title=$server.WindowTitle
    try {
        Register-DaylightToolWindow $native
        $helper=New-Object Windows.Interop.WindowInteropHelper $native; $handle=$helper.EnsureHandle()
        Assert-UI ([DaylightYouTubeWindows]::Find($server.WindowTitle,[int[]]@($PID)) -eq $handle) 'Owned player native window discovery'
        Assert-UI ([DaylightYouTubeWindows]::Find($server.WindowTitle,[int[]]@(0)) -eq [IntPtr]::Zero) 'Unrelated browser process excluded'
        [DaylightYouTubeWindows]::Pin($handle,$true)
        Assert-UI (([DaylightWindowHost]::ExtendedStyle($handle) -band 8) -ne 0) 'Player always on top'
        [DaylightYouTubeWindows]::Pin($handle,$false)
        Assert-UI (([DaylightWindowHost]::ExtendedStyle($handle) -band 8) -eq 0) 'Player always on top reset'
    } finally {$native.Close()}
    'PASS: YouTube URL safety, official player page, loopback command/state bridge, cross-origin rejection, settings and persistence'
} finally {if($server) {$server.Dispose()}; if($script:youtubeQueueWindow) {$script:youtubeQueueWindow.Close(); $script:youtubeQueueWindow=$null}; $state.youtube=$savedYouTube|ConvertFrom-Json; Stop-YouTubeWork}
