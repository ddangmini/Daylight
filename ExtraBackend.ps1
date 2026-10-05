function Wait-WidgetWinRT($Operation,[type]$ResultType) {
    $method=[System.WindowsRuntimeSystemExtensions].GetMethods()|Where-Object {$_.Name -eq 'AsTask' -and $_.IsGenericMethod -and $_.GetGenericArguments().Count -eq 1 -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'}|Select-Object -First 1
    $task=$method.MakeGenericMethod($ResultType).Invoke($null,@($Operation))
    if(-not $task.Wait(8000)) {throw '미디어 정보 응답 시간이 지났습니다.'}
    return $task.Result
}
function Get-WidgetMedia([string]$Action='Read') {
    try {
        Add-Type -AssemblyName System.Runtime.WindowsRuntime
        $managerType=[Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager,Windows.Media.Control,ContentType=WindowsRuntime]
        $propertiesType=[Windows.Media.Control.GlobalSystemMediaTransportControlsSessionMediaProperties,Windows.Media.Control,ContentType=WindowsRuntime]
        $streamType=[Windows.Storage.Streams.IRandomAccessStreamWithContentType,Windows.Storage.Streams,ContentType=WindowsRuntime]
        $manager=Wait-WidgetWinRT ($managerType::RequestAsync()) $managerType
        $session=$manager.GetCurrentSession()
        if(-not $session) {return @{ok=$true;active=$false;title='음악을 재생해보세요';artist='';cover=$null;playing=$false}}
        $accepted=$true
        switch($Action) {
            'Toggle' {$accepted=Wait-WidgetWinRT ($session.TryTogglePlayPauseAsync()) ([bool])}
            'Previous' {$accepted=Wait-WidgetWinRT ($session.TrySkipPreviousAsync()) ([bool])}
            'Next' {$accepted=Wait-WidgetWinRT ($session.TrySkipNextAsync()) ([bool])}
        }
        $properties=Wait-WidgetWinRT ($session.TryGetMediaPropertiesAsync()) $propertiesType
        $cover=$null
        if($properties.Thumbnail) {
            $random=$null; $stream=$null; $memory=$null
            try {
                $random=Wait-WidgetWinRT ($properties.Thumbnail.OpenReadAsync()) $streamType
                $stream=[System.IO.WindowsRuntimeStreamExtensions]::AsStreamForRead($random)
                $memory=New-Object IO.MemoryStream; $buffer=New-Object byte[] 8192
                while(($count=$stream.Read($buffer,0,$buffer.Length)) -gt 0 -and $memory.Length -lt 2097152) {$memory.Write($buffer,0,$count)}
                if($memory.Length -lt 2097152) {$cover=$memory.ToArray()}
            } catch {} finally {if($memory){$memory.Dispose()}; if($stream){$stream.Dispose()}; if($random -is [IDisposable]) {try {([IDisposable]$random).Dispose()} catch {}}}
        }
        return @{ok=$true;active=$true;title=[string]$properties.Title;artist=[string]$properties.Artist;cover=$cover;playing=([string]$session.GetPlaybackInfo().PlaybackStatus -eq 'Playing');accepted=$accepted}
    } catch {return @{ok=$false;message='미디어 정보를 읽지 못했습니다. 재생 앱이 Windows 미디어 표시를 지원하는지 확인하세요.';reason=$_.Exception.Message}}
}
function Get-WidgetSystem {
    try {
        if(-not ('DaylightSystemSample' -as [type])) {
Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public static class DaylightSystemSample {
 [StructLayout(LayoutKind.Sequential)] struct Memory {public uint length,load; public ulong physical,available,page,availablePage,virtualTotal,virtualAvailable,extended;}
 [StructLayout(LayoutKind.Sequential)] struct Power {public byte ac,flag,percent,reserved;public uint seconds,total;}
 [DllImport("kernel32.dll")] static extern bool GlobalMemoryStatusEx(ref Memory m);
 [DllImport("kernel32.dll")] static extern bool GetSystemTimes(out long idle,out long kernel,out long user);
 [DllImport("kernel32.dll")] static extern bool GetSystemPowerStatus(out Power p);
 static long previousIdle,previousTotal;
 public static double[] Read() {
   Memory m=new Memory(); m.length=(uint)Marshal.SizeOf(typeof(Memory)); if(!GlobalMemoryStatusEx(ref m)) throw new InvalidOperationException();
   long idle,kernel,user; double cpu=-1; if(GetSystemTimes(out idle,out kernel,out user)) {long total=kernel+user; if(previousTotal>0 && total>previousTotal) cpu=Math.Max(0,Math.Min(100,100.0*(1.0-(double)(idle-previousIdle)/(total-previousTotal)))); previousIdle=idle;previousTotal=total;}
   Power p; bool available=GetSystemPowerStatus(out p); int battery=available && p.flag!=128 && p.percent!=255 ? p.percent : -1;
   return new double[]{cpu,m.load,m.physical/1073741824.0,(m.physical-m.available)/1073741824.0,battery,available?p.ac:-1};
 }
}
'@
        }
        $sample=[DaylightSystemSample]::Read()
        $drive=New-Object IO.DriveInfo ([IO.Path]::GetPathRoot($env:SystemRoot))
        return @{ok=$true;cpu=$sample[0];memory=$sample[1];totalGB=$sample[2];usedGB=$sample[3];battery=$sample[4];ac=$sample[5];diskGB=[Math]::Round($drive.AvailableFreeSpace/1GB);disk=$drive.Name}
    } catch {return @{ok=$false;message='시스템 정보를 읽지 못했습니다.'}}
}
