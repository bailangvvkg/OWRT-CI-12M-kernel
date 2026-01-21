#!/bin/bash

#移除luci-app-attendedsysupgrade
sed -i "/attendedsysupgrade/d" $(find ./feeds/luci/collections/ -type f -name "Makefile")
#修改默认主题
sed -i "s/luci-theme-bootstrap/luci-theme-$WRT_THEME/g" $(find ./feeds/luci/collections/ -type f -name "Makefile")
#修改immortalwrt.lan关联IP
sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" $(find ./feeds/luci/modules/luci-mod-system/ -type f -name "flash.js")
#添加编译日期标识
sed -i "s/(\(luciversion || ''\))/(\1) + (' \/ $WRT_MARK-$WRT_DATE')/g" $(find ./feeds/luci/modules/luci-mod-status/ -type f -name "10_system.js")

WIFI_SH=$(find ./target/linux/{mediatek/filogic,qualcommax}/base-files/etc/uci-defaults/ -type f -name "*set-wireless.sh" 2>/dev/null)
WIFI_UC="./package/network/config/wifi-scripts/files/lib/wifi/mac80211.uc"
if [ -f "$WIFI_SH" ]; then
	#修改WIFI名称
	sed -i "s/BASE_SSID='.*'/BASE_SSID='$WRT_SSID'/g" $WIFI_SH
	#修改WIFI密码
	sed -i "s/BASE_WORD='.*'/BASE_WORD='$WRT_WORD'/g" $WIFI_SH
elif [ -f "$WIFI_UC" ]; then
	#修改WIFI名称
	sed -i "s/ssid='.*'/ssid='$WRT_SSID'/g" $WIFI_UC
	#修改WIFI密码
	sed -i "s/key='.*'/key='$WRT_WORD'/g" $WIFI_UC
	#修改WIFI地区
	sed -i "s/country='.*'/country='CN'/g" $WIFI_UC
	#修改WIFI加密
	sed -i "s/encryption='.*'/encryption='psk2+ccmp'/g" $WIFI_UC
fi

CFG_FILE="./package/base-files/files/bin/config_generate"
#修改默认IP地址
sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" $CFG_FILE
#修改默认主机名
sed -i "s/hostname='.*'/hostname='$WRT_NAME'/g" $CFG_FILE

#配置文件修改
echo "CONFIG_PACKAGE_luci=y" >> ./.config
echo "CONFIG_LUCI_LANG_zh_Hans=y" >> ./.config
echo "CONFIG_PACKAGE_luci-theme-$WRT_THEME=y" >> ./.config
echo "CONFIG_PACKAGE_luci-app-$WRT_THEME-config=y" >> ./.config

#手动调整的插件
if [ -n "$WRT_PACKAGE" ]; then
	echo -e "$WRT_PACKAGE" >> ./.config
fi

#高通平台调整
DTS_PATH="./target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/"
if [[ "${WRT_TARGET^^}" == *"QUALCOMMAX"* ]]; then
	#取消nss相关feed
	echo "CONFIG_FEED_nss_packages=n" >> ./.config
	echo "CONFIG_FEED_sqm_scripts_nss=n" >> ./.config
	#开启sqm-nss插件
	echo "CONFIG_PACKAGE_luci-app-sqm=y" >> ./.config
	echo "CONFIG_PACKAGE_sqm-scripts-nss=y" >> ./.config
	#设置NSS版本
	echo "CONFIG_NSS_FIRMWARE_VERSION_11_4=n" >> ./.config
	if [[ "${WRT_CONFIG,,}" == *"ipq50"* ]]; then
		echo "CONFIG_NSS_FIRMWARE_VERSION_12_2=y" >> ./.config
	else
		echo "CONFIG_NSS_FIRMWARE_VERSION_12_5=y" >> ./.config
	fi
	#无WIFI配置调整Q6大小
	if [[ "${WRT_CONFIG,,}" == *"wifi"* && "${WRT_CONFIG,,}" == *"no"* ]]; then
		find $DTS_PATH -type f ! -iname '*nowifi*' -exec sed -i 's/ipq\(6018\|8074\).dtsi/ipq\1-nowifi.dtsi/g' {} +
		echo "qualcommax set up nowifi successfully!"
	fi
	#其他调整
	echo "CONFIG_PACKAGE_kmod-usb-serial-qualcomm=y" >> ./.config
