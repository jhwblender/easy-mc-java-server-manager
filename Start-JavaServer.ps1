# ============================================================
# EASY MINECRAFT JAVA SERVER MANAGER
# ============================================================
# Drop this script in any folder and run it (or double-click launch.bat).
# It will download, install, update and run a Paper Minecraft server.
#
# Features:
#   - Installs and updates its own private Java runtime (Eclipse Temurin)
#     at the version the Minecraft release needs. Nothing system-wide.
#   - Installs and updates the Paper server jar (checksum verified)
#   - Installs and updates Bukkit/Paper plugins from CurseForge
#   - Optionally imports an existing world folder on first run
#   - Backs up the world before every update
#   - Updates No-IP DDNS on startup and every 15 minutes
#   - Checks for updates daily at the configured hour, with a
#     5-minute in-game countdown before restarting
#   - Auto-restarts the server if it crashes
#   - Type any server command into this window to send it
# ============================================================

$ScriptVersion = "0.1.0"
$RepoSlug      = "jhwblender/easy-mc-java-server-manager"
$UserAgent     = "easy-mc-java-server-manager/$ScriptVersion (+https://github.com/$RepoSlug)"

# ==========================
#       CONFIGURATION
# ==========================

$configPath  = "$PSScriptRoot\config.ps1"
$examplePath = "$PSScriptRoot\config.example.ps1"

function New-Config($path) {
    Write-Host ""
    Write-Host "  No config.ps1 found - let's set one up!" -ForegroundColor Cyan
    Write-Host "  (Press Enter to accept the [default].)" -ForegroundColor Gray
    Write-Host ""

    $defaultDir = "$env:USERPROFILE\MinecraftJavaServer"
    $dir = Read-Host "  Folder for server files and worlds [default: $defaultDir]"
    if (-not $dir) { $dir = $defaultDir }

    $world = Read-Host "  Existing world folder to import (copied, not moved) [leave blank for a new world]"

    $memInput = Read-Host "  Max RAM for the server in GB [default: 4]"
    $mem = if ($memInput -match '^\d+$' -and [int]$memInput -ge 1) { $memInput } else { "4" }

    $cfKey = Read-Host "  CurseForge API key (from https://console.curseforge.com) [leave blank to skip plugins]"

    $username = Read-Host "  No-IP username (email) [leave blank to skip DDNS]"
    $password = ""; $hostname = ""
    if ($username) {
        $secPass  = Read-Host "  No-IP password" -AsSecureString
        $password = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
                        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secPass))
        $hostname = Read-Host "  No-IP hostname (e.g. myserver.ddns.net)"
    }

    $hourInput = Read-Host "  Hour to check for updates 0-23 [default: 4]"
    $hour = if ($hourInput -match '^\d+$' -and [int]$hourInput -le 23) { $hourInput } else { "4" }

    $content = Get-Content $examplePath -Raw
    $values = @{
        ServerDir        = "`"$dir`""
        WorldImportPath  = "`"$world`""
        MaxMemoryGB      = $mem
        CurseForgeApiKey = "`"$cfKey`""
        NoIP_Username    = "`"$username`""
        NoIP_Password    = "`"$($password -replace '"','`"')`""
        NoIP_Hostname    = "`"$hostname`""
        UpdateCheckHour  = $hour
    }
    foreach ($k in $values.Keys) {
        $content = [regex]::Replace($content, "(?m)^\`$$k\s*=.*$", { param($m) "`$$k = $($values[$k])" })
    }
    Set-Content $path -Encoding UTF8 -Value $content

    Write-Host ""
    Write-Host "  config.ps1 created! Edit it anytime - most changes apply on the next update check or restart." -ForegroundColor Green
    Write-Host ""
}

if (!(Test-Path $configPath)) {
    if (!(Test-Path $examplePath)) {
        Write-Host "config.example.ps1 is missing - re-download it from https://github.com/$RepoSlug" -ForegroundColor Red
        Start-Sleep 10; exit 1
    }
    New-Config $configPath
}

# Defaults (overridden by config.ps1) so older configs keep working
$ServerDir         = "$env:USERPROFILE\MinecraftJavaServer"
$LevelName         = ""
$WorldImportPath   = ""
$MinecraftVersion  = "latest"
$MaxMemoryGB       = 4
$ExtraJavaArgs     = @()
$CurseForgeApiKey  = ""
$CurseForgePlugins = @()
$BackupDir         = ""
$BackupsToKeep     = 7
$NoIP_Username     = ""; $NoIP_Password = ""; $NoIP_Hostname = ""
$UpdateCheckHour   = 4
$ScriptAutoUpdate  = $true
$AcceptEula        = $false

