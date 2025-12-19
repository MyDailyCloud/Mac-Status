# Mac Status

[English](README.en.md) | [中文](README.zh-CN.md)

<div align="center">

![macOS](https://img.shields.io/badge/macOS-13.0+-blue.svg)
![Swift](https://img.shields.io/badge/Swift-5.0+-orange.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)

A lightweight macOS menu bar app for real-time system monitoring.  
一个轻量级的 macOS 菜单栏系统状态监控工具。

</div>

## Features / 功能

- CPU, memory usage with 1-min trend / CPU、内存使用量及 1 分钟趋势图
- Real SMC Sensors (Temp/Fans) / 真实硬件传感器读取（温度与风扇）
- Battery Health & Cycles / 电池电量、健康度与循环次数监控
- Top Resource Processes / 高资源占用进程实时列表
- Menu Bar Custom Display / 菜单栏图标旁动态指标显示
- Alert Notifications / 异常高温与内存不足系统通知预警
- Smart Power Saving / 低电量自动降频省电模式
- Launch at Login / 支持开机自动启动设置
- GitHub OAuth via Supabase; Device management / 通过 Supabase 登录并支持云端设备管理
- Disk usage, I/O, network throughput / 硬盘容量、读写、网络吞吐监控
- SwiftUI UI, minimal resource usage / SwiftUI 界面，极低资源占用

## Quick Start / 快速开始

- Download: GitHub Releases → `MacStatus-*-macos.zip` → `MacStatus.app`
- Build: `open MacStatus.xcodeproj` (macOS 13+, Xcode 15+)
- Supabase (required): add redirect URL `macstatus://auth-callback`, run `supabase/sql/update.sql`

## Docs / 文档

- English: `README.en.md`
- 中文：`README.zh-CN.md`

## License

MIT, see `LICENSE`.
