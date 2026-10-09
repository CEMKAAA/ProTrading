param([switch] $Resume)
$ErrorActionPreference = 'Stop'
$workspace = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$release = Join-Path $workspace 'reports/web_publish_20261009'
$repo = Join-Path $release 'CemkaCapital'
$manifest = Get-Content -LiteralPath (Join-Path $release 'release.json') -Raw | ConvertFrom-Json

function Run-Git([string[]] $Arguments) {
    & git -C $repo @Arguments
    if ($LASTEXITCODE -ne 0) { throw 'GIT_PUBLISH_FAILED' }
}
function Run-Gh([string[]] $Arguments) {
    $value = & gh @Arguments
    if ($LASTEXITCODE -ne 0) { throw 'GITHUB_PUBLISH_FAILED' }
    return $value
}
function Optional-Gh([string[]] $Arguments) {
    $previous = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $value = & gh @Arguments 2> (Join-Path $release 'github-preflight.log')
        if ($LASTEXITCODE -eq 0) { return ($value | ConvertFrom-Json) }
        if ((Get-Content -LiteralPath (Join-Path $release 'github-preflight.log') -Raw) -notmatch 'HTTP 404') { throw 'GITHUB_PREFLIGHT_FAILED' }
        return $null
    } finally { $ErrorActionPreference = $previous }
}

foreach ($file in $manifest.files) {
    $path = [IO.Path]::GetFullPath((Join-Path $repo $file.file))
    if (-not $path.StartsWith($repo + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'RELEASE_PATH_INVALID' }
    if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -ne $file.sha256) { throw 'RELEASE_FILE_CHANGED' }
}
# This isolated repository contains only the reviewed public build, not workspace history.
if (Test-Path -LiteralPath (Join-Path $repo '.git')) {
    if (-not $Resume) { throw 'RELEASE_ALREADY_INITIALIZED_USE_RESUME' }
    if ((& git -C $repo remote get-url origin) -ne $manifest.repository -or (& git -C $repo status --porcelain)) { throw 'RELEASE_REPOSITORY_CHANGED' }
} else {
    Run-Git @('init', '-b', 'main')
    Run-Git @('remote', 'add', 'origin', $manifest.repository)
    Run-Git @('add', '--', '.')
    Run-Git @('commit', '-m', 'Publish verified Stratum production frontend')
    Run-Git @('-c', 'credential.helper=', '-c', 'credential.helper=!gh auth git-credential', 'push', '-u', 'origin', 'main')
}
$commit = (Run-Gh @('api', 'repos/CEMKAAA/CemkaCapital/commits/main', '--jq', '.sha')).Trim()
$localCommit = (& git -C $repo rev-parse HEAD).Trim()
if ($commit -ne $localCommit) { throw 'PUBLISHED_COMMIT_MISMATCH' }

$pagesBody = Join-Path $release 'pages-request.json'
[IO.File]::WriteAllText($pagesBody, '{"source":{"branch":"main","path":"/"}}', [Text.UTF8Encoding]::new($false))
$pages = Optional-Gh @('api', 'repos/CEMKAAA/CemkaCapital/pages')
if (-not $pages) { $pages = Run-Gh @('api', '--method', 'POST', 'repos/CEMKAAA/CemkaCapital/pages', '--input', $pagesBody) | ConvertFrom-Json }

# Old authorized email/helper URLs use /studio. Keep them working without
# changing the unrelated root homepage, credentials or cloud configuration.
$redirect = [IO.File]::ReadAllBytes((Join-Path $PSScriptRoot 'legacy-studio-redirect.html'))
$redirectBody = Join-Path $release 'studio-redirect-request.json'
$request = @{message='Route legacy Stratum Studio links to CemkaCapital'; content=[Convert]::ToBase64String($redirect); branch='main'}
$existing = Optional-Gh @('api', 'repos/CEMKAAA/CEMKAAA.github.io/contents/studio/index.html')
if ($existing) {
    $bytes = [Convert]::FromBase64String(($existing.content -replace '\s', ''))
    if ([Text.Encoding]::UTF8.GetString($bytes) -ne [Text.Encoding]::UTF8.GetString($redirect)) { throw 'EXISTING_STUDIO_ROUTE_NOT_OWNED' }
    $redirectCommit = $null
} else {
    [IO.File]::WriteAllText($redirectBody, ($request | ConvertTo-Json -Compress), [Text.UTF8Encoding]::new($false))
    $redirectCommit = (Run-Gh @('api', '--method', 'PUT', 'repos/CEMKAAA/CEMKAAA.github.io/contents/studio/index.html', '--input', $redirectBody) | ConvertFrom-Json).commit.sha
}
$result = @{publishedAt=[DateTime]::UtcNow.ToString('o'); repository=$manifest.repository; commit=$commit; site=$pages.html_url; publicFiles=$manifest.files.Count; legacyStudioRedirectCommit=$redirectCommit; state='pushed_waiting_for_pages'}
[IO.File]::WriteAllText((Join-Path $release 'deployment.json'), ($result | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
$result | ConvertTo-Json