. $configPath

# ==========================

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ProgressPreference = 'SilentlyContinue'   # Invoke-WebRequest is 10x slower with the progress bar
$Headers = @{ 'User-Agent' = $UserAgent }

function Write-Log($msg, $color = "White") {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$ts] $msg" -ForegroundColor $color
}

function Resolve-Paths {
    $script:ServerDir   = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($ServerDir))
    $script:RuntimeDir  = Join-Path $ServerDir "runtime"
    $script:PluginsDir  = Join-Path $ServerDir "plugins"
    $script:StateFile   = Join-Path $ServerDir "manager-state.json"
    $script:BackupDirFull = if ($BackupDir) { [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($BackupDir)) } else { Join-Path $ServerDir "backups" }
    foreach ($d in @($ServerDir, $RuntimeDir, $PluginsDir)) {
        if (!(Test-Path $d)) { New-Item -ItemType Directory -Path $d | Out-Null }
    }
}

# ---------- state (installed versions) ----------

function Get-State {
    if (Test-Path $StateFile) {
        try { return Get-Content $StateFile -Raw | ConvertFrom-Json } catch {}
    }
    return [pscustomobject]@{}
}

function Set-StateValue($name, $value) {
    $s = Get-State
    $s | Add-Member -NotePropertyName $name -NotePropertyValue $value -Force
    $s | ConvertTo-Json -Depth 6 | Set-Content $StateFile -Encoding UTF8
}

function Get-StateValue($name) {
    $s = Get-State
    if ($s.PSObject.Properties.Name -contains $name) { return $s.$name }
    return $null
}

# ---------- downloads ----------

function Save-File($url, $dest, $hash, $algorithm = "SHA256") {
    $tmp = "$dest.download"
    Invoke-WebRequest -Uri $url -OutFile $tmp -Headers $Headers -UseBasicParsing
    if ($hash) {
        $actual = (Get-FileHash $tmp -Algorithm $algorithm).Hash
        if ($actual -ne $hash.ToUpper()) {
            Remove-Item $tmp -Force
            throw "Checksum mismatch for $(Split-Path $dest -Leaf) (expected $hash, got $actual)"
        }
    }
    Move-Item $tmp $dest -Force
}

# ---------- No-IP ----------

