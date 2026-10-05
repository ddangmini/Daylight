$script:stylePresets=[ordered]@{
    adaptive=@{name='배경에 맞춤';background='';tone='auto';accent='#A3E8D2';opacity=0.74;radius=20}
    paper=@{name='페이퍼 · 크림';background='#F4F0E6';tone='dark';accent='#E8B991';opacity=0.92;radius=8}
    midnight=@{name='미드나이트 · 네이비';background='#111C30';tone='light';accent='#A5C8EF';opacity=0.86;radius=18}
    forest=@{name='포레스트 · 세이지';background='#DCE9DE';tone='dark';accent='#A3E8D2';opacity=0.88;radius=24}
    rose=@{name='로즈 · 파스텔';background='#F3E4E8';tone='dark';accent='#F3BA9C';opacity=0.88;radius=28}
    lavender=@{name='라벤더 · 저녁';background='#28233B';tone='light';accent='#C8B9EC';opacity=0.86;radius=24}
    glass=@{name='글라스 · 투명';background='';tone='auto';accent='#A3E8D2';opacity=0.08;radius=0}
    air=@{name='에어 · 타이포그래피';background='';tone='auto';accent='#A5C8EF';opacity=0.06;radius=0;clockFont='Segoe UI Light';minimal=$true}
    mono=@{name='모노 · 잉크';background='#111111';tone='light';accent='#A5C8EF';opacity=0.90;radius=4;clockFont='Georgia';minimal=$true}
    cloud=@{name='클라우드 · 소프트 카드';background='#EEF2F6';tone='dark';accent='#A5C8EF';opacity=0.93;radius=28;clockFont='Segoe UI Light'}
    linen=@{name='리넨 · 보타닉';background='#EDEAE0';tone='dark';accent='#A3E8D2';opacity=0.92;radius=12;clockFont='Georgia'}
    aurora=@{name='오로라 · 그라데이션';background='#243349';background2='#41324F';tone='light';accent='#C8B9EC';opacity=0.90;radius=28;clockFont='Segoe UI Light'}
    neon=@{name='네온 · 야간';background='#101522';tone='light';accent='#A3E8D2';opacity=0.92;radius=16;clockFont='Consolas';border='#A3E8D2'}
}
$script:baseFontProperty=[Windows.DependencyProperty]::RegisterAttached('DaylightBaseFontSize',[double],[Windows.FrameworkElement],(New-Object Windows.PropertyMetadata ([double]0)))
function Set-StylePreset([string]$Key,[string]$Name) {
    if(-not $script:stylePresets.Contains($Name)) {return}
    $preset=$script:stylePresets[$Name]
    $font='Malgun Gothic'; if($Key -eq 'clock' -and $preset.clockFont) {$font=$preset.clockFont}
    $state.appearance[$Key]=@{theme=$Name;opacity=$preset.opacity;tone=$preset.tone;accent=$preset.accent;radius=$preset.radius;textScale=1.0;font=$font}
    Set-WidgetAppearance $Key; Save-State
}
function Initialize-StyleChoice($Combo) {
    foreach($name in $script:stylePresets.Keys) {$item=New-Object Windows.Controls.ComboBoxItem; $item.Content=$script:stylePresets[$name].name; $item.Tag=$name; [void]$Combo.Items.Add($item)}
}
