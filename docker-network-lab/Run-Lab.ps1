$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot
if (!(Get-Command docker -ErrorAction SilentlyContinue)) {
    $dockerBins = @(
        (Join-Path $env:LOCALAPPDATA 'Programs\DockerDesktop\resources\bin'),
        (Join-Path $env:USERPROFILE 'AppData\Local\Programs\DockerDesktop\resources\bin'),
        (Join-Path $env:ProgramFiles 'Docker\Docker\resources\bin')
    )
    foreach ($bin in $dockerBins) {
        if (Test-Path -LiteralPath (Join-Path $bin 'docker.exe')) {
            $env:PATH = "$bin;$env:PATH"
            break
        }
    }
}
$engine = & docker info --format '{{.OSType}}'
if ($LASTEXITCODE -ne 0 -or $engine -ne 'linux') {
    throw 'Open Docker Desktop and wait for its Linux container engine to start, then retry in normal Windows PowerShell.'
}

& "$PSScriptRoot\Start-Lab.ps1"
$ready = $false
foreach ($attempt in 1..24) {
    & docker compose -f compose.json exec -T client-a sh -c 'curl -fsS --max-time 3 https://app.subspace-67.test/api/status >/dev/null 2>&1'
    if ($LASTEXITCODE -eq 0) {
        $ready = $true
        break
    }
    Start-Sleep -Seconds 2
}
if (!$ready) {
    & docker compose -f compose.json ps -a
    & docker compose -f compose.json logs --tail 15
    throw 'The baseline lab did not become ready.'
}

& "$PSScriptRoot\Test-Phase1.ps1"
& "$PSScriptRoot\Test-Phase2.ps1"
Write-Output "Automated checks finished. Evidence: $PSScriptRoot\evidence"
