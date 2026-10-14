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
* Four Portal certificate sources: program self-signed, openssl self-signed, your own PEM files, or a real CA certificate through acme.sh with automatic renewal inside a 30-day window
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

A fresh install without `--version` uses nw3. If Nowhere is already installed, `--install` upgrades instead and follows the target-version rules in "Upgrade and Protocol-Line Switch" below. Portal, Vector, and Egress keys are exactly 32 lowercase hexadecimal characters (`nowhere generate-key` when the binary is available, otherwise `/dev/urandom`). `morph` defaults to `1` and is always written. `tls` accepts only `1` or `2` and follows from the certificate-source choice (see "TLS Modes"). Portal wildcard hosts are written as `*`.

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

Before TLS is chosen, the script asks for the certificate source. All four sources normalize to the `tls=1` or `tls=2` the binary accepts, so the Portal URL format never changes:

| Choice | `tls=` | Certificate | Client verification |
| ------ | ------ | ----------- | ------------------- |
| 1 program self-signed | `1` | minted by the binary, SAN fixed to `localhost` | `pin=` (changes on restart) |
| 2 openssl self-signed | `2` | written by this script to `/etc/nowhere/cert.pem` + `key.pem` (ECDSA P-256, validity defaults to 398 days and is selectable) | `pin=` (stable across restarts) |
| 3 custom certificate | `2` | your own PEM files via `--cert` / `--keyfile` | `sni=` (needs a public hostname) |
| 4 acme.sh certificate | `2` | issued by a public CA through acme.sh, renewed by cron inside a 30-day window | `sni=` (needs a public hostname) |

The default is `tls=1` (program self-signed). nw3 does not accept `tls=0`.

Nowhere 2.2+ and nw3 verify certificates by default; clients cannot skip verification. When the fingerprint can be read, a self-signed Portal share URI includes `pin=<sha256>` (64 lowercase hex characters). A program self-signed certificate is regenerated on every Portal restart, so its pin changes with it and clients need the new share URI afterwards (the certificate itself does not expire; the pin is what moves). On 1.x, clients skip certificate verification instead.

The openssl source keeps the certificate on disk, so the pin is stable across restarts and suits long-lived public services:

```bash
sudo ./oh-nowhere.sh \
  --config \
  --type portal \
  --key a1b2c3d4e5f60718293a4b5c6d7e8f90 \
  --port 2077 \
  --cert-mode openssl \
  --self-sign-days 398 \
  --host relay.example \
  --lang en
```

```text
portal://a1b2c3d4e5f60718293a4b5c6d7e8f90@*:2077?tls=2&crt=/etc/nowhere/cert.pem&key=/etc/nowhere/key.pem&out=direct&morph=1
```

The pin is stored in `/etc/nowhere/pin.conf`. `--status` reports the certificate source, the pin prefix and the expiry date, and warns from 30 days before expiry. The certificate is produced by `openssl`, which the script installs when missing.

For your own certificate use `--cert-mode custom` with `--cert` / `--keyfile`:

```bash
sudo ./oh-nowhere.sh \
  --config \
  --type portal \
  --key a1b2c3d4e5f60718293a4b5c6d7e8f90 \
  --port 2077 \
  --cert-mode custom \
  --cert /etc/nowhere/cert.pem \
  --keyfile /etc/nowhere/key.pem \
  --host relay.example \
  --lang en
```

### acme.sh certificate

