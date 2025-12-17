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

- CPU, memory, disk usage, disk I/O, network throughput / CPU、内存、硬盘使用量、硬盘读写、网络吞吐
- Temperatures & fans (currently simulated) / 温度与风扇（当前为模拟数据）
- GitHub OAuth via Supabase; uploads snapshots to Supabase / 通过 Supabase 使用 GitHub 登录，并上报监控快照
- SwiftUI UI, minimal resource usage / SwiftUI 界面，低资源占用

## Quick Start / 快速开始

- Download: GitHub Releases → `MacStatus-*-macos.zip` → `MacStatus.app`
- Build: `open MacStatus.xcodeproj` (macOS 13+, Xcode 15+)
- Supabase (required): add redirect URL `macstatus://auth-callback`, run `supabase/sql/update.sql`

## Docs / 文档

- English: `README.en.md`
- 中文：`README.zh-CN.md`

## License

MIT, see `LICENSE`.
