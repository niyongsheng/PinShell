# PinShell 模板贡献规范

**简体中文** · [English](./template-contribution.md)

PinShell 的在线模板库由 [`website/templates`](../website/templates) 生成。本文档是贡献模板的
约定：目录结构、`template.json`、HTML 与多语言规则、设计令牌、Agent 事件协议、本地校验和
评审清单。合并到 `main` 后，模板会自动发布到官网和 App 的在线模板库。

> 学习格式最快的方式是复制一个小模板：
> [`goal-progress`](../website/templates/goal-progress)（紧凑、实时数据）或
> [`desktop-pet`](../website/templates/desktop-pet)（双向事件）。

## 1. 模板是什么

模板是一个自包含的 HTML 文档，运行在 PinShell 始终置顶的透明面板中。用户从在线模板库安装后，
文件位于：

```text
~/Library/Application Support/PinShell/templates/
```

下载到本地的只有 `<id>.html`。App 启动时会在同目录播种两个共享 sidecar：

- `design-tokens.css` —— 共享设计系统与透明画布 reset
- `pinshell-i18n.js` —— 语言选择辅助脚本

因此：

- 所有 CSS 和 JavaScript 必须内联在 HTML 中；图片必须是 `data:` URI 或 `https:` URL。
- 模板目录中的其他文件会被构建拒绝，也不会随模板分发。
- HTML 必须是 UTF-8，且不超过 **512 KB（524,288 字节）**。
- 模板必须离线可用。远程数据是可选增强；请求失败时应显示明确的空状态或错误状态，而不是空白
  或布局损坏的面板。

## 2. 仓库结构

```text
website/templates/
└── <id>/
    ├── template.json   # 清单：版本、分类、作者、橱窗文案、更新日志
    └── <id>.html       # 模板本体
```

- 目录名、清单里的 `id`、HTML 文件名必须完全一致。
- 目录中必须**只有这两个可见文件**。构建会拒绝多余文件，包括 README、截图或本地图片。
- `<id>` 必须匹配 `^[a-z0-9]+(-[a-z0-9]+)*$`，且不超过 64 个字符。请选择稳定、描述性的 id
  （如 `pomodoro`、`system-monitor`）。**id 一经发布不可更改。**
- 不要在模板 PR 中修改 `Resources/templates/design-tokens.css` 或
  `Resources/templates/pinshell-i18n.js`。它们由所有模板共享，请单独提案修改。

## 3. 清单：`template.json`

```json
{
  "schemaVersion": 1,
  "id": "example-panel",
  "version": "1.0.0",
  "releaseDate": "2026-11-23",
  "minAppVersion": "1.4.0",
  "category": "productivity",
  "tags": ["example", "starter"],
  "author": {
    "name": "Your Name",
    "url": "https://github.com/your-handle"
  },
  "listing": {
    "zh-Hans": {
      "tagline": "一个最小可用的 PinShell 模板。",
      "highlights": ["单文件 HTML", "中英双语", "Agent 事件示例"]
    },
    "en": {
      "tagline": "A minimal PinShell template.",
      "highlights": ["Single-file HTML", "Chinese and English", "Agent event example"]
    }
  },
  "changelog": {
    "1.0.0": {
      "date": "2026-11-23",
      "notes": {
        "zh-Hans": "首个版本。",
        "en": "First release."
      }
    }
  }
}
```

| 字段 | 必填 | 规则 |
| --- | --- | --- |
| `schemaVersion` | 是 | 固定为 `1`。 |
| `id` | 是 | 与目录名一致。小写 slug，≤ 64 字符，发布后不可更改。 |
| `version` | 是 | 严格 `X.Y.Z` 格式。每次发布改动都必须递增。 |
| `releaseDate` | 建议 | `YYYY-MM-DD`。 |
| `minAppVersion` | 是 | 严格 `X.Y.Z` 格式。不得高于 `Resources/Info.plist` 中的 `CFBundleShortVersionString`（当前为 **1.5.0**）。请使用实际需要的最低版本；本文档涉及的 API 在 `1.4.0` 即可用。 |
| `category` | 是 | 必须是 [`website/site.json`](../website/site.json) 中定义的 id：`productivity`、`focus`、`monitoring`、`companion`、`media`、`play`、`social`。 |
| `tags` | 否 | 1–8 个不重复标签。每个标签只能包含小写字母、数字和连字符，长度 1–24。 |
| `author.name` | 是 | 1–64 个字符，单行，不能有首尾空白。 |
| `author.url` | 否 | 可选的个人主页或资料页，必须是 HTTPS。 |
| `listing` | 建议 | 按语言标签组织的橱窗文案。每项至少要有非空的 `tagline` 或 `highlights`；请同时提供 `zh-Hans` 与 `en`。 |
| `changelog` | 是 | 必须包含以当前 `version` 为 key 的条目。每个 key 都是 `X.Y.Z`；每个条目应包含 `date` 和本地化 `notes`；当前版本的 notes 必须同时包含非空的 `zh-Hans` 与 `en`。 |

