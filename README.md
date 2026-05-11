# ProxiFyre Config Editor

A portable **PowerShell + WPF GUI** for visually creating, editing, and validating ProxiFyre's `app-config.json`. No Visual Studio, no compilation, no external dependencies — just a single `.ps1` file.

![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B%20%7C%207%2B-blue?logo=powershell)
![.NET](https://img.shields.io/badge/.NET-WPF-green?logo=dotnet)
![License](https://img.shields.io/badge/license-MIT-lightgrey)

---

## ✨ Features

| Feature | Description |
|---------|-------------|
| **Visual Config Editor** | Edit `logLevel`, `bypassLan`, proxy rules, and exclusions through a clean WPF interface |
| **Live JSON Preview** | Real-time indented JSON preview with `camelCase` keys and string enums |
| **Proxy Rule CRUD** | Add, edit, clone, and remove proxy rules with per-rule app lists, endpoint, auth, and protocols |
| **Process Picker** | Double-click a running process to add it to a proxy rule (Name column → app name, Path column → full path) |
| **Config Validation** | Built-in validators for endpoint format, duplicate app names, and empty fields |
| **Service Control** | Install, start, stop, restart, and uninstall the `ProxiFyreService` directly from the GUI |
| **Auto-Detect** | Automatically loads `app-config.json` if found next to `ProxiFyre.exe` |
| **PowerShell 5.1 & 7+** | Works on both Windows PowerShell and PowerShell Core |

---

## 📋 Requirements

- Windows 10/11
- **PowerShell 5.1** or **PowerShell 7+**
- Administrator privileges (required for service management)

---

## 🚀 Quick Start

### Option 1: Run with the batch file (recommended)

```batch
Run.bat
```

The batch file automatically picks `pwsh.exe` (PS 7+) or falls back to `powershell.exe` (PS 5.1) with `-ExecutionPolicy Bypass`.

### Option 2: Run directly from PowerShell

```powershell
# PowerShell 7
pwsh -ExecutionPolicy Bypass -File .\ProxiFyre-GUI.ps1

# Windows PowerShell 5.1
powershell -ExecutionPolicy Bypass -File .\ProxiFyre-GUI.ps1
```

> **Note:** The script will auto-elevate to Administrator if not already running with elevated privileges.

---

## 📸 Interface Overview

```
┌─────────────────────────────────────────────────────────┐
│  File | Tools | Service                                 │
├─────────────────────────────────────────────────────────┤
│  [Log Level ▼] [☐ Bypass LAN traffic]                   │
├─────────────────────────────────────────────────────────┤
│  Proxy Rules                                            │
│  ┌───────────────────────────────────────────────────┐  │
│  │ Applications │ Endpoint      │ Auth │ Protocols   │  │
│  ├───────────────────────────────────────────────────┤  │
│  │ chrome       │ 127.0.0.1:...│ user │ TCP, UDP    │  │
│  └───────────────────────────────────────────────────┘  │
│  [Add] [Edit] [Remove] [Clone]                          │
├─────────────────────────────────────────────────────────┤
│  JSON Preview                                           │
│  { "logLevel": "error", ... }                           │
├─────────────────────────────────────────────────────────┤
│  Exclusions (bypass proxy)                              │
│  ┌──────────────────────┐  [Add] [Remove] [Browse...]  │
│  │ edge                 │                               │
│  └──────────────────────┘                               │
├─────────────────────────────────────────────────────────┤
│  Ready                                    Service: ON   │
└─────────────────────────────────────────────────────────┘
```

---

## ⚙️ Service Menu

If you have `ProxiFyre.exe` in the same folder (or point to it via the file dialog), the **Service** menu lets you control the Windows service:

| Menu Item | Action | Underlying Command |
|-----------|--------|--------------------|
| **Install** | Registers the service | `ProxiFyre.exe install` |
| **Uninstall** | Removes the service | `ProxiFyre.exe uninstall` |
| **Start** | Starts `ProxiFyreService` | `sc start ProxiFyreService` |
| **Stop** | Stops `ProxiFyreService` | `sc stop ProxiFyreService` |
| **Restart** | Stops then starts with wait | `sc stop` → wait → `sc start` |

Service status is shown live in the bottom-right status bar:
- 🟢 **Service: ON** — running
- 🔴 **Service: OFF** — stopped
- ⚪ **Service: NOT INSTALLED** — not found

---

## 🛠️ Example Output

```json
{
  "logLevel": "error",
  "bypassLan": true,
  "proxies": [
    {
      "appNames": ["chrome", "firefox"],
      "socks5ProxyEndpoint": "127.0.0.1:1080",
      "username": "user",
      "password": "pass",
      "supportedProtocols": ["tcp", "udp"]
    }
  ],
  "excludes": ["edge", "C:\\Program Files\\SomeApp\\app.exe"]
}
```

Empty collections and blank auth fields are automatically omitted from the JSON.

---

## 🧩 Architecture

```text
ProxiFyre-GUI.ps1          # Single-file monolith
├── C# Models (Add-Type)   # AppConfig, ProxyConfig, LogLevel, Protocol
├── XAML (inline)          # MainWindow, EditProxyDialog, ProcessPicker, InputBox
├── JSON Service           # System.Text.Json (PS 7+) / ConvertTo-Json (PS 5.1)
├── WPF Event Handlers     # Menu, Buttons, Drag&Drop
└── Service Helpers        # ProxiFyre.exe & sc.exe wrappers
```

---

## 📄 License

MIT

---

> **Disclaimer:** This project is an unofficial GUI wrapper for [ProxiFyre](https://github.com/wiresock/proxifyre). All rights to ProxiFyre belong to its respective authors.
