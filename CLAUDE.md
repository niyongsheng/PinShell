# PinShell 开发约定

## 模板目录同步

开发期间模板有两份副本，修改时**必须同步修改两处并保持内容一致**：

| 用途 | 路径 |
|---|---|
| App 运行时模板（本机预览/应用） | `~/Library/Application Support/PinShell/templates/<id>.html` |
| 官网 / 在线模板库源文件（提交用） | `website/templates/<id>/<id>.html` |

- 修改模板 HTML 时，两份文件写入相同内容。
- 新增模板时，同时创建运行时副本与 `website/templates/<id>/`（含 `template.json`）。
- 共享资源 `design-tokens.css`、`pinshell-i18n.js` 的源文件在 `Resources/templates/`，App 启动时会自动播种到运行时目录；需要修改时改源文件，不要只改运行时副本。
- `work-calendar` 是首装内置模板：`make app` 会从 `website/templates/work-calendar/work-calendar.html` 复制进 App bundle，首次启动且模板目录没有 HTML 时播种到运行时目录。修改后需重新 `make app`。
- `~/Library/Application Support/PinShell/` 下的文件不提交到仓库。