说明：

- **不要在清单里填写名称、简介、尺寸或排序。** 这些信息从 HTML 中提取：i18n `meta` 块和
  `pinshell:*` meta 标签。
- `author` 是必填项，用于在 App 和详情页中署名。
- `listing.tagline` 保持一句话，`highlights` 保持 2–4 条短语。
- 每次发布改动都需要新的 `version` 和对应的 `changelog` 条目。载荷按版本发布且不可变：
  已经发布的版本不要再修改 HTML，请发布新版本。

## 4. HTML 约定

### 4.1 文档 head

```html
<!doctype html>
<html lang="zh-Hans">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<script type="application/json" id="pinshell:i18n">
{
  "default": "zh-Hans",
  "fallback": "en",
  "languages": {
    "zh-Hans": {
      "meta": { "name": "示例面板", "description": "一个最小可用的 PinShell 模板" }
    },
    "en": {
      "meta": { "name": "Example Panel", "description": "A minimal PinShell template" },
      "ui": { "title": "Example", "hint": "Click the button to notify the agent" }
    }
  }
}
</script>
<title>示例面板</title>
<meta name="description" content="一个最小可用的 PinShell 模板">
<meta name="pinshell:size" content="280x96">
<meta name="pinshell:position" content="bottom-right">
<meta name="pinshell:radius" content="18">
<link rel="stylesheet" href="design-tokens.css">
<style>/* 模板样式 */</style>
</head>
<body>
<!-- 模板内容 -->
<script src="pinshell-i18n.js"></script>
<script>/* 模板逻辑 */</script>
</body>
</html>
```

构建会强制检查以下内容：

| 要求 | 规则 |
| --- | --- |
| 编码 | UTF-8，≤ 512 KB。 |
| `<html lang>` | 必须存在，且等于 i18n 的 `default` 语言。 |
| i18n 块 | 文档中恰好有一个 `<script type="application/json" id="pinshell:i18n">`。 |
| `default` | 必须是 `zh-Hans`。 |
| `fallback` | 必须是 `en`。 |
| `languages` | 必须声明 `zh-Hans` 和 `en`；每个声明的语言都要有非空的 `meta.name` 与 `meta.description`。 |
| `<title>` | 非空。 |
| `pinshell:size` | 必填，格式 `宽x高`，至少 `80x40`。它是初始尺寸，也是预览尺寸。 |
| `pinshell:order` | 可选的非负整数。在整个模板库中必须唯一；数值越小越靠前。 |

i18n `meta` 是模板库名称和简介的**唯一数据源**。请同时用默认语言填写 `<title>` 和
`<meta name="description">`，作为直接打开文件、以及 Agent 读取 HTML 时的兜底信息。

### 4.2 窗口元数据

PinShell 会在页面加载前应用这些元数据，并在显示或重载时重新应用。CLI 参数可以在当前会话中
覆盖它们。

| Meta 标签 | 取值 | 说明 |
| --- | --- | --- |
| `pinshell:size` | `280x96` | 必填。初始尺寸和预览尺寸；最小 `80x40`。 |
| `pinshell:position` | `top-left`、`top`、`top-right`、`left`、`center`、`right`、`bottom-left`、`bottom`、`bottom-right`，或 `x,y` | 可选的初始位置。紧凑徽章通常放在屏幕角落最合适。 |
| `pinshell:passthrough` | `true` / `false` | 可选。只有纯装饰、不可交互的模板才应在启动时开启鼠标穿透。 |
| `pinshell:opacity` | `0`–`1` | 可选窗口透明度。以文字为主的面板请保持接近 `1`。 |
| `pinshell:radius` | 像素 | 可选窗口圆角。应与页面内部表面的圆角一致。 |
| `pinshell:order` | 整数 ≥ 0 | 可选模板库排序键；在整个模板库中唯一。 |