fi

# 编译器优化
if [[ $WRT_TARGET != *"X86"* ]]; then
	echo "CONFIG_TARGET_OPTIONS=y" >> ./.config
	# echo "CONFIG_TARGET_OPTIMIZATION=\"-O3 -pipe -march=armv8-a+crypto+crc -mcpu=cortex-a53+crypto+crc -mtune=cortex-a53\"" >> ./.config
    # 均衡
	# echo "CONFIG_TARGET_OPTIMIZATION=\"-O2 -pipe -march=armv8-a+crypto+crc -mcpu=cortex-a53+crypto+crc -mtune=cortex-a53\"" >> ./.config
    # - -Ofast ：比 -O3 更激进的优化级别，自动启用 -ffast-math 等选项
    # - -ffast-math （Ofast 包含）：激进的浮点优化，忽略部分 IEEE 754 标准
    # - -funroll-all-loops ：比 -funroll-loops 更激进，展开所有循环
    # - -fipa-pta ：过程间指针分析，优化指针使用
    # - -fallow-store-data-races ：允许存储操作重排序，可能提高单线程性能
    # - -funsafe-loop-optimizations ：激进的循环优化，可能改变程序行为
    # echo "CONFIG_TARGET_OPTIMIZATION="-Ofast -pipe -flto -funroll-all-loops -fpeel-loops -ftree-vectorize -fgcse-after-reload -fipa-pta -fallow-store-data-races -funsafe-loop-optimizations -march=armv8-a+crypto+crc -mcpu=cortex-a53+crypto+crc -mtune=cortex-a53"" >> ./.config
    # 1. **向量优化**
	# 	- `-mprefer-vector-width=128` - 优先使用128位向量宽度，充分利用Cortex-A53的NEON单元
	# 2. **链接与符号优化**
	# 	- `-fno-semantic-interposition` - 禁止语义插入，减少动态链接开销
	# 	- `-fno-plt` - 禁止使用PLT（过程链接表），提高函数调用速度
	# 3. **浮点优化**
	# 	- `-ffp-contract=fast` - 快速浮点收缩，允许更多浮点表达式合并
	# 	- `-ffinite-math-only` - 假设所有浮点运算结果都是有限的
	# 	- `-fno-signed-zeros` - 忽略有符号零，允许更多优化
	# 	- `-fno-trapping-math` - 假设浮点运算不会产生陷阱
	# 	- `-fassociative-math` - 允许浮点运算重新关联
	# 	- `-freciprocal-math` - 允许使用倒数近似值
	# 	- `-fno-rounding-math` - 忽略舍入语义
	# 	- `-fno-math-errno` - 禁用数学错误号，减少错误检查
	# 4. **对齐优化**
	# 	- `-falign-functions=32` - 函数对齐到32字节
	# 	- `-falign-labels=32` - 标签对齐到32字节
	# 	- `-falign-loops=32` - 循环对齐到32字节
	# 	- `-falign-jumps=32` - 跳转对齐到32字节
	# 5. **高级优化**
	# 	- `-fdevirtualize-at-ltrans` - 在链接时转换阶段进行去虚拟化
	# 	- `-fipa-cp-clone` - 过程间复制传播克隆
	# 	- `-floop-interchange` - 循环交换，优化内存访问模式
	# 	- `-floop-unroll-and-jam` - 循环展开和合并
	# 	- `-floop-nest-optimize` - 循环嵌套优化
	# 	- `-fgraphite-identity` - Graphite 身份优化
	# 	- `-fopenmp-simd` - 启用 OpenMP SIMD 支持
	# 6. **性能与安全性权衡**
	# 	- `-mbranch-protection=none` - 禁用分支保护（提高性能但降低安全性）
	# 	- `-fomit-frame-pointer` - 省略帧指针，释放一个通用寄存器
	# 	- `-fno-unwind-tables` - 禁用 unwind 表
	# 	- `-fno-asynchronous-unwind-tables` - 禁用异步 unwind 表
	echo "CONFIG_TARGET_OPTIMIZATION="-Ofast -pipe -flto -funroll-all-loops -fpeel-loops -ftree-vectorize -fgcse-after-reload -fipa-pta -fallow-store-data-races -funsafe-loop-optimizations -march=armv8-a+crypto+crc -mcpu=cortex-a53+crypto+crc -mtune=cortex-a53 -mprefer-vector-width=128 -fno-semantic-interposition -ffp-contract=fast -falign-functions=32 -falign-labels=32 -falign-loops=32 -falign-jumps=32 -fdevirtualize-at-ltrans -fipa-cp-clone -fno-plt -mbranch-protection=none -fomit-frame-pointer -fno-unwind-tables -fno-asynchronous-unwind-tables -ffinite-math-only -fno-signed-zeros -fno-trapping-math -fassociative-math -freciprocal-math -fno-rounding-math -fno-math-errno -floop-interchange -floop-unroll-and-jam -floop-nest-optimize -fgraphite-identity -fopenmp-simd"" >> ./.config
