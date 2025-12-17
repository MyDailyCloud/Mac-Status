# Mac Status (macOS Menu Bar System Monitor)

English (current) | [中文](README.zh-CN.md)

<div align="center">

![macOS](https://img.shields.io/badge/macOS-13.0+-blue.svg)
![Swift](https://img.shields.io/badge/Swift-5.0+-orange.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)

A lightweight macOS menu bar app for real-time system monitoring, with Supabase-backed GitHub login and snapshot uploads.

</div>

## Features

- **CPU**: real-time CPU usage
- **Memory**: used/total memory and percentage
- **Disk Usage**: used/total capacity and percentage
- **Disk I/O**: real-time read/write speed (MB/s)
- **Network**: real-time download/upload speed (MB/s)
- **Temperatures/Fans**: currently simulated values (`SystemMonitor` has SMC hooks but they return `nil` for now)
- **Auth & Uploading**: GitHub OAuth via Supabase; uploads a snapshot every 5 seconds to `mac_status_metrics`

## Screenshots

Runs as a menu bar icon. Click it to open the panel. (Feel free to add screenshots to the repo and link them here.)

## Requirements

- macOS 13.0+
- Xcode 15.0+ (for building from source)

## Install

### Option A: Install from Release (no build)

1. Download the latest `MacStatus-*-macos.zip` from GitHub Releases and unzip `MacStatus.app`.
2. If macOS blocks the app (“can’t be opened / damaged / unidentified developer”), you can allow it via:
   - Finder → right-click `MacStatus.app` → Open
   - System Settings → Privacy & Security → Open Anyway
   - Or Terminal (replace with your actual path):
     ```bash
     xattr -dr com.apple.quarantine /Applications/MacStatus.app
     ```

### Option B: Build from source

1. Clone
   ```bash
   git clone https://github.com/MyDailyCloud/Mac-Status.git
   cd Mac-Status
   ```
2. Open and run
   ```bash
   open MacStatus.xcodeproj
   ```
   Select `My Mac`, then Run (⌘R).

Command-line build:

```bash
xcodebuild -project MacStatus.xcodeproj -scheme MacStatus -configuration Release
```

## Supabase + GitHub OAuth setup (required)

In the current version, monitoring is unlocked only after login, and snapshots are written to the Supabase table `mac_status_metrics`.

### 1) Provide Supabase config

Config is loaded in this order:

1. Environment variables: `SUPABASE_URL`, `SUPABASE_ANON_KEY`
2. `.env` file (recommended for local dev): copy `.env.example` to `.env` and fill values
3. `MacStatus/Info.plist`: `SUPABASE_URL`, `SUPABASE_ANON_KEY`

Note: `.env` is auto-loaded (priority: app bundle resources → Application Support → current working directory).

### 2) Supabase dashboard settings

- Authentication → URL Configuration → add redirect URL: `macstatus://auth-callback`
- Authentication → Providers → GitHub: enable and fill your GitHub OAuth App `Client ID/Secret`

### 3) Database schema + RLS

Run `supabase/sql/update.sql` in Supabase SQL Editor (idempotent). It creates/updates `mac_status_metrics` and `mac_status_devices` and configures RLS policies.

Note: `mac_status_metrics` includes a `payload jsonb` column for forward-compatible fields, while keeping common fields as separate columns for easy querying.

## Usage

1. Launch: the icon appears on the right side of the macOS menu bar.
2. Click the icon → sign in with GitHub (via Supabase OAuth).
3. After login: UI updates every second; upload interval is at least 5 seconds (see `MacStatus/MetricsUploader.swift`).
4. Quit: use the Quit action in the panel; use Sign out to switch accounts.

## Project layout

```
Mac-Status/
├── MacStatus/
│   ├── MacStatusApp.swift
│   ├── RootView.swift
│   ├── LoginView.swift
│   ├── ContentView.swift
│   ├── SystemMonitor.swift
│   ├── AuthManager.swift
│   ├── MetricsUploader.swift
│   ├── SupabaseMetricsService.swift
│   ├── SupabaseDeviceService.swift
│   ├── DeviceManager.swift
│   ├── DevicesViewModel.swift
│   ├── Info.plist
│   └── MacStatus.entitlements
├── MacStatus.xcodeproj/
└── supabase/
    └── sql/
        ├── update.sql
        ├── mac_status_metrics.sql
        └── mac_status_devices.sql
```

## Notes (implementation)

- **CPU**: `host_processor_info`
- **Memory**: `vm_statistics64` + `physicalMemory`
- **Disk I/O**: IOKit `IOBlockStorageDriver` stats delta → MB/s
- **Network**: `getifaddrs` interface byte counters delta → MB/s
- **Temps/Fans**: SMC read functions are placeholders and fall back to simulated values

## Permissions & Security

- App Sandbox is enabled; network access is required for Supabase.
- Data is uploaded to your own Supabase project; keep `SUPABASE_ANON_KEY` safe and configure RLS appropriately.

## Roadmap

- [ ] Real SMC temperature/fan readings
- [ ] Historical charts and filters
- [ ] Custom refresh/upload intervals
- [ ] Alerts/notifications (e.g., high temperature)
- [ ] Launch at login option

## Contributing

Issues and PRs are welcome.

## License

MIT, see `LICENSE`.
