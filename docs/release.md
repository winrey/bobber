# Bobber Release & Notarization Guide

## Quick Start

已配置好环境的机器，一条命令完成打包：

```bash
./Scripts/build-release.sh
```

输出：`.build/Bobber.dmg`，可直接分发。

---

## 新机器配置

### 1. 安装 Xcode Command Line Tools

```bash
xcode-select --install
```

### 2. 安装 Developer ID 证书

需要团队的 **Developer ID Application** 证书（用于 macOS app 的分发签名）。

#### 方式 A：通过 Xcode（推荐）

1. 打开 Xcode → Settings → Accounts
2. 点击 "+" 添加 Apple ID（Team: WENRUI MA, Team ID: `LVFB9KHUD7`）
3. 选择你的 Team → 点击 "Manage Certificates"
4. 点击 "+" → 选择 "Developer ID Application"
5. 证书会自动安装到 Keychain

#### 方式 B：手动导入 .p12 文件

如果有导出的 .p12 证书文件：

```bash
# 导入到 login keychain
security import DeveloperID.p12 -k ~/Library/Keychains/login.keychain-db -T /usr/bin/codesign
```

#### 验证证书已安装

```bash
security find-identity -v -p codesigning | grep "WENRUI MA"
```

应该看到类似输出：
```
BD60EBBF... "Developer ID Application: WENRUI MA (LVFB9KHUD7)"
```

### 3. 配置公证凭据

Apple 公证（Notarization）需要 App-Specific Password，**每台机器只需配置一次**。

#### Step 1: 生成 App-Specific Password

1. 打开 [appleid.apple.com](https://appleid.apple.com)
2. 登录 Apple ID：`i@iaside.com`
3. 进入 "登录和安全" → "App 专用密码"
4. 点击 "生成 App 专用密码"
5. 输入标签名（如 `bobber-notarize`）
6. 记下生成的密码（格式类似 `xxxx-xxxx-xxxx-xxxx`）

#### Step 2: 存储凭据到 Keychain

```bash
xcrun notarytool store-credentials "bobber-notarize" \
  --apple-id "i@iaside.com" \
  --team-id "LVFB9KHUD7" \
  --password "你的app-specific-password"
```

> 凭据安全地存储在 macOS Keychain 中，脚本通过 `--keychain-profile "bobber-notarize"` 引用，不需要明文密码。

#### 验证凭据

```bash
# 测试凭据是否有效（不实际提交）
xcrun notarytool history --keychain-profile "bobber-notarize"
```

---

## 打包流程

### 完整流程（含公证）

```bash
./Scripts/build-release.sh
```

流程：
1. `swift build -c release` — 编译 release 二进制
2. 组装 `.app` Bundle（二进制 + 图标 + Info.plist）
3. Developer ID 签名（含 Hardened Runtime）
4. 提交 Apple 公证 + staple 票据
5. 打包 `.dmg`

大约需要 2-3 分钟（公证等待时间取决于 Apple 服务器）。

### 跳过公证（本地测试用）

```bash
./Scripts/build-release.sh --skip-notarize
```

> 未公证的 DMG 用户首次打开需要右键 → 打开。

---

## 分发方式

### DMG（推荐）

直接发送 `.build/Bobber.dmg`，用户：
1. 双击打开 DMG
2. 拖拽 Bobber 到 Applications（或直接双击运行）
3. 首次运行打开 Settings → Plugin → Install Plugin

### 一键安装脚本

用户无需手动下载，终端运行：

```bash
curl -fsSL https://raw.githubusercontent.com/winrey/bobber/main/Scripts/install.sh | bash
```

> 注意：脚本安装走的是源码编译，需要 Xcode Command Line Tools，且不经过公证。

---

## 常见问题

### Q: "Bobber 已损坏，无法打开"

App 未签名或未公证。确保使用 `build-release.sh` 打包（不要手动 zip .app）。

### Q: 公证失败 401 Unauthorized

App-Specific Password 过期或未正确存储。重新生成并运行 `store-credentials`。

### Q: 找不到签名证书

确保 Developer ID 证书已安装到 Keychain。运行：
```bash
security find-identity -v -p codesigning
```

### Q: 公证被拒（status: Invalid）

查看详细日志：
```bash
xcrun notarytool log <submission-id> --keychain-profile "bobber-notarize"
```

常见原因：
- 未启用 Hardened Runtime（脚本已通过 `--options runtime` 处理）
- 包含未签名的动态库
- 使用了被禁止的 API

### Q: 想用其他 Apple 开发者账号

修改 `Scripts/build-release.sh` 中的：
- `SIGNING_IDENTITY` — 改为你的 Developer ID 证书名
- `KEYCHAIN_PROFILE` — 改为你存储的凭据名

然后重新运行 `store-credentials` 配置新账号的凭据。
