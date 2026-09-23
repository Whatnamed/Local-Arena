[CmdletBinding()]
param([Parameter(Mandatory)][string]$Executable, [switch]$ExpectHang)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$exe = (Resolve-Path -LiteralPath $Executable).Path
if (!(($exe + '\').StartsWith($repo + '\', [StringComparison]::OrdinalIgnoreCase))) { throw 'Probe executable must be in this worktree' }
if (Get-Process LocalArena,cs2-bot-improver-plus-panel -ErrorAction SilentlyContinue) { throw 'Close existing Panels before the isolated probe' }
$fixture = Join-Path $repo ('.cache/panel-taskbar-probe/' + [guid]::NewGuid().ToString('N'))
$state = Join-Path $fixture 'state'
$csgo = Join-Path $fixture 'game/csgo'
New-Item -ItemType Directory -Force (Join-Path $csgo 'cfg'), (Join-Path $state 'config') | Out-Null
'"GameInfo" { "FileSystem" { "SearchPaths" { "Game" "csgo" } } }' | Set-Content (Join-Path $csgo 'gameinfo.gi')
@{
 language='schinese'; difficulty='Medium'; mode='online'; insecure=$false
 bot_items=@{skins=$false;profiles=$false;agents=$false;music=$false}
 aim='off'; nades='off'; drop_knife_bind=''; drop_knife_subclasses=@()
 csgo_path=$csgo; first_run_done=$true; welcome_story_prompt_presented=$true
} | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $state 'config/panel.json')
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class TaskbarProbe {
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern uint RegisterWindowMessage(string s);
 [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h,uint m,IntPtr w,IntPtr l);
 [DllImport("user32.dll",SetLastError=true)] public static extern IntPtr SendMessageTimeout(IntPtr h,uint m,IntPtr w,IntPtr l,uint flags,uint timeout,out IntPtr result);
}
'@
$previous = $env:CS2BI_STATE_ROOT
$env:CS2BI_STATE_ROOT = $state
$process = $null
try {
 $process = Start-Process -FilePath $exe -WorkingDirectory $repo -WindowStyle Hidden -PassThru
 $deadline = [DateTime]::UtcNow.AddSeconds(20)
 do { Start-Sleep -Milliseconds 100; $process.Refresh() } while (!$process.MainWindowHandle -and !$process.HasExited -and [DateTime]::UtcNow -lt $deadline)
 if (!$process.MainWindowHandle) { throw 'No Panel HWND was created' }
 Start-Sleep -Seconds 2
 $hwnd = $process.MainWindowHandle
 $message = [TaskbarProbe]::RegisterWindowMessage('TaskbarCreated')
 $hung = $false
 for ($iteration=0; $iteration -lt 12; $iteration++) {
  [void][TaskbarProbe]::PostMessage($hwnd,$message,[IntPtr]::Zero,[IntPtr]::Zero)
  Start-Sleep -Milliseconds 100
  $response=[IntPtr]::Zero
  if ([TaskbarProbe]::SendMessageTimeout($hwnd,0,[IntPtr]::Zero,[IntPtr]::Zero,3,2000,[ref]$response) -eq [IntPtr]::Zero) { $hung=$true; break }
 }
 $result=@{ executable=$exe; pid=$process.Id; hwnd=$hwnd.ToInt64(); taskbarMessages=[Math]::Min($iteration+1,12); hung=$hung; fixture=$fixture }
 $result | ConvertTo-Json | Tee-Object (Join-Path $fixture 'result.json')
 if ($hung -ne [bool]$ExpectHang) { throw "Unexpected hang result: $hung (expected $ExpectHang)" }
} finally {
 if ($process -and !$process.HasExited) { Stop-Process -Id $process.Id }
 $env:CS2BI_STATE_ROOT = $previous
}
