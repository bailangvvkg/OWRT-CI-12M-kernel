#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 VIKINGYFY

#安装和更新软件包
UPDATE_PACKAGE() {
	local PKG_NAME=$1
	local PKG_REPO=$2
	local PKG_BRANCH=$3
	local PKG_SPECIAL=$4
	local PKG_LIST=("$PKG_NAME" $5)  # 第5个参数为自定义名称列表
	local REPO_NAME=${PKG_REPO#*/}

	echo " "

	# 删除本地可能存在的不同名称的软件包
	for NAME in "${PKG_LIST[@]}"; do
		# 查找匹配的目录
		echo "Search directory: $NAME"
		local FOUND_DIRS=$(find ../feeds/luci/ ../feeds/packages/ -maxdepth 3 -type d -iname "*$NAME*" 2>/dev/null)

		# 删除找到的目录
		if [ -n "$FOUND_DIRS" ]; then
			while read -r DIR; do
				rm -rf "$DIR"
				echo "Delete directory: $DIR"
			done <<< "$FOUND_DIRS"
		else
			echo "Not fonud directory: $NAME"
		fi
	done

	# 克隆 GitHub 仓库
	git clone --depth=1 --single-branch --branch $PKG_BRANCH "https://github.com/$PKG_REPO.git"

	# 处理克隆的仓库
	if [[ "$PKG_SPECIAL" == "pkg" ]]; then
		find ./$REPO_NAME/*/ -maxdepth 3 -type d -iname "*$PKG_NAME*" -prune -exec cp -rf {} ./ \;
		rm -rf ./$REPO_NAME/
	elif [[ "$PKG_SPECIAL" == "name" ]]; then
		mv -f $REPO_NAME $PKG_NAME
	fi
}

# 调用示例
# UPDATE_PACKAGE "OpenAppFilter" "destan19/OpenAppFilter" "master" "" "custom_name1 custom_name2"
# UPDATE_PACKAGE "open-app-filter" "destan19/OpenAppFilter" "master" "" "luci-app-appfilter oaf" 这样会把原有的open-app-filter，luci-app-appfilter，oaf相关组件删除，不会出现coremark错误。

# UPDATE_PACKAGE "包名" "项目地址" "项目分支" "pkg/name，可选，pkg为从大杂烩中单独提取包名插件；name为重命名为包名"
# UPDATE_PACKAGE "argon" "sbwml/luci-theme-argon" "openwrt-25.12"
UPDATE_PACKAGE "aurora" "eamonxg/luci-theme-aurora" "master"
UPDATE_PACKAGE "aurora-config" "eamonxg/luci-app-aurora-config" "master"
UPDATE_PACKAGE "kucat" "sirpdboy/luci-theme-kucat" "master"
UPDATE_PACKAGE "kucat-config" "sirpdboy/luci-app-kucat-config" "master"

UPDATE_PACKAGE "homeproxy" "VIKINGYFY/homeproxy" "main"
UPDATE_PACKAGE "momo" "nikkinikki-org/OpenWrt-momo" "main"
UPDATE_PACKAGE "nikki" "nikkinikki-org/OpenWrt-nikki" "main"
UPDATE_PACKAGE "openclash" "vernesong/OpenClash" "dev" "pkg"
UPDATE_PACKAGE "passwall" "Openwrt-Passwall/openwrt-passwall" "main" "pkg"
UPDATE_PACKAGE "passwall2" "Openwrt-Passwall/openwrt-passwall2" "main" "pkg"

UPDATE_PACKAGE "luci-app-tailscale" "asvow/luci-app-tailscale" "main"

#UPDATE_PACKAGE "athena-led" "unraveloop/JDC-AX6600-Athena-LED-Controller" "main"
UPDATE_PACKAGE "ddns-go" "sirpdboy/luci-app-ddns-go" "main"
UPDATE_PACKAGE "diskman" "sbwml/luci-app-diskman" "main"
UPDATE_PACKAGE "diskmanager" "4IceG/luci-app-mini-diskmanager" "main"
UPDATE_PACKAGE "easytier" "EasyTier/luci-app-easytier" "main"
UPDATE_PACKAGE "mosdns" "sbwml/luci-app-mosdns" "v5" "" "v2dat"
UPDATE_PACKAGE "netspeedtest" "sirpdboy/netspeedtest" "main" "" "homebox ookla-speedtest"
UPDATE_PACKAGE "netwizard" "sirpdboy/luci-app-netwizard" "main"
UPDATE_PACKAGE "openlist2" "sbwml/luci-app-openlist2" "main"
UPDATE_PACKAGE "partexp" "sirpdboy/luci-app-partexp" "main"
UPDATE_PACKAGE "qbittorrent" "sbwml/luci-app-qbittorrent" "master" "" "qt6base qt6tools rblibtorrent"
UPDATE_PACKAGE "qmodem" "FUjr/QModem" "main"
UPDATE_PACKAGE "quickfile" "sbwml/luci-app-quickfile" "main"
UPDATE_PACKAGE "timecontrol" "sirpdboy/luci-app-timecontrol" "main"
UPDATE_PACKAGE "viking" "VIKINGYFY/packages" "main" "" "gecoosac luci-app-timewol luci-app-wolplus"
UPDATE_PACKAGE "vnt" "lmq8267/luci-app-vnt" "main"

#更新软件包版本
UPDATE_VERSION() {
	local PKG_NAME=$1
	local PKG_MARK=${2:-false}
	local PKG_FILES=$(find ./ ../feeds/packages/ -maxdepth 3 -type f -wholename "*/$PKG_NAME/Makefile")

	if [ -z "$PKG_FILES" ]; then
		echo "$PKG_NAME not found!"
		return
	fi

	echo -e "\n$PKG_NAME version update has started!"

	for PKG_FILE in $PKG_FILES; do
		local PKG_REPO=$(grep -Po "PKG_SOURCE_URL:=https://.*github.com/\K[^/]+/[^/]+(?=.*)" $PKG_FILE)
		local PKG_TAG=$(curl -sL "https://api.github.com/repos/$PKG_REPO/releases" | jq -r "map(select(.prerelease == $PKG_MARK)) | first | .tag_name")

		local OLD_VER=$(grep -Po "PKG_VERSION:=\K.*" "$PKG_FILE")
		local OLD_URL=$(grep -Po "PKG_SOURCE_URL:=\K.*" "$PKG_FILE")
		local OLD_FILE=$(grep -Po "PKG_SOURCE:=\K.*" "$PKG_FILE")
		local OLD_HASH=$(grep -Po "PKG_HASH:=\K.*" "$PKG_FILE")

		local PKG_URL=$([[ "$OLD_URL" == *"releases"* ]] && echo "${OLD_URL%/}/$OLD_FILE" || echo "${OLD_URL%/}")

		local NEW_VER=$(echo $PKG_TAG | sed -E 's/[^0-9]+/\./g; s/^\.|\.$//g')
		local NEW_URL=$(echo $PKG_URL | sed "s/\$(PKG_VERSION)/$NEW_VER/g; s/\$(PKG_NAME)/$PKG_NAME/g")
		local NEW_HASH=$(curl -sL "$NEW_URL" | sha256sum | cut -d ' ' -f 1)

		echo "old version: $OLD_VER $OLD_HASH"
		echo "new version: $NEW_VER $NEW_HASH"

		if [[ "$NEW_VER" =~ ^[0-9].* ]] && dpkg --compare-versions "$OLD_VER" lt "$NEW_VER"; then
			sed -i "s/PKG_VERSION:=.*/PKG_VERSION:=$NEW_VER/g" "$PKG_FILE"
			sed -i "s/PKG_HASH:=.*/PKG_HASH:=$NEW_HASH/g" "$PKG_FILE"
			echo "$PKG_FILE version has been updated!"
		else
			echo "$PKG_FILE version is already the latest!"
		fi
	done
}

#UPDATE_VERSION "软件包名" "测试版，true，可选，默认为否"
UPDATE_VERSION "sing-box"

#引入私有扩展脚本
if [ -f "$GITHUB_WORKSPACE/Scripts/PRIVATE.sh" ]; then
	source "$GITHUB_WORKSPACE/Scripts/PRIVATE.sh"
fi

SCRIPT_RUN_DIR=$(pwd)
if [ -x "$SCRIPT_RUN_DIR/scripts/feeds" ] && [ -d "$SCRIPT_RUN_DIR/package" ]; then
	OPENWRT_ROOT="$SCRIPT_RUN_DIR"
	OPENWRT_PACKAGE_DIR="$SCRIPT_RUN_DIR/package"
elif [ -x "$SCRIPT_RUN_DIR/../scripts/feeds" ] && [ -d "$SCRIPT_RUN_DIR/../package" ]; then
	OPENWRT_ROOT=$(cd "$SCRIPT_RUN_DIR/.." && pwd)
	OPENWRT_PACKAGE_DIR="$SCRIPT_RUN_DIR"
else
	echo "OpenWrt root not found from $SCRIPT_RUN_DIR" >&2
	exit 1
fi

# Git稀疏克隆，只克隆指定目录到本地
function git_sparse_clone() {
	local PACKAGE_DIR
	local REPO_DIR
	branch="$1" repourl="$2" && shift 2
	PACKAGE_DIR=$(PACKAGE_WORK_DIR)
	REPO_DIR=$(basename "$repourl")

	rm -rf "$REPO_DIR"
	if ! git clone --recursive --depth=1 -b "$branch" --single-branch --filter=blob:none --sparse "$repourl" "$REPO_DIR"; then
		rm -rf "$REPO_DIR"
		return 1
	fi

	if ! (
		cd "$REPO_DIR" || exit 1
		git sparse-checkout set "$@"
		mkdir -p "$PACKAGE_DIR"
		mv -f "$@" "$PACKAGE_DIR"
	); then
		rm -rf "$REPO_DIR"
		return 1
	fi

	rm -rf "$REPO_DIR"
}

OPENWRT_ROOT_DIR() {
	echo "$OPENWRT_ROOT"
}

PACKAGE_WORK_DIR() {
	echo "$OPENWRT_PACKAGE_DIR"
}

RUN_FEEDS_INSTALL() {
	local ROOT_DIR
	ROOT_DIR=$(OPENWRT_ROOT_DIR)

	(cd "$ROOT_DIR" && ./scripts/feeds install -a)
}

FEEDS_WORK_DIR() {
	echo "$OPENWRT_ROOT/feeds"
}

git_package_clone() {
	local REPO_URL=$1
	local TARGET_NAME=$2
	local PACKAGE_DIR

	PACKAGE_DIR=$(PACKAGE_WORK_DIR)
	git clone "$REPO_URL" "$PACKAGE_DIR/$TARGET_NAME"
}

UPDATE_PODMAN() {
	local PODMAN_REPO="https://github.com/Zerogiven-OpenWRT-Packages/luci-app-podman.git"
	local PACKAGE_DIR
	local TARGET_DIR

	PACKAGE_DIR=$(PACKAGE_WORK_DIR)
	TARGET_DIR="$PACKAGE_DIR/luci-app-podman"

	rm -rf "$TARGET_DIR"
	if ! git clone --depth 1 --single-branch --recursive "$PODMAN_REPO" "$TARGET_DIR"; then
		return 1
	fi

	if [ ! -f "$TARGET_DIR/Makefile" ]; then
		echo "luci-app-podman Makefile not found: $TARGET_DIR/Makefile" >&2
		return 1
	fi
}

UPDATE_LANSPEED() {
	local LANSPEED_REPO="https://github.com/qimaoww/luci-app-lanspeed.git"
	local PACKAGE_DIR
	local TMP_DIR

	PACKAGE_DIR=$(PACKAGE_WORK_DIR)
	TMP_DIR=$(mktemp -d)

	rm -rf "$PACKAGE_DIR/luci-app-lanspeed" "$PACKAGE_DIR/lanspeedd"
	if ! git clone --depth 1 --single-branch "$LANSPEED_REPO" "$TMP_DIR"; then
		rm -rf "$TMP_DIR"
		return 1
	fi

	if [ ! -f "$TMP_DIR/applications/luci-app-lanspeed/Makefile" ]; then
		echo "luci-app-lanspeed Makefile not found in $LANSPEED_REPO" >&2
		rm -rf "$TMP_DIR"
		return 1
	fi

	if [ ! -f "$TMP_DIR/net/lanspeedd/Makefile" ]; then
		echo "lanspeedd Makefile not found in $LANSPEED_REPO" >&2
		rm -rf "$TMP_DIR"
		return 1
	fi

	cp -rf "$TMP_DIR/applications/luci-app-lanspeed" "$PACKAGE_DIR/luci-app-lanspeed"
	cp -rf "$TMP_DIR/net/lanspeedd" "$PACKAGE_DIR/lanspeedd"
	rm -rf "$TMP_DIR"
}

# 拉取Lucky最新版的源码
UPDATE_LUCKY() {
	local LUCKY_REPO="https://github.com/gdy666/luci-app-lucky.git"
	local PACKAGE_DIR
	local TMP_DIR

	PACKAGE_DIR=$(PACKAGE_WORK_DIR)

	echo "Pull latest lucky from $LUCKY_REPO"
	rm -rf "$PACKAGE_DIR/lucky" "$PACKAGE_DIR/luci-app-lucky"
	find ../feeds/luci ../feeds/packages ./feeds/luci ./feeds/packages \
		-maxdepth 4 -type d \( -name "lucky" -o -name "luci-app-lucky" \) \
		-prune -exec rm -rf {} + 2>/dev/null || true

	TMP_DIR=$(mktemp -d)
	if ! git clone --depth=1 --filter=blob:none --no-checkout "$LUCKY_REPO" "$TMP_DIR"; then
		rm -rf "$TMP_DIR"
		return 1
	fi

	if ! (
		cd "$TMP_DIR" || exit 1
		git sparse-checkout init --cone
		git sparse-checkout set luci-app-lucky lucky
		git checkout --quiet
	); then
		rm -rf "$TMP_DIR"
		return 1
	fi

	cp -rf "$TMP_DIR/luci-app-lucky" "$PACKAGE_DIR/luci-app-lucky"
	cp -rf "$TMP_DIR/lucky" "$PACKAGE_DIR/lucky"
	rm -rf "$TMP_DIR"

	if [ -f "$PACKAGE_DIR/lucky/files/luckyuci" ]; then
		sed -i "s/option enabled '1'/option enabled '0'/g" "$PACKAGE_DIR/lucky/files/luckyuci"
		sed -i "s/option logger '1'/option logger '0'/g" "$PACKAGE_DIR/lucky/files/luckyuci"
	fi
}

UPDATE_LUCKY || exit 1

#删除官方的默认插件
# rm -rf ../feeds/luci/applications/luci-app-{passwall*,mosdns,dockerman,dae*,bypass*}
# rm -rf ../feeds/packages/net/{shadowsocks-rust,shadowsocksr-libev,xray*,v2ray*,dae*,sing-box,geoview}
rm -rf "$(FEEDS_WORK_DIR)"/luci/applications/luci-app-dae*
rm -rf "$(FEEDS_WORK_DIR)"/packages/net/dae*

# QiuSimons luci-app-daed
git_package_clone https://github.com/QiuSimons/luci-app-daed dae
mkdir -p Package/libcron && wget -O Package/libcron/Makefile https://raw.githubusercontent.com/immortalwrt/packages/refs/heads/master/libs/libcron/Makefile

# # luci-app-daed-next
# git clone https://github.com/sbwml/luci-app-daed-next package/daed-next

git_sparse_clone main https://github.com/kenzok8/small-package daed-next luci-app-daed-next gost luci-app-gost luci-app-adguardhome

git_sparse_clone main https://gitlab.com/discuzamoy/Small-package luci-app-cloudflarespeedtest luci-app-nginx-manager luci-app-wechatpush || exit 1

# docker
git_sparse_clone main https://gitlab.com/discuzamoy/Small-package luci-app-dockerman dockerd || exit 1

# git clone --depth 1 --single-branch https://github.com/breeze303/openwrt-podman package/podman
UPDATE_PODMAN || exit 1
RUN_FEEDS_INSTALL || exit 1

PATCH_NGINX() {
	local ROOT_DIR
	local NGINX_UTIL_DIR
	local NGINX_CONFIG
	local UCI_TEMPLATE
	local UCI_DEFAULTS_DIR
	local UCI_DEFAULTS_FILE
	local NGINX_CONFIG_URL="https://r2.lovelyy.eu.org/raw/immortalwrt/nginx/ngnx.conf"

	ROOT_DIR=$(OPENWRT_ROOT_DIR)
	NGINX_UTIL_DIR="$ROOT_DIR/feeds/packages/net/nginx-util"
	NGINX_CONFIG="$NGINX_UTIL_DIR/files/nginx.config"
	UCI_TEMPLATE="$NGINX_UTIL_DIR/files/uci.conf.template"
	UCI_DEFAULTS_DIR="$ROOT_DIR/package/base-files/files/etc/uci-defaults"
	UCI_DEFAULTS_FILE="$UCI_DEFAULTS_DIR/99-nginx-large-client-header"

	if [ ! -d "$NGINX_UTIL_DIR/files" ]; then
		echo "nginx-util files directory not found: $NGINX_UTIL_DIR/files" >&2
		return 1
	fi

	echo "Patch nginx config: $NGINX_CONFIG"
	if ! wget -O "$NGINX_CONFIG" "$NGINX_CONFIG_URL" || [ ! -s "$NGINX_CONFIG" ]; then
		echo "nginx config download failed: $NGINX_CONFIG_URL" >&2
		return 1
	fi

	if ! grep -q "large_client_header_buffers.*8 32k" "$NGINX_CONFIG"; then
		echo "nginx config patch missing large_client_header_buffers: $NGINX_CONFIG" >&2
		return 1
	fi

	if [ -f "$UCI_TEMPLATE" ]; then
		sed -i 's/^[[:space:]]*large_client_header_buffers .*/large_client_header_buffers 8 32k;/' "$UCI_TEMPLATE"
	else
		echo "nginx uci template not found: $UCI_TEMPLATE" >&2
		return 1
	fi

	if ! grep -q "large_client_header_buffers 8 32k;" "$UCI_TEMPLATE"; then
		echo "nginx uci template patch failed: $UCI_TEMPLATE" >&2
		return 1
	fi

	mkdir -p "$UCI_DEFAULTS_DIR"
cat >"$UCI_DEFAULTS_FILE" <<'EOF'
#!/bin/sh

uci -q get nginx._lan >/dev/null || uci set nginx._lan='server'
uci -q set nginx._lan.large_client_header_buffers='8 32k'
uci -q set nginx._lan.client_max_body_size='128M'
uci -q commit nginx

if [ -f /etc/nginx/uci.conf.template ]; then
	sed -i 's/^[[:space:]]*large_client_header_buffers .*/large_client_header_buffers 8 32k;/' /etc/nginx/uci.conf.template
fi

exit 0
EOF
	chmod +x "$UCI_DEFAULTS_FILE"
}

PATCH_NGINX || exit 1

# 查看在线端
git_package_clone https://github.com/zzsj0928/luci-app-pushbot luci-app-pushbot

# 移除 openwrt feeds 自带的核心库
rm -rf "$(FEEDS_WORK_DIR)"/packages/net/{xray-core,v2ray-geodata,sing-box,chinadns-ng,dns2socks,hysteria,ipt2socks,microsocks,naiveproxy,shadowsocks-libev,shadowsocks-rust,shadowsocksr-libev,simple-obfs,tcping,trojan-plus,tuic-client,v2ray-plugin,xray-plugin,geoview,shadow-tls}
git_package_clone https://github.com/Openwrt-Passwall/openwrt-passwall-packages passwall-packages
# 移除 openwrt feeds 过时的luci版本
rm -rf "$(FEEDS_WORK_DIR)"/luci/applications/luci-app-passwall
git_package_clone https://github.com/Openwrt-Passwall/openwrt-passwall passwall-luci

UPDATE_LANSPEED || exit 1
