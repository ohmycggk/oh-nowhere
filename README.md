<div>

[**English**](README.md) | [**简体中文**](README_zh_CN.md) | [**Русский**](README_ru.md)

</div>

# oh-nowhere

A one-click installation, upgrade, and management script for [Nowhere](https://github.com/NodePassProject/Nowhere).

`oh-nowhere` is designed to make Nowhere Portal / Vector deployment simple on lightweight Linux servers. It can install the latest Nowhere binary, generate a Portal or Vector URL, write a system service, manage service lifecycle, launch the read-only TUI, and print a client share URI.

## Features

* One-click Nowhere installation
* Upgrade to the latest upstream Nowhere release
* Install a specific Nowhere release version
* Interactive version selection from GitHub releases
* Interactive configuration menu
* Non-interactive CLI mode for automated deployment
* systemd service support
* OpenRC service support for Alpine Linux
* Debian, Ubuntu, and Alpine support
* x86_64 and aarch64 architecture detection
* GNU libc and musl build selection
* Portal or Vector role selection
* Portal outbound SOCKS5, native Portal chaining (`next=`), and Vector inbound SOCKS5
* Import `nowhere://` share URIs (auto-convert to `vector://`)
* Launch Nowhere read-only TUI (`nowhere tui`)
* Service status display
* Client share URI output (`nowhere://`) for Portal
* Optional QR code support
* English, Chinese, and Russian script UI

## Nowhere 1.5 / 1.6 / 1.7 Notes

Nowhere **1.5** introduces a new wire protocol and removes the Portal `spec` parameter. Nowhere **1.6** adds a read-only TUI and structured local telemetry (Linux-only). Wire protocol is unchanged from 1.5.x. Nowhere **1.7** adds native Portal-to-Portal chaining (`next=`), upstream RTT in EVENT logs / telemetry / TUI, and a seven-hop forwarding budget.

This script is adapted for those releases:

* Portal URLs no longer include `spec=`
* Optional custom `alpn` is supported (default `now/1` is omitted from the URL)
* Share links remain `nowhere://` import URIs with `up` / `down` carriers
* `vector://` runs the native SOCKS5 client; this script can generate and manage it
* Pasting or importing `nowhere://` automatically converts to `vector://` (adds inbound `socks=` if missing)
* On upgrade, any stored `spec=` is stripped from `/etc/nowhere/url.conf`
* Stored `nowhere://` run URLs are migrated to `vector://`
* Menu item 13 / `--tui` launches the Nowhere dashboard (observational only; 1.7 shows upstream RTT)
* Portal relay nodes can use native chaining via `next=` (mutually exclusive with outbound `socks=`)
* Every Portal in a native chain must support Nowhere 1.7.0 HOPS semantics
* Portal and clients must be upgraded together for 1.5+ wire

## Supported Systems

| OS           | Init system | Package manager |
| ------------ | ----------- | --------------- |
| Debian       | systemd     | apt             |
| Ubuntu       | systemd     | apt             |
| Alpine Linux | OpenRC      | apk             |

Supported architectures:

* `x86_64`
* `aarch64`

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

This generates a Portal URL similar to:

```text
portal://change-me@:2077?tls=1&net=mix
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

Import a share URI (auto-converts `nowhere://` → `vector://`):

```bash
sudo ./oh-nowhere.sh \
  --config \
  --url 'nowhere://change-me@relay.example:2077?up=tcp&down=tcp&pool=5&sni=relay.example' \
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
  --up udp \
  --down udp \
  --lang en
```

This generates a Portal URL similar to:

```text
portal://relay-key@:2077?tls=1&net=mix&next=origin-key@origin.example:2077&up=udp&down=udp
```

## Install a Specific Version

Install a specific upstream release from the command line:

```bash
sudo ./oh-nowhere.sh \
  --install \
  --version v1.7.0 \
  --key change-me \
  --port 2077 \
  --lang en
```

Upgrade or downgrade to a specific version:

```bash
sudo ./oh-nowhere.sh --upgrade --version v1.7.0 --lang en
```

You can also select a version interactively by choosing menu item `12. Install specific version`. The script fetches the available GitHub releases and presents a numbered list. Choose `0` for the latest release or enter the number of the desired release.

## Service Roles

Configure menu item 3 asks for `portal` or `vector`, or accepts a pasted `nowhere://` / `vector://` / `portal://` URL.

| Role | Run URL | Outbound |
| ---- | ------- | -------- |
| `portal` | `portal://key@:port?...` | Optional **outbound SOCKS** (`socks=host:port`) **or** native chain (`next=key@host:port` with `up`/`down`/`pool`/`sni`/`pin`); mutually exclusive |
| `vector` | `vector://key@portal-host:port?...` | Required **inbound** listener (default `127.0.0.1:1080`) |

Only one role is active at a time (single `url.conf` / `nowhere` service). Reconfigure to switch.

### Portal native chaining (1.7+)

A relay Portal forwards flows directly to another Portal without loopback SOCKS5:

```text
portal://relay-key@:2077?next=origin-key@origin.example:2077&up=udp&down=udp
```

Interactive configure asks for outbound mode: `none`, `socks`, or `next`. When using `next`, the script also prompts for upstream carriers and optional `sni` / `pin`.

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

## Network Modes (Portal)

The script supports the following Nowhere Portal network modes:

| Mode  | Description                         | Share URI carriers       |
| ----- | ----------------------------------- | ------------------------ |
| `mix` | Enable mixed TCP/UDP transport mode | `up=udp&down=udp`        |
| `tcp` | Enable TCP mode                     | `up=tcp&down=tcp&pool=5` |
| `udp` | Enable UDP mode                     | `up=udp&down=udp`        |

Default:

```text
mix
```

## Client Share URI

Menu item 9 / `--share` prints a `nowhere://` import URI for clients when the service role is Portal (not for Vector).

Examples:

```text
nowhere://change-me@203.0.113.10:2077?up=udp&down=udp#Nowhere-US-203
nowhere://change-me@relay.example:2077?up=tcp&down=tcp&pool=5&sni=relay.example#Nowhere-DE-45
```

* Host prefers `/etc/nowhere/host.conf` (or `--host`); otherwise the detected public IP
* Node name is appended as a percent-encoded `#fragment`; set it with `--name` (default `Nowhere-<country>-<first IP octet>`, stored in `/etc/nowhere/name.conf`)
* Portal-only parameters (`tls`, `crt`, `key`, `net`, `dial`, `rate`, `etar`, `log`, outbound `socks`, **`next`**) are not copied into the share URI
* Chained Portal: clients connect to this relay's entry point; `next=` remains server-side only
* Custom `alpn` is copied when it differs from `now/1`
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
| `--alpn <alpn>`             | Set ALPN; default `now/1` is omitted             |
| `--host <hostname>`         | Portal: share/SNI host; Vector: Portal host      |
| `--name <name>`             | Node name for share URI `#` fragment             |
| `--net <mix\|tcp\|udp>`     | Portal network mode, default `mix`               |
| `--tls <1\|2>`              | Portal TLS mode, default `1`                     |
| `--cert <path>`             | Certificate path when `tls=2`                    |
| `--keyfile <path>`          | Private key path when `tls=2`                    |
| `--socks <addr>`            | Portal outbound or Vector inbound SOCKS          |
| `--next <key@host:port>`    | Portal native upstream (mutually exclusive with `--socks`) |
| `--up <tcp\|udp>`           | Uplink carrier (Vector or Portal `next` upstream; default `udp`) |
| `--down <tcp\|udp>`         | Downlink carrier (Vector or Portal `next` upstream; default `udp`) |
| `--pool <n>`                | Warm TLS pool for `tcp/tcp` (Vector or Portal `next` upstream) |
| `--sni <name>`              | Certificate name (Vector or Portal `next` upstream) |
| `--pin <sha256>`            | Certificate pin (Vector or Portal `next` upstream) |
| `-v`, `--version <ver>`     | Install a specific release version               |
| `-l`, `--lang <en\|zh\|ru>` | Set script language, default `zh`                |
| `-h`, `--help`              | Show help                                        |

`--spec` is accepted but ignored with a warning (removed in Nowhere 1.5).

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
sudo ./oh-nowhere.sh --install --version v1.7.0 --lang en
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

## QR Code Support

The script can optionally install QR code support.

On Debian/Ubuntu, it uses `qrencode`.

On Alpine Linux, it uses `python3` and `py3-qrcode`.

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