`--cert-mode acme` asks [acme.sh](https://github.com/acmesh-official/acme.sh) for a real CA-signed certificate, so clients verify it against the public chain exactly like a `custom` certificate: `tls=2`, no `pin=`, and `sni=` from `--host`. The domain must already resolve to this server.

```bash
sudo ./oh-nowhere.sh \
  --install \
  --type portal \
  --key a1b2c3d4e5f60718293a4b5c6d7e8f90 \
  --port 2077 \
  --cert-mode acme \
  --acme-domain relay.example.com \
  --acme-email me@example.com \
  --host relay.example.com \
  --lang en
```

```text
portal://a1b2c3d4e5f60718293a4b5c6d7e8f90@*:2077?tls=2&crt=/etc/nowhere/acme/relay.example.com_ecc/fullchain.cer&key=/etc/nowhere/acme/relay.example.com_ecc/relay.example.com.key&out=direct&morph=1
```

`--acme-domain` alone implies `--cert-mode acme`; with it absent the domain defaults to the share host. The default challenge is `--acme-challenge http`, which runs in acme.sh's standalone mode: it binds port 80 itself for the few seconds of validation, so **port 80 must be free** at issue time and at every renewal, and `socat` (or `python3`) must be installed. The script checks both and installs `socat` when the package manager allows it. For a host where port 80 is taken, use a DNS plugin instead:

```bash
sudo ./oh-nowhere.sh \
  --install \
  --type portal \
  --key a1b2c3d4e5f60718293a4b5c6d7e8f90 \
  --port 2077 \
  --acme-domain relay.example.com \
  --acme-dns dns_cf \
  --host relay.example.com \
  --lang en
```

`--acme-dns` implies `--acme-challenge dns`. The manager never touches DNS provider credentials — export them into acme.sh's own environment beforehand (see the [acme.sh DNS API docs](https://github.com/acmesh-official/acme.sh/wiki/dnsapi)).

What the mode installs:

| Path | Purpose |
| ---- | ------- |
| `~/.acme.sh/acme.sh` | acme.sh itself, installed on demand with `curl` |
| `/etc/nowhere/acme/<domain>_ecc/` | the issued ECDSA P-256 chain and key |
| `/etc/nowhere/acme-reload.sh` | the `--reloadcmd` hook; restarts the service after a renewal |
| `/etc/nowhere/acme-renew.sh` | the cron entry; checks the expiry locally and runs `acme.sh --renew` only inside the renewal window, logging to `/etc/nowhere/acme-renew.log` |
| `/etc/nowhere/certmode.conf` | sidecar recording `mode=` / `domain=` / `autorenew=` / `renewdays=`, because a `tls=2` URL alone cannot tell `acme` from `custom` |
| `17 3 * * *` in root's crontab (or `/etc/cron.d/nowhere-acme`) | the daily check, marked `# oh-nowhere acme.sh auto-renew` |

Auto-renew is on by default, but it is **not** a daily re-issue. The job wakes every day and reads the issued chain's `notAfter` with `openssl`; it only calls `acme.sh --renew` once the certificate is inside its renewal window — the last `--acme-renew-days` days of validity, 30 by default. A Let's Encrypt certificate lives 90 days, so with the default the renewal happens with about two months to spare and the rest of the cycle costs one local `openssl` call and no network traffic. Set `--acme-renew-days 14` to renew later, or a larger number to renew earlier.

```bash
sudo ./oh-nowhere.sh \
  --install \
  --type portal \
  --key a1b2c3d4e5f60718293a4b5c6d7e8f90 \
  --port 2077 \
  --acme-domain relay.example.com \
  --acme-renew-days 14 \
  --host relay.example.com \
  --lang en
```

Re-configuring with `--cert-mode acme` keeps the window already recorded in `certmode.conf` unless you pass `--acme-renew-days` again, and outside the window it leaves the live chain alone rather than spending a duplicate-certificate allowance. `--acme-auto-renew no` skips the cron entry entirely and you renew by hand with `--renew-cert` (menu item `renew`), which forces `acme.sh --renew` and restarts the service. `--status` reports the source, the ACME domain, the schedule and the window. `--uninstall` removes the cron entry and both hooks.

If acme.sh cannot issue the certificate — bad domain, busy port 80, no network — the install stops with an error and nothing is written. Fix the cause and re-run; the other three certificate sources are unaffected.

## Client Share URI

Menu item 11 / `--share` prints one `nowhere://` link per Portal carrier. The QR code encodes the TCP link when one exists. A self-signed Portal includes `pin=` when the fingerprint is available:

```text
nowhere://a1b2c3d4e5f60718293a4b5c6d7e8f90@203.0.113.10:2077?net=tcp&morph=1&pin=8f14e45fceea167a5a36dedd4bea2543b7e6d5c4a3f2918273645a0b1c2d3e4f#Nowhere-US-203
nowhere://a1b2c3d4e5f60718293a4b5c6d7e8f90@203.0.113.10:2077?net=udp&morph=1&pin=8f14e45fceea167a5a36dedd4bea2543b7e6d5c4a3f2918273645a0b1c2d3e4f#Nowhere-US-203
```

`pin=` and `sni=` are mutually exclusive by certificate source: the openssl self-signed mode carries `pin=` (with a pin set the binary ignores the hostname, so no `sni=` is sent), while a custom certificate has no pin and relies on `--host` to put a matching `sni=` in the link. What `pin=` means, and why the program self-signed pin changes after a restart, is covered under "TLS Modes".

* Host prefers `/etc/nowhere/host.conf` (or `--host`); otherwise the detected public IP
* The node name is a percent-encoded `#fragment`; set it with `--name` (default `Nowhere-<country>-<first IP octet>`, stored in `/etc/nowhere/name.conf`)
* `tls`, `crt`, `key`, `out`, `dial`, `rate`, `etar`, and `log` are omitted from the share URI
* Vector and Egress print only the run URL; there is no client import link
* Paste a `nowhere://` URI into configure or `--url` to run a Vector locally

2.x share links use `up` / `down`. See "Older protocol lines" below.

## Modifying the Current Configuration

Menu item **5** edits the stored run URL field by field. Enter a field number to change that value, then press Enter or `q` to save and restart the service.

On nw3 the fields include: key, ports, carrier (Vector has a single `tcp` or `udp`), certificate source, `morph`, the Portal exit `out=` (`direct` / `socks` / `egress`), the SOCKS upstream, Vector `in=`, and for Egress the host / UDP port / SNI / pin, plus the share host and node name. Parameters the editor does not manage (`rate` / `etar` / `dial` / `log`) are kept as-is.

The certificate source field replaces the raw TLS field: choosing `openssl` re-issues the certificate on the spot (validity and SAN are editable) and updates the pin, `program` clears the pin, and `custom` lets you edit the `crt` / `keyfile` paths (changing a path clears the pin too). `acme` re-runs the whole acme.sh flow — domain, email, challenge and auto-renew are all prompted — and points `crt` / `keyfile` at the issued chain.

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
| `--tls <1\|2>` | Portal TLS mode, default `1` (nw3 does not accept `0`); derived from `--cert-mode`, `--tls` is a read-only echo |
| `--cert-mode <program\|openssl\|custom\|acme>` | Certificate source: `program` (`tls=1`), `openssl` (`tls=2` + pin), `custom` (`tls=2` + `--cert`/`--keyfile`), `acme` (`tls=2` via acme.sh, no pin); `1` / `2` / `3` / `4` are also accepted |
| `--self-sign-days <days>` | Validity of the openssl self-signed certificate, 1–36500, default `398` |
| `--cert-san <CSV>` | SAN list for the openssl self-signed certificate, e.g. `DNS:relay.example,IP:203.0.113.10`; defaults to the share host, the public IP and loopback |
| `--cert <path>` | Certificate path for the `custom` source |
| `--keyfile <path>` | Private key path for the `custom` source |
| `--acme-domain <fqdn>` | Domain for the acme.sh certificate; implies `--cert-mode acme`, defaults to `--host` |
| `--acme-email <mail>` | acme.sh account email (optional, used for expiry notices) |
| `--acme-challenge <http\|dns>` | ACME challenge type, default `http` (needs port 80 free); `dns` needs `--acme-dns` |
| `--acme-dns <plugin>` | acme.sh DNS plugin, e.g. `dns_cf`; implies `--acme-challenge dns` |
| `--acme-auto-renew <yes\|no>` | Auto-renew job for the acme.sh certificate, default `yes` |
| `--acme-renew-days <n>` | Renew inside the last `n` days of validity, 1-89, default `30` |
| `--renew-cert` | Renew the live certificate now (`acme` runs `acme.sh --renew`, `openssl` re-self-signs and changes the pin) |
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

Renew the certificate now (acme.sh or openssl sources):

```bash
sudo ./oh-nowhere.sh --renew-cert --lang en
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
/etc/nowhere/pin.conf
/etc/nowhere/certmode.conf
/etc/systemd/system/nowhere.service
/etc/init.d/nowhere
/usr/local/etc/rc.d/nowhere
```

The run URL is `/etc/nowhere/url.conf`. The share host is `/etc/nowhere/host.conf`. The node name is `/etc/nowhere/name.conf`. The openssl-mode pin is `/etc/nowhere/pin.conf`, and `certmode.conf` records which `tls=2` source is live (`program` needs no file, the binary mints its own certificate).

With `--cert-mode acme` the script also keeps `acme/`, `acme-reload.sh`, `acme-renew.sh` and `acme-renew.log` under `/etc/nowhere/`, plus a marked entry in root's crontab or `/etc/cron.d/nowhere-acme`. See "TLS Modes" above.

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
* For a long-lived public service use `--cert-mode openssl` (the pin is stable across restarts) or `--cert-mode custom` with a real certificate and `--host`. The program self-signed pin changes on every Portal restart. See "TLS Modes".
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
