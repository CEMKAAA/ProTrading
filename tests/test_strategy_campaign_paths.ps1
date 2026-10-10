$ErrorActionPreference='Stop'
$workspace=Split-Path -Parent $PSScriptRoot
$root='C:\Campaign workspace'
$cases=@(
 @{input='reports\verification_build\audit_failures';expected='C:\Campaign workspace\reports\verification_build\audit_failures'},
 @{input='reports/verification_build/audit_failures';expected='C:\Campaign workspace\reports\verification_build\audit_failures'},
 @{input='C:\Campaign workspace\reports\verification_build\audit_failures';expected='C:\Campaign workspace\reports\verification_build\audit_failures'},
 @{input='D:\Other reports\audit_failures';expected='D:\Other reports\audit_failures'},
 @{input='\\server\share\audit_failures';expected='\\server\share\audit_failures'}
)
foreach($name in @('run_strategy_window_campaign.ps1','complete_corrected_strategy_campaign.ps1')){
 $tokens=$null;$errors=$null
 $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $workspace ('scripts\'+$name)),[ref]$tokens,[ref]$errors)
 if($errors.Count){throw ('PowerShell parse errors: '+$name)}
 $assignment=$ast.Find({param($node)
  $node-is [Management.Automation.Language.AssignmentStatementAst]-and $node.Left.Extent.Text-eq '$out'
 },$true)
 if(!$assignment){throw ('Missing report path assignment: '+$name)}
 foreach($case in $cases){
  $ReportDir=$case.input
  Invoke-Expression $assignment.Extent.Text
  if($out-cne $case.expected){throw ($name+': '+$ReportDir+' resolved to '+$out)}
 }
 Write-Output ($name+': '+$cases.Count+' relative/absolute path cases passed')
}
