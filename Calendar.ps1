# Google Calendar backend. Runs in a background PowerShell job; never on the WPF thread.
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$script:CalendarScopes = 'https://www.googleapis.com/auth/calendar.events.readonly https://www.googleapis.com/auth/calendar.calendarlist.readonly'

function Write-CalendarVault([string]$Path, $Value) {
    $plain = $Value | ConvertTo-Json -Depth 12 -Compress
    $secure = ConvertTo-SecureString -String $plain -AsPlainText -Force
    $encrypted = ConvertFrom-SecureString -SecureString $secure
    $temporary = "$Path.tmp"
    [IO.File]::WriteAllText($temporary, $encrypted, [Text.Encoding]::UTF8)
    if (Test-Path -LiteralPath $Path) { [IO.File]::Replace($temporary, $Path, "$Path.bak") }
    else { [IO.File]::Move($temporary, $Path) }
}
function Read-CalendarVault([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $secure = ConvertTo-SecureString -String ([IO.File]::ReadAllText($Path))
    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try { return ([Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer) | ConvertFrom-Json) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
}
function Import-CalendarClient([string]$File, [string]$Root) {
    $document = [IO.File]::ReadAllText($File) | ConvertFrom-Json
    $client = $document.installed
    if (-not $client -or $client.client_id -notmatch '^[A-Za-z0-9._-]+\.apps\.googleusercontent\.com$' -or -not $client.client_secret) {
        throw '구글에서 내려받은 데스크톱 앱용 OAuth JSON 파일을 선택하세요.'
    }
    Write-CalendarVault (Join-Path $Root 'calendar-client.dat') ([pscustomobject]@{ client_id = [string]$client.client_id; client_secret = [string]$client.client_secret })
}
function New-CalendarRandom {
    $bytes = New-Object byte[] 32
    $generator = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $generator.GetBytes($bytes) } finally { $generator.Dispose() }
    return [Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+','-').Replace('/','_')
}
function ConvertTo-CalendarQuery($Values) {
    return (($Values.GetEnumerator() | ForEach-Object { [Uri]::EscapeDataString([string]$_.Key) + '=' + [Uri]::EscapeDataString([string]$_.Value) }) -join '&')
}
function Invoke-CalendarHttp([string]$Uri, [string]$Method = 'GET', $Body, [string]$AccessToken) {
    $parameters = @{ Uri = $Uri; Method = $Method; TimeoutSec = 20; ErrorAction = 'Stop' }
    if ($Body) { $parameters.Body = $Body; $parameters.ContentType = 'application/x-www-form-urlencoded' }
    if ($AccessToken) { $parameters.Headers = @{ Authorization = "Bearer $AccessToken" } }
    try { return Invoke-RestMethod @parameters }
    catch {
        $code = 0
        if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode }
        $reason=''; try {$detail=$_.ErrorDetails.Message|ConvertFrom-Json; if($detail.error -is [string]) {$reason=$detail.error}} catch {}
        $message=switch ($code) {
            400 { '구글 인증 또는 연결 설정을 확인하세요. 다시 로그인해도 기존 일정과 메모는 유지됩니다.' }
            401 { '로그인을 갱신하지 못했습니다. 구글 연결에서 다시 로그인하세요.' }
            403 { '접근이 허용되지 않았습니다. Calendar API 사용 설정과 일정 조회 권한을 확인하세요.' }
            404 { '선택한 캘린더를 찾을 수 없습니다. 다른 캘린더를 선택하세요.' }
            429 { '잠시 요청이 많습니다. 조금 뒤 다시 새로고침하세요.' }
            default { '구글에 연결하지 못했습니다. 인터넷 연결을 확인하고 다시 시도하세요.' }
        }
        if($reason -eq 'invalid_grant') {$message='구글에서 로그인 권한이 만료되거나 취소되었습니다. 구글 연결에서 다시 로그인하세요.'}
        $failure=New-Object Exception $message
        $failure.Data['HttpStatus']=$code; $failure.Data['Reason']=$reason
        throw $failure
    }
}
function Read-CalendarCallback([Net.Sockets.TcpListener]$Listener, [string]$ExpectedState, [int]$TimeoutSeconds = 180) {
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    Add-Type -AssemblyName System.Web
    while ([DateTime]::UtcNow -lt $deadline) {
        if (-not $Listener.Pending()) { Start-Sleep -Milliseconds 100; continue }
        $connection = $Listener.AcceptTcpClient()
        try {
            $stream = $connection.GetStream(); $stream.ReadTimeout = 2000
            $buffer = New-Object byte[] 1024; $request = ''
            while ($request -notmatch "\r\n\r\n" -and $request.Length -lt 8192) {
                $count = $stream.Read($buffer, 0, $buffer.Length)
                if ($count -eq 0) { break }
                $request += [Text.Encoding]::ASCII.GetString($buffer, 0, $count)
            }
            $match = [regex]::Match($request, '^GET ([^ ]+) HTTP/1\.[01]\r\n')
            $code = $null; $denied = $false
            if ($match.Success) {
                $target = [Uri]("http://127.0.0.1" + $match.Groups[1].Value)
                $query = [Web.HttpUtility]::ParseQueryString($target.Query)
                if ($target.AbsolutePath -eq '/' -and $query['state'] -ceq $ExpectedState) {
                    $code = $query['code']; $denied = [bool]$query['error']
                }
            }
            $valid = [bool]$code -or $denied
            $message = 'This request could not be verified. Return to Daylight and try again.'
            if ($valid) { $message = 'Google sign-in received. You can close this tab and return to Daylight.' }
            $body = [Text.Encoding]::UTF8.GetBytes("<!doctype html><html><meta charset='utf-8'><title>Daylight</title><body style='font:18px sans-serif;padding:48px;background:#192235;color:#eef5fa'><h1>Daylight</h1><p>$message</p></body></html>")
            $status = '400 Bad Request'; if ($valid) { $status = '200 OK' }
            $header = [Text.Encoding]::ASCII.GetBytes("HTTP/1.1 $status`r`nContent-Type: text/html; charset=utf-8`r`nContent-Length: $($body.Length)`r`nCache-Control: no-store`r`nConnection: close`r`n`r`n")
            $stream.Write($header, 0, $header.Length); $stream.Write($body, 0, $body.Length)
            if ($denied) { throw '구글 로그인이 취소되었습니다. 연결 버튼으로 다시 시도할 수 있습니다.' }
            if ($code) { return [string]$code }
        } catch {
            if ($_.Exception.Message -like '구글 로그인이*') { throw }
            # Ignore unrelated or incomplete loopback requests. Only verified callbacks return a code.
        } finally { $connection.Close() }
    }
    throw '로그인 대기 시간이 지났습니다. 연결 버튼을 눌러 다시 시도하세요.'
}
function Connect-GoogleCalendar([string]$Root) {
    $client = Read-CalendarVault (Join-Path $Root 'calendar-client.dat')
    if (-not $client) { throw '구글 연결 설정 파일을 먼저 선택하세요.' }
    $verifier = New-CalendarRandom; $state = New-CalendarRandom
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $challenge = [Convert]::ToBase64String($sha.ComputeHash([Text.Encoding]::ASCII.GetBytes($verifier))).TrimEnd('=').Replace('+','-').Replace('/','_') }
    finally { $sha.Dispose() }
    $listener = New-Object Net.Sockets.TcpListener ([Net.IPAddress]::Loopback), 0
    try {
        $listener.Start()
        $redirect = "http://127.0.0.1:$($listener.LocalEndpoint.Port)/"
        $query = ConvertTo-CalendarQuery @{ client_id = $client.client_id; redirect_uri = $redirect; response_type = 'code'; scope = $script:CalendarScopes; code_challenge = $challenge; code_challenge_method = 'S256'; state = $state; access_type = 'offline'; prompt = 'consent' }
        Start-Process ("https://accounts.google.com/o/oauth2/v2/auth?" + $query)
        $code = Read-CalendarCallback $listener $state
        $response = Invoke-CalendarHttp 'https://oauth2.googleapis.com/token' 'POST' @{ client_id = $client.client_id; client_secret = $client.client_secret; code = $code; code_verifier = $verifier; redirect_uri = $redirect; grant_type = 'authorization_code' }
        if (-not $response.access_token -or -not $response.refresh_token) { throw '자동 갱신을 위한 로그인을 완료하지 못했습니다. 다시 연결하세요.' }
        Write-CalendarVault (Join-Path $Root 'calendar-token.dat') ([pscustomobject]@{ access_token = $response.access_token; refresh_token = $response.refresh_token; expires_at = [DateTimeOffset]::UtcNow.AddSeconds([int]$response.expires_in).ToString('o') })
    } finally { $listener.Stop() }
}
function Get-CalendarAccessToken([string]$Root, [switch]$ForceRefresh) {
    $token = Read-CalendarVault (Join-Path $Root 'calendar-token.dat')
    if (-not $token) { throw '구글 캘린더를 먼저 연결하세요.' }
    if ($ForceRefresh -or [DateTimeOffset]::Parse($token.expires_at) -lt [DateTimeOffset]::UtcNow.AddSeconds(60)) {
        $client = Read-CalendarVault (Join-Path $Root 'calendar-client.dat')
        if (-not $client) { throw '구글 연결 설정 파일을 먼저 선택하세요.' }
        $response = Invoke-CalendarHttp 'https://oauth2.googleapis.com/token' 'POST' @{ client_id = $client.client_id; client_secret = $client.client_secret; refresh_token = $token.refresh_token; grant_type = 'refresh_token' }
        if (-not $response.access_token) { throw '로그인이 만료되었습니다. 다시 연결하세요.' }
        $token.access_token = $response.access_token
        $token.expires_at = [DateTimeOffset]::UtcNow.AddSeconds([int]$response.expires_in).ToString('o')
        if ($response.refresh_token) { $token.refresh_token = $response.refresh_token }
        Write-CalendarVault (Join-Path $Root 'calendar-token.dat') $token
    }
    return [string]$token.access_token
}
function Get-GoogleCalendars([string]$AccessToken) {
    $items = @(); $page = ''
    do {
        $query = @{ maxResults = 250; minAccessRole = 'reader' }
        if ($page) { $query.pageToken = $page }
        $response = Invoke-CalendarHttp ('https://www.googleapis.com/calendar/v3/users/me/calendarList?' + (ConvertTo-CalendarQuery $query)) 'GET' $null $AccessToken
        foreach ($calendar in $response.items) {
            if ($calendar.deleted) { continue }
            $name = $calendar.summary; if ($calendar.summaryOverride) { $name = $calendar.summaryOverride }
            $items += [pscustomobject]@{ id = [string]$calendar.id; name = [string]$name; primary = [bool]$calendar.primary }
        }
        $page = $response.nextPageToken
    } while ($page)
    return @($items | Sort-Object @{ Expression = 'primary'; Descending = $true }, name)
}
function Convert-GoogleEvent($Event, [TimeZoneInfo]$Zone) {
    if ($Event.status -eq 'cancelled') { return $null }
    $allDay = [bool]$Event.start.date
    $title = [string]$Event.summary; if (-not $title) { $title = '(제목 없음)' }
    if ($allDay) {
        $start = [DateTime]::ParseExact($Event.start.date, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
        $end = [DateTime]::ParseExact($Event.end.date, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
        $date = $start.ToString('yyyy-MM-dd'); $time = '종일'
        if (($end - $start).TotalDays -gt 1) { $time = '종일 · ' + $start.ToString('M/d', [Globalization.CultureInfo]::InvariantCulture) + '–' + $end.AddDays(-1).ToString('M/d', [Globalization.CultureInfo]::InvariantCulture) }
    } else {
        $start = [TimeZoneInfo]::ConvertTime([DateTimeOffset]::Parse($Event.start.dateTime, [Globalization.CultureInfo]::InvariantCulture), $Zone)
        $end = [TimeZoneInfo]::ConvertTime([DateTimeOffset]::Parse($Event.end.dateTime, [Globalization.CultureInfo]::InvariantCulture), $Zone)
        $date = $start.ToString('yyyy-MM-dd'); $time = $start.ToString('HH:mm') + '–' + $end.ToString('HH:mm')
        if ($end.Date -ne $start.Date) { $time = $start.ToString('M/d HH:mm', [Globalization.CultureInfo]::InvariantCulture) + '–' + $end.ToString('M/d HH:mm', [Globalization.CultureInfo]::InvariantCulture) }
    }
    return [pscustomobject]@{ id = [string]$Event.id; title = $title; date = $date; time = $time; allDay = $allDay; location = [string]$Event.location }
}
function Get-GoogleAgenda([string]$AccessToken, [string]$CalendarId = 'primary') {
    $zone = [TimeZoneInfo]::FindSystemTimeZoneById('Korea Standard Time')
    $now = [TimeZoneInfo]::ConvertTime([DateTimeOffset]::UtcNow, $zone)
    $first = [DateTimeOffset]::new($now.Date, $zone.GetUtcOffset($now.Date))
    $parameters = @{ timeMin = $first.ToString('o'); timeMax = $first.AddDays(7).ToString('o'); timeZone = 'Asia/Seoul'; singleEvents = 'true'; orderBy = 'startTime'; maxResults = 100; showDeleted = 'false' }
    $events = @(); $page = ''
    do {
        $parameters.maxResults = 100 - $events.Count
        if ($page) { $parameters.pageToken = $page }
        $uri = 'https://www.googleapis.com/calendar/v3/calendars/' + [Uri]::EscapeDataString($CalendarId) + '/events?' + (ConvertTo-CalendarQuery $parameters)
        $response = Invoke-CalendarHttp $uri 'GET' $null $AccessToken
        foreach ($event in $response.items) { $item = Convert-GoogleEvent $event $zone; if ($null -ne $item -and $events.Count -lt 100) { $events += $item } }
        $page = $response.nextPageToken
    } while ($page -and $events.Count -lt 100)
    return [pscustomobject]@{ events = $events; truncated = [bool]$response.nextPageToken; fetchedAt = $now.ToString('o'); rangeStart = $first.ToString('yyyy-MM-dd'); rangeEnd = $first.AddDays(6).ToString('yyyy-MM-dd') }
}
function Invoke-CalendarWork([string]$Action, [string]$Root, [string]$CalendarId = 'primary') {
    try {
        if ($Action -eq 'Connect') { Connect-GoogleCalendar $Root }
        $accessToken = Get-CalendarAccessToken $Root
        for($attempt=0; $attempt -lt 2; $attempt++) {
            try {
                $calendars = @(Get-GoogleCalendars $accessToken)
                if ($CalendarId -ne 'primary' -and -not @($calendars | Where-Object { $_.id -eq $CalendarId }).Count) { $CalendarId = 'primary' }
                $agenda = Get-GoogleAgenda $accessToken $CalendarId
                break
            } catch {
                if($attempt -eq 0 -and $_.Exception.Data['HttpStatus'] -eq 401) {$accessToken=Get-CalendarAccessToken $Root -ForceRefresh; continue}
                throw
            }
        }
        return [pscustomobject]@{ ok = $true; calendars = $calendars; agenda = $agenda; calendarId = $CalendarId }
    } catch { return [pscustomobject]@{ ok = $false; message = $_.Exception.Message; requiresReconnect=($_.Exception.Data['HttpStatus'] -eq 401 -or $_.Exception.Data['Reason'] -eq 'invalid_grant') } }
}
