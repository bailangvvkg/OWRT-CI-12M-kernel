# 高质量<免费>交流群

[IPQ技术讨论群](https://qm.qq.com/q/v7nMhzB4oU)

# 高质量<付费>中转站

[LiBwrt-Ai](https://api.zipimg.cn/register?aff=FFPS3UMJ8HJD)

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

# 自动同步上游（保留本地定制）

仓库每天北京时间 02:30 由 `Upstream-Sync` 工作流自动合并 [VIKINGYFY/OpenWRT-CI](https://github.com/VIKINGYFY/OpenWRT-CI)：

- **冲突策略**：`.github/upstream-sync-owned.txt` 白名单内的文件（本仓库定制过的 CI/脚本/裁剪配置）冲突时保留本地版本；其余文件冲突时采用上游版本
- **自动校验**：合并后跑 `.github/scripts/validate-sync.sh`（YAML 解析、Shell 语法、`Config/*.txt` 引用、脚本是否存在、执行目录与相对路径是否一致、`WRT_*` 变量是否齐全）
- **推送规则**：无冲突且校验通过 → 直接推 `main`；有需复核的冲突或校验失败 → 推 `auto/upstream-sync` 分支并开 PR
- **私有代码**：`Scripts/PRIVATE.sh`、`Config/PRIVATE.txt` 永远不会被上游覆盖，插件与配置写在里面即可

手动触发：Actions → `Upstream-Sync` → Run workflow（可填上游分支，或勾选 `force_pr` 强制走 PR）。

# 每日自动流水线（北京时间）

每天自动跑一轮，链式串行，互不抢 runner：

| 时间 | 工作流 | 触发方式 | 作用 |
| --- | --- | --- | --- |
| 02:00 | `Release-Clean` | cron | 清理 7 天前的固件（Release + tag） |
| 02:30 | `Upstream-Sync` | cron | 同步上游（无冲突直推 main，有冲突走 PR） |
| 同步完成即开始 | `QCA-ALL` | `workflow_run` | 编译 IPQ60XX-WIFI-YES |
| QCA 完成后接上 | `MTK-ALL` | `workflow_run` | 编译 MEDIATEK-WIFI-YES |

- 两个编译不再用 `cron`，而是链在上一环节完成之后（`Upstream-Sync` → `QCA-ALL` → `MTK-ALL`）：既保证吃上游最新提交，也不会因为 GitHub 定时延迟/丢单而断档；前一环失败也会继续下一环（方便看出问题范围）
- 手动补跑：Actions → 选 `Upstream-Sync` / `QCA-ALL` / `MTK-ALL` 均可 → Run workflow
- 固件保留策略：只留最近 **7 天**，并额外保证每种配置里最新的 1 个永不删（避免连续编译失败时把可刷固件删空）；实现见 `.github/scripts/prune-releases.sh`
- 手动清理：Actions → `Release-Clean` → Run workflow（可改 `keep_days`，或勾 `dry_run` 先只预览不删）
- `Auto-Clean`（上游自带）会删除 **全部** Release，已停止定时，只作备用；如有需要请优先用 `Release-Clean`
- `QCB-ALL`（IPQ95XX）已手动禁用、定时也已注释，要启用就取消 `schedule` 注释（与上面两个错开）

# 目录简要说明

workflows——自定义CI配置

Scripts——自定义脚本

Config——自定义配置

## Star History

<a href="https://www.star-history.com/?repos=vikingyfy%2Fopenwrt-ci&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=vikingyfy/openwrt-ci&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=vikingyfy/openwrt-ci&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=vikingyfy/openwrt-ci&type=date&legend=top-left" />
 </picture>
</a>
