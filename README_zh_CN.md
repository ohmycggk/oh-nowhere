<div>

[**English**](README.md) | [**简体中文**](README_zh_CN.md) | [**Русский**](README_ru.md)

</div>

# oh-nowhere

[Nowhere](https://github.com/NodePassProject/Nowhere) 的一键安装、升级与管理脚本。

`oh-nowhere` 面向轻量 Linux 与 FreeBSD 服务器，简化 Nowhere Portal / Vector 部署：安装最新二进制、生成 Portal 或 Vector URL、写入系统服务、管理服务生命周期、启动只读 TUI，并输出客户端分享 URI。默认安装目标为 Nowhere **2.0+**；仍可用 1.x 维护旧节点。

## 功能特性

* Nowhere 一键安装（默认最新 2.x）
* 升级到上游最新版本
* 安装指定 release，含 1.x 维护版本
* 从 GitHub releases 交互式选择版本
* 交互式配置菜单
* 非交互 CLI，便于自动化部署
* systemd、OpenRC、FreeBSD rc.d 服务支持
* 支持 Debian、Ubuntu、Alpine，以及 FreeBSD（仅 2.0+）
* x86_64 / aarch64 架构检测
* Linux 自动选择 GNU libc / musl；FreeBSD 使用 `unknown-freebsd` 资产
* Portal 或 Vector 角色选择
* Portal 出站 SOCKS5、原生 Portal 链式转发（`next=`）、Vector 入站 SOCKS5
* 载体模式（`tcp` / `udp` / `mix`）：2.0 映射为端点路径，1.x 仍写 `net=`
* 独立 TCP/UDP 端口与 Morph（`--tcp-port` / `--udp-port` / `--morph`，Nowhere 2.0+）
* Vector 与 Portal `next` 支持混合载体策略（`tcp` / `udp` / `mix`）
* 导入 `nowhere://` 分享 URI（自动转为 `vector://`）
* 启动 Nowhere 只读 TUI（`nowhere tui`）
* 服务状态查看
* Portal 客户端分享 URI（`nowhere://`）
* 可选二维码支持
* 脚本界面支持中文、英文、俄文

## Nowhere 2.0（默认）与 1.x 维护

Nowhere **2.0** 是破坏性线协议变更：ALPN 固定为 `nw2`（忽略 `alpn=`），Portal 的 `net=` 被忽略（载体由端点路径决定），1.x 对端无法互通。本脚本默认安装 GitHub 最新 2.x。用 `--version v1.8.3` 或菜单项 12 保留 1.x 节点；默认升级目标不会改回 1.8。

* Portal 与客户端必须同主版本（`now/1` 与 `nw2` 不能互通）
* 交互式跨主版本升级/降级会先确认；`--upgrade` / `--install` 只打警告后继续
* `--tcp-port`、`--udp-port`、`--morph` 仅 2.0+（1.x profile 下传入会报错退出）
* 2.0 下 `--alpn` 警告并忽略（与 `--spec` / `--pool` 相同）
* 2.0 新配置默认 `up`/`down` 为 `tcp`，省略 mux（规范值 `0`）。1.x 保持默认 `udp`，且 `tcp/tcp` 仍自动补 `mux=1`
* 未拆端口时 `--port` 仍为共享默认（**2077**）
* FreeBSD 安装包仅 2.0+；在 FreeBSD 上安装 1.x 会直接拒绝。若某 2.x tag 没有 `nowhere-<arch>-unknown-freebsd.tar.gz`，下载失败会写明 tag 与期望文件名

`--net mix|tcp|udp` 仍作为操作员接口；2.0 不再写入 `net=`，而是映射为端点：

| `--net` / 端口 | Portal 监听 URL |
| -------------- | --------------- |
| `mix`（默认同端口） | `portal://KEY@:2077?tls=1`（TCP+UDP 同端口） |
| `tcp` | `portal://KEY@*/tcp:2077?tls=1` |
| `udp` | `portal://KEY@*/udp:2077?tls=1` |
| `--tcp-port 2006 --udp-port 2017` | `portal://KEY@*/tcp:2006/udp:2017?tls=1` |
| 两端口相同 | compact `KEY@:PORT` |

`--url` 仍可导入完整端点（含 `tcp4` / `udp6` 等地址族）。Vector 必须使用具体 `--host`（禁止 `*`）。

升到 2.x 时，已存 Portal 的 `net=tcp|udp` 转为 `@*/tcp:PORT` 或 `@*/udp:PORT`，`net=mix`（或缺失）保留 compact，去掉 `alpn=`，保留 `morph=`。降到 1.x 时反向映射，去掉 `morph=`，不写 `alpn`（1.x 默认 `now/1`）。TCP/UDP 端口不同无法无损还原：警告并折叠为单一端口（优先 TCP，否则 UDP）。

## Nowhere 1.5 / 1.6 / 1.7 / 1.8 说明

Nowhere **1.5** 引入新线协议并移除 Portal 的 `spec` 参数。Nowhere **1.6** 新增只读 TUI 与结构化本地遥测（仅 Linux）。线协议与 1.5.x 相同。Nowhere **1.7** 新增 Portal 原生链式转发（`next=`）、EVENT / 遥测 / TUI 中的上游 RTT，以及七跳转发预算。Nowhere **1.8** 以 TLS Mux（`mux=0|1`）取代原先 `tcp/tcp` 场景下的 `pool=<n>` 预热连接池，`pool` 参数已移除。Nowhere **1.8.3** 新增混合载体策略：Vector 与 Portal `next` 的 `up`/`down` 可为 `tcp`、`udp` 或 `mix`。

本脚本已适配上述版本：

* Portal URL 不再包含 `spec=`
* 支持自定义 `alpn`（默认 `now/1` 不写入 URL）
* 分享链接仍为带 `up` / `down` 载体的 `nowhere://` 导入 URI
* `vector://` 运行原生 SOCKS5 客户端；本脚本可生成并管理
* 粘贴或导入 `nowhere://` 时自动转为 `vector://`（缺 `socks=` 时自动补全）
* 升级时会从 `/etc/nowhere/url.conf` 剥离已废弃的 `spec=`
* 升级时会剥离已废弃的 `pool=`，并在 `tcp/tcp` 且缺少 `mux=` 时写入 `mux=1`
* 已存储的 `nowhere://` 运行 URL 会迁移为 `vector://`
* 菜单项 13 / `--tui` 启动只读仪表盘（1.7 显示上游 RTT）
* Portal 中继可通过 `next=` 原生链式转发（与出站 `socks=` 互斥）
* 原生链路上每个 Portal 须支持 Nowhere 1.7.0 HOPS 语义
* 1.5+ 线协议要求 Portal 与客户端一并升级
* Vector 与 Portal `next` 上游使用 `mux=0|1` 取代 `pool=`（1.8+）
* Vector 与 Portal `next` 的 `up`/`down` 支持 `tcp|udp|mix`（1.8.3+）；`mix/mix` 按流解析为 `tcp/tcp` 或 `udp/udp`
* 方向为 `tcp` 或 `mix` 时询问 Mux；`udp/udp` 不写入 `mux`（规范值为 `0`）
* Portal `net=mix` 的分享 URI 使用 `up=mix&down=mix`

## 支持系统

| 系统         | 初始化     | 包管理器 | 说明 |
| ------------ | ---------- | -------- | ---- |
| Debian       | systemd    | apt      | 1.x 与 2.x |
| Ubuntu       | systemd    | apt      | 1.x 与 2.x |
| Alpine Linux | OpenRC     | apk      | 1.x 与 2.x |
| FreeBSD      | rc.d       | pkg      | 仅 Nowhere 2.0+（`x86_64` / `aarch64`） |

支持架构：

* `x86_64`（FreeBSD 上为 `amd64`）
* `aarch64`（FreeBSD 上为 `arm64`）

近期 GNU Linux 构建需要 **glibc 2.39**（Ubuntu 24.04 / Debian 13）。Debian 12 等较旧 glibc 主机会自动改用 musl 构建。

## 快速开始

下载脚本：

```bash
curl -fsSL https://raw.githubusercontent.com/ohmycggk/oh-nowhere/main/oh-nowhere.sh -o oh-nowhere.sh
chmod +x oh-nowhere.sh
```

运行交互式管理器：

```bash
sudo ./oh-nowhere.sh --lang zh
```

菜单选项：

```text
1. 一键安装
2. 升级 Nowhere
3. 配置/重新配置服务
4. 启动服务
5. 停止服务
6. 重启服务
7. 查看状态
8. 卸载 Nowhere
9. 显示分享 URI
10. 安装二维码支持库
11. 切换语言
12. 安装指定版本
13. 启动 Nowhere TUI
14. 升级 oh-nowhere 管理脚本
0. 退出
```

## 一键安装

默认 Portal 参数安装：

```bash
sudo ./oh-nowhere.sh --install --lang zh
```

自定义 Portal 参数：

```bash
sudo ./oh-nowhere.sh \
  --install \
  --key change-me \
  --port 2077 \
  --net mix \
  --tls 1 \
  --lang zh
```

Nowhere 2.0 会生成 compact 双载体 Portal URL：

```text
portal://change-me@:2077?tls=1
```

加 `--version v1.8.3` 则保持 1.x 形式 `portal://change-me@:2077?tls=1&net=mix`。

独立 TCP/UDP 端口与 Morph（仅 2.0+）：

```bash
sudo ./oh-nowhere.sh \
  --install \
  --key change-me \
  --tcp-port 2006 \
  --udp-port 2017 \
  --morph 1 \
  --lang zh
```

```text
portal://change-me@*/tcp:2006/udp:2017?tls=1&morph=1
```

安装为 Vector（本地 SOCKS5 客户端）：

```bash
sudo ./oh-nowhere.sh \
  --install \
  --type vector \
  --key change-me \
  --host relay.example \
  --port 2077 \
  --up tcp \
  --down tcp \
  --socks 127.0.0.1:1080 \
  --lang zh
```

2.0 的 Vector URL 使用相同端点规则（同端口 mix 为 `relay.example:2077`，或 `relay.example/tcp:PORT`）。省略时 `up`/`down` 默认为 `tcp`，不会自动补 `mux`。1.x 的 `tcp/tcp` 仍会写入 `mux=1`。

安装混合载体 Vector（`mix/mix` 按流选择 `tcp/tcp` 或 `udp/udp`）：

```bash
sudo ./oh-nowhere.sh \
  --install \
  --type vector \
  --key change-me \
  --host relay.example \
  --port 2077 \
  --up mix \
  --down mix \
  --socks 127.0.0.1:1080 \
  --lang zh
```

导入分享 URI（`nowhere://` 自动转为 `vector://`）：

```bash
sudo ./oh-nowhere.sh \
  --config \
  --url 'nowhere://change-me@relay.example:2077?up=tcp&down=tcp&mux=1&sni=relay.example' \
  --socks 127.0.0.1:1080 \
  --lang zh
```

安装链式 Portal 中继（Nowhere 1.7+）：

```bash
sudo ./oh-nowhere.sh \
  --install \
  --type portal \
  --key relay-key \
  --port 2077 \
  --next 'origin-key@origin.example:2077' \
  --up tcp \
  --down tcp \
  --lang zh
```

2.0 生成：

```text
portal://relay-key@:2077?tls=1&next=origin-key@origin.example:2077&up=tcp&down=tcp
```

`next=` 也可使用显式路径，例如 `origin-key@origin.example/tcp:2077`。1.x 链式 Portal 仍写 `net=mix`，默认 `up`/`down` 为 `udp`。

## 安装指定版本

命令行安装指定上游版本：

```bash
sudo ./oh-nowhere.sh \
  --install \
  --version v2.0.0 \
  --key change-me \
  --port 2077 \
  --lang zh
```

保留或还原 1.x 节点：

```bash
sudo ./oh-nowhere.sh \
  --install \
  --version v1.8.3 \
  --key change-me \
  --port 2077 \
  --lang zh
```

升级或降级到指定版本：

```bash
sudo ./oh-nowhere.sh --upgrade --version v1.8.3 --lang zh
```

也可在菜单中选择 `12. 安装指定版本`，脚本会拉取 GitHub releases 列表；输入 `0` 选最新版，或输入对应编号。

## 服务角色

配置菜单项 3 可选择 `portal` / `vector`，或粘贴 `nowhere://` / `vector://` / `portal://` URL。

| 角色 | 运行 URL | 出站 |
| ---- | -------- | ---- |
| `portal` | `portal://key@:port?...` 或 `portal://key@*/tcp:port[/udp:port]?...` | 可选 **出站 SOCKS**（`socks=host:port`）或 **原生链式**（`next=key@host:port` 配合 `up`/`down`/`mux`/`sni`/`pin`）；二者互斥 |
| `vector` | `vector://key@portal-host:port?...` 或路径形式 `host/tcp:A/udp:B` | 必需 **入站** 监听（默认 `127.0.0.1:1080`） |

同一时刻仅一种角色生效（单一 `url.conf` / `nowhere` 服务），需切换时请重新配置。

### Portal 原生链式（1.7+）

中继 Portal 可直接将流量转发至下一跳 Portal，无需 loopback SOCKS5：

```text
portal://relay-key@:2077?next=origin-key@origin.example:2077&up=tcp&down=tcp
```

交互配置会询问出站模式：`none`、`socks` 或 `next`；选择 `next` 时继续配置上游载体及可选 `mux` / `sni` / `pin`。

可通过 `--url` 导入已有链式 Portal URL，或在配置菜单粘贴 `portal://...?next=...`；重新配置会保留 `next=` 及上游参数。

## TLS 模式（Portal）

### 自签 TLS

默认 `tls=1`。

```bash
sudo ./oh-nowhere.sh \
  --config \
  --type portal \
  --key change-me \
  --port 2077 \
  --net mix \
  --tls 1 \
  --lang zh
```

自签模式下客户端须跳过证书校验；分享 URI 不含 `sni`。

### 自定义证书

使用 `tls=2` 并提供证书与私钥；设置 `--host` 以便分享 URI 写入匹配的 `sni`：

```bash
sudo ./oh-nowhere.sh \
  --config \
  --type portal \
  --key change-me \
  --port 2077 \
  --net mix \
  --tls 2 \
  --cert /etc/nowhere/cert.pem \
  --keyfile /etc/nowhere/key.pem \
  --host relay.example \
  --lang zh
```

## 载体模式（Portal）

`--net` 用于声明 Portal 载体，默认仍为 `mix`。

| 模式  | 2.0 Portal 端点 | 1.x 查询参数 | 分享 URI 载体 |
| ----- | --------------- | ------------ | ------------- |
| `mix` | compact `KEY@:PORT`（TCP+UDP 同端口） | `net=mix` | `up=mix&down=mix` |
| `tcp` | `KEY@*/tcp:PORT` | `net=tcp` | `up=tcp&down=tcp`（1.x 另加 `mux=1`） |
| `udp` | `KEY@*/udp:PORT` | `net=udp` | `up=udp&down=udp` |

`--tcp-port` / `--udp-port`（仅 2.0+）覆盖 `--net` + `--port`：

* 两个都设且相同 → compact `HOST:PORT`
* 两个都设且不同 → `HOST/tcp:A/udp:B`
* 只设 `--tcp-port` → `HOST/tcp:A`
* 只设 `--udp-port` → `HOST/udp:B`
* 都未设 → 按 `--net` + `--port`

冲突直接失败：`--net tcp` 同时给 `--udp-port`、`--net udp` 同时给 `--tcp-port`，或 `up`/`down`/`mix` 选了端点未声明的载体。

## 客户端分享 URI

菜单项 9 / `--share` 在 Portal 角色下输出 `nowhere://` 导入 URI（Vector 不适用）。

示例：

```text
nowhere://change-me@203.0.113.10:2077?up=mix&down=mix#Nowhere-US-203
nowhere://change-me@relay.example/tcp:2006/udp:2017?up=mix&down=mix&morph=1#Nowhere-DE-45
nowhere://change-me@relay.example:2077?up=tcp&down=tcp&mux=1&sni=relay.example#Nowhere-DE-45
```

* 双载体 compact Portal → `host:port` 且 `up=mix&down=mix`；显式或拆端口使用路径形式
* 仅 TCP / 仅 UDP 端点分别分享 `up=tcp&down=tcp` 或 `up=udp&down=udp`；2.0 不会自动加 `mux=1`
* Portal `morph=1` 会写入分享 URI
* 主机优先 `/etc/nowhere/host.conf`（或 `--host`），否则使用检测到的公网 IP
* 节点名以 percent-encoded `#fragment` 附加；用 `--name` 设置（默认 `Nowhere-<国家>-<IP首段>`，存于 `/etc/nowhere/name.conf`）
* Portal 专用参数（`tls`、`crt`、`key`、`net`、`dial`、`rate`、`etar`、`log`、出站 `socks`、**`next`**）不会写入分享 URI
* 链式 Portal：客户端连接本中继入口；`next=` 仅服务端配置
* 1.x 下非默认 `alpn` 会复制到分享 URI；2.0 分享 URI 不含 `alpn`
* Vector 实例下 `--share` 输出当前 `vector://` 运行 URL

将 `nowhere://` 分享 URI 粘贴到配置 / `--url` 可在本地运行 Vector。

## Nowhere TUI

菜单项 13 / `--tui` 执行：

```bash
nowhere tui
```

仪表盘发现本地 Portal/Vector 实例并显示实时指标；Nowhere 1.7+ 含上游 RTT（`ping_ms`）。只读，不启停或改配置。

## CLI 用法

```bash
sudo ./oh-nowhere.sh [选项]
```

### 选项

| 选项                        | 说明 |
| --------------------------- | ---- |
| `-i`, `--install`           | 一键安装、升级并启动 |
| `-u`, `--upgrade`           | 升级 Nowhere |
| `-c`, `--config`            | 配置服务 |
| `-s`, `--status`            | 查看状态 |
| `-q`, `--share`             | 显示分享 URI |
| `--tui`                     | 启动 Nowhere TUI |
| `--upgrade-script`          | 从 GitHub 升级本 oh-nowhere 脚本 |
| `--uninstall`               | 卸载 Nowhere |
| `--type <portal\|vector>`   | 服务角色，默认 `portal` |
| `--url <uri>`               | 导入 `portal://`、`vector://` 或 `nowhere://` |
| `-k`, `--key <密钥>`        | 共享密钥 |
| `-p`, `--port <端口>`       | 监听端口，默认 `2077` |
| `--alpn <alpn>`             | 1.x TLS/QUIC ALPN（默认 `now/1` 不写入）；2.0 忽略（固定 `nw2`） |
| `--host <hostname>`         | Portal：分享/SNI 主机；Vector：Portal 主机 |
| `--name <名称>`             | 分享 URI 的 `#` 节点名 |
| `--net <mix\|tcp\|udp>`     | 载体模式（1.x 写 `net=`；2.0 映射为端点路径；默认 `mix`） |
| `--tcp-port <端口>`         | TLS/TCP 端口（Nowhere 2.0+，可与 UDP 不同） |
| `--udp-port <端口>`         | QUIC/UDP 端口（Nowhere 2.0+，可与 TCP 不同） |
| `--morph <0\|1>`            | TLS/QUIC 线形伪装（Nowhere 2.0+；默认 `0`，不写入） |
| `--tls <1\|2>`              | Portal TLS 模式，默认 `1` |
| `--cert <路径>`             | `tls=2` 时证书路径 |
| `--keyfile <路径>`          | `tls=2` 时私钥路径 |
| `--socks <地址>`            | Portal 出站或 Vector 入站 SOCKS |
| `--next <key@host:port>`    | Portal 原生上游（与 `--socks` 互斥） |
| `--up <tcp\|udp\|mix>`      | 上行载体（2.x 默认 `tcp`，1.x 默认 `udp`） |
| `--down <tcp\|udp\|mix>`    | 下行载体（2.x 默认 `tcp`，1.x 默认 `udp`） |
| `--mux <0\|1>`              | 方向为 `tcp` 或 `mix` 时的 TLS Mux（2.x 省略/默认 `0`；1.x 的 `tcp/tcp` 默认 `1`） |
| `--sni <名称>`              | 证书名（Vector 或 Portal `next` 上游） |
| `--pin <sha256>`            | 证书固定（Vector 或 Portal `next` 上游） |
| `-v`, `--version <版本>`    | 安装指定 release（例如 `v2.0.0` 或 `v1.8.3`） |
| `-l`, `--lang <en\|zh\|ru>` | 脚本语言，默认 `zh` |
| `-h`, `--help`              | 显示帮助 |

`--spec` 仍接受但会警告并忽略（Nowhere 1.5 已移除）。
`--pool` 仍接受但会警告并忽略（Nowhere 1.8 已移除，请改用 `--mux`）。
`--alpn` 在 Nowhere 2.0 下会警告并忽略（固定 ALPN `nw2`）。

## 常用命令

查看状态：

```bash
sudo ./oh-nowhere.sh --status --lang zh
```

升级：

```bash
sudo ./oh-nowhere.sh --upgrade --lang zh
```

安装指定版本：

```bash
sudo ./oh-nowhere.sh --install --version v1.8.3 --lang zh
```

重新配置：

```bash
sudo ./oh-nowhere.sh --config --lang zh
```

显示分享 URI：

```bash
sudo ./oh-nowhere.sh --share --lang zh
```

启动 TUI：

```bash
sudo ./oh-nowhere.sh --tui --lang zh
```

升级管理脚本：

```bash
sudo ./oh-nowhere.sh --upgrade-script --lang zh
```

卸载：

```bash
sudo ./oh-nowhere.sh --uninstall --lang zh
```

## 安装文件

脚本可能创建或管理：

```text
/usr/local/bin/nowhere
/usr/local/bin/nowhere-launch.sh
/etc/nowhere/url.conf
/etc/nowhere/host.conf
/etc/nowhere/name.conf
/etc/systemd/system/nowhere.service
/etc/init.d/nowhere
/usr/local/etc/rc.d/nowhere
```

Portal 或 Vector URL 存于：

```text
/etc/nowhere/url.conf
```

分享 / SNI 公网主机名（Portal）或记忆的 Portal 主机：

```text
/etc/nowhere/host.conf
```

分享 URI 的 `#fragment` 节点名：

```text
/etc/nowhere/name.conf
```

启动器读取 `url.conf` 启动 Nowhere；若仍为 `nowhere://` 会自动迁移为 `vector://`。

## systemd 管理

Debian / Ubuntu 安装 `nowhere.service` 单元。

```bash
sudo systemctl status nowhere
sudo systemctl restart nowhere
sudo systemctl stop nowhere
sudo systemctl start nowhere
```

日志：

```bash
sudo journalctl -u nowhere -f
```

## OpenRC 管理

Alpine 安装 OpenRC 服务。

```bash
sudo rc-service nowhere status
sudo rc-service nowhere restart
sudo rc-service nowhere stop
sudo rc-service nowhere start
```

开机自启：

```bash
sudo rc-update add nowhere default
```

## FreeBSD rc.d 管理

FreeBSD（Nowhere 2.0+）安装 `/usr/local/etc/rc.d/nowhere`，并用 `sysrc nowhere_enable=YES` 启用。配置仍使用 `/etc/nowhere`（与 Linux 一致）。启动器 shebang 为 `#!/usr/bin/env bash`（FreeBSD 的 bash 通常在 `/usr/local/bin/bash`）。

```bash
sudo service nowhere status
sudo service nowhere restart
sudo service nowhere stop
sudo service nowhere start
```

开机启用或关闭：

```bash
sudo sysrc nowhere_enable=YES
sudo sysrc -x nowhere_enable
```

## 二维码支持

Debian/Ubuntu 使用 `qrencode`；Alpine 使用 `python3` + `py3-qrcode`；FreeBSD 使用 `libqrencode`（`pkg install libqrencode`）。

安装后：

```bash
sudo ./oh-nowhere.sh --share --lang zh
```

## 安全说明

* 使用强共享密钥。
* 勿公开 Portal URL。
* 长期公网服务建议 `tls=2` + 有效证书 + `--host` 配置 SNI。
* `tls=1` 时客户端须跳过证书校验。
* Vector 入站 SOCKS 若暴露于本机以外，须配合认证与网络策略。
* 生产环境运行前请审阅脚本。

## 上游项目

本仓库仅提供安装与管理脚本。Nowhere 由 NodePassProject 维护：

```text
https://github.com/NodePassProject/Nowhere
```

## 许可证

遵循本仓库声明的许可证；再分发或修改前请查阅 LICENSE 文件。