### 4.3 多语言

即使模板没有可翻译的界面文案，也必须保留 i18n 块。默认语言的文案直接内联在 HTML 中；
非默认语言在 `ui` 字典中提供。

静态文案：

```html
<span data-i18n="title">示例</span>
<input data-i18n-placeholder="inputPlaceholder" placeholder="输入…">
<button data-i18n-title="actionTitle" title="操作">…</button>
```

动态文案：

```js
PS.t('remaining', '还剩 {n} 项', { n: 3 });
PS.list('lines', ['默认文案']);   // 数组和结构化数据
PS.get('seed', []);              // 原始值
PS.locale;                       // 解析后的 BCP-47 语言标签
```

规则：

- 每个非默认语言都必须为 `data-i18n`、任意 `data-i18n-*` 属性、`PS.t`、`PS.list` 和
  `PS.get` 引用的**每一个 key** 提供 `ui` 条目。缺少 key 时构建会失败——这是刻意设计，
  避免用户看到中英混杂的界面。
- 欢迎提供额外语言。只要在 `languages` 中声明了完整的 `meta` 和 `ui` 即可。
- 默认语言的文案写在 HTML 里；`zh-Hans` 条目通常只需要 `meta`。
- 在浏览器里给载荷 URL 追加 `?lang=en`（或 `?lang=zh-Hans`）即可预览对应语言。
- JSON 字符串中的 `</script` 必须转义为 `<\/script`，否则 HTML 块会提前结束。
- 在 App 中，辅助脚本按 `window.pinshell.templateLanguage` → `window.pinshell.languages`
  → 系统偏好 的顺序选择语言。`PS.lang` 保留旧版短形式（`zh-Hans` / `en`）。
- 如果模板用 `<canvas>` 绘制文字，请在绘制时读取 `PS.locale`；辅助脚本只处理 DOM 文本和
  属性。

### 4.4 资源与网络

允许引用的本地文件只有两个预置 sidecar：

```html
<link rel="stylesheet" href="design-tokens.css">
<script src="pinshell-i18n.js"></script>
```

其他资源都必须内联：

- CSS 与 JavaScript 写在文档内。
- 图片、图标和字体使用 `data:` URI 或 `https:` URL。相对路径图片不会随模板分发。
- 优先使用系统字体和 CSS 绘制，避免巨大的 base64 资源。
- 构建器技术上允许远程 `https:` 脚本，但强烈不建议：它增加评审面、破坏离线使用，而且面板
  通常不需要。
- 严禁嵌入 API key、token、个人数据、统计代码或追踪代码。
- 跨域数据请优先使用 `window.pinshell.fetch(url, { headers })`：仅 HTTPS GET，15 秒超时，
  最大 2 MB，最多 20 个请求头。`file://` 页面中的标准 `fetch` 可能被 CORS 拦截。
- 使用第三方 API 或品牌时请遵守其条款，并在需要处给出署名。

### 4.5 窗口行为与无障碍

- 窗口画布是透明的。请自己绘制表面：铺满窗口的面板通常使用
  `position: absolute; inset: 0`、背景色和 `border-radius: var(--ps-radius-lg)`。
- 窗口允许用户调整大小（最小 80×40）。不要假设声明尺寸永远不变；布局应能承受适度缩放而不
  裁掉控件。
- 按住 **⌘** 拖动可移动窗口。避免让整个窗口的拖拽处理器吞掉点击。
- 在界面装饰上设置 `user-select: none`，在输入框和可复制文字上恢复 `user-select: text`。
- 允许音频自动播放。不要在加载时突然播放响亮声音；优先使用交互触发的音效，并为持续音效提供
  静音开关。
- 尊重 `prefers-reduced-motion: reduce`：禁用或缩短动画和彩带效果。
- 键盘：所有操作都必须能不用鼠标完成；使用 `--ps-primary-focus` 显示清晰的焦点环；纯图标
  按钮要加 `aria-label`。
