# oh-nowhere

A one-click installation, upgrade, and management script for [Nowhere](https://github.com/NodePassProject/Nowhere).

`oh-nowhere` is designed to make Nowhere Portal deployment simple on lightweight Linux servers. It can install the latest Nowhere binary, generate a Portal URL, write a system service, manage service lifecycle, and print a client share URI.

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
* Portal URL generation
* Service status display
* Client share URI output (`nowhere://`)
* Optional QR code support
* English, Chinese, and Russian script UI

## Nowhere 1.5 Notes

Nowhere **1.5** introduces a new wire protocol and removes the Portal `spec` parameter. This script is adapted for that release:

* Portal URLs no longer include `spec=`
* Optional custom `alpn` is supported (default `now/1` is omitted from the URL)
* Share links remain `nowhere://` import URIs with `up` / `down` carriers
* `vector://` is only the local SOCKS5 client process URL for the Nowhere binary; this script does **not** generate or manage it
* On upgrade, any stored `spec=` is stripped from `/etc/nowhere/url.conf`
* Portal and clients must be upgraded together; Anywhere is not ready for 1.5 yet

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
curl -fsSL https://raw.githubusercontent.com/ohmycggk/oh-nowhere/main/install.sh -o install.sh
chmod +x install.sh
```

Run the interactive manager:

```bash
sudo ./install.sh --lang en
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
0. Exit
```

## One-shot Installation

Install Nowhere with default values:

```bash
sudo ./install.sh --install --lang en
```

Install with custom Portal parameters:

```bash
sudo ./install.sh \
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

## Install a Specific Version

Install a specific upstream release from the command line:

```bash
sudo ./install.sh \
  --install \
  --version v1.5.0 \
  --key change-me \
  --port 2077 \
  --lang en
```

Upgrade or downgrade to a specific version:

```bash
sudo ./install.sh --upgrade --version v1.5.0 --lang en
```

You can also select a version interactively by choosing menu item `12. Install specific version`. The script fetches the available GitHub releases and presents a numbered list. Choose `0` for the latest release or enter the number of the desired release.

## TLS Modes

### Self-signed TLS

The default mode is `tls=1`.

```bash
sudo ./install.sh \
  --config \
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
sudo ./install.sh \
  --config \
  --key change-me \
  --port 2077 \
  --net mix \
  --tls 2 \
  --cert /etc/nowhere/cert.pem \
  --keyfile /etc/nowhere/key.pem \
  --host relay.example \
  --lang en
```

## Network Modes

The script supports the following Nowhere Portal network modes:

| Mode  | Description                         | Share URI carriers      |
| ----- | ----------------------------------- | ----------------------- |
| `mix` | Enable mixed TCP/UDP transport mode | `up=udp&down=udp`       |
| `tcp` | Enable TCP mode                     | `up=tcp&down=tcp&pool=5` |
| `udp` | Enable UDP mode                     | `up=udp&down=udp`       |

Default:

```text
mix
```

## Client Share URI

Menu item 9 / `--share` prints a `nowhere://` import URI for clients (not `vector://`).

Examples:

```text
nowhere://change-me@203.0.113.10:2077?up=udp&down=udp
nowhere://change-me@relay.example:2077?up=tcp&down=tcp&pool=5&sni=relay.example
```

* Host prefers `/etc/nowhere/host.conf` (or `--host`); otherwise the detected public IP
* Portal-only parameters (`tls`, `crt`, `key`, `net`, `dial`, `rate`, `etar`, `log`, outbound `socks`) are not copied into the share URI
* Custom `alpn` is copied when it differs from `now/1`

## CLI Usage

```bash
sudo ./install.sh [options]
```

### Options

| Option                      | Description                          |
| --------------------------- | ------------------------------------ |
| `-i`, `--install`           | One-shot install, upgrade, and start |
| `-u`, `--upgrade`           | Upgrade Nowhere                      |
| `-c`, `--config`            | Configure the service                |
| `-s`, `--status`            | Show service status                  |
| `-q`, `--share`             | Show client share URI                |
| `--uninstall`               | Uninstall Nowhere                    |
| `-k`, `--key <key>`         | Set the shared key                   |
| `-p`, `--port <port>`       | Set the listen port, default `2077`  |
| `--alpn <alpn>`             | Set ALPN; default `now/1` is omitted |
| `--host <hostname>`         | Public hostname for share URI / SNI  |
| `--net <mix\|tcp\|udp>`     | Set the network mode, default `mix`  |
| `--tls <1\|2>`              | Set TLS mode, default `1`            |
| `--cert <path>`             | Certificate path when `tls=2`        |
| `--keyfile <path>`          | Private key path when `tls=2`        |
| `-v`, `--version <ver>`     | Install a specific release version   |
| `-l`, `--lang <en\|zh\|ru>` | Set script language, default `zh`    |
| `-h`, `--help`              | Show help                            |

`--spec` is accepted but ignored with a warning (removed in Nowhere 1.5).

## Common Commands

Show status:

```bash
sudo ./install.sh --status --lang en
```

Upgrade Nowhere:

```bash
sudo ./install.sh --upgrade --lang en
```

Install a specific Nowhere version:

```bash
sudo ./install.sh --install --version v1.5.0 --lang en
```

Reconfigure the Portal:

```bash
sudo ./install.sh --config --lang en
```

Show client share URI:

```bash
sudo ./install.sh --share --lang en
```

Uninstall Nowhere:

```bash
sudo ./install.sh --uninstall --lang en
```

## Installed Files

The script may create or manage the following files:

```text
/usr/local/bin/nowhere
/usr/local/bin/nowhere-launch.sh
/etc/nowhere/url.conf
/etc/nowhere/host.conf
/etc/systemd/system/nowhere.service
/etc/init.d/nowhere
```

The generated Portal URL is stored at:

```text
/etc/nowhere/url.conf
```

Optional public hostname for share / SNI:

```text
/etc/nowhere/host.conf
```

The service launcher reads `url.conf` and starts Nowhere with the stored Portal URL.

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
sudo ./install.sh --share --lang en
```

## Security Notes

* Always use a strong shared key.
* Do not publish your Portal URL publicly.
* For long-running public services, prefer `tls=2` with a valid certificate and `--host` for SNI.
* If you use `tls=1`, make sure your client is configured to skip certificate verification.
* Review the script before running it on production servers.

## Upstream Project

This repository only provides the installation and management script.

Nowhere itself is maintained by NodePassProject:

```text
https://github.com/NodePassProject/Nowhere
```

## License

This repository follows the license declared in the project repository. Please check the repository license file before redistribution or modification.