fi


function cat_ebpf_config() {
#ebpf相关
  cat >> .config <<EOF
# daed 推荐的 eBPF 配置
# 开启开发模式，允许更多调试信息 可选，便于调试但增加固件体积
CONFIG_DEVEL=y
# 生成内核调试信息 可选，daed可能需要
CONFIG_KERNEL_DEBUG_INFO=y
# 不使用简化调试信息 配合DEBUG_INFO=y使用
CONFIG_KERNEL_DEBUG_INFO_REDUCED=n
# 开启BTF支持 必选 ，现代eBPF程序依赖BTF
CONFIG_KERNEL_DEBUG_INFO_BTF=y
开启cgroups支持 必选 ，cgroup BPF依赖
CONFIG_KERNEL_CGROUPS=y
# 开启cgroup BPF挂载点 必选 ，daed可能使用cgroup BPF
CONFIG_KERNEL_CGROUP_BPF=y
开启BPF事件支持 可选，用于BPF程序事件监控
CONFIG_KERNEL_BPF_EVENTS=y
# 使用主机BPF工具链 建议开启，提高编译效率
CONFIG_BPF_TOOLCHAIN_HOST=y
# 开启XDP套接字 必选 ，daed可能使用XDP加速
CONFIG_KERNEL_XDP_SOCKETS=y
# XDP套接字诊断模块 可选，用于调试XDP套接字
CONFIG_PACKAGE_kmod-xdp-sockets-diag=y

# 为了完整支持daed的eBPF功能，建议补充以下配置：
# 启用BPF JIT编译器（显著提升eBPF性能）
# CONFIG_KERNEL_BPF_JIT=y
# CONFIG_KERNEL_HAVE_BPF_JIT=y
# # 启用BPF LSM（可选，取决于daed是否使用）
# CONFIG_KERNEL_SECURITY_BPF=y
# # 启用BPF系统调用
# CONFIG_KERNEL_BPF_SYSCALL=y
# # 启用BPF挂载点
# CONFIG_KERNEL_BPF_LSM=y
# CONFIG_KERNEL_BPF_PRELOAD=y
# # 启用XDP支持（完整）
# CONFIG_KERNEL_XDP=y
# CONFIG_PACKAGE_kmod-ebpf-core=y
# CONFIG_PACKAGE_kmod-ebpf-filter=y
# CONFIG_PACKAGE_kmod-ebpf-testing=y
# # 启用libbpf库（用户空间eBPF支持）
# CONFIG_PACKAGE_libbpf=y
# CONFIG_PACKAGE_libbpf-dev=y
# # 启用cgroup相关BPF功能
# CONFIG_KERNEL_CGROUP_BPF=y
# CONFIG_KERNEL_CGROUP_NET_PRIO=y
# CONFIG_KERNEL_CGROUP_NET_CLASSID=y
EOF
}
cat_ebpf_config

