# PinShell

**简体中文** · [English](./README.md)

[![Release](https://img.shields.io/github/v/tag/niyongsheng/PinShell?style=flat&label=Release&color=FD3532)](https://github.com/niyongsheng/PinShell/releases)
[![Platform](https://img.shields.io/badge/macOS-13%2B-black?style=flat&logo=apple&logoColor=white)](#安装)

![logo](./Resources/logo.svg)

**为 AI 打造的实时桌面窗口。** PinShell 在用户屏幕上为 Agent（智能体）提供一个始终置顶的 HTML 界面，用于实时沟通、展示、提问和响应。界面由 HTML/CSS/JS 构建，PinShell 本身只是一层轻量的原生外壳（NSPanel + WKWebView）。

![PinShell 界面预览](https://github.com/user-attachments/assets/61bfb0b1-b815-4895-a0f8-fcaf64ad3d0c)

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

### 控制台

按 ⌘K 打开控制台，采用原生侧边栏 + 详情页布局，在 macOS 26+ 上呈现 Liquid Glass 效果。

- **模板**（⌘1）：搜索、预览并应用模板。模板文件位于 `~/Library/Application Support/PinShell/templates/`；编辑后侧边栏会自动刷新。
- **MCP**（⌘2）/ **关于**（⌘3）：stdio 配置、可用工具、控制通道路径、版本信息和相关链接。
- **模板编辑器**（⌘E）：编辑标题、副标题、尺寸、位置、鼠标穿透、透明度、圆角和排序；修改会写回模板的 i18n block（旧模板仍写回 `<meta>` 标签）。标题和副标题按模板当前语言编辑，其他翻译会保留。
- **工具栏**：显示/隐藏悬浮层、重新加载、编辑、在 Finder 中显示，以及恢复已删除的内置模板。

窗口元数据来自 HTML：`<title>`、`<meta name="description">`、`<meta name="pinshell:*">`，以及可选的 JSON i18n block。首次启动时会生成十套内置模板，但不会覆盖已有副本；模板可以删除，删除的内置模板可从工具栏恢复。要获取更新后的内置模板，删除对应文件并重新启动，应用会从 bundle 重新释放该模板。

### 模板多语言

内置模板在 `<head>` 里声明一个 JSON block：

```html
<script type="application/json" id="pinshell:i18n">
{
  "default": "zh-Hans",
  "fallback": "en",
  "languages": {
    "zh-Hans": { "meta": { "name": "待办事项", "description": "…" } },
    "en": {
      "meta": { "name": "Todo List", "description": "…" },
      "ui": { "title": "Todo List", "clearDone": "Clear completed" }
    }
  }
}
</script>
```

- `meta` 用于控制台模板库；`ui` 由 `pinshell-i18n.js` 渲染到页面。
- 默认语言的正文仍以内联文案为准；非默认语言的 `ui` 会叠加在 `fallback`（英文）之上，缺 key 时先回落英文，再回落行内默认值。
- 语言顺序：应用选中的模板语言 → 系统语言偏好 → fallback。应用会注入 `window.pinshell.languages` / `templateLanguage`；浏览器里给文件 URL 加 `?lang=en` 可预览。
- 静态文案：`data-i18n="key"`，属性用 `data-i18n-placeholder|title|aria-label|data-text`。动态文案：`PS.t('key', '默认值', { name: value })`；数组：`PS.list('key', [ … ])`；原始数据：`PS.get('key', fallback)`。
- 日期/数字格式统一使用 `PS.locale`，不要写死 `en-US` / `zh-CN`。
- 旧的 `window.PINSHELL_STRINGS` 和 `<meta name="pinshell:title" lang="en">` 写法仍然兼容，但新模板建议使用 JSON block。

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

工具覆盖窗口与内容（`pinshell_html`、`pinshell_show`、`pinshell_set`、`pinshell_status`、`pinshell_close`）、页面交互（`pinshell_eval`、`pinshell_emit`、`pinshell_poll_events`）以及模板（`pinshell_templates`、`pinshell_template_read`、`pinshell_template_write`、`pinshell_template_delete`、`pinshell_template_show`）。模板写入仅限模板文件夹内的 `.html`/`.htm` 文件（不含子目录），大小上限为 512 KB；写入后控制台会刷新，正在展示的模板会原位重新加载。

MCP prompts（`create-panel`、`interactive-panel`、`live-monitor`、`pet-companion`、`edit-template`、`authoring-guide`）将常见工作流封装为一步操作；在 Claude Code 中会以 `/pinshell:create-panel` 等命令的形式提供。服务端与 CLI 共用 `~/Library/Application Support/PinShell/control.sock`。

典型工作流：`pinshell_html` → `pinshell_poll_events` → `pinshell_eval` / `pinshell_emit` / `pinshell_template_write`。

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
PinShell show ./panel.html --watch --json
PinShell set --size 240x80 --position bottom-right
PinShell eval 'document.querySelector("#status").textContent = "done"'
PinShell emit agent:message '{"text":"next step"}'
PinShell listen --json
PinShell mcp
PinShell close | quit
```

选项：`--size WxH`、`--position <anchor|x,y>`、`--passthrough on|off`、`--opacity 0..1`、`--radius px`、`--watch`、`--wait`、`--json`。退出码：`0` 成功，`1` 用法错误，`2` 应用不可用，`3` 命令执行失败。

## HTML 编写

仅支持本地 `file://` 文件。请使用 `html, body { background: transparent; overflow: hidden; }`；同目录下的相对路径 CSS/JS/图片均可正常工作。按住 **⌘** 可拖动窗口；允许音频自动播放。

窗口元数据（在加载前应用，并在显示/重载时重新应用）：

```html
<title>订阅进度</title>
<meta name="description" content="显示订阅目标与当前进度">
<!-- 需要多语言时，在这里加入 <script id="pinshell:i18n"> block，见“模板多语言” -->
<meta name="pinshell:size" content="280x64">
<meta name="pinshell:position" content="bottom-right">
<meta name="pinshell:passthrough" content="false">
<meta name="pinshell:opacity" content="0.85">
<meta name="pinshell:radius" content="18">
<meta name="pinshell:order" content="10">
```

`position` 支持 `top-left`、`top`、`top-right`、`left`、`center`、`right`、`bottom-left`、`bottom`、`bottom-right`，或 `x,y`。CLI 参数会在当前会话中覆盖元数据。

JavaScript 桥接 API：

```js
pinshell.setSize(320, 120)
pinshell.setPosition('bottom-right')     // 或 setPosition(x, y)
pinshell.setPassthrough(true)
pinshell.setOpacity(0.8)
pinshell.setRadius(18)
pinshell.emit('submit', { value: 1 })    // → CLI `listen` / MCP 事件
pinshell.on('agent:message', fn)         // ← CLI `emit` / MCP `pinshell_emit`
pinshell.log('debug message')

// 原生 fetch 代理：仅支持 https，15 秒超时，最大 2 MB，允许自定义请求头
const data = await pinshell.fetch('https://api.example.com/stats', {
  headers: { Referer: 'https://example.com/' }
})
```

可复用 `Resources/templates/design-tokens.css` 中的共享设计系统。

## 许可证

[Apache License 2.0](LICENSE)
