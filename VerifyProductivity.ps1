$saveProduct=@{}; foreach($name in @('tasks','taskRules','notes','selectedNote','activityHistory','timetable','layoutProfiles','situationRestore','activeSituation')) {$saveProduct[$name]=$state[$name]}
try {
 if(-not ('DaylightQuickHotkey' -as [type])) {Add-Type -Path (Join-Path $PSScriptRoot 'QuickInput.cs') -ReferencedAssemblies @([Windows.Interop.HwndSource].Assembly.Location,[Windows.DependencyObject].Assembly.Location,'System.dll')}
 $state.taskRules=@(); $state.tasks=@(); $state.activityHistory=@(); $state.timetable=@()
 Save-QuickEntry '빠른 할 일' 'task'; Assert-UI ($state.tasks.Count -eq 1 -and -not $state.tasks[0].done) 'Quick task input'
 $id=$state.tasks[0].id; Set-LocalTaskDone $id $true; Set-LocalTaskDone $id $true
 Assert-UI ($state.activityHistory.Count -eq 1) 'Completion history idempotence'
 Set-LocalTaskDone $id $false; Assert-UI ($state.activityHistory.Count -eq 0) 'Completion undo removes history'
 Set-LocalTaskDone $id $true; Record-FocusActivity 25 '검증 집중'
 $review=Get-WeeklyReview; Assert-UI ($review.completed -eq 1 -and $review.minutes -eq 25) 'Weekly task and focus totals'
 $count=$state.notes.Count; Save-QuickEntry "빠른 메모`n내용" 'memo'; Assert-UI ($state.notes.Count -eq $count+1 -and $ui.Note.Text.Contains('내용')) 'Quick memo preserves content'
 $today=Get-FeatureNow; Add-TaskRule '매일 복습' 'daily' 1 $today.ToString('yyyy-MM-dd'); $count=$state.tasks.Count
 Update-RecurringTasks $today; Assert-UI ($state.tasks.Count -eq $count) 'Recurring task not duplicated on refresh'
 $state.tasks=@($state.tasks|Where-Object {$_.ruleId -ne $state.taskRules[0].id}); Update-RecurringTasks $today
 Assert-UI (-not @($state.tasks|Where-Object {$_.ruleId -eq $state.taskRules[0].id}).Count) 'Cleared occurrence not recreated'
 Update-RecurringTasks $today.AddDays(1); Assert-UI (@($state.tasks|Where-Object {$_.ruleId -eq $state.taskRules[0].id}).Count -eq 1) 'Next date generates next occurrence'
 Assert-UI ((Get-RuleOccurrence @{start='2026-01-01';frequency='monthly';day=31} ([DateTime]'2026-02-28')) -eq '2026-02-28') 'Month end recurrence clamps short months'
 Assert-UI (-not (Get-RuleOccurrence @{start='2026-01-01';frequency='weekdays';day=1} ([DateTime]'2026-10-10'))) 'Weekdays skip weekends'
 Assert-UI (@(Get-TimetableDays).Count -eq 5) 'Weekends hidden by default'
 Add-TimetableClass '' '수업 A' 1 '10:00' '11:30' '101호' 'https://example.com/class' '#A3E8D2' '2026-10-01' '2026-12-31'
 $next=Get-NextClass ([DateTime]'2026-10-05T09:40:00'); Assert-UI ($next.minutes -eq 20 -and -not $next.ongoing) 'Next lesson countdown'
 $next=Get-NextClass ([DateTime]'2026-10-05T10:20:00'); Assert-UI $next.ongoing 'Current lesson recognized'
 $blocked=$false; try {Add-TimetableClass '' 'conflict' 1 '11:00' '12:00' '' '' '#A3E8D2' '2026-10-01' '2026-12-31'} catch {$blocked=$true}; Assert-UI $blocked 'Conflicting lessons rejected'
 $blocked=$false; try {Add-TimetableClass '' 'unsafe' 2 '10:00' '11:00' '' 'file:///C:/Windows' '#A3E8D2' '2026-10-01' '2026-12-31'} catch {$blocked=$true}; Assert-UI $blocked 'Unsafe class links rejected'
 Add-TimetableClass '' '주말 수업' 6 '09:00' '10:00' '' '' '#A5C8EF' '2026-10-01' '2026-12-31'
 $days=@(Get-TimetableDays); Assert-UI ($days.Count -eq 6 -and 6 -in $days -and 0 -notin $days) 'Only scheduled weekend day appears'
 Assert-UI (-not (Get-NextClass ([DateTime]'2027-01-01'))) 'Semester boundaries respected'
 Show-TimetableEditor; Assert-UI ($script:timetableEditor.FindName('ClassDay').Items.Count -eq 7) 'Timetable editor fields'
 Show-QuickEntry; Assert-UI ($script:quickWindow.FindName('QuickText')) 'Quick dialog fields'
 Show-WeeklyReview; Assert-UI ($script:reviewWindow.FindName('ReviewRows').Children.Count -eq 7) 'Weekly review renders seven days'
 Assert-UI ((Get-StartupCommand 'C:\Apps\Daylight') -eq '"C:\Apps\Daylight\Daylight.exe"') 'Startup launches hidden GUI executable with quoted path'
 $state.layoutProfiles=@(); Save-LayoutProfile '검증 상황'; Apply-Situation '검증 상황'; Assert-UI ($state.activeSituation -eq '검증 상황' -and $state.situationRestore) 'Situation switch stores undo snapshot'
 Save-State; $saved=Get-Content $DataPath -Raw -Encoding UTF8|ConvertFrom-Json
 Assert-UI ($saved.timetable.Count -eq 2 -and $saved.taskRules.Count -eq 1 -and $saved.activityHistory.Count -eq 2) 'Productivity data persistence'
 'PASS: quick input, completion history, recurring idempotence/month ends/weekends, semester timetable/countdown/conflicts, weekly review, situations, startup command and persistence'
} finally {
 foreach($name in $saveProduct.Keys) {$state[$name]=$saveProduct[$name]}
 $script:closingAll=$true; Stop-Productivity; $script:closingAll=$false
 $script:quickWindow=$null; $script:reviewWindow=$null; $script:timetableEditor=$null
 Render-NoteChoice; Select-DaylightNote $state.selectedNote; Render-Tasks; Refresh-TaskRules; Refresh-ProfileChoice; Render-Timetable
}
