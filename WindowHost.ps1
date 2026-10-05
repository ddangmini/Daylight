if(-not ('DaylightWindowHost' -as [type])) {
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class DaylightWindowHost {
    [DllImport("user32.dll", EntryPoint="GetWindowLongPtrW")] static extern IntPtr Get64(IntPtr h, int n);
    [DllImport("user32.dll", EntryPoint="GetWindowLongW")] static extern int Get32(IntPtr h, int n);
    [DllImport("user32.dll", EntryPoint="SetWindowLongPtrW", SetLastError=true)] static extern IntPtr Set64(IntPtr h, int n, IntPtr v);
    [DllImport("user32.dll", EntryPoint="SetWindowLongW", SetLastError=true)] static extern int Set32(IntPtr h, int n, int v);
    [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
    [DllImport("kernel32.dll")] public static extern bool FreeConsole();
    [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
    public static long ExtendedStyle(IntPtr h) {return IntPtr.Size==8 ? Get64(h,-20).ToInt64() : Get32(h,-20);}
    public static void HideFromSwitcher(IntPtr h) {
        if(h==IntPtr.Zero) return;
        long style=(ExtendedStyle(h) & ~0x40000L) | 0x80L;
        if(IntPtr.Size==8) Set64(h,-20,new IntPtr(style)); else Set32(h,-20,(int)style);
        SetWindowPos(h,IntPtr.Zero,0,0,0,0,0x37);
    }
}
'@
}
function Register-DaylightToolWindow($Surface) {
    $Surface.ShowInTaskbar=$false
    $Surface.Add_SourceInitialized({$helper=New-Object Windows.Interop.WindowInteropHelper $this; [DaylightWindowHost]::HideFromSwitcher($helper.Handle)})
    $Surface.Add_Loaded({$helper=New-Object Windows.Interop.WindowInteropHelper $this; [DaylightWindowHost]::HideFromSwitcher($helper.Handle)})
}
# Detach only this app's process. Never hide or terminate shared Terminal windows.
if(-not $SelfTest) {[void][DaylightWindowHost]::FreeConsole()}
