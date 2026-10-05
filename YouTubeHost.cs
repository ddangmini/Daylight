using System;
using System.IO;
using System.Text;
using System.Net;
using System.Net.Sockets;
using System.Threading;
using System.Collections.Concurrent;
using System.Runtime.InteropServices;

// A loopback-only, per-session bridge. No account credentials or browser cookies are read.
public sealed class DaylightYouTubeServer : IDisposable {
    readonly TcpListener listener;
    readonly Thread worker;
    readonly string html;
    readonly string route;
    readonly ConcurrentQueue<string> commands = new ConcurrentQueue<string>();
    volatile bool stopping;
    public string Url { get; private set; }
    public string Origin { get; private set; }
    public string WindowTitle { get; private set; }
    public string StateJson { get; private set; }
    public DaylightYouTubeServer(string template) {
        listener = new TcpListener(IPAddress.Loopback, 0);
        listener.Start();
        int port = ((IPEndPoint)listener.LocalEndpoint).Port;
        route = "/" + Guid.NewGuid().ToString("N") + "/";
        Origin = "http://127.0.0.1:" + port;
        Url = Origin + route;
        WindowTitle = "Daylight YouTube " + Guid.NewGuid().ToString("N");
        html = template.Replace("__TITLE__", WindowTitle).Replace("__ORIGIN__", Origin);
        StateJson = "{}";
        worker = new Thread(Run); worker.IsBackground = true; worker.Start();
    }
    public void Enqueue(string command) { if (command != null && command.Length < 2048) commands.Enqueue(command); }
    void Run() {
        while (!stopping) {
            try { using (TcpClient client = listener.AcceptTcpClient()) { client.ReceiveTimeout = 2000; client.SendTimeout = 2000; Serve(client); } }
            catch { if (stopping) break; }
        }
    }
    string Line(Stream stream) {
        var bytes = new MemoryStream(); int b;
        while ((b = stream.ReadByte()) >= 0) { if (b == 10) break; if (b != 13) bytes.WriteByte((byte)b); if (bytes.Length > 8192) throw new IOException("Header too long"); }
        return Encoding.ASCII.GetString(bytes.ToArray());
    }
    void Reply(Stream stream, int status, string type, string body) {
        byte[] data = Encoding.UTF8.GetBytes(body);
        string head = "HTTP/1.1 " + status + (status == 200 ? " OK" : " Error") + "\r\nContent-Type: " + type + "; charset=utf-8\r\nContent-Length: " + data.Length + "\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nReferrer-Policy: strict-origin-when-cross-origin\r\nConnection: close\r\n\r\n";
        byte[] header = Encoding.ASCII.GetBytes(head); stream.Write(header,0,header.Length); stream.Write(data,0,data.Length);
    }
    void Serve(TcpClient client) {
        Stream stream = client.GetStream(); string[] first = Line(stream).Split(' ');
        if (first.Length != 3) return;
        string path = first[1], host = "", origin = ""; int length = 0, count = 0; bool expectContinue = false;
        string line;
        while ((line = Line(stream)).Length > 0) {
            if (++count > 64) return;
            int colon = line.IndexOf(':'); if (colon < 0) continue;
            string key = line.Substring(0,colon).Trim().ToLowerInvariant(), value = line.Substring(colon+1).Trim();
            if (key == "host") host = value;
            if (key == "origin") origin = value;
            if (key == "expect" && value.Equals("100-continue",StringComparison.OrdinalIgnoreCase)) expectContinue = true;
            if (key == "content-length" && !int.TryParse(value,out length)) return;
        }
        if(length < 0 || length > 16384) {Reply(stream,413,"text/plain","Too large"); return;}
        if(expectContinue && length > 0) {byte[] interim=Encoding.ASCII.GetBytes("HTTP/1.1 100 Continue\r\n\r\n");stream.Write(interim,0,interim.Length);}
        byte[] body = new byte[length]; int offset = 0;
        while(offset < length) {int read=stream.Read(body,offset,length-offset);if(read==0)return;offset+=read;}
        if (host != new Uri(Origin).Authority || !path.StartsWith(route,StringComparison.Ordinal) || (origin.Length > 0 && origin != Origin)) { Reply(stream,403,"text/plain","Forbidden"); return; }
        path = path.Split('?')[0];
        if (first[0] == "GET" && path == route) { Reply(stream,200,"text/html",html); return; }
        if (first[0] == "GET" && path == route+"commands") {
            var batch = new StringBuilder("["); string command; bool comma = false;
            while (commands.TryDequeue(out command)) { if(comma) batch.Append(','); batch.Append(command); comma = true; }
            batch.Append(']'); Reply(stream,200,"application/json",batch.ToString()); return;
        }
        if (first[0] == "POST" && path == route+"state" && origin == Origin) {
            StateJson = Encoding.UTF8.GetString(body); Reply(stream,200,"application/json","{}"); return;
        }
        Reply(stream,404,"text/plain","Not found");
    }
    public void Dispose() { if (stopping) return; stopping = true; listener.Stop(); worker.Join(2500); }
}

public static class DaylightYouTubeWindows {
    delegate bool WindowCallback(IntPtr h, IntPtr p);
    [DllImport("user32.dll")] static extern bool EnumWindows(WindowCallback callback, IntPtr p);
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int GetWindowText(IntPtr h, StringBuilder s, int length);
    [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int w, int height, uint flags);
    [DllImport("user32.dll")] static extern bool PostMessage(IntPtr h, uint message, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out Rectangle r);
    [StructLayout(LayoutKind.Sequential)] public struct Rectangle {public int Left,Top,Right,Bottom;}
    public static IntPtr Find(string title, int[] allowedProcesses) {
        IntPtr result = IntPtr.Zero;
        EnumWindows(delegate(IntPtr h, IntPtr p) {
            var text = new StringBuilder(1024); GetWindowText(h,text,text.Capacity);
            uint pid; GetWindowThreadProcessId(h,out pid);
            if (text.ToString().StartsWith(title,StringComparison.Ordinal) && Array.IndexOf(allowedProcesses,(int)pid)>=0) {result=h; return false;} return true;
        },IntPtr.Zero);
        return result;
    }
    public static void Pin(IntPtr h, bool pin) {SetWindowPos(h,new IntPtr(pin ? -1 : -2),0,0,0,0,0x13);}
    public static void RestorePosition(IntPtr h, int left, int top, int width, int height) {SetWindowPos(h,IntPtr.Zero,left,top,width,height,0x14);}
    public static Rectangle Position(IntPtr h) {Rectangle r; GetWindowRect(h,out r); return r;}
    public static void Activate(IntPtr h) {SetForegroundWindow(h);}
    public static void Close(IntPtr h) {PostMessage(h,0x10,IntPtr.Zero,IntPtr.Zero);}
}
