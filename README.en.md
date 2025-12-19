# Mac Status (macOS Menu Bar System Monitor)

English (current) | [中文](README.zh-CN.md)

<div align="center">

![macOS](https://img.shields.io/badge/macOS-13.0+-blue.svg)
![Swift](https://img.shields.io/badge/Swift-5.0+-orange.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)

A lightweight macOS menu bar app for real-time system monitoring, with Supabase-backed GitHub login and snapshot uploads.

</div>

## Features

- **CPU**: Real-time CPU usage with 1-minute trend sparklines
- **Memory**: Used/total memory, percentage, and 1-minute trend sparklines
- **Real Hardware Sensors**: Real CPU/GPU temperature and fan speed readings (Intel & Apple Silicon support)
- **Battery Health**: Real-time monitoring of battery level, charging status, cycle count, and health percentage
- **High-Resource Processes**: List the top 5 processes consuming the most CPU and memory
- **Menu Bar Customization**: Choose to display CPU, Network, or Memory metrics directly in the menu bar
- **Alert Notifications**: System notifications for high CPU temperature, low memory, or low disk space
- **Smart Power Saving**: Automatically reduces sampling frequency when battery is low (<20%)
- **Launch at Login**: Native support for starting the app automatically at system startup
- **Cloud Sync**: GitHub OAuth login via Supabase; data synchronization with multi-device management (rename/delete records)
- **Disk I/O**: Real-time read/write speeds (MB/s)
- **Network**: Real-time download/upload speeds (MB/s)
- **SwiftUI Interface**: Native macOS look and feel with extremely low resource footprint

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

- **Sandboxing Disabled**: App Sandbox has been disabled to allow direct IOKit access for hardware sensor readings (temperature/fans).
- **Network Access**: Used only for communication with your own Supabase project.
- **Data Privacy**: All data is uploaded to your own Supabase instance; the developers do not have access to your data.

## Roadmap

- [x] Real SMC temperature/fan readings
- [x] Historical charts (recent 1 minute)
- [x] Custom refresh/upload intervals
- [x] Alerts/notifications (CPU/Memory)
- [x] Launch at login option
- [x] Smart Power Saving mode
- [x] Cloud device renaming and cleanup

## Contributing

Issues and PRs are welcome.

## License

MIT, see `LICENSE`.
