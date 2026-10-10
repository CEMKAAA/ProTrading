param([ValidateSet('inspect','redirects','deploy','cli')][string]$Action='inspect')
$ErrorActionPreference='Stop'
Add-Type @'
using System; using System.Runtime.InteropServices;
public class StratumOAuthKeyring {
 [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] public struct Entry { public uint Flags; public uint Type; public string TargetName; public string Comment; public long LastWritten; public uint CredentialBlobSize; public IntPtr CredentialBlob; public uint Persist; public uint AttributeCount; public IntPtr Attributes; public string TargetAlias; public string UserName; }
 [DllImport("advapi32.dll",EntryPoint="CredReadW",CharSet=CharSet.Unicode)] public static extern bool Read(string target,uint type,uint flags,out IntPtr value);
 [DllImport("advapi32.dll")] public static extern void CredFree(IntPtr value);
}
'@
$pointer=[IntPtr]::Zero
if(-not [StratumOAuthKeyring]::Read('secrets|7056d3b5f55a3a32.codex',1,0,[ref]$pointer)){throw 'OAuth keyring unavailable'}
try {
 $entry=[Runtime.InteropServices.Marshal]::PtrToStructure($pointer,[type][StratumOAuthKeyring+Entry])
 $bytes=New-Object byte[] $entry.CredentialBlobSize
 [Runtime.InteropServices.Marshal]::Copy($entry.CredentialBlob,$bytes,0,$bytes.Length)
 $password=[Text.Encoding]::Unicode.GetString($bytes).TrimEnd([char]0)
} finally {[StratumOAuthKeyring]::CredFree($pointer)}
$start=New-Object Diagnostics.ProcessStartInfo
$start.FileName=(Get-Command node).Source
$start.Arguments='"'+(Join-Path $PSScriptRoot 'manage.mjs')+'" '+$Action
$start.UseShellExecute=$false; $start.CreateNoWindow=$true; $start.RedirectStandardInput=$true
$child=[Diagnostics.Process]::Start($start)
$child.StandardInput.Write($password); $child.StandardInput.Close(); $password=$null
$child.WaitForExit(); if($child.ExitCode -ne 0){throw 'Supabase maintenance failed'}