- 不要只用颜色表达状态。正文文字对比度应达到 4.5:1。

## 5. 视觉设计

引入 `design-tokens.css`，并基于 `--ps-*` 令牌构建，不要复制颜色、圆角或间距数值。共享文件
还提供了透明画布 reset 和穿透模式行为。

- **只有一个强调色。** `--ps-primary`（Action Blue）是唯一的“可点击”信号。不要再引入第二个
  强调色。语义性的红绿可以用于数据涨跌，但不要用于界面装饰。
- **表面与文字。** 深色卡片使用 `--ps-surface-tile-1` / `-2` / `-3`；正文使用
  `--ps-body-on-dark`，次级文字使用 `--ps-body-muted`。描边通常是
  `rgba(255, 255, 255, 0.08)`。
- **圆角语法。** `xs`/`sm` 用于紧凑工具，`lg` 用于卡片，`pill` 用于胶囊操作。同一个面板
  内不要混用随意数值的圆角。
- **字体。** 使用 `--ps-font-text`；悬浮层正文通常为 12–17 px。只有展示级标题才使用负字距。
- **间距。** 遵循 4/8 px 节奏（`--ps-space-*`）。面板内边距通常为 12–18 px。
- **投影。** `--ps-shadow-float`（通过 `.ps-float`）只在有内缩的悬浮元素上可见。铺满窗口的
  表面会把自身投影裁掉；想要层次感请使用内缩卡片。
- **穿透。** 在窗口穿透时需要淡化的表面加上 `.ps-dim-surface`；文字保持实色。
- **品味。** 追求有触感、克制的材质：发丝描边、克制的渐变、真实的字体排版。避免千篇一律的
  “AI 应用”观感——霓虹紫光晕、满屏毛玻璃、emoji 堆砌，以及永不停止的装饰动画。
- **性能。** 这个面板可能长时间停留在屏幕上。避免持续 60 fps 的 canvas 工作、巨大的 DOM
  树和不受节流的定时器；在 `document.hidden` 时暂停动画和轮询。

## 6. Agent 事件协议

模板可以由 Agent 驱动。这是可选项，但好的模板应当能独立工作，并在 Agent 在场时变得更好。
在 App 中，`window.pinshell` 会在 document start 注入；**官网预览中没有这个对象**，因此必须
做保护：

```js
const bridge = window.pinshell || { emit() {}, on() {}, log() {} };
```

| API | 方向 | 用途 |
| --- | --- | --- |
| `bridge.emit(name, data)` | 页面 → Agent | 发送可 JSON 序列化的事件。请加命名空间，如 `todo:changed`。 |
| `bridge.on(name, callback)` | Agent → 页面 | 处理通过 `pinshell_emit` 或 `PinShell emit` 推入的事件。 |
| `bridge.ready()` / `input()` / `submit()` / `cancel()` | 页面 → Agent | `ui:ready` / `ui:input` / `ui:submit` / `ui:cancel` 的简写。 |
| `bridge.setSize(w, h)` | 页面 → App | 调整窗口尺寸。不要和用户的手动调整打架。 |
| `bridge.setPosition(anchor \| x, y)` | 页面 → App | 移动窗口。 |
| `bridge.setPassthrough(enabled)` | 页面 → App | 切换鼠标穿透。 |
| `bridge.setOpacity(value)` / `setRadius(px)` | 页面 → App | 调整窗口外观。 |
| `bridge.getState()` / `setState(state)` / `patchState(patch)` | 页面 ↔ App | 共享面板状态。`patchState` 使用 RFC 7386 merge-patch。 |
| `bridge.log(...args)` | 页面 → Agent | 转发一行诊断日志。 |
| `bridge.fetch(url, { headers })` | 页面 → 网络 | 通过原生壳发起的 HTTPS GET。 |

此外还可以读取：`bridge.version`、`bridge.session`、`bridge.language`、`bridge.languages`、
`bridge.templateLanguage`。

约定：

- 每个事件都使用命名空间：`<id>:ready`、`<id>:changed`、`<id>:set`。事件的 `type` 是第一个
  冒号之前的前缀；没有命名空间的事件名会被归类为 `ui`。
- 页面加载时发出 ready 事件（如 `my-template:ready`，带上版本和能力），让 Agent 无需抓取 DOM
  就能接入。