function Update-NoIP {
    if (-not $NoIP_Username) { return }
    try {
        $publicIP = (Invoke-WebRequest -Uri "https://api.ipify.org" -UseBasicParsing).Content.Trim()
    } catch {
        Write-Log "ERROR: Could not determine public IP: $_" "Red"; return
    }
    Write-Log "Updating No-IP DDNS ($NoIP_Hostname) with IP $publicIP..." "Yellow"
    try {
        $b64  = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("${NoIP_Username}:${NoIP_Password}"))
        $hdrs = @{ Authorization = "Basic $b64"; "User-Agent" = $UserAgent }
        $resp = Invoke-WebRequest -Uri "https://dynupdate.no-ip.com/nic/update?hostname=$NoIP_Hostname&myip=$publicIP" `
                    -Headers $hdrs -UseBasicParsing
        Write-Log "No-IP response: $($resp.Content)" "Green"
    } catch {
        Write-Log "ERROR updating No-IP: $_" "Red"
    }
}

# ---------- Paper ----------

$PaperApi = "https://fill.papermc.io/v3/projects/paper"

# Returns @{ Version; Build; Url; Sha256; FileName; JavaMajor; JavaFlags } for the newest stable build
function Get-LatestPaper {
    try {
        if ($MinecraftVersion -and $MinecraftVersion -ne "latest") {
            $candidates = @($MinecraftVersion)
        } else {
            $project = Invoke-RestMethod "$PaperApi" -Headers $Headers
            # Versions are listed newest first; skip pre-releases / release candidates
            $candidates = foreach ($group in $project.versions.PSObject.Properties) {
                $group.Value | Where-Object { $_ -notmatch '-' }
            }
        }
        foreach ($v in $candidates) {
            $builds = Invoke-RestMethod "$PaperApi/versions/$v/builds" -Headers $Headers
            $stable = $builds | Where-Object { $_.channel -eq "STABLE" } | Select-Object -First 1
            if (-not $stable) { continue }
            $info = Invoke-RestMethod "$PaperApi/versions/$v" -Headers $Headers
            $dl   = $stable.downloads.'server:default'
            return @{
                Version   = $v
                Build     = $stable.id
                Url       = $dl.url
                Sha256    = $dl.checksums.sha256
                FileName  = $dl.name
                JavaMajor = [int]$info.version.java.version.minimum
                JavaFlags = @($info.version.java.flags.recommended)
            }
        }
        throw "No stable Paper build found for: $($candidates -join ', ')"
    } catch {
        Write-Log "ERROR: Could not reach Paper download API: $_" "Red"
        return $null
    }
}

function Install-Paper($paper) {
    Write-Log "Downloading Paper $($paper.Version) build $($paper.Build)..." "Yellow"
    try {
        Save-File $paper.Url (Join-Path $ServerDir "paper.jar") $paper.Sha256
    } catch {
        Write-Log "ERROR: Paper download failed: $_" "Red"; return $false
    }
    Set-StateValue "Paper" @{ Version = $paper.Version; Build = $paper.Build; FileName = $paper.FileName;
                              JavaMajor = $paper.JavaMajor; JavaFlags = $paper.JavaFlags }
    Write-Log "Installed Paper $($paper.Version) build $($paper.Build)." "Green"
    return $true
}

# ---------- Java (Eclipse Temurin via Adoptium) ----------

function Get-LatestJava($major) {
    try {
        $arch = if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") { "aarch64" } else { "x64" }
        $assets = Invoke-RestMethod "https://api.adoptium.net/v3/assets/latest/$major/hotspot?os=windows&architecture=$arch&image_type=jre&vendor=eclipse" -Headers $Headers
        if (-not $assets) {
            # Some versions only ship a JDK
            $assets = Invoke-RestMethod "https://api.adoptium.net/v3/assets/latest/$major/hotspot?os=windows&architecture=$arch&image_type=jdk&vendor=eclipse" -Headers $Headers
        }
        $a = $assets | Select-Object -First 1
        if (-not $a) { throw "No Temurin $major build for Windows $arch" }
        return @{ Major = $major; Release = $a.release_name; Url = $a.binary.package.link;
                  Sha256 = $a.binary.package.checksum; FileName = $a.binary.package.name }
    } catch {
        Write-Log "ERROR: Could not reach Java (Adoptium) API: $_" "Red"
        return $null
    }
}

function Get-JavaExe {
    $j = Get-StateValue "Java"
    if ($j -and $j.Path -and (Test-Path $j.Path)) { return $j.Path }
    return $null
}

function Install-Java($java) {
    Write-Log "Downloading Java $($java.Release) (Eclipse Temurin)..." "Yellow"
    $zip = Join-Path $RuntimeDir $java.FileName
    $dest = Join-Path $RuntimeDir "java-$($java.Major)"
    $staging = "$dest.new"
    try {
        Save-File $java.Url $zip $java.Sha256
        if (Test-Path $staging) { Remove-Item $staging -Recurse -Force }
        Expand-Archive -LiteralPath $zip -DestinationPath $staging -Force
        $inner = Get-ChildItem $staging -Directory | Select-Object -First 1
        if (-not (Test-Path (Join-Path $inner.FullName "bin\java.exe"))) { throw "java.exe not found in archive" }
        if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
        Move-Item $inner.FullName $dest
        Remove-Item $staging -Recurse -Force
        Remove-Item $zip -Force
    } catch {
        Write-Log "ERROR: Java install failed: $_" "Red"
        return $false
    }
    Set-StateValue "Java" @{ Major = $java.Major; Release = $java.Release; Path = (Join-Path $dest "bin\java.exe") }
    Write-Log "Installed Java $($java.Release)." "Green"
    return $true
}

# ---------- CurseForge plugins ----------

$CfApi    = "https://api.curseforge.com/v1"
$CfGameId = 432   # Minecraft
$CfClass  = 5     # Bukkit Plugins

function Invoke-CurseForge($path) {
    Invoke-RestMethod "$CfApi$path" -Headers @{ 'x-api-key' = $CurseForgeApiKey; 'Accept' = 'application/json'; 'User-Agent' = $UserAgent }
}

function Resolve-CfProject($entry) {
    if ("$entry" -match '^\d+$') { return (Invoke-CurseForge "/mods/$entry").data }
    $r = Invoke-CurseForge "/mods/search?gameId=$CfGameId&classId=$CfClass&slug=$([uri]::EscapeDataString($entry))"
    $p = $r.data | Select-Object -First 1
    if (-not $p) { throw "No CurseForge Bukkit plugin with slug '$entry'" }
    return $p
}

function Select-CfFile($projectId, $mcVersion) {
    # Try the exact version, then the version family (e.g. 1.21.4 -> 1.21), then anything
    $tries = @($mcVersion)
    if ($mcVersion -match '^(\d+\.\d+)\.\d+$') { $tries += $Matches[1] }
    foreach ($gv in $tries) {
        $files = (Invoke-CurseForge "/mods/$projectId/files?gameVersion=$gv&pageSize=50").data
        $pick = Get-BestCfFile $files
        if ($pick) { return @{ File = $pick; Compatible = $true } }
    }
    $files = (Invoke-CurseForge "/mods/$projectId/files?pageSize=50").data
    $pick = Get-BestCfFile $files
    if ($pick) { return @{ File = $pick; Compatible = $false } }
    return $null
}

function Get-BestCfFile($files) {
    $usable = @($files | Where-Object { $_.isAvailable -ne $false -and $_.fileName -like "*.jar" } |
                Sort-Object { [datetime]$_.fileDate } -Descending)
    # releaseType: 1 = release, 2 = beta, 3 = alpha
    foreach ($t in 1, 2, 3) {
        $f = $usable | Where-Object { $_.releaseType -eq $t } | Select-Object -First 1
        if ($f) { return $f }
    }
    return $null
}

# Works out what plugin changes are needed. Returns a list of actions; does not download anything.
function Get-PluginPlan($mcVersion) {
    $plan = @()
    if (-not $CurseForgeApiKey) {
        if ($CurseForgePlugins.Count -gt 0) { Write-Log "CurseForge plugins are listed but no CurseForgeApiKey is set - skipping plugins." "Yellow" }
        return ,$plan
    }
    $installed = Get-StateValue "Plugins"
    $wanted = @{}
    foreach ($entry in $CurseForgePlugins) {
        try {
            $proj = Resolve-CfProject $entry
            $wanted["$($proj.id)"] = $true
            $sel  = Select-CfFile $proj.id $mcVersion
            if (-not $sel) { Write-Log "Plugin '$($proj.name)': no downloadable files found." "Yellow"; continue }
            $f = $sel.File
            $cur = if ($installed) { $installed."$($proj.id)" } else { $null }
            if ($cur -and $cur.FileId -eq $f.id -and (Test-Path (Join-Path $PluginsDir $cur.FileName))) { continue }
            if (-not $f.downloadUrl) {
                Write-Log "Plugin '$($proj.name)': the author does not allow third-party downloads. Download it manually from $($proj.links.websiteUrl)" "Yellow"
                continue
            }
            if (-not $sel.Compatible) {
                Write-Log "Plugin '$($proj.name)': no file is tagged for Minecraft $mcVersion - using newest file '$($f.fileName)' anyway." "Yellow"
            }
            $sha1 = ($f.hashes | Where-Object { $_.algo -eq 1 } | Select-Object -First 1).value
            $plan += @{ Action = "install"; Id = "$($proj.id)"; Name = $proj.name; FileId = $f.id; FileName = $f.fileName;
                        Url = $f.downloadUrl; Sha1 = $sha1; Old = $cur }
        } catch {
            Write-Log "ERROR checking plugin '$entry': $_" "Red"
        }
    }
    if ($installed) {
        foreach ($p in $installed.PSObject.Properties) {
            if (-not $wanted.ContainsKey($p.Name)) {
                $plan += @{ Action = "remove"; Id = $p.Name; Name = $p.Value.Name; Old = $p.Value }
            }
        }
    }
    return ,$plan
}

function Invoke-PluginPlan($plan) {
    $installed = Get-StateValue "Plugins"
    $map = @{}
    if ($installed) { foreach ($p in $installed.PSObject.Properties) { $map[$p.Name] = $p.Value } }
    foreach ($a in $plan) {
        try {
            if ($a.Action -eq "remove") {
                $old = Join-Path $PluginsDir $a.Old.FileName
                if (Test-Path $old) { Remove-Item $old -Force }
                $map.Remove($a.Id)
                Write-Log "Removed plugin $($a.Name) (no longer in config)." "Gray"
                continue
            }
            Save-File $a.Url (Join-Path $PluginsDir $a.FileName) $a.Sha1 "SHA1"
            if ($a.Old -and $a.Old.FileName -ne $a.FileName) {
                $old = Join-Path $PluginsDir $a.Old.FileName
                if (Test-Path $old) { Remove-Item $old -Force }
            }
            $map[$a.Id] = @{ Name = $a.Name; FileId = $a.FileId; FileName = $a.FileName }
            Write-Log "Installed plugin $($a.Name): $($a.FileName)" "Green"
        } catch {
            Write-Log "ERROR installing plugin $($a.Name): $_" "Red"
        }
    }
    Set-StateValue "Plugins" $map
}

# ---------- world, EULA, server.properties ----------

function Get-LevelName {
    if ($LevelName) { return $LevelName }
    if ($WorldImportPath) { return (Split-Path $WorldImportPath.TrimEnd('\', '/') -Leaf) }
    return "world"
}

function Set-ServerProperty($key, $value) {
    $file = Join-Path $ServerDir "server.properties"
    $lines = if (Test-Path $file) { @(Get-Content $file) } else { @() }
    $found = $false
    $lines = foreach ($l in $lines) {
        if ($l -match "^$([regex]::Escape($key))=") { $found = $true; "$key=$value" } else { $l }
    }
    if (-not $found) { $lines = @($lines) + "$key=$value" }
    Set-Content $file -Value $lines -Encoding ASCII
}

function Initialize-World {
    $level = Get-LevelName
    Set-ServerProperty "level-name" $level
    $target = Join-Path $ServerDir $level
    if ($WorldImportPath -and !(Test-Path $target)) {
        $src = [Environment]::ExpandEnvironmentVariables($WorldImportPath)
        if (!(Test-Path (Join-Path $src "level.dat"))) {
            Write-Log "WARNING: WorldImportPath '$src' has no level.dat - not importing." "Yellow"
            return
        }
        Write-Log "Importing world '$level' from $src (copying - the original is left untouched)..." "Yellow"
        Copy-Item $src $target -Recurse
        Write-Log "World imported." "Green"
    }
}

function Confirm-Eula {
    $eulaFile = Join-Path $ServerDir "eula.txt"
    if ((Test-Path $eulaFile) -and (Select-String -Path $eulaFile -Pattern '^eula=true' -Quiet)) { return $true }
    if (-not $AcceptEula) {
        Write-Host ""
        Write-Host "  Minecraft servers require agreeing to the Minecraft EULA:" -ForegroundColor Cyan
        Write-Host "  https://aka.ms/MinecraftEULA" -ForegroundColor Cyan
        $ans = Read-Host "  Do you agree to the Minecraft EULA? y/n"
        if ($ans -ne "y") { return $false }
    }
    Set-Content $eulaFile -Encoding ASCII -Value @(
        "# Agreed via easy-mc-java-server-manager on $(Get-Date -Format s). https://aka.ms/MinecraftEULA",
        "eula=true")
    return $true
}

# ---------- backups ----------

function Backup-World($reason) {
    $level = Get-LevelName
    $src = Join-Path $ServerDir $level
    if (!(Test-Path $src)) { return }
    if (!(Test-Path $BackupDirFull)) { New-Item -ItemType Directory -Path $BackupDirFull | Out-Null }
    $zip = Join-Path $BackupDirFull ("{0}_{1}_{2}.zip" -f $level, (Get-Date -Format "yyyyMMdd-HHmmss"), $reason)
    Write-Log "Backing up world to $zip..." "Yellow"
    try {
        # Hand-rolled zip so files the running server holds open (session.lock) don't abort the backup
        Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
        $archive = [IO.Compression.ZipFile]::Open($zip, [IO.Compression.ZipArchiveMode]::Create)
        try {
            $root = (Get-Item $src).Parent.FullName.TrimEnd('\') + '\'
            # Older layouts keep the Nether and End in sibling folders
            $folders = @($src, "${src}_nether", "${src}_the_end") | Where-Object { Test-Path $_ }
            foreach ($file in Get-ChildItem $folders -Recurse -File) {
                if ($file.Name -eq "session.lock") { continue }
                $entry = $archive.CreateEntry($file.FullName.Substring($root.Length).Replace('\', '/'))
                $in  = [IO.File]::Open($file.FullName, 'Open', 'Read', 'ReadWrite')
                $out = $entry.Open()
                try { $in.CopyTo($out) } finally { $out.Dispose(); $in.Dispose() }
            }
        } finally { $archive.Dispose() }
        $old = Get-ChildItem $BackupDirFull -Filter "${level}_*.zip" | Sort-Object LastWriteTime -Descending | Select-Object -Skip $BackupsToKeep
        $old | Remove-Item -Force
        Write-Log "Backup done." "Green"
    } catch {
        Write-Log "ERROR: Backup failed: $_" "Red"
    }
}

# ---------- server process ----------

function Start-MCServer {
    $java = Get-JavaExe
    $paper = Get-StateValue "Paper"
    $jargs = @("-Xms$($MaxMemoryGB)G", "-Xmx$($MaxMemoryGB)G")
    if ($paper -and $paper.JavaFlags) { $jargs += $paper.JavaFlags }
    $jargs += $ExtraJavaArgs
    $jargs += @("-jar", "paper.jar", "--nogui")

    Write-Log "Starting Paper $($paper.Version) build $($paper.Build) with $($MaxMemoryGB)GB RAM..." "Green"
    $pinfo                        = New-Object System.Diagnostics.ProcessStartInfo
    $pinfo.FileName               = $java
    $pinfo.Arguments              = ($jargs | ForEach-Object { if ($_ -match '\s') { "`"$_`"" } else { $_ } }) -join ' '
    $pinfo.WorkingDirectory       = $ServerDir
    $pinfo.RedirectStandardInput  = $true
    $pinfo.UseShellExecute        = $false
    $proc                         = New-Object System.Diagnostics.Process
    $proc.StartInfo               = $pinfo
    # .NET Framework opens the server's stdin with the console's input encoding and, if that is
    # UTF-8, writes a byte-order mark straight away - which garbles the first command we send
    # (the server sees "﻿stop"). Use UTF-8 without a BOM while starting the process.
    $prevEnc = $null
    try { $prevEnc = [Console]::InputEncoding; [Console]::InputEncoding = New-Object Text.UTF8Encoding $false } catch {}
    try { $proc.Start() | Out-Null }
    finally { if ($prevEnc) { try { [Console]::InputEncoding = $prevEnc } catch {} } }
    $writer = New-Object IO.StreamWriter($proc.StandardInput.BaseStream, (New-Object Text.UTF8Encoding $false))
    $writer.AutoFlush = $true
    $proc | Add-Member -NotePropertyName Input -NotePropertyValue $writer
    Write-Log "Server running (PID $($proc.Id))." "Green"
    return $proc
}

