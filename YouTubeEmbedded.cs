using System;
using System.IO;
using System.Runtime.InteropServices;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.Wpf;

public sealed class DaylightEmbeddedYouTube : IDisposable {
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode)]
    static extern IntPtr LoadLibrary(string path);
    public WebView2CompositionControl View { get; private set; }
    public string Error { get; private set; }
    public bool Ready { get; private set; }
    public bool Started { get; private set; }
    bool disposed;
    public DaylightEmbeddedYouTube(string root) {
        if (LoadLibrary(Path.Combine(root,"WebView2Loader.dll")) == IntPtr.Zero)
            throw new InvalidOperationException("WebView2Loader.dll could not be loaded.");
        View = new WebView2CompositionControl();
        View.DefaultBackgroundColor = System.Drawing.Color.FromArgb(255,11,16,27);
    }
    public async void Start(string url,string profile) {
        if(Started || disposed) return;
        Started=true;
        try {
            var environment=await CoreWebView2Environment.CreateAsync(null,profile);
            if(disposed) return;
            await View.EnsureCoreWebView2Async(environment);
            if(disposed) return;
            View.CoreWebView2.Settings.AreDevToolsEnabled=false;
            View.CoreWebView2.Settings.IsStatusBarEnabled=false;
            View.CoreWebView2.NewWindowRequested += (s,e)=> {
                e.Handled=true; // Account-dependent playback is opened explicitly from Daylight settings.
            };
            View.CoreWebView2.NavigationStarting += (s,e)=> {
                // Only the local player shell may replace the top-level document.
                if(!e.Uri.StartsWith(url,StringComparison.OrdinalIgnoreCase)) e.Cancel=true;
            };
            View.CoreWebView2.ProcessFailed += (s,e)=> { Error="플레이어 연결이 끊겼습니다. 다시 재생을 눌러주세요."; Ready=false; };
            View.Source=new Uri(url);
            Ready=true;
        } catch(Exception ex) { Error="내장 플레이어를 시작하지 못했습니다. WebView2 설치 상태를 확인하세요. ("+ex.GetType().Name+")"; }
    }
    public void Dispose() { if(disposed)return; disposed=true; Ready=false; View.Dispose(); }
}
