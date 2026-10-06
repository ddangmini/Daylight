Add-Type -AssemblyName System.Drawing, System.Windows.Forms
$script:wallpaperBitmap=$null
$script:wallpaperStamp=''
$script:wallpaperStyle='10'
$script:lastWallpaperCheck=[DateTime]::MinValue
$script:appearanceWindow=$null
$script:appearanceChanging=$false
$appearance=@{}
foreach($key in $widgets.Keys) {
    $opacity=0.74; if($key -eq 'clock') {$opacity=0.22}; if($key -eq 'weather') {$opacity=0.58}
    $entry=$null
    if($state.appearance) {if($state.appearance -is [hashtable]) {$entry=$state.appearance[$key]} else {$entry=$state.appearance.$key}}
    $tone='auto'; $accent='#A3E8D2'
    if($entry) {if($null -ne $entry.opacity) {$opacity=[Math]::Max(0,[Math]::Min(1,[double]$entry.opacity))}; if($entry.tone -in @('auto','light','dark')) {$tone=$entry.tone}; if($entry.accent -in @('#A3E8D2','#F3BA9C','#C8B9EC','#A5C8EF')) {$accent=$entry.accent}}
        $theme='adaptive'; $radius=20; $textScale=1.0; $font='Malgun Gothic'
    if($entry) {
        if($entry.theme -and $script:stylePresets.Contains([string]$entry.theme)) {$theme=[string]$entry.theme}
        if($null -ne $entry.radius) {$radius=[Math]::Max(0,[Math]::Min(32,[double]$entry.radius))}
        if($null -ne $entry.textScale) {$textScale=[Math]::Max(0.85,[Math]::Min(1.2,[double]$entry.textScale))}
        if($entry.font -in @('Malgun Gothic','Segoe UI','Segoe UI Light','Georgia','Consolas')) {$font=[string]$entry.font}
    }
    $appearance[$key]=@{opacity=$opacity;tone=$tone;accent=$accent;theme=$theme;radius=$radius;textScale=$textScale;font=$font}
}
$state.appearance=$appearance
function Clear-WallpaperCache {if($script:wallpaperBitmap) {$script:wallpaperBitmap.Dispose(); $script:wallpaperBitmap=$null}; $script:wallpaperStamp=''}
function Update-WallpaperCache {
    if(([DateTime]::UtcNow-$script:lastWallpaperCheck).TotalSeconds -lt 10) {return}
    $script:lastWallpaperCheck=[DateTime]::UtcNow
    try {
        $desktop=Get-ItemProperty 'HKCU:\Control Panel\Desktop'
        $path=[string]$desktop.WallPaper; $script:wallpaperStyle=[string]$desktop.WallpaperStyle
        if(-not $path -or -not (Test-Path -LiteralPath $path -PathType Leaf)) {Clear-WallpaperCache; return}
        $stamp=$path+'|'+(Get-Item -LiteralPath $path).LastWriteTimeUtc.Ticks
        if($stamp -ne $script:wallpaperStamp) {
            Clear-WallpaperCache
            $source=[Drawing.Image]::FromFile($path)
            try {$script:wallpaperBitmap=New-Object Drawing.Bitmap $source} finally {$source.Dispose()}
            $script:wallpaperStamp=$stamp
        }
    } catch {Clear-WallpaperCache}
}
function Get-WallpaperBrightness($Surface,$Bitmap=$script:wallpaperBitmap,[string]$Style=$script:wallpaperStyle) {
    if(-not $Bitmap) {return 0.25}
    $screen=[Windows.Forms.Screen]::PrimaryScreen.Bounds
    $dipWidth=[Windows.SystemParameters]::PrimaryScreenWidth; $dipHeight=[Windows.SystemParameters]::PrimaryScreenHeight
    $sx=$screen.Width/$dipWidth; $sy=$screen.Height/$dipHeight
    $sum=0; $count=0
    for($i=1;$i -le 5;$i++) {for($j=1;$j -le 5;$j++) {
        $x=($Surface.Left+$Surface.Width*$i/6)*$sx; $y=($Surface.Top+$Surface.Height*$j/6)*$sy
        # Static wallpaper fill/fit/stretch/center/tile mapping on the primary monitor.
        $px=0; $py=0
        if($Style -in @('10','6')) {
            $scale=[Math]::Max($screen.Width/$Bitmap.Width,$screen.Height/$Bitmap.Height)
            if($Style -eq '6') {$scale=[Math]::Min($screen.Width/$Bitmap.Width,$screen.Height/$Bitmap.Height)}
            $px=($x-($screen.Width-$Bitmap.Width*$scale)/2)/$scale
            $py=($y-($screen.Height-$Bitmap.Height*$scale)/2)/$scale
        } elseif($Style -eq '0') {$px=$x-($screen.Width-$Bitmap.Width)/2; $py=$y-($screen.Height-$Bitmap.Height)/2}
        else {$px=$x*$Bitmap.Width/$screen.Width; $py=$y*$Bitmap.Height/$screen.Height}
        if($x -lt 0 -or $y -lt 0 -or $x -ge $screen.Width -or $y -ge $screen.Height) {$px=$Bitmap.Width*$i/6; $py=$Bitmap.Height*$j/6}
        $px=[Math]::Max(0,[Math]::Min($Bitmap.Width-1,[int]$px)); $py=[Math]::Max(0,[Math]::Min($Bitmap.Height-1,[int]$py))
        $color=$Bitmap.GetPixel($px,$py)
        $sum+=(0.2126*$color.R+0.7152*$color.G+0.0722*$color.B)/255; $count++
    }}
    return $sum/$count
}
function Set-WidgetAppearance([string]$Key,[double]$Brightness=-1) {
    $surface=$widgets[$Key]; $style=$state.appearance[$Key]
    if($Brightness -lt 0) {$Brightness=Get-WallpaperBrightness $surface}
    $preset=$script:stylePresets[[string]$style.theme]
    if($style.tone -eq 'auto' -and $preset.background) {
        $baseColor=[Windows.Media.ColorConverter]::ConvertFromString($preset.background)
        $panelBrightness=(0.2126*$baseColor.R+0.7152*$baseColor.G+0.0722*$baseColor.B)/255
        $Brightness=$style.opacity*$panelBrightness+(1-$style.opacity)*$Brightness
    }
    $dark=$style.tone -eq 'dark' -or ($style.tone -eq 'auto' -and $Brightness -ge 0.52)
    $foreground='#F6F7FA'; $background='#172131'
    if($dark) {$foreground='#19222C'; $background='#F3F1EB'}
    $preset=$script:stylePresets[[string]$style.theme]; if($preset.background) {$background=$preset.background}
    $surface.FontFamily=$style.font; $surface.FindName('Surface').CornerRadius=[Windows.CornerRadius]$style.radius
    $color=[Windows.Media.ColorConverter]::ConvertFromString($background); $color.A=[byte][Math]::Max(1,[Math]::Round($style.opacity*255))
    $surface.FindName('Surface').Background=New-Object Windows.Media.SolidColorBrush $color
    if($preset.background2) {$endColor=[Windows.Media.ColorConverter]::ConvertFromString($preset.background2); $endColor.A=$color.A; $surface.FindName('Surface').Background=New-Object Windows.Media.LinearGradientBrush $color,$endColor,45}
    $surface.FindName('Surface').BorderBrush='#18FFFFFF'; if($preset.border) {$surface.FindName('Surface').BorderBrush=$preset.border}
    $surface.FindName('Accent').Visibility='Visible'; if($preset.minimal) {$surface.FindName('Accent').Visibility='Collapsed'}
    if($preset.minimal -or $style.theme -eq 'glass') {$surface.FindName('Surface').BorderBrush='Transparent'}
    if($Key -eq 'clock') {
        $ui.Clock.FontFamily=$style.font
        $surface.FindName('WidgetDrag').Children[0].Opacity=1; $surface.FindName('Surface').Child.RowDefinitions[0].Height=[Windows.GridLength]36
        $ui.Clock.Parent.Parent.HorizontalAlignment='Left'
        if($preset.minimal) {$surface.FindName('WidgetDrag').Children[0].Opacity=0; $surface.FindName('Surface').Child.RowDefinitions[0].Height=[Windows.GridLength]24; $ui.Clock.Parent.Parent.HorizontalAlignment='Center'}
    }
    $surface.FindName('Accent').Background=$style.accent
    $queue=New-Object 'Collections.Generic.Queue[Windows.DependencyObject]'; $queue.Enqueue($surface.Content)
    while($queue.Count) {
        $element=$queue.Dequeue()
        if(($element -is [Windows.Controls.TextBlock] -or $element -is [Windows.Controls.TextBox]) -and $element.Name -ne 'WeatherIcon') {
            $base=$element.GetValue($script:baseFontProperty)
            if($base -eq 0) {$base=$element.FontSize; $element.SetValue($script:baseFontProperty,[double]$base)}
            $element.FontSize=$base*$style.textScale
        }
        if($element -is [Windows.Controls.TextBlock] -and $element.Name -ne 'WeatherIcon') {$element.Foreground=$foreground}
        if($element -is [Windows.Controls.TextBox] -and $element.Name -in @('Note','NoteTitle','ChatHistory','TaskInput','ChatInput')) {
            $element.Foreground=$foreground; $element.CaretBrush=$foreground
            if($element.Name -in @('TaskInput','ChatInput')) { $element.Background='#18172231'; if($dark) {$element.Background='#18192231'}; $element.BorderBrush='#305C6D7D' }
        }
        if($element -is [Windows.Controls.Button] -and $element.Name -in @('TaskLocal','TaskNotion','ChatCopy','ChatCancel','ChatSend','NoteExport','ClearDone','AgendaPrev','AgendaNext','TasksPrev','TasksNext')) {
            $element.Foreground=$foreground; $element.Background='Transparent'
            if($element.Name -eq 'ChatSend') {$element.Background=$style.accent; $element.Foreground='#172131'}
        }
        if($extraCatalog.Contains($Key) -and ($element -is [Windows.Controls.Button] -or $element -is [Windows.Controls.CheckBox])) {$element.Foreground=$foreground; if($element -is [Windows.Controls.Button]) {$element.Background='Transparent'}}
        foreach($child in [Windows.LogicalTreeHelper]::GetChildren($element)) {if($child -is [Windows.DependencyObject]) {$queue.Enqueue($child)}}
    }
    if(Get-Command Set-WidgetChrome -ErrorAction SilentlyContinue) {Set-WidgetChrome $Key}
    $surface.FindName('WidgetHint').ToolTip= '글자: '+$(if($dark){'어둡게'}else{'밝게'})+' · 배경 투명도 '+[Math]::Round((1-$style.opacity)*100)+'%'
}
function Set-DaylightTextTone {Update-WallpaperCache; foreach($key in $widgets.Keys) {Set-WidgetAppearance $key}}
function Close-Appearance {if($script:appearanceWindow) {$script:appearanceWindow.Close(); $script:appearanceWindow=$null}}
function New-AppearanceDialog {
    $dialog=New-DaylightWindow @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="창 꾸미기" Width="380" Height="640" MinWidth="320" MinHeight="320" ResizeMode="CanResize" Background="#192235" Foreground="#E9EDF5" FontFamily="Malgun Gothic" WindowStartupLocation="CenterOwner" ShowInTaskbar="False"><Window.Resources>__THEME__</Window.Resources><ScrollViewer x:Name="AppearanceScroll" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled"><StackPanel Margin="24"><TextBlock Text="디자인 프리셋" FontSize="16" FontWeight="SemiBold"/><ComboBox x:Name="PresetChoice" Margin="0,10,0,16"/><TextBlock Text="배경 투명도" FontSize="16" FontWeight="SemiBold"/><TextBlock x:Name="OpacityLabel" Margin="0,8,0,10"/><Slider x:Name="OpacitySlider" Minimum="0" Maximum="100" TickFrequency="5" IsSnapToTickEnabled="True"/><TextBlock Text="글자 색" Margin="0,22,0,8"/><ComboBox x:Name="ToneChoice"><ComboBoxItem Content="자동 · 배경화면 밝기" Tag="auto"/><ComboBoxItem Content="흰 글자" Tag="light"/><ComboBoxItem Content="어두운 글자" Tag="dark"/></ComboBox><TextBlock Text="강조 색" Margin="0,18,0,8"/><ComboBox x:Name="AccentChoice"><ComboBoxItem Content="민트" Tag="#A3E8D2"/><ComboBoxItem Content="피치" Tag="#F3BA9C"/><ComboBoxItem Content="라벤더" Tag="#C8B9EC"/><ComboBoxItem Content="블루" Tag="#A5C8EF"/></ComboBox><TextBlock Text="모서리 둥글기" Margin="0,18,0,8"/><Slider x:Name="RadiusSlider" Minimum="0" Maximum="32" TickFrequency="2" IsSnapToTickEnabled="True"/><TextBlock Text="글자 크기" Margin="0,18,0,8"/><Slider x:Name="TextScaleSlider" Minimum="85" Maximum="120" TickFrequency="5" IsSnapToTickEnabled="True"/><ComboBox x:Name="FontChoice" Margin="0,18,0,0"><ComboBoxItem Content="맑은 고딕" Tag="Malgun Gothic"/><ComboBoxItem Content="Segoe UI" Tag="Segoe UI"/><ComboBoxItem Content="Segoe UI Light" Tag="Segoe UI Light"/><ComboBoxItem Content="Georgia · 세리프" Tag="Georgia"/><ComboBoxItem Content="Consolas · 모노스페이스" Tag="Consolas"/></ComboBox><Button x:Name="ApplyAllStyle" Content="이 디자인을 모든 창에 적용" Margin="0,14,0,0"/><TextBlock Text="바꾸면 바로 적용 · 자동 저장" Margin="0,16,0,0" FontSize="10"/></StackPanel></ScrollViewer></Window>
'@
    $area=[Windows.SystemParameters]::WorkArea
    $dialog.MaxHeight=[Math]::Max(320,$area.Height-24)
    $dialog.Height=[Math]::Min(640,$dialog.MaxHeight)
    return $dialog
}
function Show-Appearance([string]$Key,[switch]$NoShow) {
    Close-Appearance
    $script:appearanceWindow=New-AppearanceDialog; $appearanceWindow.Tag=$Key
    if($widgets[$Key].IsVisible) {$appearanceWindow.Owner=$widgets[$Key]}
    $slider=$appearanceWindow.FindName('OpacitySlider'); $label=$appearanceWindow.FindName('OpacityLabel'); $tone=$appearanceWindow.FindName('ToneChoice'); $accent=$appearanceWindow.FindName('AccentChoice')
    $preset=$appearanceWindow.FindName('PresetChoice'); Initialize-StyleChoice $preset
    $radius=$appearanceWindow.FindName('RadiusSlider'); $scale=$appearanceWindow.FindName('TextScaleSlider'); $font=$appearanceWindow.FindName('FontChoice')
    $script:appearanceChanging=$true
    $radius.Value=$state.appearance[$Key].radius; $scale.Value=$state.appearance[$Key].textScale*100
    foreach($item in $preset.Items) {if($item.Tag -eq $state.appearance[$Key].theme) {$preset.SelectedItem=$item}}
    foreach($item in $font.Items) {if($item.Tag -eq $state.appearance[$Key].font) {$font.SelectedItem=$item}}
    $slider.Value=[Math]::Round((1-$state.appearance[$Key].opacity)*100); $label.Text=[string]$slider.Value+'% · 글자는 선명하게 유지'
    foreach($item in $tone.Items) {if($item.Tag -eq $state.appearance[$Key].tone) {$tone.SelectedItem=$item}}
    foreach($item in $accent.Items) {if($item.Tag -eq $state.appearance[$Key].accent) {$accent.SelectedItem=$item}}
    $script:appearanceChanging=$false
    $slider.Add_ValueChanged({if($script:appearanceChanging) {return}; $key=$appearanceWindow.Tag; $state.appearance[$key].opacity=1-$this.Value/100; $appearanceWindow.FindName('OpacityLabel').Text=[string][Math]::Round($this.Value)+'% · 글자는 선명하게 유지'; Set-WidgetAppearance $key; Save-State})
    $tone.Add_SelectionChanged({if($script:appearanceChanging -or -not $this.SelectedItem) {return}; $key=$appearanceWindow.Tag; $state.appearance[$key].tone=$this.SelectedItem.Tag; Set-WidgetAppearance $key; Save-State})
    $accent.Add_SelectionChanged({if($script:appearanceChanging -or -not $this.SelectedItem) {return}; $key=$appearanceWindow.Tag; $state.appearance[$key].accent=$this.SelectedItem.Tag; Set-WidgetAppearance $key; Save-State})
    $preset.Add_SelectionChanged({
        if($script:appearanceChanging -or -not $this.SelectedItem) {return}
        $key=$appearanceWindow.Tag; Set-StylePreset $key $this.SelectedItem.Tag
        $script:appearanceChanging=$true
        $appearanceWindow.FindName('OpacitySlider').Value=[Math]::Round((1-$state.appearance[$key].opacity)*100)
        $appearanceWindow.FindName('OpacityLabel').Text=[string]$appearanceWindow.FindName('OpacitySlider').Value+'% · 글자는 선명하게 유지'
        foreach($name in @('ToneChoice','AccentChoice','FontChoice')) {
            $field=@{ToneChoice='tone';AccentChoice='accent';FontChoice='font'}[$name]
            foreach($item in $appearanceWindow.FindName($name).Items) {if($item.Tag -eq $state.appearance[$key][$field]) {$appearanceWindow.FindName($name).SelectedItem=$item}}
        }
        $appearanceWindow.FindName('RadiusSlider').Value=$state.appearance[$key].radius; $appearanceWindow.FindName('TextScaleSlider').Value=$state.appearance[$key].textScale*100
        $script:appearanceChanging=$false
    })
    $radius.Add_ValueChanged({if($script:appearanceChanging) {return}; $key=$appearanceWindow.Tag; $state.appearance[$key].radius=$this.Value; Set-WidgetAppearance $key; Save-State})
    $scale.Add_ValueChanged({if($script:appearanceChanging) {return}; $key=$appearanceWindow.Tag; $state.appearance[$key].textScale=$this.Value/100; Set-WidgetAppearance $key; Save-State})
    $font.Add_SelectionChanged({if($script:appearanceChanging -or -not $this.SelectedItem) {return}; $key=$appearanceWindow.Tag; $state.appearance[$key].font=$this.SelectedItem.Tag; Set-WidgetAppearance $key; Save-State})
    $appearanceWindow.FindName('ApplyAllStyle').Add_Click({$source=$state.appearance[$appearanceWindow.Tag]; foreach($key in $widgets.Keys) {$copy=@{}; foreach($field in $source.Keys) {$copy[$field]=$source[$field]}; $state.appearance[$key]=$copy; Set-WidgetAppearance $key}; Save-State})
    if(-not $NoShow) {$appearanceWindow.Show(); [void]$appearanceWindow.Activate()}
}
foreach($key in $widgets.Keys) {$button=$widgets[$key].FindName('Appearance'); $button.Tag=$key; $button.Add_Click({Show-Appearance $this.Tag})}
Set-DaylightTextTone
