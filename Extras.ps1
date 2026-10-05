. (Join-Path $PSScriptRoot 'ExtraBackend.ps1')
$defaultExtras=@{ddays=@();habits=@();launchers=@();progress=@();quotes=@(@{text='작은 한 걸음도 앞으로 가는 길입니다.';author=''},@{text='오늘 할 수 있는 만큼, 꾸준히.';author=''});photoFiles=@();photoMinutes=5;photoFill=$false;quoteOffset=0;launcherPage=0;ddaySelected='';habitPage=0;progressPage=0}
$extras=@{}; foreach($name in $defaultExtras.Keys) {$extras[$name]=$defaultExtras[$name]; if($state.extras -and $null -ne $state.extras.PSObject.Properties[$name]) {$extras[$name]=$state.extras.$name}}
$state.extras=$extras
foreach($name in @('ddays','habits','launchers','progress','quotes','photoFiles')) {$extras[$name]=@($extras[$name]|Where-Object {$null -ne $_})}
$script:extraJobs=@{media=$null;system=$null}; $script:extraLast=@{media=[DateTime]::MinValue;system=[DateTime]::MinValue;local=[DateTime]::MinValue;photo=[DateTime]::MinValue}
$script:extraChoosing=$false; $script:photoIndex=0; $script:cpuHistory=@(); $script:extraEditorChanging=$false; $script:pendingMediaAction=''
$extraSettingsMarkup=@'
<StackPanel TextElement.Foreground="#E9EDF5" xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
 <TextBlock Text="추가 위젯 설정" FontSize="22" FontWeight="SemiBold" Margin="0,22,0,16"/>
 <TextBlock Text="D-day" FontSize="17" Margin="0,10,0,8"/><TextBlock Text="노션의 미완료 마감과 구글 일정을 자동으로 가져옵니다. 중요한 날은 직접 추가할 수도 있습니다." FontSize="12" TextWrapping="Wrap" Margin="0,0,0,8"/>
 <TextBox x:Name="DdayNameInput" ToolTip="시험·과제·여행 이름"/><DatePicker x:Name="DdayDateInput" Margin="0,8,0,0" ToolTip="목표 날짜"/><WrapPanel><Button x:Name="DdayAdd" Content="중요한 날 추가"/><Button x:Name="DdayRemove" Content="선택 항목 삭제"/></WrapPanel><ComboBox x:Name="DdayManage"/>
 <TextBlock Text="습관" FontSize="17" Margin="0,24,0,8"/><TextBox x:Name="HabitNameInput" ToolTip="습관 이름 · 예: 20분 독서"/><WrapPanel><Button x:Name="HabitAdd" Content="습관 추가"/><Button x:Name="HabitRemove" Content="선택 습관 삭제"/></WrapPanel><ComboBox x:Name="HabitManage"/>
 <TextBlock Text="빠른 실행" FontSize="17" Margin="0,24,0,8"/><TextBox x:Name="LaunchNameInput" ToolTip="버튼 이름"/><TextBox x:Name="LaunchPathInput" ToolTip="앱·폴더 경로 또는 https:// 주소" Margin="0,8,0,0"/><WrapPanel><Button x:Name="LaunchBrowse" Content="앱·파일 선택"/><Button x:Name="LaunchFolder" Content="폴더 선택"/></WrapPanel><WrapPanel><Button x:Name="LaunchAdd" Content="바로가기 추가"/><Button x:Name="LaunchRemove" Content="선택 항목 삭제"/></WrapPanel><ComboBox x:Name="LaunchManage"/>
 <TextBlock Text="공부·독서 진행률" FontSize="17" Margin="0,24,0,8"/><TextBox x:Name="ProgressNameInput" ToolTip="책·강의·프로젝트 이름"/><WrapPanel Margin="0,8,0,0"><TextBox x:Name="ProgressCurrentInput" Text="0" Width="90" ToolTip="현재 진도"/><TextBlock Text=" / " VerticalAlignment="Center"/><TextBox x:Name="ProgressTotalInput" Text="100" Width="90" ToolTip="전체 목표"/></WrapPanel><WrapPanel><Button x:Name="ProgressAdd" Content="등록·수정"/><Button x:Name="ProgressRemove" Content="선택 항목 삭제"/></WrapPanel><ComboBox x:Name="ProgressManage"/>
 <TextBlock Text="사진·아트 프레임" FontSize="17" Margin="0,24,0,8"/><WrapPanel><Button x:Name="PhotoChoose" Content="사진 여러 장 선택"/><Button x:Name="PhotoFolder" Content="사진 폴더에서 가져오기"/><Button x:Name="PhotoClear" Content="사진 비우기"/></WrapPanel><WrapPanel Margin="0,8,0,0"><TextBox x:Name="PhotoMinutesInput" Text="5" Width="60"/><TextBlock Text="분마다 다음 사진 · 0은 자동 전환 끄기" TextWrapping="Wrap" MaxWidth="230" Foreground="#B8C5D8" VerticalAlignment="Center" FontSize="12" Margin="8,0,0,0"/></WrapPanel><CheckBox x:Name="PhotoFill" Content="프레임에 꽉 채우기" Margin="0,8,0,0"/><Button x:Name="PhotoSave" Content="사진 설정 저장" HorizontalAlignment="Left"/><TextBlock x:Name="PhotoSettingsHint" FontSize="12" TextWrapping="Wrap"/>
 <TextBlock Text="오늘의 문장" FontSize="17" Margin="0,24,0,8"/><TextBox x:Name="QuoteTextInput" AcceptsReturn="True" Height="76" TextWrapping="Wrap" ToolTip="내가 저장할 문장"/><TextBox x:Name="QuoteAuthorInput" ToolTip="글쓴이·출처 (선택)" Margin="0,8,0,0"/><WrapPanel><Button x:Name="QuoteAdd" Content="문장 추가"/><Button x:Name="QuoteRemove" Content="선택 문장 삭제"/></WrapPanel><ComboBox x:Name="QuoteManage"/>
 <TextBlock Text="지금 재생 중 · 시스템 상태" FontSize="17" Margin="0,24,0,8"/><TextBlock Text="음악은 Windows 미디어 표시를 지원하는 앱에서 재생할 때 나타납니다. 음악은 5초, 시스템 상태는 10초마다 갱신하며 위젯을 끄면 조회도 멈춥니다." FontSize="12" TextWrapping="Wrap"/>
 <TextBlock x:Name="ExtraStatus" Text="새 위젯은 위쪽의 추가 위젯 목록에서 켜세요." FontSize="12" TextWrapping="Wrap" Margin="0,16,0,20"/>
