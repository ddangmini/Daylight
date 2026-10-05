$ErrorActionPreference='Stop'
[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
# Compatible internal names; all requests now use Gemini.
function Invoke-GPTHttp([string]$Key,$Body) {
    $model=[string]$Body.model; $payload=@{}; foreach($name in $Body.Keys) {if($name -ne 'model') {$payload[$name]=$Body[$name]}}
    $json=$payload | ConvertTo-Json -Depth 12 -Compress
    return Invoke-RestMethod -Uri ('https://generativelanguage.googleapis.com/v1beta/models/'+$model+':generateContent') -Method Post -Headers @{'x-goog-api-key'=$Key} -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($json)) -TimeoutSec 120 -ErrorAction Stop
}
function New-GPTRequest([string]$Model,$Messages) {
    if($Model -notin @('gemini-3.5-flash-lite','gemini-2.5-flash-lite','gemini-2.5-flash')) {throw '권장 모델: gemini-3.5-flash-lite'}
    $items=@(); $length=0
    foreach($message in @($Messages | Select-Object -Last 12)) {
        if($message.role -notin @('user','assistant') -or -not $message.content) {continue}
        $content=[string]$message.content; if($content.Length -gt 6000) {$content=$content.Substring(0,6000)}
        $role='user'; if($message.role -eq 'assistant') {$role='model'}
        $items+=@{role=$role;parts=@(@{text=$content})}; $length+=$content.Length
    }
    while($length -gt 18000 -and $items.Count -gt 1) {$length-=$items[0].parts[0].text.Length; $items=@($items | Select-Object -Skip 1)}
    while($items.Count -and $items[0].role -ne 'user') {$items=@($items | Select-Object -Skip 1)}
    if(-not $items.Count) {throw '질문을 입력하세요.'}
    $thinking=@{thinkingBudget=0}; if($Model -eq 'gemini-3.5-flash-lite') {$thinking=@{thinkingLevel='minimal'}}
    return @{model=$Model;contents=$items;systemInstruction=@{parts=@(@{text='한국어로 명확하고 간결하게 답하세요. 사용자가 다른 언어를 원하면 그 언어를 사용하세요.'})};generationConfig=@{maxOutputTokens=2048;thinkingConfig=$thinking}}
}
function Convert-GPTResponse($Response) {
    $candidate=@($Response.candidates) | Select-Object -First 1; $parts=@()
    foreach($part in $candidate.content.parts) {if($part.text -and -not $part.thought) {$parts+=[string]$part.text}}
    $text=$parts -join "`r`n"
    if(-not $text.Trim()) {throw '표시할 답변이 없습니다. 질문을 바꾸어 다시 시도하세요.'}
    return [pscustomobject]@{ok=$true;text=$text;incomplete=($candidate.finishReason -eq 'MAX_TOKENS');tokens=$Response.usageMetadata.totalTokenCount}
}
function Invoke-GPTWork([string]$Root,$Messages) {
    try {
        $path=Join-Path $Root 'gemini-settings.dat'
        if(-not (Test-Path -LiteralPath $path)) {return [pscustomobject]@{ok=$false;message='설정에서 Gemini API 키를 먼저 저장하세요.'}}
        $config=Read-CalendarVault $path
        if(-not $config.key -or -not $config.freeTierConfirmed) {return [pscustomobject]@{ok=$false;message='설정에서 키와 프로젝트의 무료 등급을 확인하세요.'}}
        return Convert-GPTResponse (Invoke-GPTHttp ([string]$config.key) (New-GPTRequest ([string]$config.model) $Messages))
    } catch {
        $code=0; try {$code=[int]$_.Exception.Response.StatusCode} catch {}
        $message='응답을 받지 못했습니다. 인터넷 연결과 설정의 모델을 확인하세요.'
        switch($code) {
            400 {$message='API 키 또는 요청 설정이 올바르지 않습니다.'}
            401 {$message='API 키가 유효하지 않습니다. 설정에서 다시 저장하세요.'}
            403 {$message='API 키의 프로젝트 권한이나 지역 제한을 확인하세요.'}
            404 {$message='이 계정에서 모델을 사용할 수 없습니다. 설정의 모델을 gemini-3.5-flash-lite로 바꾸고 연결 저장을 누르세요.'}
            429 {$message='Gemini 사용 한도에 도달했습니다. 자동 재시도 없이 멈췄습니다. AI Studio에서 한도를 확인하세요.'}
            503 {$message='Gemini 서버가 일시적으로 혼잡합니다. 잠시 뒤 직접 다시 시도하세요.'}
        }
        return [pscustomobject]@{ok=$false;message=$message;quotaExceeded=($code -eq 429)}
    }
}
