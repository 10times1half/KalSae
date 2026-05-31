# Repo-internal — paths assume KalSae checkout layout.
param([string]$Accelerator = '^o')
$out="$env:TEMP\kdemo-stdout.log"
$err="$env:TEMP\kdemo-stderr.log"
Remove-Item -ErrorAction SilentlyContinue $out,$err
$exe = Join-Path $PSScriptRoot '..\Samples\KalsaeDemo\.build\release\kalsae-demo.exe'
$exe = (Resolve-Path $exe).Path
$cwd = Split-Path $exe
$p = Start-Process -FilePath $exe -WorkingDirectory $cwd -RedirectStandardOutput $out -RedirectStandardError $err -PassThru
Write-Host "PID: $($p.Id)"
Start-Sleep -Seconds 5
if ($p.HasExited) {
  Write-Host ("Exited BEFORE keys: code={0} (0x{1:X8})" -f $p.ExitCode, $p.ExitCode)
  Get-Content $err -Tail 50
  return
}
$proc = Get-Process -Id $p.Id
Add-Type -Name W -Namespace SW -MemberDefinition '[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool SetForegroundWindow(System.IntPtr h); [System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool ShowWindow(System.IntPtr h, int n);'
[SW.W]::ShowWindow($proc.MainWindowHandle, 9) | Out-Null
[SW.W]::SetForegroundWindow($proc.MainWindowHandle) | Out-Null
Start-Sleep -Milliseconds 800
Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.SendKeys]::SendWait($Accelerator)
Start-Sleep -Seconds 4
if ($p.HasExited) {
  Write-Host ("CRASHED: code={0} (0x{1:X8})" -f $p.ExitCode, $p.ExitCode)
} else {
  Write-Host "Still running, killing"
  Stop-Process -Id $p.Id -Force
}
Write-Host "--- stderr tail ---"
Get-Content $err -Tail 40 -ErrorAction SilentlyContinue
