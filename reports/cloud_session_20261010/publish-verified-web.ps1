param([switch] $Push)
$ErrorActionPreference = 'Stop'
$workspace = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$source = [IO.Path]::GetFullPath((Join-Path $workspace 'web-mvp/out'))
$sourcePrefix = $source + [IO.Path]::DirectorySeparatorChar
$repo = [IO.Path]::GetFullPath((Join-Path $workspace 'reports/web_publish_20261009/CemkaCapital'))
$prefix = $repo + [IO.Path]::DirectorySeparatorChar
if (-not $repo.StartsWith($workspace + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'PUBLISH_PATH_INVALID' }
function Git([string[]] $Arguments) {
    $result = & git.exe -C $repo @Arguments
    if ($LASTEXITCODE -ne 0) { throw 'PUBLISH_GIT_FAILED' }
    return $result
}
if ((Git @('remote','get-url','origin')) -ne 'https://github.com/CEMKAAA/CemkaCapital.git') { throw 'PUBLISH_REMOTE_INVALID' }
if (Git @('status','--porcelain')) { throw 'PUBLISH_REPO_NOT_CLEAN' }
$env:NEXT_PUBLIC_BASE_PATH = '/CemkaCapital'
& node (Join-Path $workspace 'web-mvp/scripts/check-pages-export.mjs')
if ($LASTEXITCODE -ne 0) { throw 'PUBLISH_EXPORT_INVALID' }
$files = @(Get-ChildItem -LiteralPath $source -Recurse -File -Force)
$manifest = @($files | ForEach-Object {
    @{file=$_.FullName.Substring($sourcePrefix.Length).Replace('\','/');sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}
})
$wanted = @{}
foreach ($file in $manifest) { $wanted[$file.file] = $true }
# Only obsolete tracked build artifacts may be removed. README and .git stay intact.
foreach ($relative in (Git @('ls-files'))) {
    if ($wanted.ContainsKey($relative) -or $relative -eq 'README.md') { continue }
    if ($relative -notmatch '^(?:_next/|_not-found/|studio/|404/|__next\..*\.txt$)') { throw "UNRECOGNIZED_OLD_PUBLIC_FILE: $relative" }
    $target = [IO.Path]::GetFullPath((Join-Path $repo $relative))
    if (-not $target.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)) { throw 'PUBLISH_DELETE_PATH_INVALID' }
    if (Test-Path -LiteralPath $target -PathType Leaf) { Remove-Item -LiteralPath $target }
}
foreach ($file in $files) {
    $relative = $file.FullName.Substring($sourcePrefix.Length)
    $target = [IO.Path]::GetFullPath((Join-Path $repo $relative))
    if (-not $target.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)) { throw 'PUBLISH_COPY_PATH_INVALID' }
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target)) | Out-Null
    Copy-Item -LiteralPath $file.FullName -Destination $target -Force
}
foreach ($file in $manifest) {
    if ((Get-FileHash -LiteralPath (Join-Path $repo $file.file) -Algorithm SHA256).Hash.ToLowerInvariant() -ne $file.sha256) { throw 'PUBLISH_COPY_HASH_MISMATCH' }
}
$record = @{site='https://cemkaaa.github.io/CemkaCapital/studio/';files=$manifest;verifiedAt=[DateTime]::UtcNow.ToString('o');state='verified_copy'}
[IO.File]::WriteAllText((Join-Path $PSScriptRoot 'publication.json'),($record | ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
Git @('add','--all') | Out-Null
Git @('diff','--cached','--check') | Out-Null
Git @('diff','--cached','--stat')
if ($Push) {
    Git @('commit','-m','Recover background session errors without clearing action failures')
    Git @('-c','credential.helper=','-c','credential.helper=!gh auth git-credential','push','origin','main')
    $record.commit = (Git @('rev-parse','HEAD')).Trim()
    $record.state = 'pushed_waiting_for_pages'
    [IO.File]::WriteAllText((Join-Path $PSScriptRoot 'publication.json'),($record | ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
}
