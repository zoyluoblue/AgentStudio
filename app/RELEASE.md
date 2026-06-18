# AgentStudio — 发布指南（Developer ID + 公证）

分发方式：**Developer ID Application + Apple 公证（notarization）**，从你自己的网站/DMG 分发，不进 Mac App Store。
原因：AgentStudio 需要调用本机 `claude`/`codex` CLI 登录态、启动 `npm`/`python` 开发服务器——这些都被 App Store 的沙盒禁止。Developer ID 不需要沙盒，功能完整。

---

## 一、前置准备（一次性）

1. 加入 **Apple Developer Program**（$99/年）。
2. 在 Xcode ▸ Settings ▸ Accounts ▸ Manage Certificates 创建 **Developer ID Application** 证书。
3. 在 appleid.apple.com 生成 **App 专用密码**，然后存一次公证凭据：
   ```bash
   xcrun notarytool store-credentials AgentStudioNotary \
     --apple-id "you@example.com" --team-id "YOURTEAMID" --password "abcd-efgh-ijkl-mnop"
   ```

## 二、一键出包

```bash
cd app
SIGN_IDENTITY="Developer ID Application: Your Name (YOURTEAMID)" ./tools/notarize.sh
```
脚本会：生成工程 → 编 Release → 用 Developer ID 签名（hardened runtime + 时间戳）→ 提交公证并等待 → 装订票据 → 产出 `dist/AgentStudio-<版本>.dmg`。

验证（应输出 `accepted / source=Notarized Developer ID`）：
```bash
spctl --assess --type execute --verbose=4 dist/AgentStudio.app
```

## 三、发布前自检清单

- [x] **App 图标**：`AppIcon.appiconset` 已含 16→1024 全套（橙色品牌 sparkles）。
- [x] **硬化运行时**：Release 配置 `ENABLE_HARDENED_RUNTIME=YES`（公证必需）。
- [x] **隐私清单** `PrivacyInfo.xcprivacy`：无追踪、无数据收集（Key/对话直连服务商，不经过我们）。
- [x] **版本号**：`MARKETING_VERSION` = 1.0.0、`CURRENT_PROJECT_VERSION` = 1（每次发布都要 +1 build）。
- [x] 类别 `public.app-category.developer-tools`、版权 `© 2026 The AgentStudio Authors`、Bundle ID `com.example.agentstudio`（请改成你自己的）。
- [ ] **Team ID**：把 `project.yml` 里的 `DEVELOPMENT_TEAM` 填上你的 10 位 Team ID（或只用脚本签名）。
- [ ] 在一台**全新/未装过 CLI** 的 Mac 上验证：API Key 路径可用；并说明 CLI 模式需用户自行安装 `claude`/`codex`。
- [ ] **隐私政策页**：托管你自己的隐私政策页 URL（示例：`https://your-site.example/agentstudio/privacy`）。
- [ ] **支持页**：托管你自己的支持页 URL（系统要求 / 快速开始 / FAQ）。

## 四、商店 / 落地页文案（可直接用）

**名称**：AgentStudio
**一句话（zh）**：用大白话描述想法，两个 AI 帮你规划、动手、自检，做出真正能用的东西——不用懂代码。
**Tagline (en)**：Describe what you want in plain words — two AIs plan, build, and self-check it for you. No coding required.

**简介（zh）**：
> AgentStudio 是给「不写代码的人」的造物工作台。你只要说出想做什么，左侧 AI 负责规划、右侧 AI 负责动手改文件，自动审查、修订，直到做出来。一键运行实时预览、自动发现并修复运行时报错、每一步都能回滚、做好一键导出分享。支持复用本机 Claude Code / Codex 登录，或填自己的 API Key，并内置花费计量与预算。

**Description (en)**：
> AgentStudio is a build-anything workbench for non-coders. Say what you want; the left AI plans, the right AI edits files, and it reviews and revises until it's done. Run it live with one click, auto-detect and self-heal runtime errors, roll back any change, and export to share when ready. Reuse your local Claude Code / Codex login or bring your own API key — with built-in cost metering and budgets.

**关键词 / Keywords**：AI, no-code, coding assistant, Claude, Codex, app builder, website builder, agent, automation

**功能点 / Highlights**：
- 引导式开局 + 模板库（个人主页 / 待办 / 落地页 / 作品集 / 小游戏 / 看板）
- 单独 / 协作两种模式（协作 = 规划→执行→审查→修订）
- 一键运行 + 实时预览 + 运行时自愈
- 改动预览 + 一键回滚（纯本地内容快照，不依赖 git）
- 成本计量 + 月度预算
- 中英双语界面

## 五、自动更新（Sparkle，已集成）

应用已内置 [Sparkle](https://sparkle-project.org/) 2.x：后台每天自动检查更新（`SUEnableAutomaticChecks` / `SUScheduledCheckInterval`），用户也可在「设置 → 帮助 → 检查更新」或菜单栏手动检查。

**一次性设置：**
1. 拿到 Sparkle 工具(`generate_keys`、`sign_update`、`generate_appcast`)：从 [Sparkle Releases](https://github.com/sparkle-project/Sparkle/releases) 下载 `Sparkle-2.x.tar.xz` 解压,工具在 `bin/`(或解析后的 SPM 包里)。设 `export SPARKLE_BIN=/path/to/Sparkle/bin`。
2. 生成签名密钥(私钥进登录钥匙串,只生成一次)：
   ```bash
   "$SPARKLE_BIN/generate_keys"
   ```
   它会打印一行 **public key**。把它填进 `project.yml` → `info.properties.SUPublicEDKey`(替换 `REPLACE_WITH_SPARKLE_PUBLIC_KEY`),然后 `xcodegen generate`。
3. **托管地址**：把 DMG 与 `appcast.xml` 放到你自己的静态托管 / 对象存储目录（如 S3 / OSS / GitHub Releases），并让它与 `project.yml` 的 `SUFeedURL` 一致。

**每次发版：**
1. 改版本号：`project.yml` 的 `MARKETING_VERSION`(如 1.0.1)和 `CURRENT_PROJECT_VERSION`(每次 +1，Sparkle 用它比较新旧),`xcodegen generate`。
2. 出公证好的 DMG：`SIGN_IDENTITY="…" ./tools/notarize.sh` → 得到 `dist/AgentStudio-<版本>.dmg`。
3. 生成/更新 appcast(自动签名 + 写好版本/长度)：
   ```bash
   "$SPARKLE_BIN/generate_appcast" dist/
   ```
   产出 `dist/appcast.xml`。
4. 把 `dist/*.dmg` 和 `dist/appcast.xml` 上传到 `SUFeedURL` 所在目录。老用户下次启动即收到更新提示。

> 提示：`tools/notarize.sh` 已会从内到外正确签名 Sparkle 的内嵌组件(XPCServices / Updater.app / Autoupdate),无需手动处理。

## 六、后续（可选）

- **双通道**：若以后想进 Mac App Store，需要单独做沙盒版（砍掉 CLI 登录与 npm 运行器，改为 API Key + 静态预览 + security-scoped bookmarks）。
