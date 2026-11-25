---
name: pinshell-release
description: 发布 PinShell 新版本：检查现场 → 确定版本 → 更新 Info.plist → 测试与官网目录校验 → 提交 → 打 vX.Y.Z tag 推送触发 CI → 校验 GitHub Release 产物与 latest 稳定链接。触发词：发布新版本、发版、release、打 tag、bump version、发 release。
---

# pinshell-release

发布 PinShell（`niyongsheng/PinShell`）新版本。**git tag 是发布版本的唯一真源**：CI 在 tag 构建时用 tag 覆盖 `CFBundleShortVersionString`，然后构建双架构产物并创建 GitHub Release。

## 发布模型

- 推送 `v*` tag 会触发 `.github/workflows/ci.yml`：
  1. `swift test`
  2. 用 tag 覆盖 `Resources/Info.plist` 的 `CFBundleShortVersionString`
  3. 校验 website 模板目录（每个模板的 `minAppVersion` 不得高于本次 tag 版本）
  4. `make app ARCH=universal` 构建 arm64 + x86_64
  5. 产出并上传 `PinShell-<v>.dmg`、`PinShell-<v>.zip`、`PinShell-<v>-mac-universal.pkg`，并复制稳定别名 `PinShell.pkg`
  6. 自动创建 GitHub Release，body 含下载表和 `What's Changed`（只收 feat/fix/perf 提交）
- 应用内更新读取 `releases/latest`，优先取 `PinShell.pkg`，用 GitHub API 的 SHA-256 digest 校验后交给系统 Installer。
- 官网由 Pages workflow 在 push `main` 且触及 `website/**`、`Resources/Info.plist` 等路径时自动部署。
- **模板的 `minAppVersion` 只能在新版本发布成功后再单独提交**。官网会先于 app 发布，提前改会让线上模板要求一个尚未发布的 app 版本。

## 工作流程

### 0. 解析参数

支持：

- 无参数：交互选择版本
- 显式版本：`/pinshell-release 1.5.0`（可带 `v` 前缀）
- `--patch` / `--minor` / `--major`：在 `max(当前 Info.plist 版本, 最新 tag)` 上递增
- `--dry-run`：只做检查与验证，不改文件、不提交、不打 tag、不推送

参数无法识别 → 停下说明用法，不要猜。

### 1. 发布前检查（只读）

```bash
git rev-parse --is-inside-work-tree
git branch --show-current
git status --porcelain
git fetch origin --tags --prune
git rev-list --left-right --count origin/main...HEAD
```

`git rev-list --left-right --count` 的输出是 `behind<TAB>ahead`。

判定与处理：

- 不在 git 仓库 / 当前分支不是 `main` → 停下，说明必须在 `main` 上发布。
- `git status --porcelain` 非空 → **停下**。不要自动 stash、不要替用户提交无关改动；提示先用 `/nico-git-commit` 处理。
- 落后 origin/main → `git pull --ff-only origin main` 后重新检查。
- 与 origin/main 分叉（ahead 与 behind 都 > 0）→ 停下，让用户先自行 rebase/merge。
- 领先 origin/main → 记录 `git log --oneline origin/main..HEAD`，这些提交会随本次发布一起推送，后续在发布计划里展示并让用户确认。

读取版本基线：

```bash
LATEST_TAG=$(git describe --tags --abbrev=0 --match 'v*')
LATEST=${LATEST_TAG#v}
CURRENT=$(plutil -extract CFBundleShortVersionString raw Resources/Info.plist)
CURRENT_BUILD=$(plutil -extract CFBundleVersion raw Resources/Info.plist)
LATEST_BUILD=$(git show "$LATEST_TAG:Resources/Info.plist" | plutil -extract CFBundleVersion raw -)
git rev-list --count "$LATEST_TAG..HEAD"
```

检查 GitHub CLI 与仓库：

```bash
gh auth status
gh api user --jq .login
gh repo view niyongsheng/PinShell --json nameWithOwner --jq .nameWithOwner
```

- 未登录 → 停下，让用户执行 `! gh auth login`。
- 当前活动账号不是 `niyongsheng` → `gh auth switch --user niyongsheng`；切换失败则停下。
- 无法访问仓库 → 停下，报告权限问题。

汇总展示：

```
📦 发布现状
  最新 tag:      v1.4.0（build 5）
  仓库版本:      1.5.0（build 6）
  待发布提交:    12 条（v1.4.0..HEAD）
  未推送提交:    3 条（origin/main..HEAD）
  工作区:        clean
```

