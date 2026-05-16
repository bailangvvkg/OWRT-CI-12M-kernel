# Git稀疏克隆，只克隆指定目录到本地
function git_sparse_clone() {
	branch="$1" repourl="$2" && shift 2
	git clone --recursive --depth=1 -b $branch --single-branch --filter=blob:none --sparse $repourl
	repodir=$(echo $repourl | awk -F '/' '{print $(NF)}')
	cd $repodir && git sparse-checkout set $@
	mv -f $@ ../package
	cd .. && rm -rf $repodir
}

# 拉取Lucky最新版的源码
git clone https://github.com/sirpdboy/luci-app-lucky.git package/lucky
# git clone https://github.com/gdy666/luci-app-lucky package/lucky

#删除官方的默认插件
# rm -rf ../feeds/luci/applications/luci-app-{passwall*,mosdns,dockerman,dae*,bypass*}
# rm -rf ../feeds/packages/net/{shadowsocks-rust,shadowsocksr-libev,xray*,v2ray*,dae*,sing-box,geoview}
rm -rf ../feeds/luci/applications/luci-app-{dae*}
rm -rf ../feeds/packages/net/{dae*}

# QiuSimons luci-app-daed
git clone https://github.com/QiuSimons/luci-app-daed package/dae
mkdir -p Package/libcron && wget -O Package/libcron/Makefile https://raw.githubusercontent.com/immortalwrt/packages/refs/heads/master/libs/libcron/Makefile

# # luci-app-daed-next
# git clone https://github.com/sbwml/luci-app-daed-next package/daed-next

git_sparse_clone main https://github.com/kenzok8/small-package daed-next luci-app-daed-next gost luci-app-gost luci-app-adguardhome

git_sparse_clone main https://github.com/kiddin9/kwrt-packages natter2 luci-app-natter2 luci-app-cloudflarespeedtest luci-app-caddy openwrt-caddy luci-app-nginx-ha luci-app-nginx-manager luci-nginxer luci-app-nginx luci-app-wechatpush

# docker
git_sparse_clone main https://github.com/kiddin9/kwrt-packages luci-app-dockerman luci-app-docker docker-lan-bridge dockerd

# git clone --depth 1 --single-branch https://github.com/breeze303/openwrt-podman package/podman
git clone --depth 1 --single-branch --recursive https://github.com/Zerogiven-OpenWRT-Packages/luci-app-podman package/luci-app-podman
./scripts/feeds install -a

# wget "https://alist.lovelyy.eu.org/d/CloudFlareR2/immortalwrt/nginx/ngnx.conf?sign=FN_uiyymuja-Aj1z4I4Pevn3arIZXBdslq8Zjd_akdo=:0" -O ../feeds/packages/net/nginx-util/files/nginx.config
wget "https://r2.lovelyy.eu.org/raw/immortalwrt/nginx/ngnx.conf" -O ../feeds/packages/net/nginx-util/files/nginx.config
# echo 检测一下nginx的配置文件
# cat ../feeds/packages/net/nginx-util/files/nginx.config

# sed -i 's/^large_client_header_buffers .*/large_client_header_buffers 8 32k;/' ../feeds/packages/net/nginx-util/files/uci.conf.template
# 检测一下nginx包头是否由2个K改成8个32K
cat ../feeds/packages/net/nginx-util/files/uci.conf.template

# 查看在线端
git clone https://github.com/zzsj0928/luci-app-pushbot package/luci-app-pushbot

# 移除 openwrt feeds 自带的核心库
rm -rf feeds/packages/net/{xray-core,v2ray-geodata,sing-box,chinadns-ng,dns2socks,hysteria,ipt2socks,microsocks,naiveproxy,shadowsocks-libev,shadowsocks-rust,shadowsocksr-libev,simple-obfs,tcping,trojan-plus,tuic-client,v2ray-plugin,xray-plugin,geoview,shadow-tls}
git clone https://github.com/Openwrt-Passwall/openwrt-passwall-packages package/passwall-packages
# 移除 openwrt feeds 过时的luci版本
rm -rf feeds/luci/applications/luci-app-passwall
git clone https://github.com/Openwrt-Passwall/openwrt-passwall package/passwall-luci

# Lanspeed
git clone https://github.com/qimaoww/luci-app-lanspeed.git package/lanspeed