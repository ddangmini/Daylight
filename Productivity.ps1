# Local productivity data. Recurring tasks use durable occurrence keys, even after clearing completed tasks.
foreach($name in @('taskRules','activityHistory','timetable')) {if(-not $state[$name]) {$state[$name]=@()}}
function Set-DaylightProperty($Object,[string]$Name,$Value) {
 if($Object -is [hashtable]) {$Object[$Name]=$Value}
 elseif($Object.PSObject.Properties[$Name]) {$Object.$Name=$Value}
 else {$Object|Add-Member -NotePropertyName $Name -NotePropertyValue $Value}
}
function Add-LocalTask([string]$Text,[string]$RuleId='',[string]$Occurrence='') {
 $Text=$Text.Trim(); if(-not $Text) {throw '할 일을 입력하세요.'}
 $task=[pscustomobject]@{id=[guid]::NewGuid().ToString();text=$Text;done=$false;createdAt=(Get-FeatureNow).ToString('o');completedAt='';ruleId=$RuleId;occurrence=$Occurrence}
 $state.tasks=@($state.tasks)+@($task); return $task
}
function Set-LocalTaskDone([string]$Id,[bool]$Done) {
 $task=$state.tasks|Where-Object {$_.id -eq $Id}|Select-Object -First 1; if(-not $task) {return}
 if($Done -and -not $task.done) {
  $now=(Get-FeatureNow).ToString('o'); Set-DaylightProperty $task 'completedAt' $now
  $state.activityHistory=@($state.activityHistory|Where-Object {$_.taskId -ne $Id})+@(@{kind='task';taskId=$Id;title=$task.text;at=$now;minutes=0})
 } elseif(-not $Done) {$state.activityHistory=@($state.activityHistory|Where-Object {$_.taskId -ne $Id}); Set-DaylightProperty $task 'completedAt' ''}
 $task.done=$Done; Save-State; Render-Tasks
}
function Record-FocusActivity([int]$Minutes,[string]$Title) {
 $state.activityHistory=@($state.activityHistory)+@(@{kind='focus';taskId='';title=$Title;at=(Get-FeatureNow).ToString('o');minutes=$Minutes})
 Save-State
}
function Get-RuleOccurrence($Rule,[DateTime]$Date) {
 $start=[DateTime]::ParseExact([string]$Rule.start,'yyyy-MM-dd',[Globalization.CultureInfo]::InvariantCulture)
 if($Date.Date -lt $start.Date) {return ''}
 $eligible=$Rule.frequency -eq 'daily'
 if($Rule.frequency -eq 'weekdays') {$eligible=$Date.DayOfWeek -notin @('Saturday','Sunday')}
 if($Rule.frequency -eq 'weekly') {$eligible=[int]$Date.DayOfWeek -eq [int]$Rule.day}
 if($Rule.frequency -eq 'monthly') {$eligible=$Date.Day -eq [Math]::Min([int]$Rule.day,[DateTime]::DaysInMonth($Date.Year,$Date.Month))}
 if($eligible) {return $Date.ToString('yyyy-MM-dd')}; return ''
}
function Update-RecurringTasks([DateTime]$Now=(Get-FeatureNow)) {
 $changed=$false
 foreach($rule in @($state.taskRules)) {
  if(-not $rule.enabled) {continue}
  $occurrence=Get-RuleOccurrence $rule $Now
  if(-not $occurrence -or ($rule.lastGenerated -and $occurrence -le $rule.lastGenerated)) {continue}
  if(-not @($state.tasks|Where-Object {$_.ruleId -eq $rule.id -and $_.occurrence -eq $occurrence}).Count) {[void](Add-LocalTask $rule.text $rule.id $occurrence)}
  Set-DaylightProperty $rule 'lastGenerated' $occurrence; $changed=$true
 }
 if($changed) {Save-State; Render-Tasks}
}
function Add-TaskRule([string]$Text,[string]$Frequency,[int]$Day,[string]$Start) {
 if(-not $Text.Trim()) {throw '반복할 일을 입력하세요.'}
 if($Frequency -notin @('daily','weekdays','weekly','monthly')) {throw '반복 주기를 선택하세요.'}
 [void][DateTime]::ParseExact($Start,'yyyy-MM-dd',[Globalization.CultureInfo]::InvariantCulture)
 if(($Frequency -eq 'weekly' -and ($Day -lt 0 -or $Day -gt 6)) -or ($Frequency -eq 'monthly' -and ($Day -lt 1 -or $Day -gt 31))) {throw '요일은 일=0~토=6, 월간 날짜는 1~31로 입력하세요.'}
 $state.taskRules=@($state.taskRules)+@(@{id=[guid]::NewGuid().ToString('N');text=$Text.Trim();frequency=$Frequency;day=$Day;start=$Start;enabled=$true;lastGenerated=''})
 Update-RecurringTasks; Save-State
}
function Get-WeeklyReview([DateTime]$Now=(Get-FeatureNow),[int]$Offset=0) {
 $monday=$Now.Date.AddDays(-(([int]$Now.DayOfWeek+6)%7)+7*$Offset); $end=$monday.AddDays(7)
 $events=@($state.activityHistory|Where-Object {try {$d=[DateTime]::Parse($_.at); $d -ge $monday -and $d -lt $end} catch {$false}})
 $tasks=@($events|Where-Object {$_.kind -eq 'task'}); $focus=@($events|Where-Object {$_.kind -eq 'focus'})
 $minutes=($focus|ForEach-Object {$_.minutes}|Measure-Object -Sum).Sum; if(-not $minutes) {$minutes=0}
 $habitChecks=0; foreach($habit in @($state.extras.habits)) {foreach($date in @($habit.dates)) {try {$d=[DateTime]::Parse($date); if($d -ge $monday -and $d -lt $end) {$habitChecks++}} catch {}}}
 return @{start=$monday;end=$end;completed=$tasks.Count;minutes=$minutes;sessions=$focus.Count;habits=$habitChecks;tasks=$tasks;events=$events}
}
function Apply-Situation([string]$Name) {
 if($script:focusSession) {throw '집중을 마친 뒤 배치를 전환하세요.'}
 $profile=$state.layoutProfiles|Where-Object {$_.name -eq $Name}|Select-Object -First 1
 if(-not $profile) {throw '먼저 현재 배치를 이 이름으로 저장하세요.'}
 $state.situationRestore=(Get-LayoutSnapshot); Restore-LayoutSnapshot $profile.snapshot; $state.activeSituation=$Name; Save-State
}
function Save-QuickEntry([string]$Text,[string]$Kind) {
 $Text=$Text.Trim(); if(-not $Text) {throw '내용을 입력하세요.'}
 if($Kind -eq 'task') {[void](Add-LocalTask $Text); Render-Tasks}
 elseif($Kind -eq 'memo') {
  Sync-CurrentNote; $id=[guid]::NewGuid().ToString(); $title=($Text -split '\r?\n')[0]; $title=$title.Substring(0,[Math]::Min(40,$title.Length))
  $state.notes=@($state.notes)+@([pscustomobject]@{id=$id;title=$title;body=$Text}); Select-DaylightNote $id
 } else {throw '할 일 또는 메모를 선택하세요.'}
 Save-State
}