### 2. 确定目标版本

校验规则：

- 只接受严格的 `X.Y.Z`（可带 `v` 前缀）。**不支持** `-beta`、`-rc`、`+build` 等后缀；应用的版本比较会忽略非数字后缀，预发布 tag 会与正式版相等。
- 目标版本必须 **大于最新已发布 tag**。
- 目标版本必须 **不低于当前 Info.plist 版本**（当前版本可能已是准备发布的下一版，不能静默降级）。
- 本地与远端都不能已存在同名 tag：

```bash
git rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null && echo "local tag exists"
git ls-remote --exit-code --tags origin "refs/tags/v$VERSION"
```

`git ls-remote --exit-code` 无匹配时返回 2，有匹配时返回 0；返回 0 就停下。

数值比较：

```bash
version_gt() {
  [ "$1" != "$2" ] && \
  [ "$(printf '%s\n%s\n' "$1" "$2" | sort -t. -k1,1n -k2,2n -k3,3n | tail -n1)" = "$1" ]
}
version_gt "$VERSION" "$LATEST" || echo "not newer than latest tag"
version_gt "$CURRENT" "$VERSION" && echo "lower than current Info.plist version"
```

交互选择（未显式传版本时）：

- **当前版本 > 最新 tag**（例如仓库 1.5.0、最新 tag v1.4.0）：
  - 第一项推荐「1.5.0（当前 Info.plist 版本）」
  - 其他项：patch / minor / major（以当前版本为基线）
- **当前版本 == 最新 tag**：
  - patch / minor / major
- **当前版本 < 最新 tag**（Info.plist 落后）：
  - 以最新 tag 为基线给 patch / minor / major，并提示当前 Info.plist 版本落后

用 AskUserQuestion 展示选项，label 用版本号，description 说明语义。用户可自行选择 Other 输入版本。

`--patch` / `--minor` / `--major` 的基线是 `max(CURRENT, LATEST)`：

```
patch: X.Y.(Z+1)
minor: X.(Y+1).0
major: (X+1).0.0
```

### 3. 更新 Info.plist（按需）

记 `VERSION` 为目标版本。判定是否需要版本提交：

1. `VERSION != CURRENT` → 需要提交：
   - `CFBundleShortVersionString` 改为 `VERSION`
   - `CFBundleVersion` 改为 `max(CURRENT_BUILD, LATEST_BUILD) + 1`
2. `VERSION == CURRENT` 且 `CURRENT_BUILD > LATEST_BUILD` → 版本已在 HEAD 准备好，**不提交**，直接给 HEAD 打 tag。
3. `VERSION == CURRENT` 且 `CURRENT_BUILD <= LATEST_BUILD` → 只把 `CFBundleVersion` 升到 `LATEST_BUILD + 1`，提交 `chore(release)`。

需要修改时：

```bash
NEXT_BUILD=$(( (CURRENT_BUILD > LATEST_BUILD ? CURRENT_BUILD : LATEST_BUILD) + 1 ))
plutil -replace CFBundleShortVersionString -string "$VERSION" Resources/Info.plist
plutil -replace CFBundleVersion -string "$NEXT_BUILD" Resources/Info.plist
plutil -lint Resources/Info.plist
git diff -- Resources/Info.plist
```

说明：

- `CFBundleVersion`（构建号）不参与应用内版本比较，但每次发布递增，保持 macOS / Installer 侧一致。
- 不需要修改时，不要为了「有提交」而制造空 commit。
- `--dry-run` 跳过本步。

### 4. 本地验证

按顺序执行，任一失败就停下报告，不继续：

```bash
swift test

swift run --package-path website -c release TemplateCatalogBuilder \
  --check --site-url https://pinshell.looplooptech.com

make app

plutil -extract CFBundleShortVersionString raw build/PinShell.app/Contents/Info.plist
git diff --check
```

- `make app` 会用当前工作区的 Info.plist 组装并 ad-hoc 签名；**不要用 sudo**。
- `plutil` 那条应输出目标版本。
- 若目录校验报 `minAppVersion ... is newer than app ...`：说明某个模板要求比本次发布更新的版本。不要为了让检查通过而降低 `minAppVersion`；先决定是本次版本号不够，还是模板应等发布后再改。
- `--dry-run` 时不要修改 Info.plist；用 `--app-version` 覆盖校验目标版本：

```bash
swift test
swift run --package-path website -c release TemplateCatalogBuilder \
  --check --site-url https://pinshell.looplooptech.com --app-version "$VERSION"
swift build -c release
```

