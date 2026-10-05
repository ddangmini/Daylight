function Start-WeatherWork([string]$Action = 'Refresh') {
    if ($script:weatherJob) { return }
    $script:lastWeatherAttempt = [DateTime]::UtcNow
    $ui.WeatherStatus.Text = '날씨 조회 중'
    if ($Action -eq 'Search') { $ui.WeatherStatus.Text = '지역 검색 중' }
    $ui.WeatherSearch.IsEnabled = $false; $ui.WeatherChoice.IsEnabled = $false; $ui.WeatherRefresh.IsEnabled = $false
    $city = $script:state.weatherCity; if ($Action -eq 'Search') { $city = $ui.WeatherCityInput.Text }
    try {
        $script:weatherJob = Start-DaylightJob -ScriptBlock { param($root,$action,$lat,$lon,$city); . (Join-Path $root 'Weather.ps1'); Invoke-WeatherWork $action $lat $lon $city } -ArgumentList $PSScriptRoot,$Action,$script:state.weatherLatitude,$script:state.weatherLongitude,$city
    } catch { $ui.WeatherStatus.Text = '날씨 조회를 시작하지 못했습니다.'; $ui.WeatherSearch.IsEnabled = $true; $ui.WeatherChoice.IsEnabled = $true; $ui.WeatherRefresh.IsEnabled = $true }
}
function Receive-WeatherWork {
    if (-not $script:weatherJob -or $script:weatherJob.State -in @('Running','NotStarted')) { return }
    $result = $null
    try { $result = @(Receive-DaylightJob -Job $script:weatherJob -ErrorAction Stop) | Select-Object -Last 1 }
    catch { $result = [pscustomobject]@{ ok = $false; message = '날씨 조회에 실패했습니다.' } }
    Remove-DaylightJob -Job $script:weatherJob -Force; $script:weatherJob = $null
    $ui.WeatherSearch.IsEnabled = $true; $ui.WeatherChoice.IsEnabled = $true; $ui.WeatherRefresh.IsEnabled = $true
    if ($result -and $result.ok) {
        if ($result.action -eq 'Search') {
            $script:weatherChoosing = $true; $ui.WeatherChoice.Items.Clear()
            foreach ($location in $result.locations) { $item = New-Object Windows.Controls.ComboBoxItem; $item.Content = $location.label; $item.Tag = $location; [void]$ui.WeatherChoice.Items.Add($item) }
            $script:weatherChoosing = $false
            if (@($result.locations).Count) { $ui.WeatherStatus.Text = '검색 결과에서 원하는 지역을 선택하세요.' }
            else { $ui.WeatherStatus.Text = '지역을 찾지 못했습니다. 다른 이름으로 검색하세요.' }
        } else {
            $script:lastWeather = $result; Set-WeatherIcon $result.code
            $ui.Temperature.Text = [string]$result.temperature + '°'
            $ui.Conditions.Text = $result.city + ' · ' + $result.description
            $ui.WeatherStatus.Text = $result.city + ' · 제공 시각 ' + $result.observedAt.Replace('T',' ') + ' · 15분마다 갱신'
            $ui.WeatherCredit.ToolTip = '날씨 모델 데이터: Open-Meteo · ' + $result.observedAt
        }
    } else {
        $ui.WeatherStatus.Text = '날씨 조회에 실패했습니다.'; if ($result.message) { $ui.WeatherStatus.Text = $result.message }
        if ($script:lastWeather) { $ui.Conditions.Text = $script:lastWeather.city + ' · 이전 조회 · ' + $script:lastWeather.description; $ui.WeatherStatus.Text += ' · 이전 조회 내용입니다.' }
        else { $ui.Conditions.Text = $script:state.weatherCity + ' · 연결 확인 필요' }
    }
}
function Stop-WeatherWork { if ($script:weatherJob) { Stop-DaylightJob $script:weatherJob; Remove-DaylightJob $script:weatherJob -Force; $script:weatherJob = $null } }