function Send-Command($proc, $cmd) {
    try {
        $proc.Input.Write("$cmd`n")
    } catch {
        Write-Log "Warning: Could not send command '$cmd': $_" "Yellow"
    }
}

function Stop-MCServer($proc) {
    if (-not $proc -or $proc.HasExited) { return }
    Write-Log "Sending stop command..." "Yellow"
    Send-Command $proc "stop"
    if (!$proc.WaitForExit(120000)) {
        Write-Log "Server did not stop within 2 minutes - killing process." "Red"
        $proc.Kill()
    }
}

function Send-Countdown($proc, $reason) {
    if (-not $proc -or $proc.HasExited) { return }
    Send-Command $proc "say [SERVER] $reason Restarting in 5 minutes."
    foreach ($m in 4, 3, 2, 1) {
        Start-Sleep -Seconds 60
        if ($proc.HasExited) { return }
        $msg = if ($m -eq 1) { "Restarting in 1 minute!" } else { "Restarting in $m minutes." }
        Send-Command $proc "say [SERVER] $msg"
    }
    Start-Sleep -Seconds 60
    Send-Command $proc "say [SERVER] Shutting down now. Back in a moment!"
    Start-Sleep -Seconds 3
}

# ---------- update orchestration ----------

# Checks Paper, Java and plugins. Returns what needs installing (nothing is changed yet).
function Get-PendingUpdates {
    $pending = @{ Paper = $null; Java = $null; Plugins = @() }
    $paper = Get-LatestPaper
    $cur   = Get-StateValue "Paper"
    if ($paper) {
        if (-not $cur -or $cur.Version -ne $paper.Version -or $cur.Build -ne $paper.Build -or
            !(Test-Path (Join-Path $ServerDir "paper.jar"))) {
            $pending.Paper = $paper
        }
        $major = $paper.JavaMajor
    } elseif ($cur) {
        $major = $cur.JavaMajor
    }
    if ($major) {
        $java = Get-LatestJava $major
        $curJava = Get-StateValue "Java"
        if ($java -and (-not $curJava -or $curJava.Release -ne $java.Release -or -not (Get-JavaExe))) {
            $pending.Java = $java
        }
    }
    $mcVersion = if ($paper) { $paper.Version } elseif ($cur) { $cur.Version } else { $null }
    if ($mcVersion) { $pending.Plugins = Get-PluginPlan $mcVersion }
    return $pending
}