- 在 HTML 顶部的 `AGENT PROTOCOL` 注释中记录双向事件。Agent 会通过
  `pinshell_template_read` 读取原始 HTML 并依赖这段注释。
- 把 Agent 发来的数据视为不可信：校验类型和范围，绝不直接传给 `eval`、`innerHTML` 或未经
  检查的 URL。
- UI 偏好保存在带命名空间的 `localStorage` key 中，如 `pinshell.<id>.<key>`。不要保存密钥。
- 限制：桥接消息 ≤ 64 KB，事件名 ≤ 256 字符，日志 ≤ 4,096 字符。Agent 收到的事件结构为
  `{ seq, ts, session, type, name, data }`。

示例：

```html
<!--
  AGENT PROTOCOL · example-panel

  Agent -> page (pinshell_emit / PinShell emit):
    example:set   { title }   更新标题文字
  Page -> agent (pinshell_poll_events):
    example:ready { version }
    example:ping  { at }
-->
```

## 7. 本地预览与校验

构建并预览完整站点（预览需要预置的 sidecar）：

```bash
make serve-site
# → http://127.0.0.1:8000
```

- 模板库：`http://127.0.0.1:8000/templates/`
- 带实时预览的详情页：`http://127.0.0.1:8000/templates/<id>/`
- 直接打开载荷并强制语言：
  `http://127.0.0.1:8000/templates/<id>/<version>/<id>.html?lang=en`

按 CI 的方式运行模板目录校验：

```bash
swift run --package-path website TemplateCatalogBuilder --check \
  --site-url https://pinshell.looplooptech.com
```

它会在临时目录中构建，并校验清单、HTML 要求、多语言覆盖、资源引用、载荷大小与哈希、站内链接
和生成的页面。遇到第一个问题就会以非零状态退出。同时运行核心测试：

```bash
swift test
```

在真实 App 中做端到端检查（App 启动时会播种 sidecar）：

```bash
cp "website/public/templates/<id>/<version>/<id>.html" \
  "$HOME/Library/Application Support/PinShell/templates/"
```

然后打开 **控制台（⌘K）→ 模板**，或执行 `PinShell show <html 路径>`。注意：直接从源码目录
打开 `website/templates/<id>/<id>.html` 是找不到 sidecar 的；请使用构建后的预览，或临时把
sidecar 复制到旁边（不要提交）。

提交 PR 前请确认：

- [ ] 模板目录中恰好只有 `template.json` 和 `<id>.html`。
- [ ] 模板目录校验和 `swift test` 都通过。
- [ ] 在声明尺寸下和调整大小后，面板都显示正常。
- [ ] `zh-Hans` 和 `en` 都能完整显示，没有中英混杂。
- [ ] 官网预览和 App 中都没有控制台报错。
- [ ] 没有 `window.pinshell` 时（官网预览）布局仍然正常。
- [ ] 离线或网络失败时显示明确状态，而不是空白面板。
- [ ] 尊重“减少动态效果”；音频只在交互后播放。
- [ ] 键盘焦点可见，图标按钮有文字标签。
- [ ] 没有追踪、远程代码、凭据或额外资源。
- [ ] 没有提交生成的 `website/public/`。

## 8. 版本与兼容性

- **id 永久有效。** 某个 id 发布后，不要重命名，也不要复用它指代另一个模板。
- **载荷不可变。** 每个版本发布在 `templates/<id>/<version>/<id>.html`，并带有大小和
  SHA-256。原地修改已发布文件会破坏所有已安装副本的更新检查。请递增 `version`、添加
  `changelog` 条目，然后发布新版本。
- **`minAppVersion`** 不得高于已经发布的 App 版本。在 App 发版前提前提高它，会让线上模板
  要求一个用户还下载不到的 App 版本。如果模板需要新的 PinShell 能力，请等对应 App 版本发布
  后再提交。
- **十款 `1.0.0` 的第一方模板**在 `Resources/legacy-templates.json` 中记录了冻结哈希，用于
  1.4 → 1.5 的迁移。这些文件处于 `1.0.0` 时不要修改；先递增版本。如果你要修改已有的第一方
  模板，请先与维护者沟通。
