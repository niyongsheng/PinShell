# PinShell — SPM 编译 + 手工组装 .app bundle
APP_NAME  := PinShell
CONFIG    := release
APP       := build/$(APP_NAME).app
PKG       := build/$(APP_NAME).pkg

# ARCH: native（默认）或 universal（arm64 + x86_64）
ARCH      ?= native
ifeq ($(ARCH),universal)
SWIFT_ARCH := --arch arm64 --arch x86_64
else
SWIFT_ARCH :=
endif

# 产物路径动态定位（universal 时位于 .build/apple/Products/Release）
BIN_PATH := $(shell swift build -c $(CONFIG) $(SWIFT_ARCH) --show-bin-path)

.PHONY: build app icon menubar-icon run install pkg universal clean site serve-site check-user

# sudo make 会把 build/ 里的产物写成 root 所有，之后普通用户删不掉（make app 会报一堆 Permission denied）。
# /Applications 对 admin 组可写，安装不需要 sudo。
check-user:
	@test "$$(id -u)" -ne 0 || { \
		echo "error: 不要用 sudo 运行 make —— build/ 中的产物会变成 root 所有，之后无法删除。"; \
		echo "       直接 make install 即可：/Applications 对 admin 组可写。"; \
		exit 1; \
	}

build: check-user ## 编译 release 二进制
	swift build -c $(CONFIG) $(SWIFT_ARCH)

app: check-user build ## 组装 PinShell.app（二进制/Info.plist/资源，ad-hoc 签名最后做）
	@rm -rf "$(APP)" 2>/dev/null || { \
		echo "error: 无法删除 $(APP) —— 它很可能属于 root（之前用过 sudo make）。"; \
		echo "       请先执行: sudo rm -rf $(APP)"; \
		exit 1; \
	}
	mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	cp "$(BIN_PATH)/$(APP_NAME)" "$(APP)/Contents/MacOS/$(APP_NAME)"
	cp Resources/Info.plist "$(APP)/Contents/Info.plist"
	cp Resources/PkgInfo "$(APP)/Contents/PkgInfo"
	cp Resources/Placeholder.html "$(APP)/Contents/Resources/Placeholder.html"
	cp Resources/PinShell.icns "$(APP)/Contents/Resources/PinShell.icns"
	cp Resources/MenuBarIcon.png "$(APP)/Contents/Resources/MenuBarIcon.png"
	cp Resources/MenuBarIcon@2x.png "$(APP)/Contents/Resources/MenuBarIcon@2x.png"
	cp -R Resources/templates "$(APP)/Contents/Resources/templates"
	cp Resources/legacy-templates.json "$(APP)/Contents/Resources/legacy-templates.json"
	cp -R Resources/en.lproj "$(APP)/Contents/Resources/en.lproj"
	cp -R Resources/zh-Hans.lproj "$(APP)/Contents/Resources/zh-Hans.lproj"
	codesign --force --deep --sign - "$(APP)"

icon: check-user ## 从 Resources/logo.svg 重新生成应用图标（背景色: ICON_BG=FFFFFF）
	rm -rf build/AppIcon.iconset
	swift scripts/make_icon.swift Resources/logo.svg build/AppIcon.iconset $(ICON_BG)
	iconutil -c icns build/AppIcon.iconset -o Resources/PinShell.icns

menubar-icon: check-user ## 从 Resources/logo.svg 重新生成菜单栏 template 图标
	swift scripts/make_menubar_icon.swift Resources/logo.svg Resources/

run: app ## 用 open 启动（隐式注册 LaunchServices —— CLI 交接的前提）
	open "$(APP)"

install: app ## 安装到 /Applications 并启动
	@rm -rf "/Applications/$(APP_NAME).app" 2>/dev/null || { \
		echo "error: 无法删除 /Applications/$(APP_NAME).app —— 它可能由 .pkg 安装（root 所有）。"; \
		echo "       请先执行: sudo rm -rf /Applications/$(APP_NAME).app"; \
		exit 1; \
	}
	cp -R "$(APP)" "/Applications/"
	open "/Applications/$(APP_NAME).app"

# 不依赖 app：CI 里 tag 构建可能已用 ARCH=universal 生成，避免被重建成 native
pkg: ## 组装 .pkg 安装包（需先 make app 或 make universal）
	@test -d "$(APP)" || { echo "error: $(APP) 不存在，请先执行 make app"; exit 1; }
	rm -rf build/pkg-scripts
	mkdir -p build/pkg-scripts
	cp scripts/pkg-postinstall build/pkg-scripts/postinstall
	chmod +x build/pkg-scripts/postinstall
	VERSION=$$(plutil -extract CFBundleShortVersionString raw Resources/Info.plist); \
	pkgbuild --component "$(APP)" --install-location /Applications \
		--identifier com.pinshell.app.pkg --version "$$VERSION" \
		--scripts build/pkg-scripts "$(PKG)"
	@echo "PKG: $(PKG)"

universal: ## 双架构构建（Apple Silicon + Intel）
	$(MAKE) app ARCH=universal

site: ## 构建官网与在线模板库
	swift run --package-path website TemplateCatalogBuilder --output website/public

serve-site: ## 本地构建并预览官网（http://127.0.0.1:8000）
	swift run --package-path website TemplateCatalogBuilder \
		--output website/public --site-url http://127.0.0.1:8000
	python3 -m http.server 8000 --directory website/public

clean: check-user
	swift package clean
	@rm -rf .build build 2>/dev/null || { \
		echo "error: 部分文件无法删除（可能属于 root），请先执行: sudo rm -rf .build build"; \
		exit 1; \
	}
