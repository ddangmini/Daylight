# Isolated in-process workers: no console host or remoting host calls on the UI thread.
function Start-DaylightJob {
    param([scriptblock]$ScriptBlock,[object[]]$ArgumentList)
    $runspace=[Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
    $runspace.ApartmentState='MTA'; $runspace.ThreadOptions='ReuseThread'
    $engine=$null
    try {
        $runspace.Open(); $engine=[Management.Automation.PowerShell]::Create(); $engine.Runspace=$runspace
        $runspace.SessionStateProxy.SetVariable('ErrorActionPreference','Stop')
        $runspace.SessionStateProxy.SetVariable('ProgressPreference','SilentlyContinue')
        [void]$engine.AddScript($ScriptBlock.ToString())
        foreach($argument in $ArgumentList) {[void]$engine.AddArgument($argument)}
        $job=[pscustomobject]@{Engine=$engine;Runspace=$runspace;Async=$engine.BeginInvoke();Disposed=$false}
        $job|Add-Member -MemberType ScriptProperty -Name State -Value {if($this.Async.IsCompleted) {return 'Completed'}; return 'Running'}
        return $job
    } catch {if($engine) {$engine.Dispose()}; $runspace.Dispose(); throw}
}
function Receive-DaylightJob {
    param($Job)
    $output=$Job.Engine.EndInvoke($Job.Async)
    if($Job.Engine.Streams.Error.Count) {throw $Job.Engine.Streams.Error[0]}
    return $output
}
function Stop-DaylightJob {param($Job); if($Job -and -not $Job.Disposed -and -not $Job.Async.IsCompleted) {$Job.Engine.Stop()}}
function Remove-DaylightJob {
    param($Job,[switch]$Force)
    if(-not $Job -or $Job.Disposed) {return}
    try {Stop-DaylightJob $Job} finally {$Job.Engine.Dispose(); $Job.Runspace.Dispose(); $Job.Disposed=$true}
}
function Wait-DaylightJob {
    param($Job,[int]$Timeout=15)
    if($Job.Async.AsyncWaitHandle.WaitOne([TimeSpan]::FromSeconds($Timeout))) {return $Job}
    throw '백그라운드 작업 대기 시간이 지났습니다.'
}