- **分类**定义在 `website/site.json`。要新增分类，请单独提交一个带中英文名称的 PR；不要在
  模板清单里发明分类。

## 9. 提交模板

1. Fork `niyongsheng/PinShell`，新建分支，例如 `template/<id>`。
2. 添加 `website/templates/<id>/template.json` 和 `website/templates/<id>/<id>.html`。
3. 运行第 7 节的检查，修复所有错误。
4. 提交 PR，标题使用 `feat(template): add <id>`（或
   `feat(template): update <id> to <version>`）。
5. 在描述中说明：模板用途、分类与标签、声明尺寸、支持的语言、事件协议（如有）、中英文截图，
   并确认没有追踪或远程代码。
6. 一个 PR 只提交一个模板。不要修改共享 sidecar、其他模板或无关代码。

评审重点：校验通过、离线自包含、双语完整、正确使用设计令牌、无障碍与减少动态效果、长时间运行
的性能、安全性（无追踪、无远程代码、无凭据），以及内容质量与授权。

合并后，Pages workflow 会重新构建官网和 `library.json`。App 的在线模板库会在下次刷新时看到
新模板；除非模板要求一个尚未发布的 App 版本，否则不需要发布新的 App 版本。用户始终自行决定
是否安装或更新；PinShell 不会自动安装模板库中的模板。

## 10. 附录：最小可用模板

`website/templates/example-panel/example-panel.html`：

```html
<!doctype html>
<html lang="zh-Hans">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<script type="application/json" id="pinshell:i18n">
{
  "default": "zh-Hans",
  "fallback": "en",
  "languages": {
    "zh-Hans": {
      "meta": { "name": "示例面板", "description": "一个最小可用的 PinShell 模板" }
    },
    "en": {
      "meta": { "name": "Example Panel", "description": "A minimal PinShell template" },
      "ui": {
        "title": "Example",
        "hint": "Click the button to notify the agent",
        "action": "Ping agent"
      }
    }
  }
}
</script>
<title>示例面板</title>
<meta name="description" content="一个最小可用的 PinShell 模板">
<meta name="pinshell:size" content="280x96">
<meta name="pinshell:position" content="bottom-right">
<meta name="pinshell:radius" content="18">
<link rel="stylesheet" href="design-tokens.css">
<style>
  .panel {
    position: absolute;
    inset: 0;
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 0 16px;
    box-sizing: border-box;
    color: var(--ps-body-on-dark);
    background: var(--ps-surface-tile-1);
    border: 1px solid rgba(255, 255, 255, 0.08);
    border-radius: var(--ps-radius-lg);
    user-select: none;
  }
  .copy { flex: 1; min-width: 0; display: flex; flex-direction: column; gap: 3px; }
  .title { font-size: 13px; font-weight: 600; }
  .hint { font-size: 11px; color: var(--ps-body-muted); }
  button {
    font: inherit;
    color: #fff;
    cursor: pointer;
    padding: 6px 12px;
    border: 0;
    border-radius: var(--ps-radius-pill);
    background: var(--ps-primary);
  }
  button:active { transform: var(--ps-press-scale); }
</style>
</head>
<body>
<div class="panel">
  <div class="copy">
    <div class="title" data-i18n="title">示例</div>
    <div class="hint" data-i18n="hint">点击按钮通知 Agent</div>
  </div>
  <button id="ping" data-i18n="action">通知 Agent</button>
</div>
<script src="pinshell-i18n.js"></script>
<script>
  var bridge = window.pinshell || { emit: function () {}, on: function () {} };

  document.getElementById('ping').addEventListener('click', function () {
    bridge.emit('example:ping', { at: Date.now() });
  });

  bridge.on('example:set', function (data) {
    document.querySelector('.title').textContent =
      (data && data.title) || PS.t('title', '示例');
  });

  bridge.emit('example:ready', { version: '1.0.0' });
</script>
</body>
</html>
```

对应的 `template.json` 见第 3 节示例：请把作者、分类和更新日志换成你自己的内容，并保持
`id` 与目录名一致。

## 11. 许可

PinShell 使用 Apache-2.0 许可证。提交模板即表示你拥有或有权使用其中的代码、美术和文案，并
同意以相同的许可证授权该贡献。署名保留在 `author` 中；第三方素材必须兼容该许可证，并在需要
时注明出处。
