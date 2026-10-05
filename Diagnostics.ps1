# Log exception summaries only. Never record prompts, notes, HTTP bodies or credentials.
$script:diagnosticSeen=@{}
function Write-DaylightDiagnostic([string]$Area,$Failure) {
    try {
        $ex=$Failure; if($Failure -is [Management.Automation.ErrorRecord]) {$ex=$Failure.Exception}
        $message=[string]$ex.Message
        $message=[regex]::Replace($message,'(?i)(AIza[\w-]+|ya29\.[\w.-]+|sk-[\w-]+|Bearer\s+\S+)','[redacted]')
        $message=[regex]::Replace($message,'(?i)((?:access_token|refresh_token|client_secret|api[_-]?key|code)\s*[=:]\s*)[^\s&,;]+','$1[redacted]')
        $message=$message.Substring(0,[Math]::Min(1600,$message.Length))
        $identity=$Area+'|'+$message
        if($diagnosticSeen.ContainsKey($identity) -and ([DateTime]::UtcNow-$diagnosticSeen[$identity]).TotalSeconds -lt 60) {return}
        $diagnosticSeen[$identity]=[DateTime]::UtcNow
        $path=Join-Path (Split-Path -Parent $DataPath) 'diagnostics.log'
        if((Test-Path -LiteralPath $path) -and (Get-Item -LiteralPath $path).Length -gt 262144) {[IO.File]::Copy($path,$path+'.previous', $true); [IO.File]::WriteAllText($path,'')}
        $stack=''; if($Failure -is [Management.Automation.ErrorRecord]) {$stack=[string]$Failure.ScriptStackTrace}
        [IO.File]::AppendAllText($path,([DateTimeOffset]::Now.ToString('o')+' ['+$Area+'] '+$ex.GetType().Name+': '+$message+"`r`n"+$stack+"`r`n"),[Text.Encoding]::UTF8)
    } catch {}
}
function Invoke-DaylightSafe([string]$Area,[scriptblock]$Work) {
    try {& $Work} catch {Write-DaylightDiagnostic $Area $_; if($ui -and $ui.Status) {$ui.Status.Text='일부 동작을 완료하지 못했습니다 · 다른 기능은 계속 사용할 수 있습니다'}}
}
