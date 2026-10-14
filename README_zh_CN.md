<div>

[**English**](README.md) | [**简体中文**](README_zh_CN.md) | [**Русский**](README_ru.md)

</div>

# oh-nowhere

[Nowhere](https://github.com/NodePassProject/Nowhere) 的一键安装、升级与管理脚本。

`oh-nowhere` 面向轻量 Linux 与 FreeBSD 服务器，用来安装二进制、生成 Portal、Vector 或 Egress URL、写入系统服务、管理服务生命周期，并输出客户端分享 URI。全新安装跟随最新稳定版（Nowhere 3 / nw3）。已经装好的 2.x 节点留在 2.x 升级，不会自行跨到 nw3。不带版本号时，1.x 会升到最新 2.x；要留在 1.x，用 `--version` 或菜单项 3。

## 功能特性

* 一键安装最新稳定版（nw3）；已安装的 2.x 留在 2.x 升级，不自行跨到 nw3
* 安装指定 release，也可从 GitHub releases 交互选择
* 交互式菜单与非交互 CLI
* 按字段修改当前配置，保存后自动重启；配置时检测端口占用
* systemd、OpenRC、FreeBSD rc.d
* Debian、Ubuntu、Alpine，以及 FreeBSD（仅 Nowhere 2.0+）
* x86_64 / aarch64；Linux 自动选择 GNU libc 或 musl
* Portal、Vector，以及 nw3 的 Egress
* Portal 分享 URI（`nowhere://`）与可选二维码
* 2.x 只读 TUI；nw3 改为 `nowhere status`
* 脚本界面支持中文、英文、俄文

## 支持系统

| 系统         | 初始化  | 包管理器 | 说明 |
| ------------ | ------- | -------- | ---- |
| Debian       | systemd | apt      | 1.x、2.x 与 3.x |
| Ubuntu       | systemd | apt      | 1.x、2.x 与 3.x |
| Alpine Linux | OpenRC  | apk      | 1.x、2.x 与 3.x |
| FreeBSD      | rc.d    | pkg      | 仅 Nowhere 2.0+（`x86_64` / `aarch64`） |

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
3. 安装指定版本

4. 配置/重新配置服务
5. 修改当前配置

6. 启动服务
7. 停止服务
8. 重启服务
9. 查看状态
10. TUI / 实例状态

11. 显示分享 URI
12. 安装二维码支持库

13. 切换语言
14. 升级 oh-nowhere 管理脚本
15. 卸载 Nowhere
0. 退出
```

菜单头部会显示 oh-nowhere 脚本版本、已安装的 Nowhere 版本和服务运行状态（运行中 / 已停止 / 未安装）。

## 默认安装（Nowhere 3）

不带 `--version` 的全新安装使用 nw3。本机已经装有 Nowhere 时，`--install` 转入升级，并遵守下文「升级与跨线」的目标版本规则。三种角色的密钥都是恰好 32 位小写十六进制（优先 `nowhere generate-key`，否则取 `/dev/urandom`）。`morph` 默认为 `1`，并且总会写入 URL。`tls` 只接受 `1` 或 `2`。Portal 通配主机写成 `*`。

nw3 二进制会静默忽略不认识的参数。脚本在写入前校验。二进制已是 nw3，而 Portal 或 Vector 的 `url.conf` 仍含 `up`、`down`、`mux`、`next`、`socks`、`net`、`alpn`、`log`、`pool`、`spec` 时，启动器直接拒绝启动。

### Portal

```bash
sudo ./oh-nowhere.sh --install --lang zh
```

默认同端口 `mix`。URL 形态如下（密钥由脚本生成，下面这串只是 32 位的例子）：

```text
portal://a1b2c3d4e5f60718293a4b5c6d7e8f90@*:2077?tls=1&out=direct&morph=1
```

`*:2077` 表示 TCP 与 UDP 监听同一端口。出口用 `--out`：

| `--out` | 运行 URL 中的出口 |
| ------- | ----------------- |
| `direct`（默认） | `out=direct` |
| `socks` | `out=127.0.0.1:1080`（地址来自 `--socks`，可带 `user:pass@`） |
| `egress` | `out=egress`（端点必须包含 UDP） |

`--socks` 在 Portal 上是 `--out socks` 的兼容别名。`--next` 在 nw3 下直接报错。

载体：

| 写法 | Portal 端点 |
| ---- | ----------- |
| `--net mix`（默认，未拆端口） | `*:2077` |
| `--net tcp` | `*/tcp:2077` |
| `--net udp` | `*/udp:2077` |
| `--tcp-port 2006 --udp-port 2017` | `*/tcp:2006/udp:2017` |

两端口相同则收成 `*:PORT`。`--net tcp` 同时给 `--udp-port`，或 `--net udp` 同时给 `--tcp-port`，会直接失败。

SOCKS5 上游：

```bash
sudo ./oh-nowhere.sh \
  --install \
  --key a1b2c3d4e5f60718293a4b5c6d7e8f90 \
  --port 2077 \
  --socks 127.0.0.1:1080 \
  --lang zh
```

```text
portal://a1b2c3d4e5f60718293a4b5c6d7e8f90@*:2077?tls=1&out=127.0.0.1:1080&morph=1
```

把流量交给已注册的 Egress（Portal 与 Egress 使用同一把密钥）：

```bash
sudo ./oh-nowhere.sh \
  --install \
  --type portal \
  --key a1b2c3d4e5f60718293a4b5c6d7e8f90 \
  --port 2077 \
  --out egress \
  --lang zh
```

```text
portal://a1b2c3d4e5f60718293a4b5c6d7e8f90@*:2077?tls=1&out=egress&morph=1
```

### Vector

Vector 是本地 SOCKS5 客户端，端点恰好一个载体。`--host` 必须是具体主机，不能是 `*`。

```bash
sudo ./oh-nowhere.sh \
  --install \
  --type vector \
  --key a1b2c3d4e5f60718293a4b5c6d7e8f90 \
  --host relay.example \
  --port 2077 \
  --net tcp \
  --socks 127.0.0.1:1080 \
  --lang zh
```

```text
vector://a1b2c3d4e5f60718293a4b5c6d7e8f90@relay.example/tcp:2077?in=127.0.0.1:1080&morph=1
```

`--net udp` 得到 `/udp:PORT`。`--up` / `--down` / `--mux` 只作为兼容垫片：上下行相同则取该载体（`mix` 折成 `tcp`），不一致则取 `tcp` 并告警。

导入分享链接会转成 Vector。nw3 下补上 `in=`（默认 `127.0.0.1:1080`）：

```bash
sudo ./oh-nowhere.sh \
  --config \
  --url 'nowhere://a1b2c3d4e5f60718293a4b5c6d7e8f90@relay.example:2077?net=tcp&morph=1' \
  --socks 127.0.0.1:1080 \
  --lang zh
```

### Egress

Egress 向 `out=egress` 的 Portal 发起出站 QUIC，不需要入站防火墙端口。

```bash
sudo ./oh-nowhere.sh \
  --install \
  --type egress \
  --key a1b2c3d4e5f60718293a4b5c6d7e8f90 \
  --host relay.example \
  --port 2077 \
  --lang zh
```

```text
egress://a1b2c3d4e5f60718293a4b5c6d7e8f90@relay.example/udp:2077?morph=1
```

## 服务角色

配置菜单项 4 可选 `portal` / `vector` / `egress`，也可以粘贴 `nowhere://`、`vector://`、`portal://` 或 `egress://`。同一时刻只有一种角色（一份 `url.conf`、一个 `nowhere` 服务）。

| 角色 | 运行 URL | 说明 |
| ---- | -------- | ---- |
| `portal` | `portal://KEY@*:2077?tls=1&out=direct&morph=1` | 出口为 `out=direct`、`out=[user:pass@]host:port` 或 `out=egress` |
| `vector` | `vector://KEY@HOST/tcp:2077?in=127.0.0.1:1080&morph=1` | 入站监听 `in=`，端点只有一个载体 |
| `egress` | `egress://KEY@HOST/udp:2077?morph=1` | 连到 `out=egress` 的 Portal；无入站端口 |

2.x 的 `socks=`、`next=` 与双载体路径见文末「旧协议线」。

## TLS 模式（Portal）

默认 `tls=1`（自签）。nw3 不接受 `tls=0`。

Nowhere 2.2+ 与 nw3 默认校验证书，客户端不能跳过。自签 Portal 的分享 URI 会在拿得到指纹时写入 `pin=<sha256>`（64 位小写十六进制）。指纹来自服务日志（systemd journal，或 OpenRC / FreeBSD 的 `/var/log/nowhere.log`），也可以用 `nowhere fingerprint`。自签证书每次 Portal 重启都会重新生成，重启后需要把新的分享 URI 发给客户端。1.x 客户端改为跳过证书校验。

要固定指纹、长期公开服务，使用 `tls=2` 和真实证书，并用 `--host` 让分享 URI 带上匹配的 `sni`：

```bash
sudo ./oh-nowhere.sh \
  --config \
  --type portal \
  --key a1b2c3d4e5f60718293a4b5c6d7e8f90 \
  --port 2077 \
  --tls 2 \
  --cert /etc/nowhere/cert.pem \
  --keyfile /etc/nowhere/key.pem \
  --host relay.example \
  --lang zh
```

```text
portal://a1b2c3d4e5f60718293a4b5c6d7e8f90@*:2077?tls=2&crt=/etc/nowhere/cert.pem&key=/etc/nowhere/key.pem&out=direct&morph=1
```

## 客户端分享 URI

菜单项 11 / `--share` 在 Portal 上为每个载体各输出一条 `nowhere://`。二维码优先编码 TCP 那条。自签（`tls=1`）且能取到指纹时，链接里带 `pin=`：

```text
nowhere://a1b2c3d4e5f60718293a4b5c6d7e8f90@203.0.113.10:2077?net=tcp&morph=1&pin=8f14e45fceea167a5a36dedd4bea2543b7e6d5c4a3f2918273645a0b1c2d3e4f#Nowhere-US-203
nowhere://a1b2c3d4e5f60718293a4b5c6d7e8f90@203.0.113.10:2077?net=udp&morph=1&pin=8f14e45fceea167a5a36dedd4bea2543b7e6d5c4a3f2918273645a0b1c2d3e4f#Nowhere-US-203
```

`tls=2` 且设置了分享主机时，链接带 `sni`，不依赖 `pin`。`pin=` 的含义与重启后失效，见上文「TLS 模式」。

* 主机优先 `/etc/nowhere/host.conf`（或 `--host`），否则用检测到的公网 IP
* 节点名以 percent-encoded `#fragment` 附在末尾；用 `--name` 设置（默认 `Nowhere-<国家>-<IP首段>`，存于 `/etc/nowhere/name.conf`）
* `tls`、`crt`、`key`、`out`、`dial`、`rate`、`etar`、`log` 不写入分享 URI
* Vector 与 Egress 只打印运行 URL，没有客户端导入链接
* 把 `nowhere://` 粘贴到配置或 `--url`，可在本机跑成 Vector

2.x 分享链接使用 `up` / `down`，见文末「旧协议线」。

## 修改当前配置

菜单项 **5** 按字段编辑已保存的运行 URL。输入编号只改那一项，直接回车或输入 `q` 保存并自动重启。

nw3 下列出的字段包括：密钥、端口、载体（Vector 只有一个 `tcp` 或 `udp`）、TLS、`morph`、Portal 出口 `out=`（`direct` / `socks` / `egress`）、SOCKS 上游、Vector 的 `in=`、Egress 的主机 / UDP 端口 / SNI / pin、分享地址、节点名称。编辑器不管理的参数（如 `rate` / `etar` / `dial` / `log`）原样保留。

端口会对照本地监听表（`ss` / `sockstat` / `netstat`）。已被占用时给出警告，确认后才能使用。交互安装与配置同样做这项检查。

## 升级与跨线

不带 `--version` 的 `--upgrade`：

* 已安装的 2.x 留在 2.x：取最近 30 个 release 里最新的 `v2.*`，没有则用 `v2.2.1`
* 已安装的 1.x 在不指定版本时也指向这个最新 `v2.*`，不会留在 1.x
* 已安装的 nw3，以及全新安装，跟随最新稳定版

菜单项 3 列出 GitHub releases。输入 `0` 时，全新安装跟随最新稳定版；已经安装的 2.x 仍去最新 2.x，已经安装的 1.x 也指向最新 2.x。输入编号则安装列表里的那一版；跨到另一主版本时仍要确认。

1.x 升到 2.x 会先警告。交互模式下确认后继续；`--upgrade` / `--install` 打印警告后继续。

nw2 与 nw3 之间切换是另一道门槛。显式 `--version` 不会跳过它。下载之前先预检 `url.conf`：

* 迁往 nw3：Portal 带 `next=` 则中止（nw3 没有对应能力，请先改成 Vector，或改用 `out=socks` / `out=egress`）
* 迁回 nw2：角色是 Egress，或 Portal 使用 `out=egress`，则中止

预检通过后：

* 交互菜单里输入 `MIGRATE`
* `--upgrade` / `--install` 需要同时带上 `--allow-protocol-breaking-upgrade`（不带 `--version` 时，该开关会直接跳到最新 3.x）

确认之后，脚本把 `url.conf` 备份为 `url.conf.nw<旧主版本>.bak.<时间戳>`，二进制备份为 `nowhere.bak.<时间戳>`，再迁移 URL：

* nw2 → nw3：`socks=` 变为 `out=`（没有 `socks` 则 `out=direct`）；空主机 `@:PORT` 变为 `*:PORT`；Vector 的 `socks=` 变为 `in=`，多载体收成一个（`mix` 或上下行不一致时取 `tcp` 并告警）。`morph` 显式写出（nw2 省略时按 `0`）。Portal 密钥不是 32 位小写十六进制时重新生成，并提示重发分享 URI；Vector 密钥属于对端 Portal，只告警不改写。`rate` / `etar` / `dial*` 保留，`up` / `down` / `mux` / `sni` / `pin` / `alpn` / `net` / `log` 从 Portal URL 去掉
* nw3 → nw2：`out=direct` 去掉出口，`out=<端点>` 变回 `socks=`，`in=` 变回 `socks=`，单载体展开为 `up`=`down`。`morph=1` 保留，`morph=0` 省略

## CLI 用法

```bash
sudo ./oh-nowhere.sh [选项]
```

### 选项

| 选项 | 说明 |
| ---- | ---- |
| `-i`, `--install` | 一键安装、升级并启动 |
| `-u`, `--upgrade` | 升级 Nowhere |
| `--allow-protocol-breaking-upgrade` | 确认 nw2↔nw3 跨协议线切换（迁移已存 URL） |
| `-c`, `--config` | 配置服务 |
| `-s`, `--status` | 查看状态 |
| `-q`, `--share` | 显示分享 URI |
| `--tui` | 启动 Nowhere TUI（2.x）或 `nowhere status`（nw3） |
| `--upgrade-script` | 从 GitHub 升级本 oh-nowhere 脚本 |
| `--uninstall` | 卸载 Nowhere |
| `--type <portal\|vector\|egress>` | 服务角色，默认 `portal`（`egress` 需要 nw3） |
| `--url <uri>` | 导入 `portal://`、`vector://`、`egress://` 或 `nowhere://` |
| `-k`, `--key <密钥>` | 共享密钥（nw3：恰好 32 位小写十六进制；2.2+ Portal：32–64 位小写十六进制） |
| `-p`, `--port <端口>` | 监听端口，默认 `2077` |
| `--alpn <alpn>` | 1.x TLS/QUIC ALPN（默认 `now/1` 不写入）；2.0 与 nw3 警告后忽略 |
| `--host <hostname>` | Portal：分享/SNI 主机；Vector / Egress：Portal 主机 |
| `--name <名称>` | 分享 URI 的 `#` 节点名 |
| `--net <mix\|tcp\|udp>` | 载体（1.x 写 `net=`；2.0 映射为端点路径；nw3 的 Vector 只用 `tcp` / `udp`；默认 `mix`） |
| `--tcp-port <端口>` | TLS/TCP 端口（Nowhere 2.0+，可与 UDP 不同） |
| `--udp-port <端口>` | QUIC/UDP 端口（Nowhere 2.0+；nw3 Egress 也用它） |
| `--morph <0\|1>` | TLS/QUIC 线形伪装（Nowhere 2.0+；2.x 默认 `0` 且不写入，nw3 默认 `1` 并写入） |
| `--tls <1\|2>` | Portal TLS 模式，默认 `1`（nw3 不接受 `0`） |
| `--cert <路径>` | `tls=2` 时的证书路径 |
| `--keyfile <路径>` | `tls=2` 时的私钥路径 |
| `--socks <地址>` | Vector 入站 SOCKS；在 nw3 Portal 上等价于 `--out socks` |
| `--out <direct\|socks\|egress>` | Portal 出口（nw3；默认 `direct`） |
| `--next <key@host:port>` | Portal 原生上游，仅 2.x（与 `--socks` 互斥；nw3 直接拒绝） |
| `--up <tcp\|udp\|mix>` | 上行载体（2.x 默认 `tcp`，1.x 默认 `udp`；nw3 仅作兼容垫片） |
| `--down <tcp\|udp\|mix>` | 下行载体（2.x 默认 `tcp`，1.x 默认 `udp`；nw3 仅作兼容垫片） |
| `--mux <0\|1>` | 方向为 `tcp` 或 `mix` 时的 TLS Mux（2.x 省略即 `0`；1.x 的 `tcp/tcp` 默认 `1`） |
| `--sni <名称>` | 证书名（Vector、Egress，或 2.x Portal 的 `next` 上游） |
| `--pin <sha256>` | 证书指纹（自签 Portal 的客户端必需；也可写在 Vector / Egress 上） |
| `-v`, `--version <版本>` | 安装指定的 Nowhere release（例如 `v3.0.0`、`v2.2.1` 或 `v1.8.3`） |
| `--script-version` | 打印本 oh-nowhere 脚本版本后退出 |
| `-l`, `--lang <en\|zh\|ru>` | 脚本语言，默认 `zh` |
| `-h`, `--help` | 显示帮助 |

`--spec` 仍接受，但会警告并忽略（Nowhere 1.5 已移除）。
`--pool` 仍接受，但会警告并忽略（Nowhere 1.8 已移除，请改用 `--mux`）。
`--alpn` 在 2.0 与 nw3 上警告并忽略。
`--next` 在 nw3 上直接报错。

## 常用命令

查看状态：

```bash
sudo ./oh-nowhere.sh --status --lang zh
```

留在当前协议线上升级：

```bash
sudo ./oh-nowhere.sh --upgrade --lang zh
```

确认后跨到 nw3：

```bash
sudo ./oh-nowhere.sh --upgrade --allow-protocol-breaking-upgrade --lang zh
```

重新配置：

```bash
sudo ./oh-nowhere.sh --config --lang zh
```

显示分享 URI：

```bash
sudo ./oh-nowhere.sh --share --lang zh
```

启动 TUI（2.x）或状态快照（nw3）：

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

运行 URL 在 `/etc/nowhere/url.conf`。分享主机在 `/etc/nowhere/host.conf`。节点名在 `/etc/nowhere/name.conf`。

启动器读取 `url.conf` 再执行 Nowhere。若里面仍是 `nowhere://`：nw3 转成 `vector://` 并补 `in=127.0.0.1:1080`；更早的版本补 `socks=`。nw3 二进制遇到仍带 2.x 参数的 Portal / Vector URL 时，启动器报错退出，避免那些参数被静默忽略。

## systemd 管理

Debian / Ubuntu 安装 `nowhere.service`。

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

FreeBSD（Nowhere 2.0+）安装 `/usr/local/etc/rc.d/nowhere`，并用 `sysrc nowhere_enable=YES` 启用。配置仍使用 `/etc/nowhere`。启动器 shebang 为 `#!/usr/bin/env bash`（FreeBSD 的 bash 通常在 `/usr/local/bin/bash`）。

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

Debian / Ubuntu 使用 `qrencode`；Alpine 使用 `python3` + `py3-qrcode`；FreeBSD 使用 `libqrencode`（`pkg install libqrencode`）。菜单项 12 可安装对应包。安装后执行 `--share`，Portal 的二维码编码 TCP 分享链接（没有 TCP 时用 UDP）。

## 安全说明

* 使用脚本生成的密钥。nw3 三种角色都是恰好 32 位小写十六进制；2.2 Portal 为 32–64 位。不合规的 Portal 会拒绝启动。
* 不要公开 Portal 的运行 URL。
* 长期公网服务使用 `tls=2`、有效证书和 `--host`。自签模式下必须分发 `pin=`，且 Portal 每次重启后指纹都会变，见「TLS 模式」。
* Vector 的入站 SOCKS 若暴露在本机以外，需要认证和网络限制。
* 生产环境运行前请审阅脚本。

## 上游项目

本仓库只提供安装与管理脚本。Nowhere 由 NodePassProject 维护：

```text
https://github.com/NodePassProject/Nowhere
```

## 许可证

遵循本仓库声明的许可证；再分发或修改前请查阅 LICENSE 文件。

## 旧协议线（2.x / 1.x）

用 `--version v2.2.1`、`--version v1.8.3` 或菜单项 3 安装、保留或降回旧线。下面的 URL 形态只在对应主版本上生成。跨到 nw3 或从 nw3 回来的步骤见「升级与跨线」。

### Nowhere 2.0

Nowhere 2.0 更换了线协议：ALPN 固定为 `nw2`（`--alpn` 警告后忽略），Portal 的 `net=` 被忽略，载体由端点路径决定，1.x 对端无法互通。`--tcp-port`、`--udp-port`、`--morph` 仅 2.0+（1.x 下传入会报错退出）。FreeBSD 安装包仅 2.0+；某个 2.x tag 若没有 `nowhere-<arch>-unknown-freebsd.tar.gz`，下载失败会写明 tag 与文件名。

`--net` 在 2.0 映射为端点，不再写入 `net=`：

| `--net` / 端口 | Portal 监听 URL |
| -------------- | --------------- |
| `mix`（默认同端口） | `portal://KEY@:2077?tls=1` |
| `tcp` | `portal://KEY@*/tcp:2077?tls=1` |
| `udp` | `portal://KEY@*/udp:2077?tls=1` |
| `--tcp-port 2006 --udp-port 2017` | `portal://KEY@*/tcp:2006/udp:2017?tls=1` |
| 两端口相同 | compact `KEY@:PORT` |

2.0 新配置的 `up` / `down` 默认为 `tcp`，省略 mux（规范值 `0`）。1.x 默认 `udp`，且 `tcp/tcp` 仍自动补 `mux=1`。未拆端口时 `--port` 默认 **2077**。

`--url` 可导入完整端点，包括 `tcp4` / `udp6`。Vector 必须使用具体 `--host`。

升到 2.x 时，已存 Portal 的 `net=tcp|udp` 转为 `@*/tcp:PORT` 或 `@*/udp:PORT`，`net=mix`（或缺失）保留 compact，去掉 `alpn=`，保留 `morph=`。降到 1.x 时反向映射，去掉 `morph=`，不写 `alpn`（1.x 默认 `now/1`）。TCP/UDP 端口不同无法无损还原：警告并折叠为单一端口（优先 TCP，否则 UDP）。

同端口 Portal：

```bash
sudo ./oh-nowhere.sh \
  --install \
  --version v2.2.1 \
  --key a1b2c3d4e5f60718293a4b5c6d7e8f90 \
  --port 2077 \
  --net mix \
  --tls 1 \
  --lang zh
```

```text
portal://a1b2c3d4e5f60718293a4b5c6d7e8f90@:2077?tls=1
```

独立端口与 Morph：

```bash
sudo ./oh-nowhere.sh \
  --install \
  --version v2.2.1 \
  --key a1b2c3d4e5f60718293a4b5c6d7e8f90 \
  --tcp-port 2006 \
  --udp-port 2017 \
  --morph 1 \
  --lang zh
```

```text
portal://a1b2c3d4e5f60718293a4b5c6d7e8f90@*/tcp:2006/udp:2017?tls=1&morph=1
```

Vector（省略 `up` / `down` 时默认为 `tcp`，不会自动补 `mux`）：

```bash
sudo ./oh-nowhere.sh \
  --install \
  --version v2.2.1 \
  --type vector \
  --key a1b2c3d4e5f60718293a4b5c6d7e8f90 \
  --host relay.example \
  --port 2077 \
  --up tcp \
  --down tcp \
  --socks 127.0.0.1:1080 \
  --lang zh
```

同端口 mix 的 Vector 端点是 `relay.example:2077`，单载体是 `relay.example/tcp:PORT`。`mix/mix` 按流选择 `tcp/tcp` 或 `udp/udp`。

导入 2.x 分享 URI 时，`nowhere://` 转为 `vector://`，缺 `socks=` 则补上：

```bash
sudo ./oh-nowhere.sh \
  --config \
  --version v2.2.1 \
  --url 'nowhere://a1b2c3d4e5f60718293a4b5c6d7e8f90@relay.example:2077?up=tcp&down=tcp&mux=1&sni=relay.example' \
  --socks 127.0.0.1:1080 \
  --lang zh
```

### Nowhere 2.2

2.2 对已有 2.x 节点是运行时破坏性变更：

* Portal 密钥以及 `next=` 上游密钥必须是 32–64 位小写十六进制（2.2.0 要求恰好 64 位，2.2.1 放宽为 32–64）。不符合的 Portal 拒绝启动
* 默认强制校验证书。`tls=1` 时客户端需要 `pin=<sha256>`。细节见「TLS 模式」

脚本的处理：

* 新 Portal 密钥生成为 32 位小写十六进制
* `--key` 与交互输入按 32–64 位校验
* 升级到 2.2 时，不合规的 Portal 密钥自动重新生成并打印警告，随后请重发分享 URI。不合规的 `next=` 密钥只报告，不改写
* 配置 Vector 且 `pin=` 为空时，可以自动用 `nowhere fingerprint` 获取 Portal 指纹
* 工具箱里有 `nowhere generate-key`、`nowhere fingerprint`、`nowhere probe`、`nowhere status`；脚本使用前两个

`dial` / `dial4` / `dial6`（双栈出口绑定，仅 Portal，2.2+）不是一级选项；逐项编辑器在改其他字段时原样保留它们。

### Portal 原生链式（1.7+，2.x）

中继 Portal 把流量直接转到下一跳，不必在本机回环 SOCKS5。`next=` 与出站 `socks=` 互斥。链上每个 Portal 都要支持 1.7.0 的 HOPS 语义（最多七跳）。

```bash
sudo ./oh-nowhere.sh \
  --install \
  --version v2.2.1 \
  --type portal \
  --key b1c2d3e4f5a60718293a4b5c6d7e8f90 \
  --port 2077 \
  --next '00112233445566778899aabbccddeeff@origin.example:2077' \
  --up tcp \
  --down tcp \
  --lang zh
```

```text
portal://b1c2d3e4f5a60718293a4b5c6d7e8f90@:2077?tls=1&next=00112233445566778899aabbccddeeff@origin.example:2077&up=tcp&down=tcp
```

`next=` 也可以写成路径，例如 `00112233445566778899aabbccddeeff@origin.example/tcp:2077`。1.x 链式 Portal 仍写 `net=mix`，默认 `up` / `down` 为 `udp`。

交互配置的出站选项是 `none`、`socks` 或 `next`。选择 `next` 后继续填写上游载体，以及可选的 `mux` / `sni` / `pin`。重新配置会保留 `next=` 和上游参数。客户端只连接本中继的入口，`next=` 不出现在分享 URI 里。nw3 不能迁移带 `next=` 的节点。

### Nowhere 1.5 / 1.6 / 1.7 / 1.8

* **1.5** 更换线协议并移除 Portal 的 `spec`。升级时从 `url.conf` 剥掉 `spec=`。自定义 `alpn` 可写；默认 `now/1` 不写入
* **1.6** 增加只读 TUI 和结构化本地遥测（仅 Linux）。线协议与 1.5 相同
* **1.7** 增加 `next=`、EVENT / 遥测 / TUI 中的上游 RTT，以及七跳预算。已存的 `nowhere://` 运行 URL 会迁成 `vector://`
* **1.8** 用 TLS Mux（`mux=0|1`）取代 `pool=<n>`。升级时剥掉 `pool=`，并在 `tcp/tcp` 缺少 `mux=` 时写入 `mux=1`。方向为 `tcp` 或 `mix` 时询问 Mux；`udp/udp` 不写 `mux`
* **1.8.3** 的 Vector 与 Portal `next` 接受 `up` / `down` 为 `tcp`、`udp` 或 `mix`。`mix/mix` 按流解析为 `tcp/tcp` 或 `udp/udp`

Portal 与客户端必须同主版本。1.5 及以后的线协议需要两边一起升级。

保留或还原 1.x（任意非空密钥均可）：

```bash
sudo ./oh-nowhere.sh \
  --install \
  --version v1.8.3 \
  --key a1b2c3d4e5f60718293a4b5c6d7e8f90 \
  --port 2077 \
  --lang zh
```

```text
portal://a1b2c3d4e5f60718293a4b5c6d7e8f90@:2077?tls=1&net=mix
```

降级：

```bash
sudo ./oh-nowhere.sh --upgrade --version v1.8.3 --lang zh
```

菜单项 10 / `--tui` 在 2.x 及 1.6+ 上执行 `nowhere tui`（只读；1.7 起显示上游 RTT）。nw3 改为 `nowhere status`。

### 2.x / 1.x 分享 URI

```text
nowhere://a1b2c3d4e5f60718293a4b5c6d7e8f90@203.0.113.10:2077?up=udp&down=udp#Nowhere-US-203
nowhere://a1b2c3d4e5f60718293a4b5c6d7e8f90@relay.example/tcp:2006/udp:2017?up=udp&down=udp&morph=1#Nowhere-DE-45
nowhere://a1b2c3d4e5f60718293a4b5c6d7e8f90@relay.example:2077?up=tcp&down=tcp&mux=1&sni=relay.example#Nowhere-DE-45
nowhere://a1b2c3d4e5f60718293a4b5c6d7e8f90@203.0.113.10:2077?up=udp&down=udp&pin=8f14e45fceea167a5a36dedd4bea2543b7e6d5c4a3f2918273645a0b1c2d3e4f#Nowhere-US-203
```

最后一条是 2.2 自签 Portal。

* 双载体 compact Portal 分享为 `host:port`。某一侧是 `mix` 时，只把那一侧写成 `udp`（`net=mix` 两侧都是 `mix`，所以是 `up=udp&down=udp`）。显式路径或拆端口使用路径形式
* 仅 TCP / 仅 UDP 分别是 `up=tcp&down=tcp` 或 `up=udp&down=udp`。2.0 不会自动加 `mux=1`；1.x 的 `tcp/tcp` 会加 `mux=1`
* Portal `morph=1` 会写入分享 URI
* `tls`、`crt`、`key`、`net`、`dial`、`rate`、`etar`、`log`、出站 `socks`、`next` 不写入分享 URI
* 1.x 下非默认 `alpn` 会复制到分享 URI；2.0 分享 URI 不含 `alpn`
* 2.2+ 且 `tls=1` 时，能取到指纹就嵌入 `pin=`