function Test-HasUpdates($p) { return ($p.Paper -or $p.Java -or $p.Plugins.Count -gt 0) }

function Get-UpdateSummary($p) {
    $parts = @()
    if ($p.Paper)   { $parts += "Paper $($p.Paper.Version) build $($p.Paper.Build)" }
    if ($p.Java)    { $parts += "Java $($p.Java.Release)" }
    if ($p.Plugins.Count) { $parts += "$($p.Plugins.Count) plugin change(s)" }
    return ($parts -join ", ")
}

function Install-Updates($p) {
    if ($p.Java)  { Install-Java $p.Java | Out-Null }
    if ($p.Paper) { Install-Paper $p.Paper | Out-Null }
    if ($p.Plugins.Count) { Invoke-PluginPlan $p.Plugins }
}

function Update-Script($proc) {
    if (-not $ScriptAutoUpdate) { return $proc }
    try {
        $rel    = Invoke-RestMethod "https://api.github.com/repos/$RepoSlug/releases/latest" -Headers $Headers
        $latest = $rel.tag_name -replace '^v', ''
    } catch {
        Write-Log "Could not check for script updates: $_" "Gray"
        return $proc
    }
    if ([Version]$latest -le [Version]$ScriptVersion) {
        Write-Log "Manager script is up to date (v$ScriptVersion)." "Green"
        return $proc
    }
    Write-Log "Manager script update available: v$latest (current: v$ScriptVersion)" "Cyan"
    $base = "https://raw.githubusercontent.com/$RepoSlug/v$latest"
    $tmp  = "$PSScriptRoot\_Update-JavaServer.ps1"
    try {
        Invoke-WebRequest -Uri "$base/Start-JavaServer.ps1" -OutFile $tmp -UseBasicParsing
        Invoke-WebRequest -Uri "$base/config.example.ps1" -OutFile $examplePath -UseBasicParsing
    } catch {
        Write-Log "ERROR: Failed to download script update: $_" "Red"
        return $proc
    }
    if ($proc -and !$proc.HasExited) {
        Send-Command $proc "say [SERVER] Server manager is updating. Restarting in 30 seconds."
        Start-Sleep -Seconds 30
        Stop-MCServer $proc
    }
    Copy-Item $tmp "$PSScriptRoot\Start-JavaServer.ps1" -Force
    Remove-Item $tmp
    Write-Log "Script updated to v$latest. Relaunching..." "Cyan"
    Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass -NoExit -File `"$PSScriptRoot\Start-JavaServer.ps1`""
    exit
}

