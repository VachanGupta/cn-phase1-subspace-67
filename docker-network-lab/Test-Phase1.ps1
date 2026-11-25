$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot
$domain = 'app.subspace-67.test'
$url = "https://$domain"
$compose = @('compose', '-f', 'compose.json')
function Lab {
    & docker @compose @args
    if ($LASTEXITCODE) { throw "Docker command failed: $($args -join ' ')" }
}
function Client {
    Lab exec -T client-a @args
}
function ClientShell($name, $script) {
    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($script))
    Lab exec -T $name sh -c 'echo $1 | base64 -d | sh -e' sh $encoded
}
function Require($condition, $message) {
    if (!$condition) { throw $message }
}
function HeaderValue($output, $name) {
    foreach ($line in $output) {
        if ($line -match ('^' + [regex]::Escape($name) + ':\s*(.+)$')) { return $Matches[1].Trim() }
    }
}
New-Item -ItemType Directory -Force evidence | Out-Null
Start-Transcript -Path evidence/phase1.txt -Force
try {
    Lab ps
    # Collect interface/MAC addresses, routes, and peer reachability on each shared LAN.
    $members = @{
        clients = @('client-a','client-b','dns-primary','edge')
        backends = @('backend-a','backend-b','edge')
    }
    foreach ($network in $members.Keys) {
        $addresses = @{}
        foreach ($member in $members[$network]) {
            $container = Lab ps -q $member
            $info = (& docker inspect $container | ConvertFrom-Json)[0]
            $addresses[$member] = $info.NetworkSettings.Networks."subspace67_$network".IPAddress
        }
        foreach ($member in $members[$network]) {
            $container = Lab ps -q $member
            $peers = @($members[$network] | Where-Object { $_ -ne $member } | ForEach-Object { $addresses[$_] })
            Write-Output "LAN $network, source $member, peers $peers"
            $probe = 'ip -br link; ip -br -4 address; ip route; for peer in ' + ($peers -join ' ') + '; do ping -c 1 -W 2 "$peer" || exit 1; done'
            $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($probe))
            & docker run --rm --network "container:$container" --entrypoint sh subspace67-tools:local -c 'echo $1 | base64 -d | sh -e' sh $encoded
            if ($LASTEXITCODE) { throw "LAN probe failed for $member on $network." }
        }
    }
    & docker network inspect subspace67_clients subspace67_backends
    if ($LASTEXITCODE) { throw 'Could not inspect the lab networks.' }
    foreach ($client in 'client-a','client-b') {
        Lab exec -T $client ip -br address
        Lab exec -T $client ping -c 1 10.67.10.10
        foreach ($name in $domain,'api.subspace-67.test') {
            $answer = Lab exec -T $client dig +short +time=2 +tries=2 $name
            $answer
            Require ($answer -contains '10.67.10.10') "$client could not resolve $name"
        }
    }
    foreach ($endpoint in '10.67.20.11:3001','10.67.20.12:3002') {
        $backend = if ($endpoint.EndsWith('3001')) { 'backend-a' } else { 'backend-b' }
        Lab exec -T $backend python -c "import urllib.request; r=urllib.request.urlopen('http://$endpoint/api/status'); print(dict(r.headers)); print(r.read().decode())"
    }
    $hits = @(1..6 | ForEach-Object {
        $response = Client curl -fsSi --max-time 10 "$url/api/status"
        $response | Out-Host
        HeaderValue $response 'X-Backend'
    })
    Require (($hits -join '') -in 'ABABAB','BABABA') "Expected round robin, got $hits"
    $headers = Client curl -fsSI --max-time 10 "$url/api/cache-demo"
    $headers
    $etag = HeaderValue $headers ETag
    Require ($etag -and (HeaderValue $headers 'Cache-Control')) 'Cache headers missing'
    $cacheCommand = 'curl -sS --max-time 10 -o /dev/null -w ''%{{http_code}}'' -H ''If-None-Match: {0}'' ''{1}/api/cache-demo''' -f $etag, $url
    $status = ClientShell client-a $cacheCommand
    Require ($status -eq '304') "Expected 304, got $status"
    Write-Output 'Conditional cache validation returned HTTP 304.'

    ClientShell client-a 'tcpdump -i any -U -w /evidence/phase1.pcap "port 53 or tcp port 443" >/tmp/phase1-cap.log 2>&1 & echo $! >/tmp/phase1-cap.pid'
    try {
        Start-Sleep -Seconds 2
        Client dig +time=2 +tries=1 '@10.67.10.53' $domain
        Client curl -fsSi --max-time 10 --tlsv1.2 --tls-max 1.2 "$url/api/status"
        Client curl -fsSi --max-time 10 --tlsv1.3 "$url/api/status"
    } finally {
        Start-Sleep -Seconds 2
        ClientShell client-a 'kill -INT "$(cat /tmp/phase1-cap.pid)"'
    }
    Start-Sleep -Milliseconds 500
    Client tcpdump -nn -r /evidence/phase1.pcap -c 8
    Write-Output 'F1 - Wrong client DNS address with the edge still reachable.'
    ClientShell client-a 'cp /etc/resolv.conf /tmp/lab-resolv; trap "cat /tmp/lab-resolv >/etc/resolv.conf" EXIT; printf "nameserver 10.67.10.253\n" >/etc/resolv.conf; if dig +time=2 +tries=1 app.subspace-67.test; then exit 1; fi; ping -c 1 10.67.10.10'

    Write-Output 'F2 - DNS responds with the wrong IP.'
    $zone = (Resolve-Path 'runtime/dns-primary/hosts').Path
    $original = [IO.File]::ReadAllText($zone)
    try {
        [IO.File]::WriteAllText($zone, ('10.67.10.99 app.subspace-67.test api.subspace-67.test' + [char]10))
        Lab kill -s HUP dns-primary client-a
        $answer = Client dig +short +time=2 +tries=2 $domain
        $answer
        Require ($answer -contains '10.67.10.99') 'Expected the changed DNS answer.'
        ClientShell client-a 'if curl -fsS --connect-timeout 2 --max-time 4 https://app.subspace-67.test/api/status; then exit 1; fi'
    } finally {
        [IO.File]::WriteAllText($zone, $original)
        Lab kill -s HUP dns-primary client-a
    }

    try {
        Write-Output 'F3 - Backend A stopped.'
        Lab stop backend-a
        foreach ($attempt in 1..4) {
            $response = Client curl -fsSi --max-time 10 "$url/api/status"
            $response
            Require ((HeaderValue $response 'X-Backend') -eq 'B') 'Expected only Backend B.'
        }

        Write-Output 'F4 - Both backends stopped.'
        Lab stop backend-b
        $response = Client curl -sSi --max-time 10 "$url/api/status"
        $response
        Require ($response[0] -match '\s502\s') 'Expected 502 after valid HTTPS.'
    } finally {
        Lab start backend-a backend-b
    }

    Write-Output 'F5 - Wrong destination TCP port with the edge still reachable.'
    Client ping -c 1 10.67.10.10
    ClientShell client-a 'if curl -fsS --connect-timeout 2 --max-time 4 https://app.subspace-67.test:9443/api/status; then exit 1; fi'

} finally {
    Stop-Transcript
}