# BPFtool 支持 eBPF 程序 反汇编（disassembly）
echo "CONFIG_PACKAGE_bpftool-full=y" >> ./.config

function set_kernel_size() {
  #修改jdc ax1800 pro 的内核大小为12M
  image_file='./target/linux/qualcommax/image/ipq60xx.mk'
  sed -i "/^define Device\/jdcloud_re-ss-01/,/^endef/ { /KERNEL_SIZE := 6144k/s//KERNEL_SIZE := 12288k/ }" $image_file
  sed -i "/^define Device\/jdcloud_re-cs-02/,/^endef/ { /KERNEL_SIZE := 6144k/s//KERNEL_SIZE := 12288k/ }" $image_file
  sed -i "/^define Device\/jdcloud_re-cs-07/,/^endef/ { /KERNEL_SIZE := 6144k/s//KERNEL_SIZE := 12288k/ }" $image_file
  sed -i "/^define Device\/redmi_ax5-jdcloud/,/^endef/ { /KERNEL_SIZE := 6144k/s//KERNEL_SIZE := 12288k/ }" $image_file
  sed -i "/^define Device\/linksys_mr/,/^endef/ { /KERNEL_SIZE := 8192k/s//KERNEL_SIZE := 12288k/ }" $image_file
  sed -i "/^define Device\/link_nn6000-v1/,/^endef/ { /KERNEL_SIZE := 6144k/s//KERNEL_SIZE := 12288k/ }" $image_file
}
set_kernel_size

# #修复dropbear
sed -i "s/Interface/DirectInterface/" ./package/network/services/dropbear/files/dropbear.config

# 想要剔除的
# echo "CONFIG_PACKAGE_htop=n" >> ./.config
# echo "CONFIG_PACKAGE_iperf3=n" >> ./.config
echo "CONFIG_PACKAGE_luci-app-wolplus=n" >> ./.config
echo "CONFIG_PACKAGE_luci-app-tailscale=n" >> ./.config
echo "CONFIG_PACKAGE_luci-app-advancedplus=n" >> ./.config
echo "CONFIG_PACKAGE_luci-theme-kucat=n" >> ./.config

# Docker --cpuset-cpus="0-1"
echo "CONFIG_CGROUPS=y" >> ./.config
echo "CONFIG_CPUSETS=y" >> ./.config