</StackPanel>
'@
$extraSettingsMarkup=[regex]::Replace($extraSettingsMarkup,'<TextBlock Text="(D-day|습관|빠른 실행|공부·독서 진행률|사진·아트 프레임|오늘의 문장)" FontSize="17"[^>]*/>(.*?)(?=<TextBlock Text="(?:습관|빠른 실행|공부·독서 진행률|사진·아트 프레임|오늘의 문장|지금 재생 중 · 시스템 상태)" FontSize="17")','<Expander Header="$1" Foreground="#E9EDF5" FontSize="16" Margin="0,8,0,8"><StackPanel Margin="0,12,0,8">$2</StackPanel></Expander>',[Text.RegularExpressions.RegexOptions]::Singleline)
[xml]$extraSettingsXML=$extraSettingsMarkup
$script:extraSettings=[Windows.Markup.XamlReader]::Load((New-Object Xml.XmlNodeReader $extraSettingsXML))
$settingsWindow.Content.Content.Children.Insert($settingsWindow.Content.Content.Children.Count-2,$extraSettings)
$script:extraUI=@{}
foreach($name in @('DdayNameInput','DdayDateInput','DdayAdd','DdayRemove','DdayManage','HabitNameInput','HabitAdd','HabitRemove','HabitManage','LaunchNameInput','LaunchPathInput','LaunchBrowse','LaunchFolder','LaunchAdd','LaunchRemove','LaunchManage','ProgressNameInput','ProgressCurrentInput','ProgressTotalInput','ProgressAdd','ProgressRemove','ProgressManage','PhotoChoose','PhotoFolder','PhotoClear','PhotoMinutesInput','PhotoFill','PhotoSave','PhotoSettingsHint','QuoteTextInput','QuoteAuthorInput','QuoteAdd','QuoteRemove','QuoteManage','ExtraStatus')) {$extraUI[$name]=$extraSettings.FindName($name)}
$extraUI.PhotoMinutesInput.Text=[string]$extras.photoMinutes; $extraUI.PhotoFill.IsChecked=[bool]$extras.photoFill; $extraUI.DdayDateInput.SelectedDate=[DateTime]::Today
function Get-ExtraToday {return (Get-FeatureNow).Date}
function Get-DdayCandidates {
    $all=@()
    foreach($item in $state.extras.ddays) {$all+= [pscustomobject]@{id=$item.id;title=$item.title;date=$item.date;source='직접 등록'}}
    foreach($item in $script:lastNotionAgenda.tasks) {if(-not $item.done -and $item.due) {$all+=[pscustomobject]@{id='notion:'+ $item.id;title=$item.text;date=([string]$item.due).Substring(0,[Math]::Min(10,([string]$item.due).Length));source='노션'}}}
    foreach($item in $script:lastAgenda.events) {$all+=[pscustomobject]@{id='calendar:'+ $item.id;title=$item.title;date=$item.date;source='캘린더'}}
    $valid=@(); foreach($item in $all) {$date=[DateTime]::MinValue; if([DateTime]::TryParseExact([string]$item.date,'yyyy-MM-dd',[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::None,[ref]$date)) {$valid+=$item}}
    return @($valid|Sort-Object date,title)
}
function Render-Dday {
    $all=@(Get-DdayCandidates); $selected=$extras.ddaySelected
    if(-not @($all|Where-Object {$_.id -eq $selected}).Count) {$next=$all|Where-Object {$_.date -ge (Get-ExtraToday).ToString('yyyy-MM-dd')}|Select-Object -First 1; if(-not $next) {$next=$all|Select-Object -Last 1}; $selected=$next.id; $extras.ddaySelected=$selected}
    $script:extraChoosing=$true
    try {$ui.DdayChoice.Items.Clear(); foreach($item in $all) {$entry=New-Object Windows.Controls.ComboBoxItem; $entry.Content=$item.title+' · '+$item.source; $entry.Tag=$item; [void]$ui.DdayChoice.Items.Add($entry); if($item.id -eq $selected) {$ui.DdayChoice.SelectedItem=$entry}}} finally {$script:extraChoosing=$false}
    $item=$all|Where-Object {$_.id -eq $selected}|Select-Object -First 1
    if(-not $item) {$ui.DdayNumber.Text='D−?'; $ui.DdayTitle.Text='중요한 날을 등록하세요'; $ui.DdayDate.Text=''; $ui.DdayHint.Text='설정에서 날짜 추가 · 노션·캘린더 마감도 표시'; return}
    $days=([DateTime]::ParseExact($item.date,'yyyy-MM-dd',[Globalization.CultureInfo]::InvariantCulture)-(Get-ExtraToday)).Days
    $ui.DdayNumber.Text='D−'+$days; if($days -eq 0) {$ui.DdayNumber.Text='D-DAY'} elseif($days -lt 0) {$ui.DdayNumber.Text='D+'+[Math]::Abs($days)}
    $ui.DdayTitle.Text=$item.title; $ui.DdayDate.Text=$item.date+' · '+$item.source
    $ui.DdayHint.Text='다른 날짜는 아래 목록에서 선택'; if($item.source -eq '캘린더') {$ui.DdayHint.Text='현재 조회된 7일 범위의 일정입니다'}
}
function Get-HabitStreak($Dates,[DateTime]$Today=(Get-ExtraToday)) {
    $day=$Today.Date; if($day.ToString('yyyy-MM-dd') -notin $Dates) {$day=$day.AddDays(-1)}
    $count=0; while($day.ToString('yyyy-MM-dd') -in $Dates) {$count++; $day=$day.AddDays(-1); if($count -gt 10000) {break}}
    return $count
}
function Render-Habits {
    $ui.HabitRows.Children.Clear(); $today=Get-ExtraToday
    $capacity=[Math]::Max(1,[Math]::Floor(($widgets.habits.Height-150)/65))
    $count=@($extras.habits).Count; $pages=[Math]::Max(1,[Math]::Ceiling($count/$capacity)); $extras.habitPage=[Math]::Max(0,[Math]::Min($pages-1,[int]$extras.habitPage))
    foreach($habit in @($extras.habits|Select-Object -Skip ($extras.habitPage*$capacity) -First $capacity)) {
        $block=New-Object Windows.Controls.StackPanel; $block.Margin='0,0,0,10'
        $check=New-Object Windows.Controls.CheckBox; $check.Content=$habit.name+' · '+(Get-HabitStreak $habit.dates $today)+'일 연속'; $check.IsChecked=$today.ToString('yyyy-MM-dd') -in @($habit.dates); $check.Tag=$habit.id
        $check.Add_Click({$h=$extras.habits|Where-Object {$_.id -eq $this.Tag}|Select-Object -First 1; $day=(Get-ExtraToday).ToString('yyyy-MM-dd'); $h.dates=@($h.dates|Where-Object {$_ -ne $day}); if($this.IsChecked) {$h.dates+= $day}; Save-State; Render-Habits})
        [void]$block.Children.Add($check)
        $week=New-Object Windows.Controls.StackPanel; $week.Orientation='Horizontal'; $week.Margin='24,5,0,0'
        for($i=6;$i -ge 0;$i--) {$day=$today.AddDays(-$i).ToString('yyyy-MM-dd'); $dot=New-Object Windows.Controls.Border; $dot.Width=12; $dot.Height=8; $dot.CornerRadius=3; $dot.Margin='0,0,5,0'; $dot.Background='#304055'; if($day -in @($habit.dates)) {$dot.Background=$state.appearance.habits.accent}; $dot.ToolTip=$day; [void]$week.Children.Add($dot)}
        [void]$block.Children.Add($week); [void]$ui.HabitRows.Children.Add($block)
    }
    $ui.HabitHint.Text="최근 7일 · $($extras.habitPage+1) / $pages"
    if(-not $count) {$ui.HabitHint.Text='설정에서 습관을 추가하세요'}
}
function Test-LaunchTarget([string]$Target) {
    $uri=$null; if([Uri]::TryCreate($Target,[UriKind]::Absolute,[ref]$uri) -and $uri.Scheme -in @('http','https')) {return $true}
    return ([IO.Path]::IsPathRooted($Target) -and (Test-Path -LiteralPath $Target))
}
function Get-LauncherIcon([string]$Path) {
    if(-not (Test-Path -LiteralPath $Path -PathType Leaf)) {return $null}
    $icon=$null; $bitmap=$null; $stream=$null
    try {
        $icon=[Drawing.Icon]::ExtractAssociatedIcon($Path); if(-not $icon) {return $null}
        $bitmap=$icon.ToBitmap(); $stream=New-Object IO.MemoryStream; $bitmap.Save($stream,[Drawing.Imaging.ImageFormat]::Png); $stream.Position=0
        $image=New-Object Windows.Media.Imaging.BitmapImage; $image.BeginInit(); $image.CacheOption='OnLoad'; $image.StreamSource=$stream; $image.EndInit(); $image.Freeze(); return $image
    } catch {return $null} finally {if($stream){$stream.Dispose()}; if($bitmap){$bitmap.Dispose()}; if($icon){$icon.Dispose()}}
}
function Render-Launcher {
    $ui.LaunchItems.Children.Clear()
    $capacity=[Math]::Max(1,[Math]::Floor(($widgets.launcher.Width-48)/148))*[Math]::Max(1,[Math]::Floor(($widgets.launcher.Height-125)/45))
    $pages=[Math]::Max(1,[Math]::Ceiling($extras.launchers.Count/$capacity)); $extras.launcherPage=[Math]::Max(0,[Math]::Min($pages-1,[int]$extras.launcherPage))
    foreach($item in @($extras.launchers|Select-Object -Skip ($extras.launcherPage*$capacity) -First $capacity)) {$button=New-Object Windows.Controls.Button; $button.Tag=$item.target; $button.ToolTip=$item.target; $button.Margin='0,0,8,8'; $button.Width=140; $button.Height=36
        $content=New-Object Windows.Controls.StackPanel; $content.Orientation='Horizontal'; $icon=Get-LauncherIcon $item.target
        if($icon) {$image=New-Object Windows.Controls.Image; $image.Source=$icon; $image.Width=18; $image.Height=18; $image.Margin='0,0,8,0'; [void]$content.Children.Add($image)}
        $label=New-Object Windows.Controls.TextBlock; $label.Text=$item.name; $label.MaxWidth=90; $label.TextTrimming='CharacterEllipsis'; [void]$content.Children.Add($label); $button.Content=$content
        $button.Add_Click({try {if(-not (Test-LaunchTarget $this.Tag)) {throw 'missing'}; Start-Process -FilePath $this.Tag; $ui.LaunchHint.Text='앱 · 폴더 · 사이트'} catch {$ui.LaunchHint.Text='경로를 찾지 못했습니다. 설정에서 다시 등록하세요'}}); [void]$ui.LaunchItems.Children.Add($button)}
    $ui.LaunchHint.Text="앱 · 폴더 · 사이트 · $($extras.launcherPage+1) / $pages"; if(-not $extras.launchers.Count) {$ui.LaunchHint.Text='설정에서 자주 쓰는 앱·폴더·사이트를 추가하세요'}
}
function Get-ProgressPercent($Current,$Total) {if([double]$Total -le 0) {return 0}; return [Math]::Max(0,[Math]::Min(100,[Math]::Round(100*[double]$Current/[double]$Total)))}
function Render-ProgressWidgets {
    $ui.ProgressRows.Children.Clear(); $capacity=[Math]::Max(1,[Math]::Floor(($widgets.progress.Height-145)/80))
    $pages=[Math]::Max(1,[Math]::Ceiling($extras.progress.Count/$capacity)); $extras.progressPage=[Math]::Max(0,[Math]::Min($pages-1,[int]$extras.progressPage))
    foreach($item in @($extras.progress|Select-Object -Skip ($extras.progressPage*$capacity) -First $capacity)) {
        $block=New-Object Windows.Controls.StackPanel; $block.Margin='0,0,0,15'; $line=New-Object Windows.Controls.DockPanel
        $plus=New-Object Windows.Controls.Button; $plus.Content='+'; $plus.Tag=$item.id; $plus.Padding='7,1'; $plus.ToolTip='진도 1 추가'; $plus.Style=$widgets.progress.FindResource('QuietAction'); [Windows.Controls.DockPanel]::SetDock($plus,'Right'); $plus.Add_Click({$item=$extras.progress|Where-Object {$_.id -eq $this.Tag}|Select-Object -First 1; $item.current=[Math]::Min([double]$item.total,[double]$item.current+1); Save-State; Render-ProgressWidgets})
        [void]$line.Children.Add($plus); $label=New-Object Windows.Controls.TextBlock; $label.Text=$item.name+' · '+(Get-ProgressPercent $item.current $item.total)+'%'; $label.TextTrimming='CharacterEllipsis'; $label.VerticalAlignment='Center'; [void]$line.Children.Add($label); [void]$block.Children.Add($line)
        $bar=New-Object Windows.Controls.ProgressBar; $bar.Maximum=100; $bar.Value=Get-ProgressPercent $item.current $item.total; $bar.Height=5; $bar.Margin='0,8,0,5'; $bar.Foreground=$state.appearance.progress.accent; [void]$block.Children.Add($bar)
        $count=New-Object Windows.Controls.TextBlock; $count.Text=[string]$item.current+' / '+[string]$item.total; $count.FontSize=10; [void]$block.Children.Add($count); [void]$ui.ProgressRows.Children.Add($block)
    }
    if(-not $extras.progress.Count) {$empty=New-Object Windows.Controls.TextBlock; $empty.Text='설정에서 책·강의·프로젝트를 등록하세요'; $empty.TextWrapping='Wrap'; [void]$ui.ProgressRows.Children.Add($empty)}
}
function Set-Photo([int]$Direction=0) {
    $files=@($extras.photoFiles|Where-Object {Test-Path -LiteralPath $_ -PathType Leaf})
    $ui.PhotoImage.Stretch=$(if($extras.photoFill){'UniformToFill'}else{'Uniform'})
    if(-not $files.Count) {$ui.PhotoImage.Source=$null; $ui.PhotoPlaceholder.Visibility='Visible'; $ui.PhotoCaption.Text='사진을 선택하세요'; return}
    $script:photoIndex=($script:photoIndex+$Direction+$files.Count)%$files.Count
    $image=$null
    for($attempt=0;$attempt -lt $files.Count;$attempt++) {
        try {
            $stream=[IO.File]::OpenRead($files[$photoIndex]); try {$image=New-Object Windows.Media.Imaging.BitmapImage; $image.BeginInit(); $image.CacheOption='OnLoad'; $image.DecodePixelWidth=1600; $image.StreamSource=$stream; $image.EndInit(); $image.Freeze()} finally {$stream.Dispose()}
            break
        } catch {$image=$null; $script:photoIndex=($photoIndex+1)%$files.Count}
    }
    $ui.PhotoImage.Source=$image; $ui.PhotoPlaceholder.Visibility=$(if($image){'Collapsed'}else{'Visible'})
    $ui.PhotoCaption.Text=[IO.Path]::GetFileNameWithoutExtension($files[$photoIndex]); $script:extraLast.photo=[DateTime]::UtcNow
    $extraUI.PhotoSettingsHint.Text=$files.Count.ToString()+'장 등록 · 원본 파일을 그대로 사용합니다'
}
function Render-Quote {
    if(-not $extras.quotes.Count) {$ui.QuoteText.Text='설정에서 나만의 문장을 추가하세요'; $ui.QuoteAuthor.Text=''; return}
    $index=([int](Get-ExtraToday).DayOfYear+[int]$extras.quoteOffset)%$extras.quotes.Count
    $item=$extras.quotes[$index]; $ui.QuoteText.Text=$item.text; $ui.QuoteAuthor.Text=$item.author
}
function Refresh-ExtraEditors {
    $script:extraEditorChanging=$true
    try {
        foreach($pair in @(@('DdayManage','ddays','title'),@('HabitManage','habits','name'),@('LaunchManage','launchers','name'),@('ProgressManage','progress','name'),@('QuoteManage','quotes','text'))) {
            $combo=$extraUI[$pair[0]]; $combo.Items.Clear()
            foreach($item in $extras[$pair[1]]) {$entry=New-Object Windows.Controls.ComboBoxItem; $entry.Content=[string]$item.($pair[2]); $entry.Tag=$item; [void]$combo.Items.Add($entry)}
        }
    } finally {$script:extraEditorChanging=$false}
}
function Commit-ExtraEdit {Save-State; Refresh-ExtraEditors; Render-Dday; Render-Habits; Render-Launcher; Render-ProgressWidgets; Render-Quote; Set-DaylightTextTone; $extraUI.ExtraStatus.Text='저장했습니다 · 위젯을 켜면 표시됩니다'}
$extraUI.DdayAdd.Add_Click({$name=$extraUI.DdayNameInput.Text.Trim(); if(-not $name -or -not $extraUI.DdayDateInput.SelectedDate) {$extraUI.ExtraStatus.Text='이름과 날짜를 입력하세요'; return}; $extras.ddays+= [pscustomobject]@{id=[guid]::NewGuid().ToString();title=$name;date=$extraUI.DdayDateInput.SelectedDate.ToString('yyyy-MM-dd')}; $extraUI.DdayNameInput.Clear(); Commit-ExtraEdit})
$extraUI.HabitAdd.Add_Click({$name=$extraUI.HabitNameInput.Text.Trim(); if(-not $name) {return}; $extras.habits+= [pscustomobject]@{id=[guid]::NewGuid().ToString();name=$name;dates=@()}; $extraUI.HabitNameInput.Clear(); Commit-ExtraEdit})
$extraUI.LaunchAdd.Add_Click({$name=$extraUI.LaunchNameInput.Text.Trim(); $target=$extraUI.LaunchPathInput.Text.Trim().Trim('"'); if(-not $name -or -not (Test-LaunchTarget $target)) {$extraUI.ExtraStatus.Text='이름과 실제 파일·폴더 경로 또는 웹 주소를 확인하세요'; return}; $extras.launchers+= [pscustomobject]@{id=[guid]::NewGuid().ToString();name=$name;target=$target}; Commit-ExtraEdit})
$extraUI.LaunchBrowse.Add_Click({$picker=New-Object Microsoft.Win32.OpenFileDialog; $picker.Filter='앱·파일|*.*'; if($picker.ShowDialog($settingsWindow)) {$extraUI.LaunchPathInput.Text=$picker.FileName; if(-not $extraUI.LaunchNameInput.Text) {$extraUI.LaunchNameInput.Text=[IO.Path]::GetFileNameWithoutExtension($picker.FileName)}}})
$extraUI.LaunchFolder.Add_Click({$picker=New-Object Windows.Forms.FolderBrowserDialog; $picker.ShowNewFolderButton=$false; if($picker.ShowDialog() -eq 'OK') {$extraUI.LaunchPathInput.Text=$picker.SelectedPath; if(-not $extraUI.LaunchNameInput.Text) {$extraUI.LaunchNameInput.Text=[IO.Path]::GetFileName($picker.SelectedPath)}}; $picker.Dispose()})
$extraUI.ProgressAdd.Add_Click({$current=0.0; $total=0.0; $name=$extraUI.ProgressNameInput.Text.Trim(); if(-not $name -or -not [double]::TryParse($extraUI.ProgressCurrentInput.Text,[ref]$current) -or -not [double]::TryParse($extraUI.ProgressTotalInput.Text,[ref]$total) -or $current -lt 0 -or $total -le 0 -or [double]::IsInfinity($total) -or [double]::IsNaN($total) -or [double]::IsNaN($current) -or [double]::IsInfinity($current)) {$extraUI.ExtraStatus.Text='현재 진도는 0 이상, 전체 목표는 0보다 큰 숫자로 입력하세요'; return}; $item=$extras.progress|Where-Object {$_.name -eq $name}|Select-Object -First 1; if($item) {$item.current=[Math]::Min($total,$current); $item.total=$total} else {$extras.progress+=[pscustomobject]@{id=[guid]::NewGuid().ToString();name=$name;current=[Math]::Min($total,$current);total=$total}}; Commit-ExtraEdit})
$extraUI.ProgressManage.Add_SelectionChanged({if(-not $script:extraEditorChanging -and $this.SelectedItem) {$item=$this.SelectedItem.Tag; $extraUI.ProgressNameInput.Text=$item.name; $extraUI.ProgressCurrentInput.Text=[string]$item.current; $extraUI.ProgressTotalInput.Text=[string]$item.total}})
$extraUI.QuoteAdd.Add_Click({$text=$extraUI.QuoteTextInput.Text.Trim(); if(-not $text) {return}; $extras.quotes+=[pscustomobject]@{id=[guid]::NewGuid().ToString();text=$text;author=$extraUI.QuoteAuthorInput.Text.Trim()}; $extraUI.QuoteTextInput.Clear(); Commit-ExtraEdit})
foreach($pair in @(@('DdayRemove','DdayManage','ddays'),@('HabitRemove','HabitManage','habits'),@('LaunchRemove','LaunchManage','launchers'),@('ProgressRemove','ProgressManage','progress'),@('QuoteRemove','QuoteManage','quotes'))) {
    $extraUI[$pair[0]].Tag=@($pair[1],$pair[2]); $extraUI[$pair[0]].Add_Click({$info=$this.Tag; $selected=$extraUI[$info[0]].SelectedItem; if(-not $selected) {return}; if([Windows.MessageBox]::Show($settingsWindow,'선택한 항목을 삭제할까요?','항목 삭제','YesNo') -ne 'Yes') {return}; $target=$selected.Tag; $extras[$info[1]]=@($extras[$info[1]]|Where-Object {$_ -ne $target}); Commit-ExtraEdit})
}
function Import-PhotoFiles($Files) {$extras.photoFiles=@($Files|Where-Object {[IO.Path]::GetExtension($_).ToLowerInvariant() -in @('.jpg','.jpeg','.png','.bmp','.gif','.webp')}|Select-Object -Unique -First 500); $script:photoIndex=0; Set-Photo; Save-State}
$extraUI.PhotoChoose.Add_Click({$picker=New-Object Microsoft.Win32.OpenFileDialog; $picker.Multiselect=$true; $picker.Filter='사진|*.jpg;*.jpeg;*.png;*.bmp;*.gif;*.webp'; if($picker.ShowDialog($settingsWindow)) {Import-PhotoFiles $picker.FileNames}})
$extraUI.PhotoFolder.Add_Click({$picker=New-Object Windows.Forms.FolderBrowserDialog; $picker.ShowNewFolderButton=$false; if($picker.ShowDialog() -eq 'OK') {Import-PhotoFiles @(Get-ChildItem -LiteralPath $picker.SelectedPath -File|Sort-Object Name|Select-Object -ExpandProperty FullName)}; $picker.Dispose()})
$extraUI.PhotoClear.Add_Click({$extras.photoFiles=@(); Set-Photo; Save-State})
$extraUI.PhotoSave.Add_Click({$minutes=0; if(-not [int]::TryParse($extraUI.PhotoMinutesInput.Text,[ref]$minutes) -or $minutes -lt 0 -or $minutes -gt 1440) {$extraUI.ExtraStatus.Text='사진 전환은 0~1440분 사이로 입력하세요'; return}; $extras.photoMinutes=$minutes; $extras.photoFill=[bool]$extraUI.PhotoFill.IsChecked; Set-Photo; Save-State})
$ui.PhotoPrev.Add_Click({Set-Photo -1}); $ui.PhotoNext.Add_Click({Set-Photo 1})
$ui.QuoteNext.Add_Click({$extras.quoteOffset=[int]$extras.quoteOffset+1; Render-Quote; Save-State})
$ui.DdayChoice.Add_SelectionChanged({if(-not $script:extraChoosing -and $this.SelectedItem) {$extras.ddaySelected=$this.SelectedItem.Tag.id; Render-Dday; Save-State}})
foreach($pair in @(@('habits','habitPage'),@('progress','progressPage'),@('launcher','launcherPage'))) {$next=New-Object Windows.Controls.Button; $next.Content='›'; $next.Padding='7,3'; $next.ToolTip='다음 항목'; $next.Tag=$pair[1]; $next.Add_Click({
    $key='habits'; $rows=65; $space=150; if($this.Tag -eq 'progressPage') {$key='progress'; $rows=80; $space=145}
    $capacity=[Math]::Max(1,[Math]::Floor(($widgets[$key].Height-$space)/$rows)); $count=$extras[$key].Count
    if($this.Tag -eq 'launcherPage') {$capacity=[Math]::Max(1,[Math]::Floor(($widgets.launcher.Width-48)/148))*[Math]::Max(1,[Math]::Floor(($widgets.launcher.Height-125)/45)); $count=$extras.launchers.Count}
    $extras[$this.Tag]=([int]$extras[$this.Tag]+1)%[Math]::Max(1,[Math]::Ceiling($count/$capacity))
    if($this.Tag -eq 'habitPage') {Render-Habits} elseif($this.Tag -eq 'progressPage') {Render-ProgressWidgets} else {Render-Launcher}
}); $widgets[$pair[0]].FindName('WidgetTools').Children.Insert(0,$next)}
function Start-ExtraWork([string]$Kind,[string]$Action='Read') {
    if($extraJobs[$Kind]) {return}
    $extraLast[$Kind]=[DateTime]::UtcNow
    $extraJobs[$Kind]=Start-DaylightJob -ScriptBlock {param($root,$kind,$action); . (Join-Path $root 'ExtraBackend.ps1'); if($kind -eq 'media') {Get-WidgetMedia $action} else {Get-WidgetSystem}} -ArgumentList $PSScriptRoot,$Kind,$Action
}
function Stop-ExtraWork {foreach($kind in @('media','system')) {if($extraJobs[$kind]) {Stop-DaylightJob $extraJobs[$kind]; Remove-DaylightJob $extraJobs[$kind]; $extraJobs[$kind]=$null}}}
function Receive-ExtraWork([string]$Kind) {
    $job=$extraJobs[$Kind]; if(-not $job -or $job.State -eq 'Running') {return}
    try {$result=@(Receive-DaylightJob $job)|Select-Object -Last 1} catch {Write-DaylightDiagnostic ('extra-'+$Kind) $_; $result=@{ok=$false;message='정보를 읽지 못했습니다'}} finally {Remove-DaylightJob $job; $extraJobs[$Kind]=$null}
    if($Kind -eq 'media') {
        $ui.MediaPrevious.IsEnabled=$true; $ui.MediaToggle.IsEnabled=$true; $ui.MediaNext.IsEnabled=$true
        if(-not $result.ok) {$ui.MediaHint.Text=$result.message; if($result.reason) {Write-DaylightDiagnostic 'media' (New-Object Exception $result.reason)}; return}
        $ui.MediaTitle.Text=$result.title; $ui.MediaArtist.Text=$result.artist; $ui.MediaToggle.Content=$(if($result.playing){'Ⅱ'}else{'▶'})
        $ui.MediaHint.Text=$(if($result.active){'지금 재생 중'}else{'Windows 미디어 정보를 지원하는 앱에서 재생하세요'})
        if($result.ContainsKey('accepted') -and -not $result.accepted) {$ui.MediaHint.Text='이 재생 앱에서 해당 조작을 지원하지 않습니다'}
        $ui.MediaPrevious.IsEnabled=[bool]$result.active; $ui.MediaToggle.IsEnabled=[bool]$result.active; $ui.MediaNext.IsEnabled=[bool]$result.active
        $ui.MediaArt.Source=$null; $ui.MediaPlaceholder.Visibility='Visible'
        if($result.cover) {try {$stream=New-Object IO.MemoryStream (,$result.cover); try {$bitmap=New-Object Windows.Media.Imaging.BitmapImage; $bitmap.BeginInit(); $bitmap.CacheOption='OnLoad'; $bitmap.StreamSource=$stream; $bitmap.EndInit(); $bitmap.Freeze(); $ui.MediaArt.Source=$bitmap; $ui.MediaPlaceholder.Visibility='Collapsed'} finally {$stream.Dispose()}} catch {}}
    } else {
        if(-not $result.ok) {$ui.SystemHint.Text=$result.message; return}
        $ui.SystemCpu.Text='CPU —'; if($result.cpu -ge 0) {$ui.SystemCpu.Text='CPU '+[Math]::Round($result.cpu)+'%'; $script:cpuHistory=@($cpuHistory)+@([double]$result.cpu); $script:cpuHistory=@($cpuHistory|Select-Object -Last 40)}
        $ui.SystemMemory.Text='메모리 '+$result.memory+'% · '+[Math]::Round($result.usedGB,1)+' / '+[Math]::Round($result.totalGB,1)+' GB'; $ui.MemoryBar.Value=$result.memory
        $ui.SystemBattery.Text='배터리 없음 · 데스크톱'; if($result.battery -ge 0) {$ui.SystemBattery.Text='배터리 '+$result.battery+'%'; if($result.ac -eq 1) {$ui.SystemBattery.Text+=' · 전원 연결'}}
        $ui.SystemDisk.Text=$result.disk+' 여유 공간 '+$result.diskGB+' GB'; $ui.SystemHint.Text='10초마다 갱신 · CPU 최근 '+($cpuHistory.Count*10)+'초'
        $points=New-Object Windows.Media.PointCollection; $width=[Math]::Max(100,$widgets.system.Width-52); for($i=0;$i -lt $cpuHistory.Count;$i++) {[void]$points.Add((New-Object Windows.Point ($i*$width/39),(46-$cpuHistory[$i]*0.44)))}; $ui.CpuLine.Points=$points
    }
    if($Kind -eq 'media' -and $script:pendingMediaAction) {$action=$script:pendingMediaAction; $script:pendingMediaAction=''; Start-ExtraWork media $action; $ui.MediaPrevious.IsEnabled=$false; $ui.MediaToggle.IsEnabled=$false; $ui.MediaNext.IsEnabled=$false}
}
foreach($pair in @(@('MediaPrevious','Previous'),@('MediaToggle','Toggle'),@('MediaNext','Next'))) {$ui[$pair[0]].Tag=$pair[1]; $ui[$pair[0]].Add_Click({$ui.MediaPrevious.IsEnabled=$false; $ui.MediaToggle.IsEnabled=$false; $ui.MediaNext.IsEnabled=$false; if(-not $extraJobs.media) {Start-ExtraWork media $this.Tag} else {$script:pendingMediaAction=$this.Tag}})}
function Update-ExtraWidgets {
    foreach($kind in @('media','system')) {
        Receive-ExtraWork $kind
        $visible=$state[$kind+'Visible'] -and $widgets[$kind].IsVisible
        if(-not $visible) {if($extraJobs[$kind]) {Stop-DaylightJob $extraJobs[$kind]; Remove-DaylightJob $extraJobs[$kind]; $extraJobs[$kind]=$null}; continue}
        $seconds=10; if($kind -eq 'media') {$seconds=5}
        if(-not $SelfTest -and -not $extraJobs[$kind] -and ([DateTime]::UtcNow-$extraLast[$kind]).TotalSeconds -ge $seconds) {Start-ExtraWork $kind}
    }
    if(([DateTime]::UtcNow-$extraLast.local).TotalSeconds -ge 15) {Render-Dday; Render-Habits; Render-ProgressWidgets; Render-Quote; $extraLast.local=[DateTime]::UtcNow}
    if($state.photoVisible -and $widgets.photo.IsVisible -and $extras.photoMinutes -gt 0 -and ([DateTime]::UtcNow-$extraLast.photo).TotalMinutes -ge $extras.photoMinutes) {Set-Photo 1}
}
foreach($key in $extraCatalog.Keys) {
    $button=New-Object Windows.Controls.Button; $button.Content='✎'; $button.Padding='7,3'; $button.ToolTip='이 위젯 설정'; $button.Tag=$key; $button.Add_Click({Show-DaylightSettings; $headers=@{youtube='YouTube · 계정과 재생';dday='D-day';habits='습관';launcher='빠른 실행';progress='공부·독서 진행률';photo='사진·아트 프레임';quote='오늘의 문장'}; $target=$extraSettings.Children|Where-Object {$_ -is [Windows.Controls.Expander] -and $_.Header -eq $headers[$this.Tag]}|Select-Object -First 1; if($target) {$target.IsExpanded=$true; $target.BringIntoView()} else {$extraSettings.BringIntoView()}}); $widgets[$key].FindName('WidgetTools').Children.Insert(0,$button)
    $widgets[$key].Add_SizeChanged({if($script:layoutReady -and (Get-Command Render-Habits -ErrorAction SilentlyContinue)) {if($this.Tag -eq 'habits') {Render-Habits} elseif($this.Tag -eq 'progress') {Render-ProgressWidgets} elseif($this.Tag -eq 'launcher') {Render-Launcher}}})
}
Refresh-ExtraEditors; Render-Dday; Render-Habits; Render-Launcher; Render-ProgressWidgets; Render-Quote; Set-Photo
