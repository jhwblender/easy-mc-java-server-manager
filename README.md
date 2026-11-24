# Easy Minecraft Java Server Manager

A drop-in PowerShell script that installs, updates and runs a **Minecraft Java Edition** server on Windows: no Java install, no jar hunting, no manual plugin updates.

It's the Java Edition sibling of [easy-bedrock-server-manager](https://github.com/jhwblender/easy-bedrock-server-manager).

## What it does

- **Java, handled for you.** Downloads a private copy of [Eclipse Temurin](https://adoptium.net) at the exact version your Minecraft release needs (Java 25 for 26.x) into the server folder, and keeps it patched. Other Java versions on your PC are not touched or used.
- **Paper server.** Runs [Paper](https://papermc.io), a fast server that vanilla clients join with no mods and that supports Bukkit/Paper plugins. It installs the newest stable build and verifies its checksum.
- **CurseForge plugins.** List plugins by slug or project ID; it installs the best file for your Minecraft version, keeps it updated, and removes it when you take it off the list.
- **Import an existing world.** Point it at a singleplayer or vanilla server world folder. The world is *copied*, so the original is never touched.
- **Backups.** Zips the world before every update and once a day, keeping the last 7.
- **Daily update check** at an hour you choose, with a 5-minute in-game countdown before restarting.
- **Auto-restart** if the server crashes.
- **No-IP DDNS** updates, so friends can use a hostname instead of your changing IP.
- **Self-updating** from this repo's GitHub releases.

## Quick start

1. Download this repo (green **Code** button → **Download ZIP**) and extract it anywhere.
2. Double-click **`launch.bat`**.
3. Answer the setup questions. Press Enter to accept a default.
4. Agree to the [Minecraft EULA](https://aka.ms/MinecraftEULA) when asked.

The first run downloads Java (~60 MB) and Paper (~55 MB), then starts the server. Players connect to your PC's IP on port **25565**. For people outside your home network, forward TCP port 25565 on your router.

By default the server, world and everything else live in the same folder as `launch.bat`. Set `ServerDir` to put them somewhere else.

> **Keep the server folder out of cloud-synced folders** (OneDrive, Dropbox, Google Drive, Synology Drive). Syncing files while the server writes them can corrupt your world.

## Using it

| To... | Do this |
|---|---|
| Run a server command | Type it into the manager window (e.g. `op Steve`, `say hi`, `whitelist add Alex`) |
| Stop the server cleanly | Type `stop` in the window, or double-click **`stop.bat`** |
| Change settings | Edit `config.ps1`. Plugin and version changes apply at the next update check or restart |
| Change game settings | Edit `server.properties` (next to `launch.bat` by default), then restart |
| Keep someone out | `ban <player>` (`pardon <player>` to undo). New servers start with the whitelist **off**, so anyone with your address can join |
| Allow only listed players | `whitelist on`, then `whitelist add <player>` for each person |

## Plugins from CurseForge

CurseForge requires an API key to download files:

1. Sign in at <https://console.curseforge.com> and create an API key (free).
2. Put it in `config.ps1` in **single** quotes: `$CurseForgeApiKey = '$2a$10$...'`. Keys contain `$` signs, which PowerShell treats as variables inside double quotes.
3. Add plugins by slug: the last part of `https://www.curseforge.com/minecraft/bukkit-plugins/<slug>`.

```powershell
$CurseForgePlugins = @(
    "worldedit"
    "essentialsx"
)
```

Notes:
- If a plugin has no file tagged for your Minecraft version, the newest file is used and a warning is shown.
- Some authors don't allow third-party downloads. The script tells you, and you can drop that jar into `plugins\` yourself. The manager only touches plugin files it installed.

## Configuration

Everything lives in `config.ps1` (created from [`config.example.ps1`](config.example.ps1) on first run; it's git-ignored because it holds your keys).

| Setting | Default | |
|---|---|---|
| `ServerDir` | `""` (this folder) | Server, worlds, plugins, Java runtime, backups |
| `WorldImportPath` | `""` | World folder to copy in on first run |
| `LevelName` | `""` | World folder name (the imported world's name, or `world`) |
| `MinecraftVersion` | `"latest"` | Or pin e.g. `"26.3"` |
| `MaxMemoryGB` | `4` | Server RAM |
| `CurseForgeApiKey` / `CurseForgePlugins` | | See above |
| `BackupDir` / `BackupsToKeep` | `<ServerDir>\backups` / `7` | |
| `NoIP_Username` / `NoIP_Password` / `NoIP_Hostname` | | Leave username blank to skip |
| `UpdateCheckHour` | `4` | 0–23 |
| `ScriptAutoUpdate` | `$true` | Update this script from GitHub releases |
| `AcceptEula` | `$false` | `$true` skips the EULA prompt |

## Server folder layout

```
<this folder>\
  launch.bat, stop.bat, Start-JavaServer.ps1, config.ps1
  paper.jar             server (managed)
  runtime\java-25\      Java (managed)
  plugins\              your plugins
  world\                your world (or the imported world's name)
  backups\              world backups
  manager-state.json    what the manager installed
  server.properties ... normal Paper/Minecraft files
```

## Requirements

Windows 10/11 (64-bit) with Windows PowerShell 5.1 (built in) or PowerShell 7.

## License

MIT