# bash命令兼容工具
echo "CONFIG_PACKAGE_bash=y" >> ./.config
# 可以让FinalShell查看文件列表并且ssh连上不会自动断开
echo "CONFIG_PACKAGE_openssh-sftp-server=y" >> ./.config
# 解析、查询、操作和格式化 JSON 数据
echo "CONFIG_PACKAGE_jq=y" >> ./.config
# base64 修改码云上的内容 需要用到
echo "CONFIG_PACKAGE_coreutils-base64=y" >> ./.config
echo "CONFIG_PACKAGE_coreutils=y" >> ./.config
# 简单明了的系统资源占用查看工具
echo "CONFIG_PACKAGE_btop=y" >> ./.config
# 多网盘存储
# echo "CONFIG_PACKAGE_luci-app-alist=y" >> ./.config
echo "CONFIG_PACKAGE_luci-app-openlist2=y" >> ./.config
# 强大的工具(需要添加源或git clone)
echo "CONFIG_PACKAGE_luci-app-lucky=y" >> ./.config
# 网络通信工具
echo "CONFIG_PACKAGE_curl=y" >> ./.config
echo "CONFIG_PACKAGE_tcping=y" >> ./.config
# BBR 拥塞控制算法(终端侧) + CAKE 一种现代化的队列管理算法(路由侧)
echo "CONFIG_PACKAGE_kmod-tcp-bbr=y" >> ./.config
# echo "CONFIG_DEFAULT_tcp_bbr=y" >> ./.config
# echo "CONFIG_DEFAULT_tcp_cubic=y" >> ./.config
# 更改默认的拥塞控制算法为cubic
echo "CONFIG_DEFAULT_tcp_cubic=y" >> ./.config
# 磁盘管理
echo "CONFIG_PACKAGE_luci-app-diskman=y" >> ./.config
echo "CONFIG_PACKAGE_cfdisk=y" >> ./.config
# docker(只能集成)
echo "CONFIG_PACKAGE_luci-app-dockerman=y" >> ./.config
# Podman
# echo "CONFIG_PACKAGE_luci-app-podman=y" >> ./.config
# qBittorrent
# echo "CONFIG_PACKAGE_luci-app-qbittorrent=y" >> ./.config
# 强大的工具Lucky大吉(需要添加源或git clone)
echo "CONFIG_PACKAGE_luci-app-lucky=y" >> ./.config
# Caddy
# echo "CONFIG_PACKAGE_luci-app-caddy=y" >> ./.config
# V2rayA
# echo "CONFIG_PACKAGE_luci-app-v2raya=y" >> ./.config
# echo "CONFIG_PACKAGE_v2ray-core=y" >> ./.config
# echo "CONFIG_PACKAGE_v2ray-geoip=y" >> ./.config
# echo "CONFIG_PACKAGE_v2ray-geosite=y" >> ./.config
# Natter2 报错
# echo "CONFIG_PACKAGE_luci-app-natter2=y" >> ./.config
# 文件管理器
echo "CONFIG_PACKAGE_luci-app-filemanager=y" >> ./.config
# 基于Golang的多协议转发工具
echo "CONFIG_PACKAGE_luci-app-gost=y" >> ./.config
# Git
echo "CONFIG_PACKAGE_git-http=y" >> ./.config
# Nginx替换Uhttpd
echo "CONFIG_PACKAGE_nginx-mod-luci=y" >> ./.config
# Nginx的图形化界面
echo "CONFIG_PACKAGE_luci-app-nginx=y" >> ./.config
# HAProxy 比Nginx更强大的反向代理服务器
# echo "CONFIG_PACKAGE_luci-app-haproxy-tcp=y" >> ./.config
# Adguardhome去广告
echo "CONFIG_PACKAGE_luci-app-adguardhome=y" >> ./.config
# cloudflre速度筛选器
# echo "CONFIG_PACKAGE_luci-app-cloudflarespeedtest=y" >> ./.config
# OpenClash
# echo "CONFIG_PACKAGE_luci-app-openclash=y" >> ./.config
# nfs-kernel-server共享
# echo "CONFIG_PACKAGE_nfs-kernel-server=y" >> ./.config
# Kiddin9 luci-app-nfs
# echo "CONFIG_PACKAGE_luci-app-nfs=y" >> ./.config
# zoneinfo-asia tzdata（时区数据库）的一部分，只包含亚洲相关的时区数据 zoneinfo-all全部时区（体积较大，不推荐在嵌入设备）
echo "CONFIG_PACKAGE_zoneinfo-all=y" >> ./.config
# Caddy
# echo "CONFIG_PACKAGE_luci-app-caddy=y" >> ./.config
# Openssl
# echo "CONFIG_PACKAGE_openssl-util=y" >> ./.config
# dig命令
echo "CONFIG_PACKAGE_bind-dig=y" >> ./.config
# ss 网络抓包工具
echo "CONFIG_PACKAGE_ss=y" >> ./.config
# coreutils-date让你的时间计步器精确到纳秒
echo "CONFIG_PACKAGE_coreutils-date=y" >> ./.config
# 查看在线端
# echo "CONFIG_PACKAGE_luci-app-serverchand=y" >> ./.config
echo "CONFIG_PACKAGE_luci-app-pushbot=y" >> ./.config
# 主题
echo "CONFIG_PACKAGE_luci-app-argon-config=y" >> ./.config