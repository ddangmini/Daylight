using System;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;
using System.Windows.Forms;
internal static class Launcher {
    static string Redact(string s) {
        s=Regex.Replace(s,@"(?i)(AIza[\w-]+|ya29\.[\w.-]+|sk-[\w-]+|Bearer\s+\S+)","[redacted]");
        return Regex.Replace(s,@"(?i)((?:access_token|refresh_token|client_secret|api[_-]?key|code)\s*[=:]\s*)[^\s&,;]+","$1[redacted]");
    }
    [STAThread] static int Main() {
        try {
            string root=AppDomain.CurrentDomain.BaseDirectory;
            string script=Path.Combine(root,"Daylight.ps1");
            if(!File.Exists(script)) throw new FileNotFoundException();
            ProcessStartInfo start=new ProcessStartInfo();
            start.FileName=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),@"WindowsPowerShell\v1.0\powershell.exe");
            start.Arguments="-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File \""+script+"\"";
            start.WorkingDirectory=root;
            start.UseShellExecute=false;
            start.CreateNoWindow=true;
            start.WindowStyle=ProcessWindowStyle.Hidden;
            start.RedirectStandardOutput=true; start.RedirectStandardError=true;
            using(Process child=new Process()) {
                StringBuilder errors=new StringBuilder();
                child.StartInfo=start;
                child.OutputDataReceived+=(s,e)=>{};
                child.ErrorDataReceived+=(s,e)=>{if(!String.IsNullOrWhiteSpace(e.Data)) lock(errors) {if(errors.Length<12000) errors.AppendLine(Redact(e.Data));}};
                child.Start(); child.BeginOutputReadLine(); child.BeginErrorReadLine(); child.WaitForExit();
                if(child.ExitCode!=0) {
                    try {File.AppendAllText(Path.Combine(root,"diagnostics.log"),DateTimeOffset.Now.ToString("o")+" [launcher] exit="+child.ExitCode+Environment.NewLine+errors.ToString(),Encoding.UTF8);} catch {}
                    MessageBox.Show("Daylight 실행 중 오류가 발생했습니다. 메모와 연결 정보는 유지됩니다. 앱 폴더의 diagnostics.log에 원인을 기록했습니다.","Daylight",MessageBoxButtons.OK,MessageBoxIcon.Warning);
                }
                return child.ExitCode;
            }
        } catch {MessageBox.Show("Daylight.ps1이 있는 앱 폴더에서 실행하세요.","Daylight",MessageBoxButtons.OK,MessageBoxIcon.Warning);return 1;}
    }
}