`--dry-run` 到此结束：汇报计划与验证结果，不提交、不打 tag、不推送。

### 5. 提交版本变更（仅在需要时）

```bash
git add Resources/Info.plist
git status --short
git commit -m "chore(release): v$VERSION"
git show --stat --oneline HEAD
```

- 确认暂存区**只有** `Resources/Info.plist`；不要用 `git add .`。
- commit message 末尾**不追加** `Co-Authored-By`（沿用项目提交习惯）。
- 不需要版本提交时跳过本步，记录当前 HEAD 即可。

### 6. 发布前确认

展示完整计划：

```
🚀 发布计划
  目标版本:    1.5.0（build 6）
  基线 tag:    v1.4.0
  版本提交:    chore(release): v1.5.0（或无，版本已在 HEAD 准备好）
  待推送:      origin main（含 12 条提交） + tag v1.5.0
  CI:          swift test → universal app → DMG/ZIP/PKG → GitHub Release
  影响:        应用内更新与官网 latest 下载链接将指向 v1.5.0
```

如果 `v$LATEST..HEAD` 里没有 feat/fix/perf 提交，提示用户 CI 生成的 `What's Changed` 会是空的；需要的话在发布后用 `gh release edit` 补充说明。

用 AskUserQuestion 确认：

- **确认发布** — push main、打 tag、push tag
- **只保留本地** — 已完成版本提交但不推送、不打 tag（无版本提交时变成「放弃」）
- **放弃并回滚** — 若有本次版本提交：`git reset --hard HEAD~1`（仅在 preflight 确认工作区干净、且该提交就是本次新建时使用）；然后退出

push tag 是外发操作，未得到明确确认前不得执行。

### 7. 推送与打 tag

```bash
git push origin main
git tag -a "v$VERSION" -m "PinShell v$VERSION"
git push origin "v$VERSION"
```

- **先 push main，再打 tag**，保证 tag 指向的提交已经在远端 main 上。
- 校验远端 tag 指向 HEAD：

```bash
git rev-parse HEAD
git ls-remote --tags origin "refs/tags/v$VERSION" "refs/tags/v$VERSION^{}"
```

本 skill 创建的是 annotated tag，`^{}` 解引用出的 commit 必须等于 HEAD。如果只有一行（轻量 tag 没有 `^{}`），则比较该行 commit 是否等于 HEAD。

- push main 失败 → 停下，不创建 tag。
- tag 已存在导致 push 失败 → 不要 force push tag，按第 11 节排查。

### 8. 等待 CI

```bash
RUN_ID=$(gh run list --repo niyongsheng/PinShell --workflow=ci.yml --limit 30 \
  --json databaseId,event,headBranch \
  --jq "[.[] | select(.event == \"push\" and .headBranch == \"v$VERSION\")][0].databaseId")

gh run watch "$RUN_ID" --repo niyongsheng/PinShell --exit-status
```

- `RUN_ID` 为空：GitHub 注册 run 可能延迟，稍等后重试；同时用 `git ls-remote` 确认 tag 已在远端。
- universal 构建通常需要 5–15 分钟。等待期间不要重复 push tag；重复 push 会产生多个 run。
- 失败时：

```bash
gh run view "$RUN_ID" --log-failed
```

报告失败的 job / step 与日志摘要，不要盲目重试。修复后按第 11 节重新发版。

### 9. 校验 GitHub Release

```bash
gh api "repos/niyongsheng/PinShell/releases/tags/v$VERSION" \
  --jq '{tag: .tag_name, draft: .draft, prerelease: .prerelease,
         assets: [.assets[] | {name, size, digest}]}'

gh api repos/niyongsheng/PinShell/releases/latest --jq '.tag_name'

curl -sIL -o /dev/null -w '%{http_code}\n' \
  "https://github.com/niyongsheng/PinShell/releases/latest/download/PinShell.pkg"
```

必须满足：

- 恰好包含四个产物：
  - `PinShell-$VERSION.dmg`
  - `PinShell-$VERSION.zip`
  - `PinShell-$VERSION-mac-universal.pkg`
  - `PinShell.pkg`
- `draft == false` 且 `prerelease == false`
- 两个 `.pkg` 的 size 相同，且 `digest` 非 null（形如 `sha256:...`）
- `/releases/latest` 返回 `v$VERSION`
- 稳定下载链接最终返回 `200`

刚完成 CI 时 Release 可能还在创建，稍等后重试；持续缺失按失败处理。

