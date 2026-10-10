param([string]$Action = 'inspect')
$ErrorActionPreference = 'Stop'
$project = 'uvzhrrqzzdjqtmydpvwo'
Add-Type @'
using System;
using System.Runtime.InteropServices;
public class StratumCloudCredential {
 [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] public struct Entry {public uint Flags; public uint Type; public string TargetName; public string Comment; public long LastWritten; public uint CredentialBlobSize; public IntPtr CredentialBlob; public uint Persist; public uint AttributeCount; public IntPtr Attributes; public string TargetAlias; public string UserName;}
 [DllImport("advapi32.dll", EntryPoint="CredReadW", CharSet=CharSet.Unicode)] public static extern bool Read(string target,uint type,uint flags,out IntPtr value);
 [DllImport("advapi32.dll")] public static extern void CredFree(IntPtr value);
}
'@
$pointer = [IntPtr]::Zero
if (-not [StratumCloudCredential]::Read('supabase|88a39f8cfe7ef7ec.Codex MCP Credentials', 1, 0, [ref]$pointer)) { throw 'Supabase credential unavailable' }
try {
 $entry = [Runtime.InteropServices.Marshal]::PtrToStructure($pointer, [type][StratumCloudCredential+Entry])
 $bytes = New-Object byte[] $entry.CredentialBlobSize
 [Runtime.InteropServices.Marshal]::Copy($entry.CredentialBlob, $bytes, 0, $bytes.Length)
 $credential = [Text.Encoding]::Unicode.GetString($bytes).TrimEnd([char]0) | ConvertFrom-Json
} finally { [StratumCloudCredential]::CredFree($pointer) }
if ($Action -eq 'inspect-store') {
 if (-not [StratumCloudCredential]::Read('secrets|7056d3b5f55a3a32.codex', 1, 0, [ref]$pointer)) { throw 'Credential store unavailable' }
 try {
  $entry = [Runtime.InteropServices.Marshal]::PtrToStructure($pointer, [type][StratumCloudCredential+Entry])
  $bytes = New-Object byte[] $entry.CredentialBlobSize
  [Runtime.InteropServices.Marshal]::Copy($entry.CredentialBlob, $bytes, 0, $bytes.Length)
  $store = [Text.Encoding]::Unicode.GetString($bytes).TrimEnd([char]0) | ConvertFrom-Json
  Write-Output ('Store fields: ' + ($store.psobject.Properties.Name -join ', '))
  foreach ($property in $store.psobject.Properties) {
   if ($property.Value -is [pscustomobject]) { Write-Output ($property.Name + ': ' + ($property.Value.psobject.Properties.Name -join ', ')) }
  }
 } finally { [StratumCloudCredential]::CredFree($pointer) }
 exit
}
if ($credential.url -notmatch "project_ref=$project(?:&|$)") { throw 'Stored credential is not scoped to the Stratum project' }
$headers = @{ Authorization = 'Bearer ' + $credential.token_response.access_token; Accept = 'application/json, text/event-stream' }
if ($Action -eq 'inspect') {
 try {
  $config = Invoke-RestMethod -Uri "https://api.supabase.com/v1/projects/$project/config/auth" -Headers $headers -TimeoutSec 25
  $config | Select-Object site_url,uri_allow_list,mailer_autoconfirm,external_email_enabled | ConvertTo-Json -Compress
  $functions = Invoke-RestMethod -Uri "https://api.supabase.com/v1/projects/$project/functions" -Headers $headers -TimeoutSec 25
  $functions | Where-Object slug -eq 'stratum-control' | Select-Object id,slug,status,version,verify_jwt | ConvertTo-Json -Compress
 } catch { Write-Output ('Management request status: ' + [int]$_.Exception.Response.StatusCode) }
 $body = @{ jsonrpc = '2.0'; id = 2; method = 'tools/list'; params = @{} } | ConvertTo-Json -Depth 10
 try {
  $response = Invoke-WebRequest -UseBasicParsing -Uri $credential.url -Method POST -Headers $headers -ContentType 'application/json' -Body $body -TimeoutSec 25
  $json = $response.Content -replace '(?m)^data: ',''
  $data = $json | ConvertFrom-Json
  $data.result.tools | Where-Object name -match 'deploy_edge_function|get_logs|execute_sql|search_docs' | Select-Object name,inputSchema | ConvertTo-Json -Depth 15
 } catch { Write-Output ('MCP request status: ' + [int]$_.Exception.Response.StatusCode) }
}
