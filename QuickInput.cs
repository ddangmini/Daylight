using System;
using System.Runtime.InteropServices;
using System.Windows.Interop;
public sealed class DaylightQuickHotkey : IDisposable {
 [DllImport("user32.dll",SetLastError=true)] static extern bool RegisterHotKey(IntPtr hwnd,int id,uint modifiers,uint key);
 [DllImport("user32.dll")] static extern bool UnregisterHotKey(IntPtr hwnd,int id);
 readonly IntPtr handle; readonly HwndSource source; readonly HwndSourceHook hook;
 public event Action Triggered;
 public bool Registered {get;private set;} public int ErrorCode {get;private set;}
 public DaylightQuickHotkey(IntPtr hwnd) : this(hwnd,0x4003,0x20) {} public DaylightQuickHotkey(IntPtr hwnd,uint modifiers,uint key) {
  handle=hwnd; source=HwndSource.FromHwnd(hwnd);
  hook=(IntPtr h,int msg,IntPtr w,IntPtr l,ref bool handled)=> {if(msg==0x312 && w.ToInt32()==0x5A10) {handled=true; var callback=Triggered; if(callback!=null)callback();} return IntPtr.Zero;};
  source.AddHook(hook); Registered=RegisterHotKey(hwnd,0x5A10,modifiers,key); ErrorCode=Marshal.GetLastWin32Error();
 }
 public void Dispose() {if(Registered)UnregisterHotKey(handle,0x5A10); Registered=false; if(source!=null)source.RemoveHook(hook);}
}
