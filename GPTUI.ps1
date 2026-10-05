$script:geminiCooldown=[DateTime]::MinValue
. (Join-Path $PSScriptRoot 'GPT.ps1')
$script:gptJob=$null
$script:chatMessages=@()
$script:pendingPrompt=''
$script:lastGPTAnswer=''
function Update-GPTSettings {
    $ui.GPTStatus.Text='연결 안 됨 · API 키를 저장하세요'
    if(Test-Path -LiteralPath (Join-Path $PSScriptRoot 'gemini-settings.dat')) {
        try {$config=Read-CalendarVault (Join-Path $PSScriptRoot 'gemini-settings.dat'); $ui.GPTModel.Text=[string]$config.model; $ui.GeminiFreeTier.IsChecked=[bool]$config.freeTierConfirmed; $ui.GPTStatus.Text='Gemini 키 저장됨 · '+$config.model+' · 전송할 때 API 호출'} catch {$ui.GPTStatus.Text='키를 읽지 못했습니다. 같은 Windows 계정에서 실행하거나 키를 다시 저장하세요.'}
    }
    $ui.ChatStatus.Text=$ui.GPTStatus.Text
}
function Set-GPTBusy([bool]$Busy) {$ui.ChatSend.IsEnabled=(-not $Busy -and [DateTime]::UtcNow -ge $script:geminiCooldown); $ui.ChatClear.IsEnabled=-not $Busy; $ui.ChatCancel.IsEnabled=$Busy; $ui.GPTSave.IsEnabled=-not $Busy; $ui.GPTDisconnect.IsEnabled=-not $Busy}
function Render-Chat {
    $parts=@()
    foreach($message in $script:chatMessages) {$label='나'; if($message.role -eq 'assistant') {$label='Gemini'}; $parts+=($label+"`r`n"+$message.content)}
    if($script:pendingPrompt) {$parts+=("나`r`n"+$script:pendingPrompt+"`r`n`r`nGemini · 답변을 기다리는 중…")}
    $ui.ChatHistory.Text=$parts -join "`r`n`r`n────────────`r`n`r`n"; $ui.ChatHistory.ScrollToEnd()
}
function Start-GPTWork {
    if($script:gptJob) {return}; if([DateTime]::UtcNow -lt $script:geminiCooldown) {$ui.ChatStatus.Text='한도 오류 후 잠시 대기 중 · 자동 전송하지 않습니다.'; return}
    $prompt=$ui.ChatInput.Text.Trim()
    if(-not $prompt) {return}
    if($prompt.Length -gt 6000) {$ui.ChatStatus.Text='질문을 6,000자 이하로 줄여주세요.'; return}
    if(-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'gemini-settings.dat'))) {$ui.ChatStatus.Text='설정에서 API 키를 먼저 저장하세요.'; Show-DaylightSettings; return}
    $script:pendingPrompt=$prompt; $ui.ChatInput.Clear(); Set-GPTBusy $true; Render-Chat; $ui.ChatStatus.Text='답변 생성 중 · 최대 2분'
    try {
        $messages=@($script:chatMessages)+@([pscustomobject]@{role='user';content=$prompt})
        $script:gptJob=Start-DaylightJob -ScriptBlock {param($root,$messages); . (Join-Path $root 'Calendar.ps1'); . (Join-Path $root 'GPT.ps1'); Invoke-GPTWork $root $messages} -ArgumentList @($PSScriptRoot,$messages)
    } catch {$ui.ChatInput.Text=$script:pendingPrompt; $script:pendingPrompt=''; Set-GPTBusy $false; Render-Chat; $ui.ChatStatus.Text='전송을 시작하지 못했습니다. 다시 시도하세요.'}
}
function Receive-GPTWork {
    if(-not $script:gptJob) {Set-GPTBusy $false; return}
    if(-not $script:gptJob -or $script:gptJob.State -in @('Running','NotStarted')) {return}
    $result=$null
    try {$result=@(Receive-DaylightJob -Job $script:gptJob -ErrorAction Stop) | Select-Object -Last 1} catch {}
    Remove-DaylightJob -Job $script:gptJob -Force; $script:gptJob=$null
    if($result -and $result.ok) {
        $script:chatMessages+= [pscustomobject]@{role='user';content=$script:pendingPrompt}
        $script:chatMessages+= [pscustomobject]@{role='assistant';content=[string]$result.text}
        $script:lastGPTAnswer=[string]$result.text; $ui.ChatStatus.Text='답변 완료 · 최근 대화 최대 12개를 참고합니다'
        if($result.incomplete) {$ui.ChatStatus.Text='답변 길이 제한에 도달했습니다. 이어서 요청할 수 있습니다.'}
    } else {$ui.ChatInput.Text=$script:pendingPrompt; $ui.ChatStatus.Text='응답을 받지 못했습니다. 다시 시도하세요.'; if($result.message) {$ui.ChatStatus.Text=$result.message}; if($result.quotaExceeded) {$script:geminiCooldown=[DateTime]::UtcNow.AddSeconds(60)}}
    $script:pendingPrompt=''; Set-GPTBusy $false; Render-Chat
}
function Stop-GPTWork {
    if($script:gptJob) {Stop-DaylightJob $script:gptJob; Remove-DaylightJob $script:gptJob -Force; $script:gptJob=$null}
    if($script:pendingPrompt) {$ui.ChatInput.Text=$script:pendingPrompt}
    $script:pendingPrompt=''; Set-GPTBusy $false; Render-Chat
}
$ui.ChatCancel.ToolTip='기다리기를 중단합니다. 이미 처리된 요청은 사용 한도에 포함될 수 있습니다.'
$ui.ChatCancel.Add_Click({Stop-GPTWork; $ui.ChatStatus.Text='기다리기를 중단했습니다.'})
$ui.ChatSend.Add_Click({Start-GPTWork})
$ui.ChatInput.Add_KeyDown({if($_.Key -eq 'Return' -and ([Windows.Input.Keyboard]::Modifiers -band [Windows.Input.ModifierKeys]::Control)) {Start-GPTWork; $_.Handled=$true}})
$ui.ChatClear.Add_Click({$script:chatMessages=@(); $script:lastGPTAnswer=''; $ui.ChatInput.Clear(); Render-Chat; Update-GPTSettings})
$ui.ChatCopy.Add_Click({if($script:lastGPTAnswer) {[Windows.Clipboard]::SetText($script:lastGPTAnswer); $ui.ChatStatus.Text='답변을 복사했습니다.'}})
$ui.GPT.Add_Click({Set-WidgetVisible 'chat' $true})
$ui.GPTSave.Add_Click({
    try {
        $path=Join-Path $PSScriptRoot 'gemini-settings.dat'; $key=$ui.GPTKey.Password.Trim()
        if(-not $key -and (Test-Path -LiteralPath $path)) {$key=(Read-CalendarVault $path).key}
        $model=$ui.GPTModel.Text.Trim()
        if(-not $key -or $key -notmatch '^AIza[A-Za-z0-9_-]{20,}$') {$ui.GPTStatus.Text='Gemini API 키를 입력하세요.'; return}
        if($model -notin @('gemini-3.5-flash-lite','gemini-2.5-flash-lite','gemini-2.5-flash')) {$ui.GPTStatus.Text='권장 모델: gemini-3.5-flash-lite'; return}
        if(-not $ui.GeminiFreeTier.IsChecked) {$ui.GPTStatus.Text='AI Studio에서 프로젝트의 무료 등급을 확인한 뒤 체크하세요.'; return}; Write-CalendarVault $path @{key=$key;model=$model;freeTierConfirmed=$true}; $ui.GPTKey.Clear(); Update-GPTSettings
    } catch {$ui.GPTStatus.Text='연결 정보를 저장하지 못했습니다. 폴더 권한을 확인하세요.'}
})
$ui.GPTDisconnect.Add_Click({try {foreach($name in @('gemini-settings.dat','gemini-settings.dat.bak','gemini-settings.dat.tmp')) {$path=Join-Path $PSScriptRoot $name; if(Test-Path -LiteralPath $path) {Remove-Item -LiteralPath $path -Force}}; $ui.GPTKey.Clear(); Update-GPTSettings} catch {$ui.GPTStatus.Text='연결 정보를 지우지 못했습니다.'}})
$ui.GPTHelp.Add_Click({Start-Process 'https://aistudio.google.com/api-keys'})
Update-GPTSettings

$ui.GeminiQuota.Add_Click({Start-Process 'https://ai.google.dev/gemini-api/docs/rate-limits'})