# ============================================================
#  STARTUP
# ============================================================

Write-Host ""
Write-Host "  EASY MINECRAFT JAVA SERVER MANAGER v$ScriptVersion" -ForegroundColor Cyan
Write-Host "  ==========================================" -ForegroundColor Cyan
Write-Host ""

Resolve-Paths
Write-Log "Server folder: $ServerDir" "Gray"

Update-NoIP

Write-Log "Checking for Paper, Java and plugin updates..." "Yellow"
$pending = Get-PendingUpdates
if (Test-HasUpdates $pending) {
    Write-Log "Installing: $(Get-UpdateSummary $pending)" "Cyan"
    if ($pending.Paper -and (Get-StateValue "Paper")) { Backup-World "pre-update" }
    Install-Updates $pending
} else {
    Write-Log "Everything is up to date." "Green"
}

if (-not (Get-JavaExe) -or !(Test-Path (Join-Path $ServerDir "paper.jar"))) {
    Write-Log "FATAL: Java or paper.jar is missing. Check errors above." "Red"
    Start-Sleep 10; exit 1
}

if (-not (Confirm-Eula)) {
    Write-Log "The server cannot run without agreeing to the EULA. Exiting." "Red"
    Start-Sleep 10; exit 1
}

Initialize-World
Remove-Item (Join-Path $ServerDir "manager-stop") -Force -ErrorAction SilentlyContinue

