# Mac Status（macOS 菜单栏系统状态监控）

[English](README.en.md) | 中文（当前）

<div align="center">

![macOS](https://img.shields.io/badge/macOS-13.0+-blue.svg)
![Swift](https://img.shields.io/badge/Swift-5.0+-orange.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)

一个轻量级的 macOS 菜单栏应用，用于实时查看系统状态，并通过 Supabase（GitHub 登录）解锁监控与上报。

</div>

## 功能

- **CPU**：实时 CPU 使用率
- **内存**：已用/总内存与占用比例
- **硬盘使用量**：已用/总容量与占用比例
- **硬盘 I/O**：实时读写速度（MB/s）
- **网络**：实时上下行速度（MB/s）
- **温度/风扇**：当前版本为模拟数据（`SystemMonitor` 内 SMC 读取函数暂未实现）
- **登录与上报**：通过 Supabase 的 GitHub OAuth 登录；每 5 秒向 Supabase 写入一次监控快照（表 `mac_status_metrics`）

## 截图

应用以菜单栏图标形式运行；点击图标弹出面板查看详情。（欢迎补充截图到仓库并在此处引用）

## 系统要求

- macOS 13.0+
- Xcode 15.0+（从源码构建时需要）

## 安装

### 方式一：从 Release 安装（免编译）

1. 到 GitHub Releases 下载最新的 `MacStatus-*-macos.zip`，解压得到 `MacStatus.app`。
2. 首次打开若提示“无法打开 / 已损坏 / 来自身份不明开发者”（未公证应用常见提示），可按以下方式放行：
   - Finder 中右键 `MacStatus.app` → “打开”
   - 或到 `系统设置 -> 隐私与安全性`，在“已阻止打开”处点“仍要打开”
   - 或终端执行（把路径替换为你的实际位置）：
     ```bash
     xattr -dr com.apple.quarantine /Applications/MacStatus.app
     ```

### 方式二：从源码构建

1. 克隆仓库
   ```bash
   git clone https://github.com/MyDailyCloud/Mac-Status.git
   cd Mac-Status
   ```
2. 打开项目并运行
   ```bash
   open MacStatus.xcodeproj
   ```
   在 Xcode 中选择 `My Mac`，运行（⌘R）。

也可以用命令行构建：

```bash
xcodebuild -project MacStatus.xcodeproj -scheme MacStatus -configuration Release
```

## Supabase + GitHub 登录配置（需要）

当前版本登录成功后才会解锁监控，并把数据写入 Supabase 表 `mac_status_metrics`。

### 1）配置 Supabase 连接信息

应用按以下优先级读取配置：

1. 环境变量：`SUPABASE_URL`、`SUPABASE_ANON_KEY`
2. `.env` 文件（推荐本地开发）：复制 `.env.example` 为 `.env` 并填写
3. `MacStatus/Info.plist`：`SUPABASE_URL`、`SUPABASE_ANON_KEY`

说明：`.env` 会自动读取（优先级：App 包资源 → Application Support → 当前工作目录）。

### 2）Supabase 控制台设置

- Authentication → URL Configuration → `Redirect URLs` 添加：`macstatus://auth-callback`
- Authentication → Providers → GitHub：启用并填好 GitHub OAuth App 的 `Client ID/Secret`

### 3）初始化数据库表与 RLS

在 Supabase SQL Editor 里执行 `supabase/sql/update.sql`（幂等）：创建/补齐 `mac_status_metrics` 与 `mac_status_devices`，并配置 RLS policies。

说明：`mac_status_metrics` 同时提供常用列与 `payload jsonb`，客户端会把指标与设备信息写入 `payload`，后续新增字段通常无需改表。

## 使用说明

1. 启动后，应用图标出现在菜单栏右上角。
2. 点击图标打开面板，使用 GitHub 登录（通过 Supabase OAuth）。
3. 登录成功后开始刷新与上报：UI 每秒更新一次；上报最小间隔为 5 秒（见 `MacStatus/MetricsUploader.swift`）。
4. 退出：面板内选择“退出”；切换账号可先“退出登录”。

## 项目结构

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

## 技术要点（简述）

- **CPU**：`host_processor_info`
- **内存**：`vm_statistics64` + `physicalMemory`
- **硬盘 I/O**：IOKit `IOBlockStorageDriver` 的统计项差分计算速率
- **网络**：`getifaddrs` 汇总网卡字节数差分计算速率
- **温度/风扇**：保留 SMC 读取接口，但当前实现返回 `nil`，因此会回退到模拟值

## 权限与安全

- 工程启用了 App Sandbox，并允许网络访问（用于 Supabase）。
- 上报数据写入你自己的 Supabase 项目；请妥善保管 `SUPABASE_ANON_KEY`，并按需配置 RLS。

## Roadmap

- [ ] 接入真实 SMC 温度/风扇数据
- [ ] 增加历史数据图表与筛选
- [ ] 自定义刷新/上报间隔
- [ ] 告警通知（如温度过高）
- [ ] 开机自启选项

## 贡献

欢迎提交 Issue 和 Pull Request。

## 协议

MIT，见 `LICENSE`。
