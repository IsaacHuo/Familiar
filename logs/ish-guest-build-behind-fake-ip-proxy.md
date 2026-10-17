# fake-IP 代理下无法在 iSH guest 内联网构建 rootfs

## 症状

`Scripts/prepare-ish-rootfs.sh` 中 guest 内 `apk update` 报 `Connection refused`，pip 全部失败；guest 内 `nslookup` 返回 `127.0.0.1` 为 DNS、域名解析成 `198.18.x.x`。宿主 `curl` 一切正常。

## 根因

宿主（macOS）跑着 fake-IP 模式的透明代理：系统 DNS 返回 `198.18.0.0/15` 的假地址，只有宿主进程经 TUN 才能连上。iSH guest 的 socket 直连假 IP，代理不认；而 guest 默认 `/etc/resolv.conf` 指向宿主解析器，同样拿到假 IP。

## 修复

构建时给 guest 换真实 DNS（`FAMILIAR_GUEST_DNS="223.5.5.5 119.29.29.29" Scripts/prepare-ish-rootfs.sh`），脚本在打包前恢复原 `resolv.conf`。同时：

- `FAMILIAR_ALPINE_MIRROR` / `FAMILIAR_PIP_INDEX_URL` 可切到国内镜像（TUNA），host 下载 75 MiB 的字体包从 4 分钟超时降到 8 秒。
- iSH 命令行 builder **不传递 guest 退出码**（总是 exit 0），脚本必须用输出标记（`FAMILIAR_APK_READY` 等）显式校验每一步。

## 备注

宿主 `git`/`raw.githubusercontent.com` 可能被代理策略拒绝（HTTP 000）：字体等构建资产要选可达来源（Alpine 镜像里的 `font-noto-cjk` + `fontTools` 子集化），不要依赖 GitHub raw。