$serverProc      = Start-MCServer
$lastCheckDate   = (Get-Date).ToString("yyyyMMdd")   # just checked
$lastCrashTime   = $null
$crashCooldown   = 60
$noIPIntervalMin = 15
$lastNoIPUpdate  = Get-Date
$configLastWrite = (Get-Item $configPath).LastWriteTime

Write-Log "Manager running. Update check daily at $($UpdateCheckHour):00. Press Ctrl+C to exit." "Cyan"
Write-Log "Type any Minecraft server command and press Enter to send it." "Cyan"

function Wait-OrInput($proc, $seconds) {
    $deadline = (Get-Date).AddSeconds($seconds)
    while ((Get-Date) -lt $deadline) {
        # "stop" typed here, or a stop file (see stop.bat), shuts down cleanly and exits the manager
        $stopFile = Join-Path $ServerDir "manager-stop"
        if (Test-Path $stopFile) {
            Remove-Item $stopFile -Force
            Exit-Manager $proc
        }
        $hasKey = $false
        if (-not [Console]::IsInputRedirected) { try { $hasKey = [Console]::KeyAvailable } catch {} }
        if ($hasKey) {
            $line = [Console]::ReadLine()
            if ($line -and $line.Trim() -eq "stop") { Exit-Manager $proc }
            if ($line -and $proc -and !$proc.HasExited) {
                Send-Command $proc $line
            }
        }
        if ($proc.HasExited) { return }
        Start-Sleep -Milliseconds 100
    }
}

