$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
function Get-WeatherDescription([int]$Code) {
    switch ($Code) {
        0 { '맑음' } 1 { '대체로 맑음' } 2 { '구름 조금' } 3 { '흐림' }
        { $_ -in @(45,48) } { '안개' }
        { $_ -in @(51,53,55,56,57) } { '이슬비' }
        { $_ -in @(61,63,65,66,67,80,81,82) } { '비' }
        { $_ -in @(71,73,75,77,85,86) } { '눈' }
        { $_ -in @(95,96,99) } { '뇌우' }
        default { '날씨 정보' }
    }
}
function Invoke-WeatherHttp([string]$Uri) {
    try { return Invoke-RestMethod -Uri $Uri -TimeoutSec 15 -ErrorAction Stop }
    catch { throw '날씨를 가져오지 못했습니다. 인터넷 연결을 확인하세요.' }
}
function Invoke-WeatherWork([string]$Action, [double]$Latitude, [double]$Longitude, [string]$City) {
    try {
        if ($Action -eq 'Search') {
            if ($City.Trim().Length -lt 2) { throw '두 글자 이상으로 도시 이름을 입력하세요.' }
            $result = Invoke-WeatherHttp ('https://geocoding-api.open-meteo.com/v1/search?name=' + [Uri]::EscapeDataString($City.Trim()) + '&count=10&language=ko&format=json')
            $locations = @($result.results | Where-Object { $null -ne $_ } | ForEach-Object {
                $label = $_.name + ' · ' + $_.admin1 + ' · ' + $_.country
                [pscustomobject]@{ name = $_.name; label = $label; latitude = $_.latitude; longitude = $_.longitude }
            })
            return [pscustomobject]@{ ok = $true; action = 'Search'; locations = $locations }
        }
        if ($Latitude -lt -90 -or $Latitude -gt 90 -or $Longitude -lt -180 -or $Longitude -gt 180) { throw '날씨 지역 좌표가 올바르지 않습니다.' }
        $culture = [Globalization.CultureInfo]::InvariantCulture
        $uri = 'https://api.open-meteo.com/v1/forecast?latitude=' + $Latitude.ToString($culture) + '&longitude=' + $Longitude.ToString($culture) + '&current=temperature_2m,weather_code&timezone=Asia%2FSeoul&forecast_days=1'
        $result = Invoke-WeatherHttp $uri
        if ($null -eq $result.current.temperature_2m -or $null -eq $result.current.weather_code) { throw '날씨 정보가 아직 제공되지 않았습니다.' }
        return [pscustomobject]@{ ok = $true; action = 'Refresh'; city = $City; temperature = [Math]::Round([double]$result.current.temperature_2m); code = [int]$result.current.weather_code; description = Get-WeatherDescription $result.current.weather_code; observedAt = [string]$result.current.time; fetchedAt = [DateTimeOffset]::UtcNow.ToString('o') }
    } catch { return [pscustomobject]@{ ok = $false; action = $Action; message = $_.Exception.Message } }
}
