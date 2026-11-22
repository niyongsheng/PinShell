# PinShell

**简体中文** · [English](./README.md)

[![Release](https://img.shields.io/github/v/tag/niyongsheng/PinShell?style=flat&label=Release&color=FD3532)](https://github.com/niyongsheng/PinShell/releases)
[![Platform](https://img.shields.io/badge/macOS-13%2B-black?style=flat&logo=apple&logoColor=white)](#安装)

![logo](./Resources/logo.svg)

**为 AI 打造的实时桌面窗口。** PinShell 在用户屏幕上为 Agent（智能体）提供一个始终置顶的 HTML 界面，用于实时沟通、展示、提问和响应。界面由 HTML/CSS/JS 构建，PinShell 本身只是一层轻量的原生外壳（NSPanel + WKWebView）。

https://github.com/user-attachments/assets/61bfb0b1-b815-4895-a0f8-fcaf64ad3d0c

## 功能

- 始终置顶的 HTML 悬浮层，可跨所有「空间」（Spaces）显示；支持鼠标穿透、透明度、圆角和热重载。
- MCP 服务端与 CLI 共用同一个控制 socket；页面可以把事件推回给 Agent。
- 控制台（⌘K）：模板、实时预览、模板编辑器、MCP 信息与「关于」。
- 十套内置模板：轮播徽章、目标进度、LIVE 状态点、待办事项、系统状态、桌面宠物、番茄时钟、时间水印、社交胶囊栏、小决定。
- 仅驻留菜单栏，不显示 Dock 图标；支持从 GitHub Releases 检查更新，应用内下载安装包（SHA-256 校验）并交给系统安装器完成升级。

## 安装

从 [Releases](https://github.com/niyongsheng/PinShell/releases/latest) 下载 `PinShell-<version>-mac-universal.pkg`，或使用固定下载链接 `https://github.com/niyongsheng/PinShell/releases/latest/download/PinShell.pkg`。

`.pkg` 会安装到 `/Applications` 并清除隔离属性。构建产物使用 ad-hoc 签名，尚未公证；如果 macOS 阻止打开，请前往 **系统设置 → 隐私与安全性 → 仍要打开**，或执行：

```bash
xattr -dr com.apple.quarantine ~/Downloads/PinShell-*.pkg
```

## 构建

需要 macOS 13+ 以及 Xcode 命令行工具。

```bash
make build      # 构建 Release 可执行文件
make run        # 构建、组装并启动
make install    # 安装到 /Applications 并启动
make pkg        # 打包 build/PinShell.pkg（请先执行 make app）
make universal  # 构建 arm64 + x86_64 通用版本
```

## 使用

启动 PinShell 后，使用菜单栏图标：

| 菜单项 | 快捷键 | 操作 |
|---|---|---|
| 控制台 | ⌘K | 打开控制台 |
| 窗口位置 ▸ | ⌘0 | 将悬浮层放到屏幕角落（⌘0 为右下角） |
| 窗口状态：交互 / 穿透 | ⌘T | 切换鼠标穿透 |
| 显示窗口 | ⌘H | 开关悬浮层显隐（勾选为显示） |
| 检查更新… | ⌘U | 检查 GitHub Releases 更新，下载并安装新版本 |
| 退出 PinShell | ⌘Q | 退出 |

你可以直接在悬浮层内点击和输入；按住 **⌘** 拖动可移动窗口，拖动右下角手柄可调整大小（最小 80×40）。开启鼠标穿透后，鼠标事件会发送给下方的应用。

## MCP

打开 **控制台 → MCP** 复制配置，或手动添加：

```json
{
  "mcpServers": {
    "pinshell": {
      "command": "/Applications/PinShell.app/Contents/MacOS/PinShell",
      "args": ["mcp"]
    }
  }
}
```

工具覆盖窗口与内容（`pinshell_html`、`pinshell_show`）、页面交互（`pinshell_eval`、`pinshell_emit`、`pinshell_poll_events`、`pinshell_await_event`、`pinshell_state`）以及模板。MCP prompts 封装常见工作流；服务端与 CLI 共用 `~/Library/Application Support/PinShell/control.sock`。

### 桌面宠物

内置的 `desktop-pet.html` 是一个双向示例：它自己会换情绪、做小动作、被摸头、打瞌睡，agent 还能通过事件通道遥控它。

```bash
PinShell emit pet:hello '{"name":"Claude"}'
PinShell emit pet:mood '{"mood":"thinking"}'
PinShell emit pet:task '{"label":"跑测试","progress":0.4,"status":"running"}'
PinShell emit pet:say '{"text":"还差两个用例","mood":"working"}'
PinShell emit pet:celebrate '{"text":"全部通过 🎉"}'
```

agent → 页面：`pet:hello`、`pet:say`、`pet:mood`、`pet:task`、`pet:animate`、`pet:celebrate`、`pet:alert`、`pet:reply`、`pet:reset`。页面 → agent：`pet:ready`、`pet:tap`、`pet:pet`、`pet:ask`、`pet:sleep`、`pet:wake`。宠物的聊天框会发出 `pet:ask { requestId, text }`；在 ~10 秒内用 `pet:reply { requestId, text }` 回复，否则它会用本地台词兜底。MCP prompt `pet-companion` 会把整套流程串起来。

## CLI

如果应用尚未运行，命令会自动启动它并等待控制 socket 就绪。

```bash
PinShell show ./panel.html --watch
PinShell eval 'document.querySelector("#status").textContent = "done"'
PinShell emit agent:message '{"text":"next step"}'
PinShell listen --json
PinShell mcp
```

运行 `PinShell --help` 查看命令、选项和退出码。

## HTML 编写

仅支持本地 `file://` 文件。请使用 `html, body { background: transparent; overflow: hidden; }`；同目录下的相对路径 CSS/JS/图片均可正常工作。按住 **⌘** 可拖动窗口；允许音频自动播放。

窗口元数据（在加载前应用，并在显示/重载时重新应用）：

```html
<title>订阅进度</title>
<meta name="description" content="显示订阅目标与当前进度">
<meta name="pinshell:size" content="280x64">
<meta name="pinshell:position" content="bottom-right">
<meta name="pinshell:passthrough" content="false">
<meta name="pinshell:opacity" content="0.85">
<meta name="pinshell:radius" content="18">
<meta name="pinshell:order" content="10">
```

`position` 支持 `top-left`、`top`、`top-right`、`left`、`center`、`right`、`bottom-left`、`bottom`、`bottom-right`，或 `x,y`。CLI 参数会在当前会话中覆盖元数据。

可复用 `Resources/templates/design-tokens.css` 中的共享设计系统。

## 许可证

[Apache License 2.0](LICENSE)