function Exit-Manager($proc) {
    Write-Log "Stopping server and exiting manager..." "Yellow"
    Stop-MCServer $proc
    Write-Log "Server stopped. Goodbye!" "Green"
    exit 0
}

# ============================================================
#  MAIN LOOP
# ============================================================

while ($true) {
    Wait-OrInput $serverProc 30

    # -- Auto-restart on crash / stop ------------------------
    if ($serverProc.HasExited) {
        $now = Get-Date
        if ($lastCrashTime -and (($now - $lastCrashTime).TotalSeconds -lt $crashCooldown)) {
            Write-Log "Server exited again quickly - waiting $crashCooldown seconds before restart." "Yellow"
            Start-Sleep -Seconds $crashCooldown
        }
        Write-Log "Server is not running (exit code $($serverProc.ExitCode)) - restarting..." "Yellow"
        $lastCrashTime = Get-Date
        $serverProc    = Start-MCServer
        continue
    }

    # -- Config hot-reload -----------------------------------
    $configWrite = (Get-Item $configPath).LastWriteTime
    if ($configWrite -ne $configLastWrite) {
        . $configPath
        Resolve-Paths
        $configLastWrite = $configWrite
        Write-Log "Config reloaded. Plugin and version changes apply at the next update check." "Cyan"
    }

    # -- Periodic No-IP refresh ------------------------------
    if (((Get-Date) - $lastNoIPUpdate).TotalMinutes -ge $noIPIntervalMin) {
        Update-NoIP
        $lastNoIPUpdate = Get-Date
    }

    # -- Daily update check ----------------------------------
    $now     = Get-Date
    $dateKey = $now.ToString("yyyyMMdd")
    if ($now.Hour -eq $UpdateCheckHour -and $lastCheckDate -ne $dateKey) {
        $lastCheckDate = $dateKey
        Write-Log "Running scheduled update check..." "Yellow"

        $serverProc = Update-Script $serverProc

        $pending = Get-PendingUpdates
        if (Test-HasUpdates $pending) {
            $desc = Get-UpdateSummary $pending
            Write-Log "Updates found: $desc" "Green"
            Send-Countdown $serverProc "Updates are available."
            Stop-MCServer $serverProc
            Backup-World "pre-update"
            Install-Updates $pending
            Update-NoIP
            $serverProc    = Start-MCServer
            $lastCrashTime = $null
        } else {
            Write-Log "Everything is already up to date." "Green"
            # Live backup: flush the world to disk and pause autosave while zipping
            Send-Command $serverProc "save-off"
            Send-Command $serverProc "save-all flush"
            Start-Sleep -Seconds 10
            Backup-World "daily"
            Send-Command $serverProc "save-on"
        }
    }
}