可选：确认官网部署（版本提交触及 `Resources/Info.plist` 会触发 Pages）：

```bash
gh run list --workflow=pages.yml --limit 3 \
  --json databaseId,status,conclusion,headBranch,createdAt
curl -fsS https://pinshell.looplooptech.com/ >/dev/null && echo "site ok"
```

### 10. 报告完成

```
✅ v1.5.0 发布完成
  版本提交:  <hash> chore(release): v1.5.0（或无）
  Tag:       v1.5.0 → <hash>
  Release:   https://github.com/niyongsheng/PinShell/releases/tag/v1.5.0
  产物:      dmg / zip / mac-universal.pkg / PinShell.pkg（均含 sha256）
  latest:    v1.5.0
  更新链接:  https://github.com/niyongsheng/PinShell/releases/latest/download/PinShell.pkg
```

发布后提醒：

1. 用上一版本安装包做一次应用内更新回归：⌘U 检查 → 下载 → SHA-256 校验 → 系统 Installer 安装。
2. 如果本版本引入了模板需要的新能力，**现在**再单独提交模板的 `minAppVersion`：
   - 修改 `website/templates/<id>/template.json`（`version` + `changelog` + `minAppVersion`）
   - 跑目录校验
   - 单独 commit 并 push main，触发 Pages 部署
3. 不要修改 `Resources/legacy-templates.json`（它描述 1.4 → 1.5 的旧模板迁移契约），除非迁移逻辑本身要变。

### 11. 失败与回滚

| 阶段 | 处理 |
| --- | --- |
| 本地验证失败 | 修复后重跑；未推送前可 `git reset --hard HEAD~1` 删除本次版本提交（前提：preflight 时工作区干净）。 |
| main 已推送、tag 未推送 | 修复后补打 tag；版本提交已在 main，无需回滚。 |
| tag 已推送、CI 失败 | `gh run view --log-failed` 定位；修复后删除远端/本地 tag，重新打 tag 推送。若 Release 已创建，先删除 Release。 |
| Release 已发布但 body 有误 | `gh release edit "v$VERSION" --notes-file <file>`，不要重发版本。 |
| Release 已发布但产物有误 | 优先重新运行失败的 CI job 或上传修正产物；需要重建时删除 Release + tag 后重打。**不要让已发布 tag 指向新提交。** |
| 发布后发现代码问题 | 不要移动已发布 tag；发一个新的 patch 版本。 |

删除 tag / Release（确认该版本尚未被用户依赖后）：

```bash
gh release delete "v$VERSION" --yes    # 若已创建
git push origin ":refs/tags/v$VERSION"
git tag -d "v$VERSION"
# 修复并提交后重新 tag
```

## 注意事项

1. **发布是外发操作**：push tag 前必须让用户明确确认（第 6 步）。
2. **tag 不可随意移动**：应用内更新按 `releases/latest` 和 tag 工作；已发布 tag 改指向会造成版本混乱。需要重发时删除 Release + tag 再重建，或发新 patch。
3. **版本格式严格 `X.Y.Z`**：不支持预发布后缀。应用的版本比较会忽略非数字后缀。
4. **Info.plist 与 tag 保持一致**：CI 会用 tag 覆盖 short version；仓库里保留同值，避免本地构建 / About 页面显示旧版本。
5. **构建号递增**：`CFBundleVersion` 每次发布 +1；即使 short version 已在 HEAD 准备好，也要确认它高于上一 tag。
6. **模板 `minAppVersion` 不进入发布提交**：Pages 会先部署，线上会出现要求未发布版本的模板。发布成功后再单独提交。
7. **不要 sudo make**：`build/` 会变成 root 所有，后续无法清理。
8. 工作区有未提交改动时，调用 `/nico-git-commit` 提交后，继续。
9. 发布提交只包含 `Resources/Info.plist`；commit 末尾不追加 `Co-Authored-By`。
10. 不修改 `website/site.json` 的下载链接（已指向 `latest` 稳定别名），也不改 `Resources/legacy-templates.json` 的 `sourceVersion`。
11. 网络失败 / 未登录 / CI 失败时原样报告，不静默重试、不掩盖。

## 调用方式

```
/pinshell-release                 # 交互选择版本
/pinshell-release 1.5.0           # 指定版本
/pinshell-release --patch         # 在 max(当前版本, 最新 tag) 上 patch
/pinshell-release --minor
/pinshell-release --major
/pinshell-release --dry-run       # 只检查与验证，不写文件/不提交/不推送
```
