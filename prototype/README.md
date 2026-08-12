# Interaction Prototype

这是 English Companion 已批准的交互与视觉参考，不是生产代码。

## Run

```bash
cd prototype
python3 -m http.server 4173 --bind 127.0.0.1
```

打开 `http://127.0.0.1:4173/`。

## Covered flows

- 中文→英文＋中文回译
- 英文→中文＋建议回复
- 英文和中英混合优化
- ECDICT 词典卡
- Quick Panel → Workspace
- History、Glossary、Review 和 Settings
- Loading、Copy、`Esc` 与键盘操作

数字键 `1–5` 切换场景，`⌘↵` 运行，`⌘O` 打开 Workspace，`Esc` 隐藏或关闭当前窗口。

## Purpose

SwiftUI 实现应沿用本原型的：

- 深色 design tokens；
- 信息层级；
- 间距和结果结构；
- Quick Panel 与 Workspace 的状态关系。

状态模型测试：

```bash
node --test tests/app-model.test.mjs
```
