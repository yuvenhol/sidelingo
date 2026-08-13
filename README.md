# SideLingo

SideLingo 是一款轻量、键盘优先的 macOS 中英沟通与学习助手，服务香港职场沟通：快速翻译、表达优化、离线查词，以及从真实工作内容中沉淀可复习的学习数据。

## Current status

- 产品范围与 Quick Panel 视觉方向已确认。
- 当前实现采用 **AppKit shell + SwiftUI UI**，无 WebView。
- SwiftUI Quick Panel 已运行；Workspace、History 和 Review 待实现。
- 新 Bundle ID 为 `dev.kris.sidelingo`；macOS 不会继承旧应用的 Accessibility 授权，首次安装 SideLingo 后需要重新授权并刷新一次跨应用选区 E2E。
- 安全 pasteboard fallback 已完成单元测试：只接受变化后稳定的新文本，拒绝 unchanged/conflict；为避免 TOCTOU 覆盖风险，不自动恢复 general pasteboard。Preview PDF、Obsidian/Electron 和真实 fallback E2E 仍待验证。
- 当前已接通 DeepSeek BYOK 流式处理；Provider 测试使用假数据，不发出真实网络请求。
- 应用数据规范目录为 `Application Support/SideLingo`；启动时会在打开 SQLite 前安全迁移旧目录中的受管数据库文件。

## Project structure

- [`app/`](app/) — 当前 Swift macOS 应用。
- [`prototype/`](prototype/) — 已批准的交互与视觉参考，不是生产代码。
- [`docs/PRD-v0.1.md`](docs/PRD-v0.1.md) — 产品需求与验收标准。
- [`docs/architecture.md`](docs/architecture.md) — 当前技术架构和剩余门槛。
- [`docs/model-evaluation.md`](docs/model-evaluation.md) — DeepSeek、豆包和 OpenAI 的盲测方案。

## Product decisions

- 两个明确功能：**翻译**、**优化**。
- 两个可录制的全局快捷键；选区优先，剪贴板安全兜底。
- Raycast 风格 Quick Panel，可无损打开到 Workspace Window。
- 中文→英文：简短职场英文＋中文回译。
- 英文→中文：中文翻译＋建议英文回复。
- 优化支持英文、中文和中英混杂内容。
- 完整 ECDICT SQLite 随 App 发布并离线可用。
- DeepSeek、豆包和 OpenAI 使用统一 BYOK Provider 接口。
- 当前 Provider、模型和 API Key 作为单行配置保存在独立的本地 `provider.sqlite`；API Key 明文且未加密。
- 历史、术语和学习数据保存在本地 SQLite。
- 不使用有道 API，不自动覆盖用户剪贴板。

## Run

```bash
cd app
swift test
./build-app.sh
open -n "dist/SideLingo.app"
```

## Next

1. 冻结当前已验证 Swift/AppKit 基线。
2. 继续验证产品自有分帧协议在真实匿名化请求中的流式质量，不在测试或文档中使用真实凭据。
3. 验证 Preview PDF、Obsidian/Electron 和真实安全 pasteboard fallback。
4. 使用已批准的 SwiftUI design tokens 实现 Workspace、History 和 Review。

架构决策见 [`ADR-001`](docs/decisions/001-framed-streaming-and-plaintext-provider-sqlite.md)。
