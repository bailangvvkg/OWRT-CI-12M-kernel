# 高质量<免费>交流群

[IPQ技术讨论群](https://qm.qq.com/q/v7nMhzB4oU)

# 高质量<付费>中转站

[LiBwrt-Ai](https://api.zipimg.cn/register?aff=LR7FSZ2ZZ4D3)

# 本地编译器

https://github.com/VIKINGYFY/OWRT-Tools.git

# 自用修改版插件

https://github.com/VIKINGYFY/packages.git

# OpenWRT-CI

官方版：

https://github.com/immortalwrt/immortalwrt.git

自用版：

https://github.com/VIKINGYFY/immortalwrt.git

# U-BOOT

高通版-沉心：

https://github.com/chenxin527/uboot-qsdk12.5-build.git

高通版-小猪：

https://github.com/1980490718/u-boot-2016.git

联发科-全新版：

https://github.com/VIKINGYFY/UBOOT-CI/releases

联发科-官方版：

https://drive.wrt.moe/uboot/mediatek

# 固件简要说明

固件每天早上5点自动编译。

固件信息里的时间为编译开始的时间，方便核对上游源码提交时间。

MEDIATEK系列、QUALCOMMAX系列、ROCKCHIP系列、X86系列。

# 纯 nftables 防火墙（Docker 原生 nft 后端）

自 2026-10 起，本仓库固件不再携带任何 iptables 兼容层：

- Docker 使用官方 feeds 的 dockerd（29.x，moby >= 28.4），通过 `Scripts/Packages.sh` 的 `PATCH_DOCKER_NATIVE_NFTABLES` 去掉 iptables/ip6tables/kmod-ipt-* 硬依赖，改为 `+firewall4 +kmod-br-netfilter`，并在 `/etc/config/dockerd` 里默认 `firewall_backend 'nftables'`（写入 daemon.json 的 `"firewall-backend": "nftables"`）。
- 升级/新刷均无感：固件内置 `/etc/uci-defaults/99-dockerd-native-nftables`，首次开机自动把 sysupgrade 保留的旧 `/etc/config/dockerd` 补写为 `firewall_backend 'nftables'` 并提交（哪怕之前是 iptables/nftables 混合规则，重启后即全部重建为纯 nft），无需任何手动操作。
- 代理插件均为 nft 模式：PassWall 透明代理钉死 nftables（fw4 下默认即 nft），OpenClash/Daed/HomeProxy 本身就是 nft/eBPF 实现。
- `WRT-CORE.yml` 编译后会扫描 manifest：任何 `iptables*/ip6tables*/xtables*` 前端混入即直接报错，确保 LuCI 防火墙页不再出现「检测到旧版规则」。
- 方案移植自 [minihuber/openwrt-7.X](https://cnb.cool/minihuber/openwrt-7.X)（已在其 x86 固件上长期验证）。

# 目录简要说明

workflows——自定义CI配置

Scripts——自定义脚本

Config——自定义配置

#
[![Stargazers over time](https://starchart.cc/VIKINGYFY/OpenWRT-CI.svg?variant=adaptive)](https://starchart.cc/VIKINGYFY/OpenWRT-CI)
