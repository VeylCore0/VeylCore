# VeylCore database backup.
#   powershell -ExecutionPolicy Bypass -File tools\backup-db.ps1 -ServerCfg ..\server\server.cfg
# Reads mysql_connection_string from server.cfg, runs mysqldump and keeps the newest -Keep backups.

param(
    [string]$ServerCfg = "..\server\server.cfg",
    [string]$OutDir = "..\backups",
    [string]$MySqlDump = "",
    [int]$Keep = 14
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $ServerCfg)) { throw "server.cfg not found at $ServerCfg (use -ServerCfg)" }
$line = Select-String -Path $ServerCfg -Pattern 'mysql_connection_string\s+"([^"]+)"' | Select-Object -First 1
if (-not $line) { throw "No mysql_connection_string in $ServerCfg" }
$conn = $line.Matches[0].Groups[1].Value

# mysql://user:password@host:port/database?options   or   key=value;key=value
$user = 'root'; $pass = ''; $dbHost = 'localhost'; $port = '3306'; $db = ''
if ($conn -match '^mysql://([^:@/]+)(?::([^@/]*))?@([^:/]+)(?::(\d+))?/([^?]+)') {
    $user = $Matches[1]; $pass = $Matches[2]; $dbHost = $Matches[3]; if ($Matches[4]) { $port = $Matches[4] }; $db = $Matches[5]
} else {
    foreach ($pair in $conn.Split(';')) {
        $kv = $pair.Split('=', 2)
        if ($kv.Count -ne 2) { continue }
        switch -Regex ($kv[0].Trim().ToLower()) {
            '^(user|user id|uid|username)$' { $user = $kv[1] }
            '^(password|pwd)$' { $pass = $kv[1] }
            '^(host|server)$' { $dbHost = $kv[1] }
            '^port$' { $port = $kv[1] }
            '^(database|db)$' { $db = $kv[1] }
        }
    }
}
if (-not $db) { throw "Could not read the database name from the connection string" }

if (-not $MySqlDump) {
    $candidates = @('C:\xampp\mysql\bin\mysqldump.exe', 'C:\Program Files\MariaDB 10.4\bin\mysqldump.exe', 'mysqldump')
    foreach ($c in $candidates) { if (Get-Command $c -ErrorAction SilentlyContinue) { $MySqlDump = $c; break } }
}
if (-not $MySqlDump) { throw "mysqldump not found (use -MySqlDump <path>)" }

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$stamp = Get-Date -Format 'yyyy-MM-dd_HH-mm'
$file = Join-Path $OutDir "veylcore_${db}_$stamp.sql"
$dumpArgs = @("--host=$dbHost", "--port=$port", "--user=$user", '--single-transaction', '--routines', '--default-character-set=utf8mb4', "--result-file=$file", $db)
if ($pass) { $dumpArgs = @("--password=$pass") + $dumpArgs }
& $MySqlDump @dumpArgs
if ($LASTEXITCODE -ne 0) { throw "mysqldump failed with exit code $LASTEXITCODE" }

$size = [math]::Round((Get-Item $file).Length / 1MB, 2)
Write-Host "Backup written: $file ($size MB)"

Get-ChildItem $OutDir -Filter "veylcore_${db}_*.sql" | Sort-Object LastWriteTime -Descending | Select-Object -Skip $Keep | Remove-Item -Force
