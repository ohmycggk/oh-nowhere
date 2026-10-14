<div>

[**English**](README.md) | [**简体中文**](README_zh_CN.md) | [**Русский**](README_ru.md)

</div>

# oh-nowhere

A one-click installation, upgrade, and management script for [Nowhere](https://github.com/NodePassProject/Nowhere).

`oh-nowhere` installs the Nowhere binary on lightweight Linux and FreeBSD servers, generates a Portal, Vector, or Egress URL, writes a system service, manages the service lifecycle, and prints a client share URI. Fresh installs follow the latest stable release (Nowhere 3 / nw3). An installed 2.x node stays on 2.x and does not cross to nw3 on its own. Without a version, a 1.x node upgrades to the newest 2.x; to stay on 1.x, pass `--version` or use menu item 3.

## Features

* One-click install of the latest stable release (nw3); an installed 2.x node stays on 2.x and does not cross to nw3 on its own
* Install a specific release, or pick one interactively from GitHub releases
* Interactive menu and non-interactive CLI
* Per-field edits of the current configuration, with an automatic restart; port-conflict checks while configuring
* systemd, OpenRC, and FreeBSD rc.d
* Debian, Ubuntu, Alpine, and FreeBSD (Nowhere 2.0+ only)
* x86_64 / aarch64; GNU libc or musl selected automatically on Linux
* Portal, Vector, and the nw3 Egress role
* Portal share URIs (`nowhere://`) and optional QR codes
* Read-only TUI on 2.x; `nowhere status` on nw3
* English, Chinese, and Russian script UI

## Supported Systems

| OS           | Init system | Package manager | Notes |
| ------------ | ----------- | --------------- | ----- |
| Debian       | systemd     | apt             | 1.x, 2.x, and 3.x |
| Ubuntu       | systemd     | apt             | 1.x, 2.x, and 3.x |
| Alpine Linux | OpenRC      | apk             | 1.x, 2.x, and 3.x |
| FreeBSD      | rc.d        | pkg             | Nowhere 2.0+ only (`x86_64` / `aarch64`) |

Supported architectures:

* `x86_64` (`amd64` on FreeBSD)
* `aarch64` (`arm64` on FreeBSD)

Recent GNU Linux assets require **glibc 2.39** (Ubuntu 24.04 / Debian 13). Debian 12 and other hosts with an older glibc automatically install the musl build.

## Quick Start

Download the script:

```bash
curl -fsSL https://raw.githubusercontent.com/ohmycggk/oh-nowhere/main/oh-nowhere.sh -o oh-nowhere.sh
chmod +x oh-nowhere.sh
```

Run the interactive manager:

```bash
sudo ./oh-nowhere.sh --lang en
```

Menu:

```text
1. One-click install
2. Upgrade Nowhere
3. Install specific version

4. Configure service
5. Modify current configuration

6. Start service
7. Stop service
8. Restart service
9. Show status
10. TUI / instance status

11. Show share URI
12. Install QR code support

13. Change language
14. Upgrade oh-nowhere script
15. Uninstall Nowhere
0. Exit
```

The menu header shows the oh-nowhere script version, the installed Nowhere version, and the service state (running / stopped / not installed).

## Default Install (Nowhere 3)

A fresh install without `--version` uses nw3. If Nowhere is already installed, `--install` upgrades instead and follows the target-version rules in "Upgrade and Protocol-Line Switch" below. Portal, Vector, and Egress keys are exactly 32 lowercase hexadecimal characters (`nowhere generate-key` when the binary is available, otherwise `/dev/urandom`). `morph` defaults to `1` and is always written. `tls` accepts only `1` or `2`. Portal wildcard hosts are written as `*`.

The nw3 binary silently ignores parameters it does not know. The script checks them before writing. When the binary is already nw3 and a Portal or Vector `url.conf` still contains `up`, `down`, `mux`, `next`, `socks`, `net`, `alpn`, `log`, `pool`, or `spec`, the launcher refuses to start.

### Portal

```bash
sudo ./oh-nowhere.sh --install --lang en
```

The default is shared-port `mix`. The URL has this shape (the script generates the key; the hex below is only a 32-character example):

```text
portal://a1b2c3d4e5f60718293a4b5c6d7e8f90@*:2077?tls=1&out=direct&morph=1
```

`*:2077` listens for TCP and UDP on the same port. Choose the exit with `--out`:

| `--out` | Exit in the run URL |
| ------- | ------------------- |
| `direct` (default) | `out=direct` |
| `socks` | `out=127.0.0.1:1080` (address from `--socks`; `user:pass@` is allowed) |
| `egress` | `out=egress` (the endpoint must include UDP) |

On a Portal, `--socks` is the compatibility alias for `--out socks`. `--next` is rejected on nw3.

Carriers:

| Form | Portal endpoint |
| ---- | --------------- |
| `--net mix` (default, ports not split) | `*:2077` |
| `--net tcp` | `*/tcp:2077` |
| `--net udp` | `*/udp:2077` |
| `--tcp-port 2006 --udp-port 2017` | `*/tcp:2006/udp:2017` |

Equal TCP and UDP ports collapse to `*:PORT`. `--net tcp` together with `--udp-port`, or `--net udp` together with `--tcp-port`, fails immediately.

SOCKS5 upstream:

```bash
sudo ./oh-nowhere.sh \
  --install \
  --key a1b2c3d4e5f60718293a4b5c6d7e8f90 \
  --port 2077 \
  --socks 127.0.0.1:1080 \
  --lang en
```

```text
portal://a1b2c3d4e5f60718293a4b5c6d7e8f90@*:2077?tls=1&out=127.0.0.1:1080&morph=1
```

Hand traffic to a registered Egress (the Portal and the Egress share one key):

```bash
sudo ./oh-nowhere.sh \
  --install \
  --type portal \
  --key a1b2c3d4e5f60718293a4b5c6d7e8f90 \
  --port 2077 \
  --out egress \
  --lang en
```

```text
portal://a1b2c3d4e5f60718293a4b5c6d7e8f90@*:2077?tls=1&out=egress&morph=1
```

### Vector

Vector is the local SOCKS5 client. Its endpoint declares exactly one carrier. `--host` must be a concrete host; `*` is rejected.

```bash
sudo ./oh-nowhere.sh \
  --install \
  --type vector \
  --key a1b2c3d4e5f60718293a4b5c6d7e8f90 \
  --host relay.example \
  --port 2077 \
  --net tcp \
  --socks 127.0.0.1:1080 \
  --lang en
```

```text
vector://a1b2c3d4e5f60718293a4b5c6d7e8f90@relay.example/tcp:2077?in=127.0.0.1:1080&morph=1
```

`--net udp` produces `/udp:PORT`. `--up` / `--down` / `--mux` are compatibility shims: equal carriers are kept (`mix` folds to `tcp`); a mismatch becomes `tcp` and prints a warning.

Importing a share URI turns it into a Vector. On nw3 the script adds `in=` (default `127.0.0.1:1080`):

```bash
sudo ./oh-nowhere.sh \
  --config \
  --url 'nowhere://a1b2c3d4e5f60718293a4b5c6d7e8f90@relay.example:2077?net=tcp&morph=1' \
  --socks 127.0.0.1:1080 \
  --lang en
```

### Egress

Egress dials out over QUIC to a Portal configured with `out=egress`. It does not need an inbound firewall port.

```bash
sudo ./oh-nowhere.sh \
  --install \
  --type egress \
  --key a1b2c3d4e5f60718293a4b5c6d7e8f90 \
  --host relay.example \
  --port 2077 \
  --lang en
```

```text
egress://a1b2c3d4e5f60718293a4b5c6d7e8f90@relay.example/udp:2077?morph=1
```

## Service Roles

Configure (menu item 4) accepts `portal`, `vector`, or `egress`, or a pasted `nowhere://`, `vector://`, `portal://`, or `egress://` URL. Only one role is active at a time (one `url.conf`, one `nowhere` service).

| Role | Run URL | Notes |
| ---- | ------- | ----- |
| `portal` | `portal://KEY@*:2077?tls=1&out=direct&morph=1` | Exit is `out=direct`, `out=[user:pass@]host:port`, or `out=egress` |
| `vector` | `vector://KEY@HOST/tcp:2077?in=127.0.0.1:1080&morph=1` | Inbound listener `in=`; the endpoint has one carrier |
| `egress` | `egress://KEY@HOST/udp:2077?morph=1` | Dials a Portal with `out=egress`; no inbound port |

2.x `socks=`, `next=`, and dual-carrier paths are in "Older protocol lines" at the end.

## TLS Modes (Portal)

The default is `tls=1` (self-signed). nw3 does not accept `tls=0`.

Nowhere 2.2+ and nw3 verify certificates by default; clients cannot skip verification. When the fingerprint can be read, a self-signed Portal share URI includes `pin=<sha256>` (64 lowercase hex characters). The fingerprint comes from the service log (the systemd journal, or `/var/log/nowhere.log` on OpenRC / FreeBSD) or from `nowhere fingerprint`. A self-signed certificate is regenerated on every Portal restart, so send clients the new share URI afterwards. On 1.x, clients skip certificate verification instead.

For a stable fingerprint on a long-lived public service, use `tls=2` with a real certificate and set `--host` so the share URI includes a matching `sni`:

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
  --lang en
```

```text
portal://a1b2c3d4e5f60718293a4b5c6d7e8f90@*:2077?tls=2&crt=/etc/nowhere/cert.pem&key=/etc/nowhere/key.pem&out=direct&morph=1
```

## Client Share URI

Menu item 11 / `--share` prints one `nowhere://` link per Portal carrier. The QR code encodes the TCP link when one exists. A self-signed Portal (`tls=1`) includes `pin=` when the fingerprint is available:

```text
nowhere://a1b2c3d4e5f60718293a4b5c6d7e8f90@203.0.113.10:2077?net=tcp&morph=1&pin=8f14e45fceea167a5a36dedd4bea2543b7e6d5c4a3f2918273645a0b1c2d3e4f#Nowhere-US-203
nowhere://a1b2c3d4e5f60718293a4b5c6d7e8f90@203.0.113.10:2077?net=udp&morph=1&pin=8f14e45fceea167a5a36dedd4bea2543b7e6d5c4a3f2918273645a0b1c2d3e4f#Nowhere-US-203
```

With `tls=2` and a share host set, the link carries `sni` and does not depend on `pin`. What `pin=` means, and why it changes after a restart, is covered under "TLS Modes".

* Host prefers `/etc/nowhere/host.conf` (or `--host`); otherwise the detected public IP
* The node name is a percent-encoded `#fragment`; set it with `--name` (default `Nowhere-<country>-<first IP octet>`, stored in `/etc/nowhere/name.conf`)
* `tls`, `crt`, `key`, `out`, `dial`, `rate`, `etar`, and `log` are omitted from the share URI
* Vector and Egress print only the run URL; there is no client import link
* Paste a `nowhere://` URI into configure or `--url` to run a Vector locally

2.x share links use `up` / `down`. See "Older protocol lines" below.

## Modifying the Current Configuration

Menu item **5** edits the stored run URL field by field. Enter a field number to change that value, then press Enter or `q` to save and restart the service.

On nw3 the fields include: key, ports, carrier (Vector has a single `tcp` or `udp`), TLS, `morph`, the Portal exit `out=` (`direct` / `socks` / `egress`), the SOCKS upstream, Vector `in=`, and for Egress the host / UDP port / SNI / pin, plus the share host and node name. Parameters the editor does not manage (`rate` / `etar` / `dial` / `log`) are kept as-is.

Ports are checked against the local listener table (`ss` / `sockstat` / `netstat`). A port already in use warns and must be confirmed. Interactive install and configure run the same check.

## Upgrade and Protocol-Line Switch

`--upgrade` without `--version`:

* An installed 2.x node stays on 2.x: the newest `v2.*` among the latest 30 releases, or `v2.2.1` when that list has none
* An installed 1.x node, when no version is given, targets that same newest `v2.*` and does not stay on 1.x
* An installed nw3 node, and a fresh install, follow the latest stable release

Menu item 3 lists GitHub releases. Enter `0` and a fresh install follows the latest stable release; an installed 2.x node still goes to the newest 2.x, and an installed 1.x node targets that newest 2.x as well. Enter a list number to install that release. Moving to another major version still asks for confirmation.

An upgrade from 1.x to 2.x prints a warning first. Interactive mode continues after confirmation; `--upgrade` / `--install` print the warning and continue.

Switching between nw2 and nw3 is a separate gate. An explicit `--version` does not skip it. Before anything is downloaded, the script preflights `url.conf`:

* Moving to nw3 stops when the Portal has `next=` (nw3 has no equivalent; reconfigure as a Vector, or use `out=socks` / `out=egress`)
* Moving back to nw2 stops when the role is Egress, or the Portal uses `out=egress`

After the preflight:

* In the interactive menu, type `MIGRATE`
* `--upgrade` / `--install` also need `--allow-protocol-breaking-upgrade` (without `--version`, that flag jumps straight to the latest 3.x)

After confirmation the script copies `url.conf` to `url.conf.nw<old-major>.bak.<timestamp>`, copies the binary to `nowhere.bak.<timestamp>`, then migrates the URL:

* nw2 → nw3: `socks=` becomes `out=` (`out=direct` when `socks` is absent); an empty host `@:PORT` becomes `*:PORT`; Vector `socks=` becomes `in=`, and multiple carriers collapse to one (`mix`, or mismatched up/down, becomes `tcp` with a warning). `morph` is written explicitly (`0` when nw2 omitted it). A Portal key that is not 32 lowercase hex is regenerated, and the script asks you to redistribute the share URI. A Vector key belongs to the peer Portal and is only reported. `rate` / `etar` / `dial*` are kept. `up` / `down` / `mux` / `sni` / `pin` / `alpn` / `net` / `log` are removed from the Portal URL
* nw3 → nw2: `out=direct` drops the exit, `out=<endpoint>` becomes `socks=`, `in=` becomes `socks=`, and a single carrier expands to `up`=`down`. `morph=1` is kept; `morph=0` is omitted

## CLI Usage

```bash
sudo ./oh-nowhere.sh [options]
```

### Options

| Option | Description |
| ------ | ----------- |
| `-i`, `--install` | One-shot install, upgrade, and start |
| `-u`, `--upgrade` | Upgrade Nowhere |
| `--allow-protocol-breaking-upgrade` | Confirm an nw2↔nw3 protocol-line switch (migrates stored URLs) |
| `-c`, `--config` | Configure the service |
| `-s`, `--status` | Show service status |
| `-q`, `--share` | Show the client share URI |
| `--tui` | Launch the Nowhere TUI (2.x) or `nowhere status` (nw3) |
| `--upgrade-script` | Upgrade this oh-nowhere script from GitHub |
| `--uninstall` | Uninstall Nowhere |
| `--type <portal\|vector\|egress>` | Service role, default `portal` (`egress` requires nw3) |
| `--url <uri>` | Import `portal://`, `vector://`, `egress://`, or `nowhere://` |
| `-k`, `--key <key>` | Shared key (nw3: exactly 32 lowercase hex; 2.2+ Portal: 32–64 lowercase hex) |
| `-p`, `--port <port>` | Listen port, default `2077` |
| `--alpn <alpn>` | 1.x TLS/QUIC ALPN (default `now/1` is omitted); warned and ignored on 2.0 and nw3 |
| `--host <hostname>` | Portal: share/SNI host; Vector / Egress: Portal host |
| `--name <name>` | Node name for the share URI `#` fragment |
| `--net <mix\|tcp\|udp>` | Carrier (1.x writes `net=`; 2.0 maps it to the endpoint path; nw3 Vector uses only `tcp` / `udp`; default `mix`) |
| `--tcp-port <port>` | TLS/TCP port (Nowhere 2.0+; may differ from UDP) |
| `--udp-port <port>` | QUIC/UDP port (Nowhere 2.0+; also the nw3 Egress port) |
| `--morph <0\|1>` | Keyed TLS/QUIC wire mask (Nowhere 2.0+; default `0` and omitted on 2.x, default `1` and written on nw3) |
| `--tls <1\|2>` | Portal TLS mode, default `1` (nw3 does not accept `0`) |
| `--cert <path>` | Certificate path when `tls=2` |
| `--keyfile <path>` | Private key path when `tls=2` |
| `--socks <addr>` | Vector inbound SOCKS; on an nw3 Portal, alias for `--out socks` |
| `--out <direct\|socks\|egress>` | Portal exit (nw3; default `direct`) |
| `--next <key@host:port>` | Portal native upstream, 2.x only (mutually exclusive with `--socks`; rejected on nw3) |
| `--up <tcp\|udp\|mix>` | Uplink carrier (default `tcp` on 2.x, `udp` on 1.x; compatibility shim on nw3) |
| `--down <tcp\|udp\|mix>` | Downlink carrier (default `tcp` on 2.x, `udp` on 1.x; compatibility shim on nw3) |
| `--mux <0\|1>` | TLS Mux when a direction is `tcp` or `mix` (2.x omits it, meaning `0`; 1.x `tcp/tcp` defaults to `1`) |
| `--sni <name>` | Certificate name (Vector, Egress, or a 2.x Portal `next` upstream) |
| `--pin <sha256>` | Certificate fingerprint (required for clients of a self-signed Portal; may also be set on Vector / Egress) |
| `-v`, `--version <ver>` | Install a specific Nowhere release (for example `v3.0.0`, `v2.2.1`, or `v1.8.3`) |
| `--script-version` | Print this oh-nowhere version and exit |
| `-l`, `--lang <en\|zh\|ru>` | Script language, default `zh` |
| `-h`, `--help` | Show help |

`--spec` is still accepted, then warned and ignored (removed in Nowhere 1.5).
`--pool` is still accepted, then warned and ignored (removed in Nowhere 1.8; use `--mux`).
`--alpn` is warned and ignored on 2.0 and on nw3.
`--next` is rejected on nw3.

## Common Commands

Show status:

```bash
sudo ./oh-nowhere.sh --status --lang en
```

Upgrade while staying on the current protocol line:

```bash
sudo ./oh-nowhere.sh --upgrade --lang en
```

Cross to nw3 after confirmation:

```bash
sudo ./oh-nowhere.sh --upgrade --allow-protocol-breaking-upgrade --lang en
```

Reconfigure:

```bash
sudo ./oh-nowhere.sh --config --lang en
```

Show the share URI:

```bash
sudo ./oh-nowhere.sh --share --lang en
```

Launch the TUI (2.x) or the status snapshot (nw3):

```bash
sudo ./oh-nowhere.sh --tui --lang en
```

Upgrade the manager script:

```bash
sudo ./oh-nowhere.sh --upgrade-script --lang en
```

Uninstall:

```bash
sudo ./oh-nowhere.sh --uninstall --lang en
```

## Installed Files

The script may create or manage:

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

The run URL is `/etc/nowhere/url.conf`. The share host is `/etc/nowhere/host.conf`. The node name is `/etc/nowhere/name.conf`.

The launcher reads `url.conf` and execs Nowhere. A stored `nowhere://` URL becomes `vector://`: nw3 adds `in=127.0.0.1:1080`; older releases add `socks=`. If an nw3 binary still sees 2.x parameters on a Portal or Vector URL, the launcher exits with an error so those parameters are not silently ignored.

## systemd Management

Debian / Ubuntu install a `nowhere.service` unit.

```bash
sudo systemctl status nowhere
sudo systemctl restart nowhere
sudo systemctl stop nowhere
sudo systemctl start nowhere
```

Logs:

```bash
sudo journalctl -u nowhere -f
```

## OpenRC Management

Alpine installs an OpenRC service.

```bash
sudo rc-service nowhere status
sudo rc-service nowhere restart
sudo rc-service nowhere stop
sudo rc-service nowhere start
```

Enable at boot:

```bash
sudo rc-update add nowhere default
```

## FreeBSD rc.d Management

FreeBSD (Nowhere 2.0+) installs `/usr/local/etc/rc.d/nowhere` and enables it with `sysrc nowhere_enable=YES`. Configuration stays in `/etc/nowhere`. The launcher shebang is `#!/usr/bin/env bash` (FreeBSD bash is usually `/usr/local/bin/bash`).

```bash
sudo service nowhere status
sudo service nowhere restart
sudo service nowhere stop
sudo service nowhere start
```

Enable or disable at boot:

```bash
sudo sysrc nowhere_enable=YES
sudo sysrc -x nowhere_enable
```

## QR Code Support

Debian / Ubuntu use `qrencode`; Alpine uses `python3` + `py3-qrcode`; FreeBSD uses `libqrencode` (`pkg install libqrencode`). Menu item 12 installs the matching package. After that, `--share` encodes the Portal TCP share link as a QR code (UDP when there is no TCP link).

## Security Notes

* Use a key the script generates. On nw3 every role uses exactly 32 lowercase hex characters; a 2.2 Portal uses 32–64. A Portal with a non-conforming key refuses to start.
* Do not publish the Portal run URL.
* For a long-lived public service use `tls=2`, a valid certificate, and `--host`. Self-signed mode requires distributing `pin=`, and the fingerprint changes on every Portal restart. See "TLS Modes".
* If a Vector inbound SOCKS listener is reachable beyond the host, add authentication and a network policy.
* Review the script before running it in production.

## Upstream Project

This repository provides the install and management script. Nowhere is maintained by NodePassProject:

```text
https://github.com/NodePassProject/Nowhere
```

## License

Follow the license declared in this repository. Read the LICENSE file before redistributing or modifying it.

## Older Protocol Lines (2.x / 1.x)

Install, keep, or return to an older line with `--version v2.2.1`, `--version v1.8.3`, or menu item 3. The URL forms below are produced only on that major version. Crossing to nw3, or back from it, is described under "Upgrade and Protocol-Line Switch".

### Nowhere 2.0

Nowhere 2.0 changes the wire protocol: ALPN is fixed to `nw2` (`--alpn` warns and is ignored), Portal `net=` is ignored, carriers come from the endpoint path, and 1.x peers cannot connect. `--tcp-port`, `--udp-port`, and `--morph` require 2.0+ (passing them on 1.x exits with an error). FreeBSD packages exist only for 2.0+. If a 2.x tag has no `nowhere-<arch>-unknown-freebsd.tar.gz`, the download error names the tag and the expected filename.

On 2.0, `--net` is mapped to the endpoint and is not written as `net=`:

| `--net` / ports | Portal listen URL |
| --------------- | ----------------- |
| `mix` (default, shared port) | `portal://KEY@:2077?tls=1` |
| `tcp` | `portal://KEY@*/tcp:2077?tls=1` |
| `udp` | `portal://KEY@*/udp:2077?tls=1` |
| `--tcp-port 2006 --udp-port 2017` | `portal://KEY@*/tcp:2006/udp:2017?tls=1` |
| both ports equal | compact `KEY@:PORT` |

New 2.0 configs default `up` / `down` to `tcp` and omit mux (canonical `0`). 1.x defaults to `udp` and still adds `mux=1` for `tcp/tcp`. When ports are not split, `--port` defaults to **2077**.

`--url` can import a full endpoint, including address-family suffixes such as `tcp4` / `udp6`. Vector requires a concrete `--host`.

On upgrade to 2.x, stored Portal `net=tcp|udp` becomes `@*/tcp:PORT` or `@*/udp:PORT`, `net=mix` (or a missing value) stays compact, `alpn=` is stripped, and `morph=` is kept. Downgrade to 1.x reverses that mapping, drops `morph=`, and does not write `alpn` (1.x default `now/1`). Split TCP/UDP ports cannot be represented on 1.x: the script warns and collapses to one port (TCP if set, otherwise UDP).

Shared-port Portal:

```bash
sudo ./oh-nowhere.sh \
  --install \
  --version v2.2.1 \
  --key a1b2c3d4e5f60718293a4b5c6d7e8f90 \
  --port 2077 \
  --net mix \
  --tls 1 \
  --lang en
```

```text
portal://a1b2c3d4e5f60718293a4b5c6d7e8f90@:2077?tls=1
```

Independent ports and Morph:

```bash
sudo ./oh-nowhere.sh \
  --install \
  --version v2.2.1 \
  --key a1b2c3d4e5f60718293a4b5c6d7e8f90 \
  --tcp-port 2006 \
  --udp-port 2017 \
  --morph 1 \
  --lang en
```

```text
portal://a1b2c3d4e5f60718293a4b5c6d7e8f90@*/tcp:2006/udp:2017?tls=1&morph=1
```

Vector (`up` / `down` default to `tcp` when omitted; `mux` is not added automatically):

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
  --lang en
```

A mixed Vector on one port uses `relay.example:2077`; a single carrier uses `relay.example/tcp:PORT`. `mix/mix` picks `tcp/tcp` or `udp/udp` per flow.

Importing a 2.x share URI converts `nowhere://` to `vector://` and adds `socks=` when it is missing:

```bash
sudo ./oh-nowhere.sh \
  --config \
  --version v2.2.1 \
  --url 'nowhere://a1b2c3d4e5f60718293a4b5c6d7e8f90@relay.example:2077?up=tcp&down=tcp&mux=1&sni=relay.example' \
  --socks 127.0.0.1:1080 \
  --lang en
```

### Nowhere 2.2

2.2 is a breaking runtime change for existing 2.x nodes:

* Portal keys, and the `next=` upstream key, must be 32–64 lowercase hexadecimal characters (2.2.0 required exactly 64; 2.2.1 relaxed that to 32–64). A non-conforming Portal refuses to start
* Certificate verification is mandatory. With `tls=1`, clients need `pin=<sha256>`. See "TLS Modes"

What this script does:

* New Portal keys are 32 lowercase hexadecimal characters
* `--key` and interactive input are checked as 32–64 hex
* On upgrade to 2.2, a non-conforming Portal key is regenerated and a warning is printed; redistribute the share URI afterwards. A non-conforming `next=` key is reported and left unchanged
* Configuring a Vector with an empty `pin=` can fetch the Portal fingerprint with `nowhere fingerprint`
* The 2.2 toolbox includes `nowhere generate-key`, `nowhere fingerprint`, `nowhere probe`, and `nowhere status`; the script uses the first two

`dial` / `dial4` / `dial6` (dual-stack outbound source binding, Portal only, 2.2+) are not first-class options. The per-field editor keeps them when other fields change.

### Portal Native Chaining (1.7+, 2.x)

A relay Portal forwards flows to the next hop without a loopback SOCKS5. `next=` and outbound `socks=` are mutually exclusive. Every Portal in the chain must support 1.7.0 HOPS semantics (seven hops).

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
  --lang en
```

```text
portal://b1c2d3e4f5a60718293a4b5c6d7e8f90@:2077?tls=1&next=00112233445566778899aabbccddeeff@origin.example:2077&up=tcp&down=tcp
```

`next=` may also use a path, for example `00112233445566778899aabbccddeeff@origin.example/tcp:2077`. A 1.x chained Portal still writes `net=mix` and defaults `up` / `down` to `udp`.

Interactive configure offers `none`, `socks`, or `next`. Choosing `next` continues with the upstream carriers and optional `mux` / `sni` / `pin`. Reconfigure keeps `next=` and the upstream parameters. Clients connect to this relay's entry; `next=` is absent from the share URI. A node that still has `next=` cannot be migrated to nw3.

### Nowhere 1.5 / 1.6 / 1.7 / 1.8

* **1.5** changes the wire protocol and removes Portal `spec`. Upgrade strips `spec=` from `url.conf`. A custom `alpn` may be written; the default `now/1` is omitted
* **1.6** adds the read-only TUI and structured local telemetry (Linux only). The wire protocol matches 1.5
* **1.7** adds `next=`, upstream RTT in EVENT logs / telemetry / the TUI, and a seven-hop budget. Stored `nowhere://` run URLs are migrated to `vector://`
* **1.8** replaces `pool=<n>` with TLS Mux (`mux=0|1`). Upgrade strips `pool=` and writes `mux=1` for `tcp/tcp` when `mux=` is missing. Mux is offered when a direction is `tcp` or `mix`; `udp/udp` omits `mux`
* **1.8.3** Vector and Portal `next` accept `up` / `down` of `tcp`, `udp`, or `mix`. `mix/mix` resolves per flow to `tcp/tcp` or `udp/udp`

Portal and clients must share a major version. The 1.5+ wire protocol requires upgrading both sides together.

Keep or restore 1.x (any non-empty key is accepted):

```bash
sudo ./oh-nowhere.sh \
  --install \
  --version v1.8.3 \
  --key a1b2c3d4e5f60718293a4b5c6d7e8f90 \
  --port 2077 \
  --lang en
```

```text
portal://a1b2c3d4e5f60718293a4b5c6d7e8f90@:2077?tls=1&net=mix
```

Downgrade:

```bash
sudo ./oh-nowhere.sh --upgrade --version v1.8.3 --lang en
```

Menu item 10 / `--tui` runs `nowhere tui` on 2.x and on 1.6+ (read-only; upstream RTT from 1.7). nw3 runs `nowhere status` instead.

### 2.x / 1.x Share URIs

```text
nowhere://a1b2c3d4e5f60718293a4b5c6d7e8f90@203.0.113.10:2077?up=udp&down=udp#Nowhere-US-203
nowhere://a1b2c3d4e5f60718293a4b5c6d7e8f90@relay.example/tcp:2006/udp:2017?up=udp&down=udp&morph=1#Nowhere-DE-45
nowhere://a1b2c3d4e5f60718293a4b5c6d7e8f90@relay.example:2077?up=tcp&down=tcp&mux=1&sni=relay.example#Nowhere-DE-45
nowhere://a1b2c3d4e5f60718293a4b5c6d7e8f90@203.0.113.10:2077?up=udp&down=udp&pin=8f14e45fceea167a5a36dedd4bea2543b7e6d5c4a3f2918273645a0b1c2d3e4f#Nowhere-US-203
```

The last example is a 2.2 self-signed Portal.

* A dual-carrier compact Portal is shared as `host:port`. A `mix` side is published as `udp` (`net=mix` is `mix` on both sides, so `up=udp&down=udp`). Explicit paths or split ports use the path form
* TCP-only / UDP-only endpoints share `up=tcp&down=tcp` or `up=udp&down=udp`. 2.0 does not add `mux=1`; 1.x `tcp/tcp` does
* Portal `morph=1` is copied onto the share URI
* `tls`, `crt`, `key`, `net`, `dial`, `rate`, `etar`, `log`, outbound `socks`, and `next` are omitted
* On 1.x a non-default `alpn` is copied; 2.0 share URIs never include `alpn`
* On 2.2+ with `tls=1`, an available fingerprint is embedded as `pin=`
