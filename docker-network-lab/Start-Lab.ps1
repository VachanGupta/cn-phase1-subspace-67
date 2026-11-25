param([switch]$Phase2)

$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot

function Invoke-Docker {
    & docker @args
    if ($LASTEXITCODE -ne 0) { throw "Docker exited with code $LASTEXITCODE." }
}

Invoke-Docker info --format '{{.OSType}}'
Invoke-Docker compose -f compose.json build client-a
New-Item -ItemType Directory -Force -Path runtime,evidence | Out-Null
Invoke-Docker run --rm --network none --mount "type=bind,source=$PSScriptRoot\runtime,target=/lab/runtime" --mount "type=bind,source=$PSScriptRoot\init-runtime.sh,target=/init-runtime.sh,readonly" subspace67-tools:local bash /init-runtime.sh
$composeArgs = @('compose', '-f', 'compose.json')
if ($Phase2) { $composeArgs += @('--profile', 'phase2') }
$rotationMarker = 'runtime/recreate-after-rotation'
if (Test-Path -LiteralPath $rotationMarker) {
    Invoke-Docker compose -f compose.json --profile phase2 up -d --force-recreate edge standby client-a client-b
    Remove-Item -LiteralPath $rotationMarker
}
Invoke-Docker @composeArgs up -d
Invoke-Docker @composeArgs ps
