# oh-nowhere

A one-click installation, upgrade, and management script for [Nowhere](https://github.com/NodePassProject/Nowhere).

`oh-nowhere` is designed to make Nowhere Portal deployment simple on lightweight Linux servers. It can install the latest Nowhere binary, generate a Portal URL, write a system service, manage service lifecycle, and print a client share URI.

## Features

* One-click Nowhere installation
* Upgrade to the latest upstream Nowhere release
* Interactive configuration menu
* Non-interactive CLI mode for automated deployment
* systemd service support
* OpenRC service support for Alpine Linux
* Debian, Ubuntu, and Alpine support
* x86_64 and aarch64 architecture detection
* GNU libc and musl build selection
* Portal URL generation
* Service status display
* Client share URI output
* Optional QR code support
* English, Chinese, and Russian script UI

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
  --spec nightfall \
  --net mix \
  --tls 1 \
  --lang en
```

This generates a Portal URL similar to:

```text
portal://change-me@:2077?tls=1&net=mix&spec=nightfall
```

## TLS Modes

### Self-signed TLS

The default mode is `tls=1`.

```bash
sudo ./install.sh \
  --config \
  --key change-me \
  --port 2077 \
  --spec nightfall \
  --net mix \
  --tls 1 \
  --lang en
```

When using self-signed TLS, clients must skip certificate verification.

### Custom Certificate

Use `tls=2` when you want to provide your own certificate and private key:

```bash
sudo ./install.sh \
  --config \
  --key change-me \
  --port 2077 \
  --spec nightfall \
  --net mix \
  --tls 2 \
  --cert /etc/nowhere/cert.pem \
  --keyfile /etc/nowhere/key.pem \
  --lang en
```

## Network Modes

The script supports the following Nowhere Portal network modes:

| Mode  | Description                         |
| ----- | ----------------------------------- |
| `mix` | Enable mixed TCP/UDP transport mode |
| `tcp` | Enable TCP mode                     |
| `udp` | Enable UDP mode                     |

Default:

```text
mix
```

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
| `--spec <spec>`             | Set the Nowhere spec, default `auto` |
| `--net <mix\|tcp\|udp>`     | Set the network mode, default `mix`  |
| `--tls <1\|2>`              | Set TLS mode, default `1`            |
| `--cert <path>`             | Certificate path when `tls=2`        |
| `--keyfile <path>`          | Private key path when `tls=2`        |
| `-l`, `--lang <en\|zh\|ru>` | Set script language, default `zh`    |
| `-h`, `--help`              | Show help                            |

## Common Commands

Show status:

```bash
sudo ./install.sh --status --lang en
```

Upgrade Nowhere:

```bash
sudo ./install.sh --upgrade --lang en
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
/etc/systemd/system/nowhere.service
/etc/init.d/nowhere
```

The generated Portal URL is stored at:

```text
/etc/nowhere/url.conf
```

The service launcher reads this file and starts Nowhere with the stored URL.

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
* For long-running public services, prefer `tls=2` with a valid certificate.
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
