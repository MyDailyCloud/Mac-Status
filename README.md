# Mac Status - Mac系统状态监控工具

<div align="center">

![macOS](https://img.shields.io/badge/macOS-13.0+-blue.svg)
![Swift](https://img.shields.io/badge/Swift-5.0+-orange.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)

一个轻量级的macOS菜单栏应用，实时监控您的Mac系统状态

</div>

## ✨ 功能特性

- 🖥️ **CPU监控** - 实时显示CPU使用率
- 🧠 **内存监控** - 显示内存使用情况和可用内存
- 💾 **硬盘读写** - 实时监控硬盘读写速度（MB/s）
- 🌡️ **温度监控** - 显示CPU、GPU等关键部件温度
- 🌀 **风扇转速** - 实时显示风扇转速（RPM）
- 🎨 **美观界面** - 采用SwiftUI构建的现代化界面
- ⚡ **轻量级** - 占用资源极少，常驻后台运行

## 📸 截图

应用会以菜单栏图标的形式运行，点击图标即可查看详细的系统状态信息。

## 🚀 快速开始

### 系统要求

- macOS 13.0 或更高版本
- Xcode 15.0 或更高版本

### 安装步骤

1. **克隆仓库**
```bash
git clone https://github.com/yourusername/Mac-Status.git
cd Mac-Status
```

2. **打开项目**
```bash
open MacStatus.xcodeproj
```

3. **编译运行**
   - 在Xcode中选择目标设备（My Mac）
   - 点击运行按钮（⌘R）或选择 Product > Run

### 配置 Supabase + GitHub 登录（必须）

登录成功后才会解锁监控，并把数据写入 Supabase 表 `mac_status_metrics`。

1. **Supabase 配置已写入 Info.plist**（SUPABASE_URL/ANON_KEY），可直接运行。如需替换，请在 `MacStatus/Info.plist` 中修改。

2. **Supabase 控制台设置**
   - 在 Authentication > URL Configuration 中，`Redirect URLs` 添加 `macstatus://auth-callback`
   - 确保已启用 GitHub Provider，并填好 GitHub OAuth App 的 Client ID/Secret

3. **数据库表**
   - 在 Supabase SQL 编辑器执行（或参考 `supabase/sql/`）：

     ```sql
     create extension if not exists "uuid-ossp";

     create table if not exists public.mac_status_metrics (
       id uuid primary key default uuid_generate_v4(),
       created_at timestamptz not null default now(),
       user_id text,
       cpu_usage double precision,
       memory_usage double precision,
       used_memory_gb double precision,
       total_memory_gb double precision,
       disk_read_mb_s double precision,
       disk_write_mb_s double precision
     );

     alter table public.mac_status_metrics enable row level security;

     create policy "insert_own_metrics"
     on public.mac_status_metrics
     for insert
     to authenticated
     with check (auth.uid()::text = coalesce(user_id, auth.uid()::text));

     create policy "select_own_metrics"
     on public.mac_status_metrics
     for select
     to authenticated
     using (auth.uid()::text = user_id);
     ```

   - 设备列表（每台设备单独注册一次）：

     ```sql
     create extension if not exists "uuid-ossp";

     create table if not exists public.mac_status_devices (
       id uuid primary key default uuid_generate_v4(),
       created_at timestamptz not null default now(),
       user_id text not null,
       device_uuid uuid not null,
       device_name text,
       model text,
       os_version text,
       app_version text,
       last_seen_at timestamptz not null default now()
     );

     create unique index if not exists mac_status_devices_user_device_unique
       on public.mac_status_devices (user_id, device_uuid);

     alter table public.mac_status_devices enable row level security;

     create policy "insert_own_devices"
     on public.mac_status_devices
     for insert
     to authenticated
     with check (auth.uid()::text = user_id);

     create policy "select_own_devices"
     on public.mac_status_devices
     for select
     to authenticated
     using (auth.uid()::text = user_id);

     create policy "update_own_devices"
     on public.mac_status_devices
     for update
     to authenticated
     using (auth.uid()::text = user_id)
     with check (auth.uid()::text = user_id);
     ```

### 从源码构建

```bash
# 使用Xcode命令行工具构建
xcodebuild -project MacStatus.xcodeproj -scheme MacStatus -configuration Release

# 构建的应用位于
# ./build/Release/MacStatus.app
```

## 📖 使用说明

1. **启动应用**
   - 首次启动后，应用图标会出现在菜单栏右上角
   - 图标显示为一个图表符号

2. **查看系统状态**
   - 点击菜单栏图标，弹出状态面板
   - 使用 GitHub 登录（通过 Supabase OAuth）；成功后解锁监控并开始刷新/上报数据
   - 每 5 秒上传一次监控快照到 Supabase 表 `mac_status_metrics`，登录状态自动持久化，access token 过期时自动用 refresh token 刷新

3. **退出应用**
   - 点击状态面板底部的“退出”按钮
   - 如需切换账号，点击“退出登录”重新登录

## 🏗️ 项目结构

```
Mac-Status/
├── MacStatusApp.swift        # 应用入口和菜单栏配置
├── RootView.swift            # 登录/内容切换与监控启动控制
├── LoginView.swift           # Supabase 登录界面
├── ContentView.swift         # 主界面UI
├── SystemMonitor.swift       # 系统监控核心逻辑
├── AuthManager.swift         # Supabase 登录状态管理
├── MetricsUploader.swift     # 周期上传监控数据到 Supabase
├── SupabaseMetricsService.swift # Supabase REST 上传实现
├── Info.plist                # 应用配置文件
├── MacStatus.entitlements    # 权限配置
└── MacStatus.xcodeproj/      # Xcode项目文件
```

## 🔧 技术实现

### CPU监控
使用`host_processor_info`系统API获取CPU负载信息：
- 读取每个CPU核心的使用情况
- 计算总体CPU使用率百分比

### 内存监控
通过`vm_statistics64`获取虚拟内存统计：
- Active内存 + Wired内存 = 已使用内存
- 计算内存使用百分比和实际使用量

### 硬盘监控
使用IOKit框架的`IOBlockStorageDriver`：
- 获取磁盘I/O字节数
- 计算每秒读写速度

### 温度和风扇（高级功能）
- 当前版本使用模拟数据进行展示
- 实际读取需要访问SMC（System Management Controller）
- 可集成第三方库如`SMCKit`实现真实数据读取

## 🔒 权限说明

应用需要以下权限：
- **禁用沙盒** - 访问系统硬件信息需要完整系统访问权限
- **Apple Events** - 用于系统信息收集

## 🛠️ 进阶定制

### 添加SMC支持（真实温度和风扇数据）

如需读取真实的温度和风扇数据，可以集成SMC库：

1. 添加SMCKit依赖
2. 在`SystemMonitor.swift`中实现SMC读取
3. 替换模拟数据为真实数据

### 自定义刷新频率

在`SystemMonitor.swift`中修改定时器间隔：

```swift
// 当前为1秒刷新一次
timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { ... }
```

### 自定义UI样式

在`ContentView.swift`中可以修改：
- 颜色主题
- 卡片布局
- 字体大小
- 图标样式

## 📝 待办事项

- [ ] 添加真实的SMC温度读取
- [ ] 添加真实的风扇转速读取
- [ ] 支持网络流量监控
- [ ] 添加历史数据图表
- [ ] 支持自定义刷新间隔
- [ ] 添加通知功能（温度过高提醒等）
- [ ] 支持多语言
- [ ] 添加启动时自动运行选项
- [ ] 持久化 Supabase Session，减少重复登录

## 🤝 贡献

欢迎提交Issue和Pull Request！

1. Fork本仓库
2. 创建您的特性分支 (`git checkout -b feature/AmazingFeature`)
3. 提交您的改动 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 开启Pull Request

## 📄 开源协议

本项目采用MIT协议 - 详见 [LICENSE](LICENSE) 文件

## 🙏 致谢

- 感谢Swift和SwiftUI社区
- 感谢所有贡献者

## 📮 联系方式

如有问题或建议，请通过以下方式联系：

- 提交Issue
- 发送邮件至：your.email@example.com

---

<div align="center">
Made with ❤️ for macOS
</div>
