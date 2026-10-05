# Keep WPF windows at desktop z-order without reparenting them into Explorer.
# This preserves keyboard input, DPI, transparency and recovery after Explorer restarts.
if(-not ('DaylightDesktopLayer' -as [type])) {
Add-Type -ReferencedAssemblies @([Windows.Interop.HwndSource].Assembly.Location,[Windows.DependencyObject].Assembly.Location) -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Interop;
public static class DaylightDesktopLayer {
    [StructLayout(LayoutKind.Sequential)] struct Pos {public IntPtr hwnd,after; public int x,y,cx,cy; public uint flags;}
    [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr h,IntPtr after,int x,int y,int cx,int cy,uint flags);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr h,StringBuilder s,int max);
    [DllImport("user32.dll")] static extern bool IsWindow(IntPtr h);
    [DllImport("user32.dll")] static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr h,int cmd);
    static readonly Dictionary<IntPtr,HwndSourceHook> hooks=new Dictionary<IntPtr,HwndSourceHook>();
    static bool ownChange;
    public static bool DesktopActive() {
        var s=new StringBuilder(256); GetClassName(GetForegroundWindow(),s,256);
        return s.ToString()=="Progman" || s.ToString()=="WorkerW" || s.ToString()=="SHELLDLL_DefView";
    }
    public static bool Enabled(IntPtr h) {return hooks.ContainsKey(h);}
    public static void RestoreOrder(IntPtr h,bool pinned) {SetWindowPos(h,new IntPtr(pinned ? -1 : -2),0,0,0,0,0x13);}
    public static void SetMode(IntPtr h,bool enabled) {
        if(h==IntPtr.Zero || !IsWindow(h)) return;
        if(enabled && !hooks.ContainsKey(h)) {
            ownChange=true;
            try {SetWindowPos(h,new IntPtr(-2),0,0,0,0,0x13);} finally {ownChange=false;}
            HwndSourceHook hook=(IntPtr hwnd,int msg,IntPtr w,IntPtr l,ref bool handled)=> {
                if(msg==0x46 && !ownChange && l!=IntPtr.Zero) {
                    var p=(Pos)Marshal.PtrToStructure(l,typeof(Pos)); p.flags|=4;
                    Marshal.StructureToPtr(p,l,false);
                }
                return IntPtr.Zero;
            };
            var source=HwndSource.FromHwnd(h); if(source==null) return;
            hooks[h]=hook; source.AddHook(hook);
        } else if(!enabled && hooks.ContainsKey(h)) {
            var source=HwndSource.FromHwnd(h); if(source!=null) source.RemoveHook(hooks[h]); hooks.Remove(h);
        }
    }
    public static void Maintain(IntPtr h,bool desktopActive) {
        if(!Enabled(h) || !IsWindow(h)) return;
        ownChange=true;
        try {
            if(desktopActive && IsIconic(h)) ShowWindow(h,4);
            SetWindowPos(h,desktopActive ? IntPtr.Zero : new IntPtr(1),0,0,0,0,0x13);
        } finally {ownChange=false;}
    }
}
'@
}
foreach($mapName in @('widgetDesktop','widgetLocks')) {
    $map=@{}; foreach($key in $widgets.Keys) {$value=$false; if($state[$mapName]) {$value=[bool]$state[$mapName].$key}; $map[$key]=$value}; $state[$mapName]=$map
}
function Toggle-WidgetDesktop([string]$Key) {
    $state.widgetDesktop[$Key]=-not $state.widgetDesktop[$Key]
    if($state.widgetDesktop[$Key]) {$state.widgetPins[$Key]=$false}
    Set-DaylightMode; Save-State
}
function Toggle-WidgetLock([string]$Key) {$state.widgetLocks[$Key]=-not $state.widgetLocks[$Key]; Update-DesktopWidgets; Save-State}
function Update-DesktopWidgets {
    $desktopActive=[DaylightDesktopLayer]::DesktopActive()
    foreach($key in $widgets.Keys) {
        $surface=$widgets[$key]; $helper=New-Object Windows.Interop.WindowInteropHelper $surface
        $enabled=[bool]$state.widgetDesktop[$key]
        if($enabled) {$surface.Topmost=$false}
        $wasEnabled=[DaylightDesktopLayer]::Enabled($helper.Handle)
        [DaylightDesktopLayer]::SetMode($helper.Handle,$enabled)
        if($wasEnabled -and -not $enabled) {[DaylightDesktopLayer]::RestoreOrder($helper.Handle,[bool]$state.widgetPins[$key])}
        if($enabled -and $surface.IsVisible) {[DaylightDesktopLayer]::Maintain($helper.Handle,$desktopActive)}
        $locked=[bool]$state.widgetLocks[$key]
        $handle=$surface.FindName('WidgetResize'); $handle.IsEnabled=-not $locked; $handle.Visibility=$(if($locked){'Collapsed'}else{'Visible'})
        $surface.FindName('WidgetHint').ToolTip=$(if($locked){'이동·크기 잠금 · 우클릭 또는 설정에서 해제'}else{'드래그로 이동 · 모서리로 크기 조절'})
        foreach($item in $surface.ContextMenu.Items) {
            if($item -is [Windows.Controls.MenuItem]) {
                if($item.Header -eq '바탕화면에 붙이기') {$item.IsChecked=$enabled}
                if($item.Header -eq '이동·크기 잠금') {$item.IsChecked=$locked}
            }
        }
    }
    $ui.LockAllWidgets.IsChecked=(@($widgets.Keys|Where-Object {-not $state.widgetLocks[$_]}).Count -eq 0)
    $ui.DesktopAllWidgets.IsChecked=(@($widgets.Keys|Where-Object {-not $state.widgetDesktop[$_]}).Count -eq 0)
}
foreach($key in $widgets.Keys) {
    $surface=$widgets[$key]
    $item=New-Object Windows.Controls.MenuItem; $item.Header='바탕화면에 붙이기'; $item.IsCheckable=$true; $item.Tag=$key; $item.Add_Click({Toggle-WidgetDesktop $this.Tag}); $surface.ContextMenu.Items.Insert(3,$item)
    $item=New-Object Windows.Controls.MenuItem; $item.Header='이동·크기 잠금'; $item.IsCheckable=$true; $item.Tag=$key; $item.Add_Click({Toggle-WidgetLock $this.Tag}); $surface.ContextMenu.Items.Insert(4,$item)
    $surface.Add_Loaded({Update-DesktopWidgets})
}
$ui.LockAllWidgets.Add_Click({foreach($key in $widgets.Keys) {$state.widgetLocks[$key]=[bool]$this.IsChecked}; Update-DesktopWidgets; Save-State})
$ui.DesktopAllWidgets.Add_Click({foreach($key in $widgets.Keys) {$state.widgetDesktop[$key]=[bool]$this.IsChecked; if($this.IsChecked) {$state.widgetPins[$key]=$false}}; Set-DaylightMode; Save-State})
Update-DesktopWidgets
