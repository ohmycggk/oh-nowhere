<div>

[**English**](README.md) | [**简体中文**](README_zh_CN.md) | [**Русский**](README_ru.md)

</div>

# oh-nowhere

A one-click installation, upgrade, and management script for [Nowhere](https://github.com/NodePassProject/Nowhere).

`oh-nowhere` is designed to make Nowhere Portal / Vector deployment simple on lightweight Linux and FreeBSD servers. It can install the latest Nowhere binary, generate a Portal or Vector URL, write a system service, manage service lifecycle, launch the read-only TUI, and print a client share URI. The default target is Nowhere **2.0+**; 1.x remains available for maintaining older nodes.

## Features

* One-click Nowhere installation (defaults to the latest 2.x release)
* Upgrade to the latest upstream Nowhere release
* Install a specific Nowhere release version, including 1.x maintenance tags
* Interactive version selection from GitHub releases
* Interactive configuration menu
* Non-interactive CLI mode for automated deployment
* systemd, OpenRC, and FreeBSD rc.d service support
* Debian, Ubuntu, Alpine, and FreeBSD (2.0+ only) support
* x86_64 and aarch64 architecture detection
* GNU libc and musl build selection on Linux; `unknown-freebsd` assets on FreeBSD
* Portal or Vector role selection
* Portal outbound SOCKS5, native Portal chaining (`next=`), and Vector inbound SOCKS5
* Carrier mode (`tcp` / `udp` / `mix`) mapped to 2.0 endpoint paths, or written as `net=` on 1.x
* Independent TCP/UDP listen ports and Morph (`--tcp-port` / `--udp-port` / `--morph`, Nowhere 2.0+)
* Mixed carrier policy (`tcp` / `udp` / `mix`) for Vector and Portal `next`
* Import `nowhere://` share URIs (auto-convert to `vector://`)
* Launch Nowhere read-only TUI (`nowhere tui`)
* Service status display
* Client share URI output (`nowhere://`) for Portal
* Optional QR code support
* English, Chinese, and Russian script UI

## Nowhere 2.0 (default) and 1.x maintenance

Nowhere **2.0** is a breaking wire change: ALPN is fixed to `nw2` (`alpn=` is ignored), Portal `net=` is ignored (carriers are selected by the endpoint path), and 1.x peers cannot connect. This script defaults to the latest 2.x GitHub release. Keep a 1.x node with `--version v1.8.3` or menu item 12; 1.x is not the default upgrade target.

* Portal and clients must share a major version (`now/1` vs `nw2`)
* Interactive 1↔2 upgrade/downgrade asks for confirmation; `--upgrade` / `--install` print the warning and continue
* `--tcp-port`, `--udp-port`, and `--morph` require Nowhere 2.0+ (the script exits if the profile is 1.x)
* `--alpn` is ignored on 2.0 (same pattern as `--spec` / `--pool`)
* New 2.0 configs default `up`/`down` to `tcp`; mux is omitted (canonical `0`). 1.x keeps default `udp` and still adds `mux=1` for `tcp/tcp`
* `--port` remains the shared default (**2077**) when TCP/UDP ports are not split
* FreeBSD packages exist only for Nowhere 2.0+; installing 1.x on FreeBSD is refused. If a 2.x tag has no `nowhere-<arch>-unknown-freebsd.tar.gz` asset, download fails with the tag and expected filename

`--net mix|tcp|udp` stays the operator interface. On 2.0 it is mapped to the endpoint instead of `net=`:

| `--net` / ports | Portal listen URL |
| --------------- | ----------------- |
| `mix` (default shared port) | `portal://KEY@:2077?tls=1` (TCP+UDP on the same port) |
| `tcp` | `portal://KEY@*/tcp:2077?tls=1` |
| `udp` | `portal://KEY@*/udp:2077?tls=1` |
| `--tcp-port 2006 --udp-port 2017` | `portal://KEY@*/tcp:2006/udp:2017?tls=1` |
| both ports set and equal | compact `KEY@:PORT` |

`--url` can still import a full endpoint, including address-family suffixes such as `tcp4` / `udp6`. Vector requires a concrete `--host` (`*` is rejected).

On upgrade to 2.x, stored Portal `net=tcp|udp` becomes `@*/tcp:PORT` or `@*/udp:PORT`, `net=mix` (or missing) stays compact, and `alpn=` is stripped. `morph=` is kept. Downgrade to 1.x reverses that mapping, drops `morph=`, and does not write `alpn` (1.x default `now/1`). Split TCP/UDP ports cannot be represented in 1.x: the script warns and collapses to a single port (TCP if set, otherwise UDP).

## Nowhere 1.5 / 1.6 / 1.7 / 1.8 Notes

Nowhere **1.5** introduces a new wire protocol and removes the Portal `spec` parameter. Nowhere **1.6** adds a read-only TUI and structured local telemetry (Linux-only). Wire protocol is unchanged from 1.5.x. Nowhere **1.7** adds native Portal-to-Portal chaining (`next=`), upstream RTT in EVENT logs / telemetry / TUI, and a seven-hop forwarding budget. Nowhere **1.8** replaces the `tcp/tcp` warm TLS pool (`pool=<n>`) with TLS Mux (`mux=0|1`); the `pool` parameter is removed. Nowhere **1.8.3** adds mixed carrier policy: Vector and Portal `next` `up`/`down` accept `tcp`, `udp`, or `mix`.

This script is adapted for those releases:

* Portal URLs no longer include `spec=`
* Optional custom `alpn` is supported (default `now/1` is omitted from the URL)
* Share links remain `nowhere://` import URIs with `up` / `down` carriers
* `vector://` runs the native SOCKS5 client; this script can generate and manage it
* Pasting or importing `nowhere://` automatically converts to `vector://` (adds inbound `socks=` if missing)
* On upgrade, any stored `spec=` is stripped from `/etc/nowhere/url.conf`
* On upgrade, any stored `pool=` is stripped; `mux=1` is added for `tcp/tcp` when missing
* Stored `nowhere://` run URLs are migrated to `vector://`
* Menu item 13 / `--tui` launches the Nowhere dashboard (observational only; 1.7 shows upstream RTT)
* Portal relay nodes can use native chaining via `next=` (mutually exclusive with outbound `socks=`)
* Every Portal in a native chain must support Nowhere 1.7.0 HOPS semantics
* Portal and clients must be upgraded together for 1.5+ wire
* Vector and Portal `next` upstreams use `mux=0|1` instead of `pool=` (1.8+)
* Vector and Portal `next` `up`/`down` accept `tcp|udp|mix` (1.8.3+); `mix/mix` resolves per flow to `tcp/tcp` or `udp/udp`
* Mux is offered when a direction is `tcp` or `mix`; `udp/udp` omits `mux` (canonical `0`)
* Portal `net=mix` share URIs use `up=mix&down=mix`

## Supported Systems

| OS           | Init system | Package manager | Notes |
| ------------ | ----------- | --------------- | ----- |
| Debian       | systemd     | apt             | 1.x and 2.x |
| Ubuntu       | systemd     | apt             | 1.x and 2.x |
| Alpine Linux | OpenRC      | apk             | 1.x and 2.x |
| FreeBSD      | rc.d        | pkg             | Nowhere 2.0+ only (`x86_64` / `aarch64`) |

Supported architectures:

* `x86_64` (`amd64` on FreeBSD)
* `aarch64` (`arm64` on FreeBSD)

Recent GNU Linux assets require **glibc 2.39** (Ubuntu 24.04 / Debian 13). Debian 12 and other hosts with an older glibc automatically install the musl build.

## Quick Start

Download the script first:

```bash
curl -fsSL https://raw.githubusercontent.com/ohmycggk/oh-nowhere/main/oh-nowhere.sh -o oh-nowhere.sh
chmod +x oh-nowhere.sh
```

Run the interactive manager:

```bash
sudo ./oh-nowhere.sh --lang en
```

Then select the action from the menu:

```text
1. One-click install
2. Upgrade Nowhere
3. Configure service
4. Start service
5. Stop service
6. Restart service
7. Show status
8. Uninstall Nowhere
9. Show share URI
10. Install QR code support
11. Change language
12. Install specific version
13. Launch Nowhere TUI
14. Upgrade oh-nowhere script
0. Exit
```

## One-shot Installation

Install Nowhere with default Portal values:

```bash
sudo ./oh-nowhere.sh --install --lang en
```

Install with custom Portal parameters:

```bash
sudo ./oh-nowhere.sh \
  --install \
  --key change-me \
  --port 2077 \
  --net mix \
  --tls 1 \
  --lang en
```

On Nowhere 2.0 this generates a compact dual-carrier Portal URL:

```text
portal://change-me@:2077?tls=1
```

Pass `--version v1.8.3` to keep the 1.x form `portal://change-me@:2077?tls=1&net=mix`.

Independent TCP/UDP ports and Morph (2.0+ only):

```bash
sudo ./oh-nowhere.sh \
  --install \
  --key change-me \
  --tcp-port 2006 \
  --udp-port 2017 \
  --morph 1 \
  --lang en
```

```text
portal://change-me@*/tcp:2006/udp:2017?tls=1&morph=1
```

Install as Vector (local SOCKS5 client):

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
  --lang en
```

On 2.0 the Vector URL uses the same endpoint rules (`relay.example:2077` for mixed carriers on one port, or `relay.example/tcp:PORT`). `up`/`down` default to `tcp` when omitted; `mux` is not auto-set. On 1.x, `tcp/tcp` still gets `mux=1`.

Install Vector with mixed carriers (`mix/mix` picks `tcp/tcp` or `udp/udp` per flow):

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
  --lang en
```

Import a share URI (auto-converts `nowhere://` → `vector://`):

```bash
sudo ./oh-nowhere.sh \
  --config \
  --url 'nowhere://change-me@relay.example:2077?up=tcp&down=tcp&mux=1&sni=relay.example' \
  --socks 127.0.0.1:1080 \
  --lang en
```

Install a chained Portal relay (Nowhere 1.7+):

```bash
sudo ./oh-nowhere.sh \
  --install \
  --type portal \
  --key relay-key \
  --port 2077 \
  --next 'origin-key@origin.example:2077' \
  --up tcp \
  --down tcp \
  --lang en
```

On 2.0 this generates:

```text
portal://relay-key@:2077?tls=1&next=origin-key@origin.example:2077&up=tcp&down=tcp
```

`next=` can also use an explicit path such as `origin-key@origin.example/tcp:2077`. 1.x chained Portals still write `net=mix` and default `up`/`down` to `udp`.

## Install a Specific Version

Install a specific upstream release from the command line:

```bash
sudo ./oh-nowhere.sh \
  --install \
  --version v2.0.0 \
  --key change-me \
  --port 2077 \
  --lang en
```

Keep or restore a 1.x node:

```bash
sudo ./oh-nowhere.sh \
  --install \
  --version v1.8.3 \
  --key change-me \
  --port 2077 \
  --lang en
```

Upgrade or downgrade to a specific version:

```bash
sudo ./oh-nowhere.sh --upgrade --version v1.8.3 --lang en
```

You can also select a version interactively by choosing menu item `12. Install specific version`. The script fetches the available GitHub releases and presents a numbered list. Choose `0` for the latest release or enter the number of the desired release.

## Service Roles

Configure menu item 3 asks for `portal` or `vector`, or accepts a pasted `nowhere://` / `vector://` / `portal://` URL.

| Role | Run URL | Outbound |
| ---- | ------- | -------- |
| `portal` | `portal://key@:port?...` or `portal://key@*/tcp:port[/udp:port]?...` | Optional **outbound SOCKS** (`socks=host:port`) **or** native chain (`next=key@host:port` with `up`/`down`/`mux`/`sni`/`pin`); mutually exclusive |
| `vector` | `vector://key@portal-host:port?...` or path form `host/tcp:A/udp:B` | Required **inbound** listener (default `127.0.0.1:1080`) |

Only one role is active at a time (single `url.conf` / `nowhere` service). Reconfigure to switch.

### Portal native chaining (1.7+)

A relay Portal forwards flows directly to another Portal without loopback SOCKS5:

```text
portal://relay-key@:2077?next=origin-key@origin.example:2077&up=tcp&down=tcp
```

Interactive configure asks for outbound mode: `none`, `socks`, or `next`. When using `next`, the script also prompts for upstream carriers and optional `mux` / `sni` / `pin`.

Import an existing chained Portal URL via `--url` or paste `portal://...?next=...` in the configure menu; reconfigure preserves `next=` and upstream parameters.

## TLS Modes (Portal)

### Self-signed TLS

The default mode is `tls=1`.

```bash
sudo ./oh-nowhere.sh \
  --config \
  --type portal \
  --key change-me \
  --port 2077 \
  --net mix \
  --tls 1 \
  --lang en
```

When using self-signed TLS, clients must skip certificate verification. The share URI omits `sni` in this mode.

### Custom Certificate

Use `tls=2` when you want to provide your own certificate and private key. Set `--host` so the share URI can include a matching `sni`:

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
  --lang en
```

## Carrier Modes (Portal)

`--net` is the operator switch for which carriers the Portal advertises. Default is still `mix`.

| Mode  | 2.0 Portal endpoint | 1.x query | Share URI carriers |
| ----- | ------------------- | --------- | ------------------ |
| `mix` | compact `KEY@:PORT` (TCP+UDP same port) | `net=mix` | `up=mix&down=mix` |
| `tcp` | `KEY@*/tcp:PORT` | `net=tcp` | `up=tcp&down=tcp` (1.x also adds `mux=1`) |
| `udp` | `KEY@*/udp:PORT` | `net=udp` | `up=udp&down=udp` |

`--tcp-port` / `--udp-port` (2.0+ only) override `--net` + `--port`:

* both set and equal → compact `HOST:PORT`
* both set and different → `HOST/tcp:A/udp:B`
* only `--tcp-port` → `HOST/tcp:A`
* only `--udp-port` → `HOST/udp:B`
* neither set → `--net` + `--port`

Conflicts exit immediately: `--net tcp` with `--udp-port`, `--net udp` with `--tcp-port`, or `up`/`down`/`mix` requesting a carrier the endpoint did not declare.

## Client Share URI

Menu item 9 / `--share` prints a `nowhere://` import URI for clients when the service role is Portal (not for Vector).

Examples:

```text
nowhere://change-me@203.0.113.10:2077?up=mix&down=mix#Nowhere-US-203
nowhere://change-me@relay.example/tcp:2006/udp:2017?up=mix&down=mix&morph=1#Nowhere-DE-45
nowhere://change-me@relay.example:2077?up=tcp&down=tcp&mux=1&sni=relay.example#Nowhere-DE-45
```

* Dual-carrier compact Portal → `host:port` with `up=mix&down=mix`; explicit or split ports use the path form
* TCP-only / UDP-only endpoints share `up=tcp&down=tcp` or `up=udp&down=udp`; 2.0 does not auto-add `mux=1`
* Portal `morph=1` is copied onto the share URI
* Host prefers `/etc/nowhere/host.conf` (or `--host`); otherwise the detected public IP
* Node name is appended as a percent-encoded `#fragment`; set it with `--name` (default `Nowhere-<country>-<first IP octet>`, stored in `/etc/nowhere/name.conf`)
* Portal-only parameters (`tls`, `crt`, `key`, `net`, `dial`, `rate`, `etar`, `log`, outbound `socks`, **`next`**) are not copied into the share URI
* Chained Portal: clients connect to this relay's entry point; `next=` remains server-side only
* Custom `alpn` is copied on 1.x when it differs from `now/1`; 2.0 share URIs never include `alpn`
* On a Vector instance, `--share` prints the current `vector://` run URL instead

Paste a `nowhere://` share URI into configure / `--url` to run Vector locally.

## Nowhere TUI

Menu item 13 / `--tui` runs:

```bash
nowhere tui
```

The dashboard discovers local Portal/Vector instances and shows live metrics, including upstream RTT (`ping_ms`) in Nowhere 1.7+. It is read-only and does not start, stop, or reconfigure the service.

## CLI Usage

```bash
sudo ./oh-nowhere.sh [options]
```

### Options

| Option                      | Description                                      |
| --------------------------- | ------------------------------------------------ |
| `-i`, `--install`           | One-shot install, upgrade, and start             |
| `-u`, `--upgrade`           | Upgrade Nowhere                                  |
| `-c`, `--config`            | Configure the service                            |
| `-s`, `--status`            | Show service status                              |
| `-q`, `--share`             | Show client share URI                            |
| `--tui`                     | Launch Nowhere TUI                               |
| `--upgrade-script`          | Upgrade this oh-nowhere script from GitHub       |
| `--uninstall`               | Uninstall Nowhere                                |
| `--type <portal\|vector>`   | Service role, default `portal`                   |
| `--url <uri>`               | Import `portal://`, `vector://`, or `nowhere://` |
| `-k`, `--key <key>`         | Set the shared key                               |
| `-p`, `--port <port>`       | Set the listen / Portal port, default `2077`     |
| `--alpn <alpn>`             | 1.x TLS/QUIC ALPN (default `now/1` omitted); ignored on 2.0 (`nw2`) |
| `--host <hostname>`         | Portal: share/SNI host; Vector: Portal host      |
| `--name <name>`             | Node name for share URI `#` fragment             |
| `--net <mix\|tcp\|udp>`     | Carrier mode (1.x writes `net=`; 2.0 maps to endpoint path; default `mix`) |
| `--tcp-port <port>`         | TLS/TCP port (Nowhere 2.0+; independent of `--udp-port`) |
| `--udp-port <port>`         | QUIC/UDP port (Nowhere 2.0+; independent of `--tcp-port`) |
| `--morph <0\|1>`            | Keyed TLS/QUIC wire mask (Nowhere 2.0+; default `0`, omitted) |
| `--tls <1\|2>`              | Portal TLS mode, default `1`                     |
| `--cert <path>`             | Certificate path when `tls=2`                    |
| `--keyfile <path>`          | Private key path when `tls=2`                    |
| `--socks <addr>`            | Portal outbound or Vector inbound SOCKS          |
| `--next <key@host:port>`    | Portal native upstream (mutually exclusive with `--socks`) |
| `--up <tcp\|udp\|mix>`      | Uplink carrier (default `tcp` on 2.x, `udp` on 1.x) |
| `--down <tcp\|udp\|mix>`    | Downlink carrier (default `tcp` on 2.x, `udp` on 1.x) |
| `--mux <0\|1>`              | TLS Mux when a direction is `tcp` or `mix` (2.x omits/default `0`; 1.x `tcp/tcp` defaults to `1`) |
| `--sni <name>`              | Certificate name (Vector or Portal `next` upstream) |
| `--pin <sha256>`            | Certificate pin (Vector or Portal `next` upstream) |
| `-v`, `--version <ver>`     | Install a specific release (e.g. `v2.0.0` or `v1.8.3`) |
| `-l`, `--lang <en\|zh\|ru>` | Set script language, default `zh`                |
| `-h`, `--help`              | Show help                                        |

`--spec` is accepted but ignored with a warning (removed in Nowhere 1.5).
`--pool` is accepted but ignored with a warning (removed in Nowhere 1.8; use `--mux`).
`--alpn` is ignored with a warning on Nowhere 2.0 (fixed ALPN `nw2`).

## Common Commands

Show status:

```bash
sudo ./oh-nowhere.sh --status --lang en
```

Upgrade Nowhere:

```bash
sudo ./oh-nowhere.sh --upgrade --lang en
```

Install a specific Nowhere version:

```bash
sudo ./oh-nowhere.sh --install --version v1.8.3 --lang en
```

Reconfigure the service:

```bash
sudo ./oh-nowhere.sh --config --lang en
```

Show client share URI:

```bash
sudo ./oh-nowhere.sh --share --lang en
```

Launch TUI:

```bash
sudo ./oh-nowhere.sh --tui --lang en
```

Upgrade the management script:

```bash
sudo ./oh-nowhere.sh --upgrade-script --lang en
```

Uninstall Nowhere:

```bash
sudo ./oh-nowhere.sh --uninstall --lang en
```

## Installed Files

The script may create or manage the following files:

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

The generated Portal or Vector URL is stored at:

```text
/etc/nowhere/url.conf
```

Optional public hostname for share / SNI (Portal) or remembered Portal host:

```text
/etc/nowhere/host.conf
```

Node name appended to the share URI as `#fragment`:

```text
/etc/nowhere/name.conf
```

The service launcher reads `url.conf` and starts Nowhere with the stored URL. If the file still contains `nowhere://`, the launcher migrates it to `vector://` automatically.

## systemd Management

On Debian and Ubuntu, the script installs a `nowhere.service` unit.

Manual service commands:

```bash
sudo systemctl status nowhere
sudo systemctl restart nowhere
sudo systemctl stop nowhere
sudo systemctl start nowhere
```

View logs:

```bash
sudo journalctl -u nowhere -f
```

## OpenRC Management

On Alpine Linux, the script installs an OpenRC service.

Manual service commands:

```bash
sudo rc-service nowhere status
sudo rc-service nowhere restart
sudo rc-service nowhere stop
sudo rc-service nowhere start
```

Enable service on boot:

```bash
sudo rc-update add nowhere default
```

## FreeBSD rc.d Management

On FreeBSD (Nowhere 2.0+), the script installs `/usr/local/etc/rc.d/nowhere` and enables it with `sysrc nowhere_enable=YES`. Config stays at `/etc/nowhere` (same as Linux). The launcher uses `#!/usr/bin/env bash` because FreeBSD bash is typically `/usr/local/bin/bash`.

```bash
sudo service nowhere status
sudo service nowhere restart
sudo service nowhere stop
sudo service nowhere start
```

Enable or disable on boot:

```bash
sudo sysrc nowhere_enable=YES
sudo sysrc -x nowhere_enable
```

## QR Code Support

The script can optionally install QR code support.

On Debian/Ubuntu, it uses `qrencode`.

On Alpine Linux, it uses `python3` and `py3-qrcode`.

On FreeBSD, it uses `libqrencode` (`pkg install libqrencode`).

After installing QR support, use:

```bash
sudo ./oh-nowhere.sh --share --lang en
```

## Security Notes

* Always use a strong shared key.
* Do not publish your Portal URL publicly.
* For long-running public services, prefer `tls=2` with a valid certificate and `--host` for SNI.
* If you use `tls=1`, make sure your client is configured to skip certificate verification.
* Vector inbound SOCKS exposed beyond localhost should use authentication and network policy.
* Review the script before running it on production servers.

## Upstream Project

This repository only provides the installation and management script.

Nowhere itself is maintained by NodePassProject:

```text
https://github.com/NodePassProject/Nowhere
```

## License

This repository follows the license declared in the project repository. Please check the repository license file before redistribution or modification.
