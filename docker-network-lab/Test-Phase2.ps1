$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot
$domain = 'app.subspace-67.test'
$url = "https://$domain/api/status"
$compose = @('compose', '-f', 'compose.json', '--profile', 'phase2')
function Lab {
    & docker @compose @args
    if ($LASTEXITCODE) { throw "Docker command failed: $($args -join ' ')" }
}
function Client($name) {
    Lab exec -T $name @args
}
function ClientShell($name, $script) {
    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($script))
    Lab exec -T $name sh -c 'echo $1 | base64 -d | sh -e' sh $encoded
}
function Require($condition, $message) {
    if (!$condition) { throw $message }
}
function Resolve-Edge($client) {
    Client $client dig +short +time=3 +tries=5 $domain
}
function Set-EdgeRecord($address) {
    $record = "$address app.subspace-67.test api.subspace-67.test" + [char]10
    foreach ($service in 'dns-primary','dns-backup') {
        [IO.File]::WriteAllText((Resolve-Path "runtime/$service/hosts").Path, $record)
    }
    Lab kill -s HUP dns-primary dns-backup | Out-Host
}
function Show-Edge($client, $address) {
    $response = Client $client curl -fsSi --max-time 10 $url
    $response | Out-Host
    Require ($response -match ('^X-Edge:\s*' + [regex]::Escape($address) + '\s*$')) "Expected $client to reach edge $address."
}
New-Item -ItemType Directory -Force evidence | Out-Null
Start-Transcript -Path evidence/phase2.txt -Force
try {
    Lab up -d
    Set-EdgeRecord '10.67.10.10'
    Write-Output 'A - Primary DNS stopped, clients query through backup.'
    try {
        Lab stop dns-primary
        Lab kill -s HUP client-a client-b
        foreach ($client in 'client-a','client-b') {
            $answer = Resolve-Edge $client
            $answer
            Require ($answer -contains '10.67.10.10') "Backup DNS failed for $client."
        }
        Lab logs --tail 25 dns-backup
    } finally {
        Lab start dns-primary
    }

    Write-Output 'C - Direct client access fails while the edge can reach both backends.'
    Client client-a ip route
    ClientShell client-a 'for target in 10.67.20.11:3001 10.67.20.12:3002; do if curl -fsS --connect-timeout 2 --max-time 4 "http://$target/api/status"; then exit 1; fi; done'
    Lab exec -T edge wget -qO- http://10.67.20.11:3001/api/status
    Lab exec -T edge wget -qO- http://10.67.20.12:3002/api/status
    Show-Edge client-a '10.67.10.10'

    Write-Output 'D - Service continues on B and resumes balancing after A returns.'
    try {
        Lab stop backend-a
        foreach ($attempt in 1..4) {
            $response = Client client-a curl -fsSi --max-time 10 $url
            $response
            Require ($response -match '^X-Backend:\s*B\s*$') 'Backend B should serve every request.'
        }
    } finally {
        Lab start backend-a
    }
    Start-Sleep -Seconds 6
    $response = @(1..8 | ForEach-Object { Client client-a curl -fsSi --max-time 10 $url })
    $response
    Require (($response -match '^X-Backend:\s*A\s*$') -and ($response -match '^X-Backend:\s*B\s*$')) 'Both backends should serve traffic again.'

    Write-Output 'B/E - Cached and fresh lookups reach different edges during a 30-second cutover.'
    Lab kill -s HUP client-a client-b
    Client client-a dig +noall +answer $domain
    Set-EdgeRecord '10.67.10.20'
    Client client-a dig +noall +answer $domain
    Show-Edge client-a '10.67.10.10'
    Show-Edge client-b '10.67.10.20'
    Start-Sleep -Seconds 31
    Show-Edge client-a '10.67.10.20'

    Write-Output 'B - Flush client cache to observe a record change immediately.'
    Set-EdgeRecord '10.67.10.10'
    Show-Edge client-a '10.67.10.20'
    Lab kill -s HUP client-a
    Show-Edge client-a '10.67.10.10'
} finally {
    try {
        Lab start dns-primary dns-backup backend-a backend-b
        Set-EdgeRecord '10.67.10.10'
        Lab kill -s HUP client-a client-b
    } finally {
        Stop-Transcript
    }
}
