Add-Type -AssemblyName System.Drawing
$script:daylightIcon=New-Object Windows.Media.Imaging.BitmapImage
$daylightIcon.BeginInit(); $daylightIcon.CacheOption=[Windows.Media.Imaging.BitmapCacheOption]::OnLoad
$daylightIcon.UriSource=New-Object Uri (Join-Path $PSScriptRoot 'Daylight.png'); $daylightIcon.EndInit(); $daylightIcon.Freeze()
$source=New-Object Drawing.Icon (Join-Path $PSScriptRoot 'Daylight.ico')
try {$script:daylightTrayIcon=$source.Clone()} finally {$source.Dispose()}
foreach($surface in @($widgets.Values)+@($settingsWindow)) {$surface.Icon=$daylightIcon; $surface.ShowInTaskbar=$false}
