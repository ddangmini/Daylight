$script:noteChanging=$false
if(-not @($state.notes).Count) {
    $id=[guid]::NewGuid().ToString()
    $state.notes=@([pscustomobject]@{id=$id;title='메모';body=[string]$state.note})
    $state.selectedNote=$id
}
if(-not @($state.notes | Where-Object {$_.id -eq $state.selectedNote}).Count) { $state.selectedNote=$state.notes[0].id }
function Sync-CurrentNote {
    if($script:noteChanging) { return }
    foreach($note in $state.notes) { if($note.id -eq $state.selectedNote) { $note.title=$ui.NoteTitle.Text; $note.body=$ui.Note.Text; $state.note=$note.body } }
    $ui.NoteCount.Text = "$($state.notes.Count)개 메모 · $($ui.Note.Text.Length)자"
}
function Render-NoteChoice {
    $script:noteChanging=$true
    try {
        $ui.NoteChoice.Items.Clear()
        foreach($note in $state.notes) { $item=New-Object Windows.Controls.ComboBoxItem; $item.Content=[string]$note.title; if(-not $item.Content.Trim()) {$item.Content='제목 없는 메모'}; $item.Tag=$note.id; [void]$ui.NoteChoice.Items.Add($item); if($note.id -eq $state.selectedNote) {$ui.NoteChoice.SelectedItem=$item} }
    } finally { $script:noteChanging=$false }
}
function Select-DaylightNote([string]$Id) {
    $noteTimer.Stop(); Sync-CurrentNote
    $target=$state.notes | Where-Object {$_.id -eq $Id} | Select-Object -First 1
    if(-not $target) { return }
    $state.selectedNote=$Id
    $script:noteChanging=$true
    try {$ui.NoteTitle.Text=[string]$target.title; $ui.Note.Text=[string]$target.body; $state.note=$target.body} finally {$script:noteChanging=$false}
    Render-NoteChoice; Sync-CurrentNote; Save-State
}
$script:noteTimer=New-Object Windows.Threading.DispatcherTimer
$noteTimer.Interval=[TimeSpan]::FromMilliseconds(600)
$noteTimer.Add_Tick({$noteTimer.Stop(); Sync-CurrentNote; Render-NoteChoice; Save-State})
foreach($name in @('Note','NoteTitle')) { $ui[$name].Add_TextChanged({if(-not $script:noteChanging) {$noteTimer.Stop(); $noteTimer.Start()}}) }
$script:noteChanging=$true
$initial=$state.notes | Where-Object {$_.id -eq $state.selectedNote} | Select-Object -First 1
$ui.NoteTitle.Text=[string]$initial.title; $ui.Note.Text=[string]$initial.body
$script:noteChanging=$false; Render-NoteChoice; Sync-CurrentNote
$ui.NoteChoice.Add_SelectionChanged({if(-not $script:noteChanging -and $ui.NoteChoice.SelectedItem) {Select-DaylightNote $ui.NoteChoice.SelectedItem.Tag}})
$ui.NoteNew.Add_Click({Sync-CurrentNote; $id=[guid]::NewGuid().ToString(); $state.notes+= [pscustomobject]@{id=$id;title='새 메모';body=''}; Select-DaylightNote $id; $ui.NoteTitle.Focus(); $ui.NoteTitle.SelectAll()})
$ui.NoteDelete.Add_Click({
    if([Windows.MessageBox]::Show($memoWindow,'현재 메모를 삭제할까요?','메모 삭제','YesNo') -ne 'Yes') {return}
    $noteTimer.Stop(); $state.notes=@($state.notes | Where-Object {$_.id -ne $state.selectedNote})
    if(-not $state.notes.Count) {$state.notes=@([pscustomobject]@{id=[guid]::NewGuid().ToString();title='메모';body=''})}
    # Change the id before selection so the old editor cannot overwrite a surviving note.
    $state.selectedNote=''; Select-DaylightNote $state.notes[0].id
})
$ui.NoteExport.Add_Click({
    Sync-CurrentNote; Save-State
    $picker=New-Object Microsoft.Win32.SaveFileDialog; $picker.Filter='텍스트 파일 (*.txt)|*.txt'; $picker.FileName='Daylight 메모.txt'
    if($picker.ShowDialog($memoWindow)) {try {[IO.File]::WriteAllText($picker.FileName,($ui.NoteTitle.Text+"`r`n`r`n"+$ui.Note.Text),(New-Object Text.UTF8Encoding $true)); $ui.Status.Text='텍스트로 저장했습니다'} catch {$ui.Status.Text='텍스트 저장에 실패했습니다'}}
})
function Convert-NoteToTasks([string]$Text) {
    if(-not $Text.Trim()) {$ui.NoteCount.Text='할 일로 만들 문장을 먼저 선택하세요'; return 0}
    $lines=@($Text -split '\r?\n' | ForEach-Object {($_ -replace '^\s*(?:[-*•]|\d+[.)]|\[[ xX]\])\s*','').Trim()} | Where-Object {$_} | Select-Object -First 100)
    $added=0
    foreach($line in $lines) {
        if(@($state.tasks|Where-Object {-not $_.done -and $_.text -eq $line}).Count) {continue}
        $state.tasks+= [pscustomobject]@{id=[guid]::NewGuid().ToString();text=$line;done=$false}; $added++
    }
    Sync-CurrentNote; Save-State; $script:taskSource='local'; $script:pages.local=0; Update-DaylightLayout
    $ui.NoteCount.Text="$added 개를 내 할 일에 추가했습니다 · 메모는 유지됩니다"
    return $added
}
$noteMenu=New-Object Windows.Controls.ContextMenu
$convertItem=New-Object Windows.Controls.MenuItem; $convertItem.Header='선택한 문장 → 내 할 일'
$convertItem.Add_Click({[void](Convert-NoteToTasks $ui.Note.SelectedText)})
[void]$noteMenu.Items.Add($convertItem)
foreach($pair in @(@('잘라내기',[Windows.Input.ApplicationCommands]::Cut),@('복사',[Windows.Input.ApplicationCommands]::Copy),@('붙여넣기',[Windows.Input.ApplicationCommands]::Paste),@('모두 선택',[Windows.Input.ApplicationCommands]::SelectAll))) {
    $item=New-Object Windows.Controls.MenuItem; $item.Header=$pair[0]; $item.Command=$pair[1]; $item.CommandTarget=$ui.Note; [void]$noteMenu.Items.Add($item)
}
$noteMenu.Add_Opened({$convertItem.IsEnabled=-not [string]::IsNullOrWhiteSpace($ui.Note.SelectedText)})
$ui.Note.ContextMenu=$noteMenu
$convertButton=New-Object Windows.Controls.Button; $convertButton.Content='☑'; $convertButton.ToolTip='선택한 문장 → 내 할 일'; $convertButton.Padding='7,3'; $convertButton.Add_Click({[void](Convert-NoteToTasks $ui.Note.SelectedText)})
$memoWindow.FindName('WidgetTools').Children.Insert(0,$convertButton)
