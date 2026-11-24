# ============================================================
# CONFIGURATION  -  copied to config.ps1 on first run.
# config.ps1 is never committed to git (it holds your keys).
# ============================================================

# Where the server, worlds, plugins, Java runtime and backups live.
# Keep this OUT of cloud-synced folders (OneDrive, Dropbox, Synology Drive):
# syncing files while the server writes them can corrupt worlds.
$ServerDir = "$env:USERPROFILE\MinecraftJavaServer"

# Existing world folder to copy in on first run (leave "" for a fresh world).
# The original is never modified. The world's folder name becomes the level name.
$WorldImportPath = ""

# World folder name inside ServerDir. Leave "" to use the imported world's name (or "world").
$LevelName = ""

# "latest" follows the newest Minecraft release that Paper has a stable build for.
# Pin a version (e.g. "26.3") to stay on it and only receive Paper bug-fix builds.
$MinecraftVersion = "latest"

# Server RAM in GB
$MaxMemoryGB = 4

# Extra JVM arguments, if you need any, e.g. @("-Dfile.encoding=UTF-8")
$ExtraJavaArgs = @()

# ---- CurseForge plugins ----
# Get a free API key at https://console.curseforge.com (sign in, then "API keys").
$CurseForgeApiKey = ""

# Bukkit/Paper plugins to install and keep updated. Use the project's slug
# (the last part of its curseforge.com/minecraft/bukkit-plugins/<slug> URL)
# or its numeric Project ID. Remove a line to uninstall that plugin.
$CurseForgePlugins = @(
    # "worldedit"
    # "essentialsx"
)

# ---- Backups ----
# A world backup is made before each update and once a day. "" = <ServerDir>\backups
$BackupDir     = ""
$BackupsToKeep = 7

# ---- No-IP DDNS ----  leave Username empty to skip
$NoIP_Username = ""
$NoIP_Password = ""
$NoIP_Hostname = ""

# Hour (24h) to check for Paper / Java / plugin updates each day
$UpdateCheckHour = 4

# Auto-update this manager script from GitHub releases
$ScriptAutoUpdate = $true

# Set to $true to agree to the Minecraft EULA (https://aka.ms/MinecraftEULA)
# without being asked. Otherwise you'll be asked once on first run.
$AcceptEula = $false
