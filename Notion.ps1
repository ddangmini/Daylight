$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
function Get-NotionObjectId([string]$InputValue) {
    $value = $InputValue.Trim()
    if ($value -match '^https?://') {
        $uri = [Uri]$value
        if ($uri.Scheme -ne 'https' -or $uri.Host -notmatch '(^|\.)(notion\.so|notion\.site|notion\.com)$') { throw '노션 데이터베이스 링크 또는 ID를 입력하세요.' }
        $value = $uri.AbsolutePath
    }
    $matches = [regex]::Matches($value, '(?i)[0-9a-f]{8}-?[0-9a-f]{4}-?[0-9a-f]{4}-?[0-9a-f]{4}-?[0-9a-f]{12}')
    if ($matches.Count -eq 0) { throw '링크에서 데이터베이스 ID를 찾지 못했습니다. 데이터베이스 자체의 링크를 복사하세요.' }
    return ([guid]$matches[$matches.Count - 1].Value).ToString()
}
function Invoke-NotionHttp([string]$Path, [string]$Token, [string]$Method = 'GET', $Body) {
    $parameters = @{ Uri = 'https://api.notion.com/v1/' + $Path; Method = $Method; TimeoutSec = 20; ErrorAction = 'Stop'; Headers = @{ Authorization = 'Bearer ' + $Token; 'Notion-Version' = '2025-09-03' } }
    if ($null -ne $Body) { $parameters.Body = [Text.Encoding]::UTF8.GetBytes(($Body | ConvertTo-Json -Depth 20 -Compress)); $parameters.ContentType = 'application/json; charset=utf-8' }
    try { return Invoke-RestMethod @parameters }
    catch {
        $status = 0; if ($_.Exception.Response) { $status = [int]$_.Exception.Response.StatusCode }
        switch ($status) {
            401 { throw '노션 연결 토큰이 올바르지 않거나 만료되었습니다. 연결 설정에서 다시 입력하세요.' }
            403 { throw '노션 연결에 필요한 읽기·수정 권한이 없습니다. 연결 권한을 확인하세요.' }
            404 { throw '노션 데이터베이스를 찾지 못했습니다. 데이터베이스의 연결 메뉴에서 Daylight 연결을 추가했는지 확인하세요.' }
            400 { throw '노션 속성 설정이 맞지 않습니다. 완료 속성 이름과 상태 이름을 확인하세요.' }
            429 { throw '노션 요청이 많습니다. 잠시 후 새로고침하세요.' }
            default { throw '노션에 연결하지 못했습니다. 인터넷 연결을 확인하세요.' }
        }
    }
}
function Get-NotionTaskSchema($Settings) {
    $database = Invoke-NotionHttp ('databases/' + $Settings.databaseId) $Settings.token
    $sources = @($database.data_sources)
    if ($sources.Count -eq 0) { throw '이 데이터베이스에 할 일 표가 없습니다. 데이터베이스 링크를 확인하세요.' }
    $source = $sources | Where-Object { $_.id -eq $Settings.sourceId } | Select-Object -First 1
    if (-not $source -and $sources.Count -eq 1) { $source = $sources[0] }
    if (-not $source) { throw '데이터 소스가 여러 개입니다. 연결 설정에 표시할 데이터 소스 ID를 입력하세요.' }
    $schema = Invoke-NotionHttp ('data_sources/' + $source.id) $Settings.token
    $properties = @($schema.properties.PSObject.Properties | ForEach-Object { $_.Value })
    $title = $properties | Where-Object { $_.type -eq 'title' } | Select-Object -First 1
    if (-not $title) { throw '노션 표에서 제목 속성을 찾지 못했습니다.' }
    $completion = $properties | Where-Object { $_.name -eq $Settings.completionProperty -and $_.type -in @('checkbox','status') } | Select-Object -First 1
    if (-not $completion -and -not $Settings.completionProperty) {
        $candidates = @($properties | Where-Object { $_.type -in @('checkbox','status') })
        if ($candidates.Count -eq 1) { $completion = $candidates[0] }
    }
    if (-not $completion) { throw '완료 속성을 찾지 못했습니다. 연결 설정에 체크박스 또는 상태 속성의 이름을 입력하세요.' }
    if ($completion.type -eq 'status') {
        $options = @($completion.status.options | ForEach-Object { $_.name })
        if ($Settings.doneStatus -notin $options -or $Settings.openStatus -notin $options -or $Settings.doneStatus -eq $Settings.openStatus) { throw '완료·미완료 상태 이름을 노션 표의 상태 옵션과 똑같이 입력하세요.' }
    }
    $due = $properties | Where-Object { $_.type -eq 'date' } | Select-Object -First 1
    return [pscustomobject]@{ sourceId = $source.id; titleId = $title.id; completionId = $completion.id; completionType = $completion.type; dueId = $due.id }
}
function Find-NotionProperty($Properties, [string]$Id) {
    return ($Properties.PSObject.Properties | ForEach-Object { $_.Value } | Where-Object { $_.id -eq $Id } | Select-Object -First 1)
}
function Get-NotionTasks($Settings, $Schema) {
    $items = @(); $cursor = ''; $more = $false
    do {
        $body = @{ page_size = [Math]::Min(100, 200 - $items.Count); sorts = @(@{ timestamp = 'last_edited_time'; direction = 'descending' }) }
        if ($cursor) { $body.start_cursor = $cursor }
        $response = Invoke-NotionHttp ('data_sources/' + $Schema.sourceId + '/query') $Settings.token 'POST' $body
        foreach ($page in $response.results) {
            if ($page.object -ne 'page' -or $page.archived -or $page.in_trash -or $page.is_archived) { continue }
            $titleProperty = Find-NotionProperty $page.properties $Schema.titleId
            $title = (($titleProperty.title | ForEach-Object { if ($_.plain_text) { $_.plain_text } else { $_.text.content } }) -join '')
            if (-not $title) { $title = '(제목 없음)' }
            $doneProperty = Find-NotionProperty $page.properties $Schema.completionId
            $done = $false; $status = ''
            if ($Schema.completionType -eq 'checkbox') { $done = [bool]$doneProperty.checkbox } else { $status = [string]$doneProperty.status.name; $done = $status -eq $Settings.doneStatus }
            $due = ''; if ($Schema.dueId) { $dueProperty = Find-NotionProperty $page.properties $Schema.dueId; if ($dueProperty.date) { $due = [string]$dueProperty.date.start } }
            $items += [pscustomobject]@{ id = [string]$page.id; text = $title; done = $done; status = $status; due = $due; url = [string]$page.url }
            if ($items.Count -ge 200) { break }
        }
        $more = [bool]$response.has_more; $cursor = $response.next_cursor
    } while ($more -and $cursor -and $items.Count -lt 200)
    return [pscustomobject]@{ tasks = @($items | Sort-Object done); truncated = $more; fetchedAt = [DateTimeOffset]::UtcNow.ToString('o') }
}
function Set-NotionTaskDone($Settings, $Schema, [string]$PageId, [bool]$Done) {
    if ($PageId -notmatch '^[0-9a-fA-F-]{36}$') { throw '노션 할 일 ID가 올바르지 않습니다.' }
    # Re-read the page before writing; a moved page must not receive a stale property update.
    $page = Invoke-NotionHttp ('pages/' + $PageId) $Settings.token
    if ($page.parent.data_source_id -ne $Schema.sourceId) { throw '이 할 일은 연결한 표에서 이동되었습니다. 새로고침하세요.' }
    $value = @{ checkbox = $Done }
    if ($Schema.completionType -eq 'status') { $name = $Settings.openStatus; if ($Done) { $name = $Settings.doneStatus }; $value = @{ status = @{ name = $name } } }
    $properties = @{}; $properties[$Schema.completionId] = $value
    [void](Invoke-NotionHttp ('pages/' + $PageId) $Settings.token 'PATCH' @{ properties = $properties })
}
function Invoke-NotionWork([string]$Root, [string]$Action = 'Refresh', [string]$PageId, [bool]$Done) {
    try {
        $settings = Read-CalendarVault (Join-Path $Root 'notion-settings.dat')
        if (-not $settings) { throw '노션 연결을 먼저 설정하세요.' }
        $schema = Get-NotionTaskSchema $settings
        if ($Action -eq 'Complete') {
            Set-NotionTaskDone $settings $schema $PageId $Done
            # A successful write and a failed follow-up read are distinct; do not misreport or retry the write.
            try { $agenda = Get-NotionTasks $settings $schema }
            catch { return [pscustomobject]@{ ok = $false; writeSucceeded = $true; message = '완료 상태는 노션에 반영되었습니다. 목록 갱신은 실패했습니다. 새로고침하세요.' } }
        } else { $agenda = Get-NotionTasks $settings $schema }
        return [pscustomobject]@{ ok = $true; agenda = $agenda }
    } catch { return [pscustomobject]@{ ok = $false; message = $_.Exception.Message } }
}
