#!/usr/bin/env bash

# Nowhere one-click install / upgrade / management script
# Supports Debian/Ubuntu, Alpine Linux, and FreeBSD (Nowhere 2.0+)
# Project: https://github.com/NodePassProject/Nowhere

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Paths and constants
INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/etc/nowhere"
URL_FILE="${CONFIG_DIR}/url.conf"
HOST_FILE="${CONFIG_DIR}/host.conf"
NAME_FILE="${CONFIG_DIR}/name.conf"
# Certificate pin of an openssl self-signed Portal (tls=2). Absent for tls=1
# (the binary regenerates the certificate on every start) and for a custom
# certificate (clients verify through sni= instead).
PIN_FILE="${CONFIG_DIR}/pin.conf"
DEFAULT_CERT="${CONFIG_DIR}/cert.pem"
DEFAULT_KEYFILE="${CONFIG_DIR}/key.pem"
CERT_MODE_DEFAULT="program"
SELF_SIGN_DAYS_DEFAULT=398
SELF_SIGN_KEY_CURVE="prime256v1"
# acme.sh mode. acme and custom both end up as tls=2 without a pin, so the
# stored run URL cannot tell them apart: the sidecar below records which one
# is live (mode=/domain=/autorenew=) and is the only place auto-renew state is
# kept. ACME_*_FILE/DIR are variables rather than literals so the test suite
# can re-point them at a sandbox.
ACME_BIN="${HOME}/.acme.sh/acme.sh"
ACME_DIR="${CONFIG_DIR}/acme"
ACME_RELOAD_HOOK="${CONFIG_DIR}/acme-reload.sh"
ACME_RENEW_HOOK="${CONFIG_DIR}/acme-renew.sh"
ACME_RENEW_LOG="${CONFIG_DIR}/acme-renew.log"
CERT_MODE_FILE="${CONFIG_DIR}/certmode.conf"
ACME_KEY_LENGTH="ec-256"
ACME_CA_SERVER="letsencrypt"
# The Portal has no HTTP listener, so the http challenge has to run in acme.sh's
# own standalone mode: it binds this port itself for the few seconds of
# validation, which means the port must be free at issue and renewal time.
ACME_HTTP_PORT="80"
ACME_CRON_SCHEDULE="17 3 * * *"
# The job wakes daily but only issues inside this window, the way certbot's
# timer does. Let's Encrypt certificates live 90 days, so the default renews
# with two months to spare and leaves the rest of the cycle as a local check.
ACME_RENEW_DAYS="30"
ACME_CRON_MARK="# oh-nowhere acme.sh auto-renew"
ACME_CRON_D_FILE="/etc/cron.d/nowhere-acme"
# acme.sh account email. Only used when installing acme.sh itself; renewals
# never need it. Empty is legal (acme.sh registers without an address).
ACME_EMAIL=""
PORTAL_LOG="/var/log/nowhere.log"
LAUNCHER="${INSTALL_DIR}/nowhere-launch.sh"
RC_SCRIPT="/usr/local/etc/rc.d/nowhere"
SERVICE_NAME="nowhere"
# A variable for the same reason as the ACME_* paths above: the test suite has to
# be able to re-point it, or a sourced install flow would write the real unit.
SYSTEMD_UNIT_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
GITHUB_REPO="NodePassProject/Nowhere"
GITHUB_API="https://api.github.com/repos/${GITHUB_REPO}/releases/latest"
SCRIPT_REPO="ohmycggk/oh-nowhere"
SCRIPT_BRANCH="main"
SCRIPT_FILENAME="oh-nowhere.sh"
SCRIPT_RAW_URL="https://raw.githubusercontent.com/${SCRIPT_REPO}/${SCRIPT_BRANCH}/${SCRIPT_FILENAME}"
# Manager release. Semver, independent of the Nowhere binary (selected with
# --version). Bump MAJOR for a breaking manager change, MINOR for capability,
# PATCH for a fix. Keep this line parseable: ^SCRIPT_VERSION="[0-9.]+"$
SCRIPT_VERSION="1.0.0"
DEFAULT_ALPN="now/1"
# Recent GNU Nowhere assets are built on Ubuntu 24.04 (glibc 2.39).
GNU_MIN_GLIBC="2.39"

# Detected system info
OS_ID=""
OS_VERSION_ID=""
ARCH=""
LIBC=""
PKG_MANAGER=""
INIT_SYSTEM=""

# CLI mode flag
AUTO_MODE=""

# One-click install arguments
ARG_KEY=""
ARG_PORT=""
ARG_ALPN=""
ARG_HOST=""
ARG_NAME=""
ARG_NET=""
ARG_TLS=""
ARG_CERT=""
ARG_KEYFILE=""
ARG_CERT_MODE=""
ARG_SELF_SIGN_DAYS=""
ARG_CERT_SAN=""
ARG_ACME_DOMAIN=""
ARG_ACME_EMAIL=""
ARG_ACME_CHALLENGE="http"
ARG_ACME_DNS=""
ARG_ACME_AUTO_RENEW="yes"
ARG_ACME_RENEW_DAYS=""
ARG_LANG=""
ARG_VERSION=""
ARG_TYPE=""
ARG_SOCKS=""
ARG_NEXT=""
ARG_UP=""
ARG_DOWN=""
ARG_MUX=""
ARG_SNI=""
ARG_PIN=""
ARG_URL=""
ARG_MORPH=""
ARG_TCP_PORT=""
ARG_UDP_PORT=""
ARG_OUT=""
ARG_ALLOW_BREAKING=""
DEFAULT_SOCKS_IN="127.0.0.1:1080"
TARGET_VERSION=""

# Language
SCRIPT_LANG="zh"
declare -A MSG

# ==================== i18n ====================
t() {
    local key="$1"
    shift
    local msg="${MSG[$key]:-$key}"
    if [[ $# -gt 0 ]]; then
        # shellcheck disable=SC2059
        printf -- "$msg" "$@"
    else
        printf '%s' "$msg"
    fi
}

set_language() {
    local lang="${1:-zh}"
    case "$lang" in
        en|zh|ru) SCRIPT_LANG="$lang" ;;
        *) SCRIPT_LANG="zh" ;;
    esac
    MSG=()

    case "$SCRIPT_LANG" in
        en)
            MSG[err_root]="This script must be run as root"
            MSG[err_os_unknown]="Unable to detect OS"
            MSG[err_os_unsupported]="Only Debian/Ubuntu/Alpine/FreeBSD are supported, detected: %s"
            MSG[err_arch]="Unsupported architecture: %s"
            MSG[err_github]="Failed to fetch latest GitHub release"
            MSG[err_github_parse]="Failed to parse GitHub API response"
            MSG[err_download]="Download failed: %s"
            MSG[err_binary]="nowhere binary not found in archive"
            MSG[err_unknown_opt]="Unknown option: %s"
            MSG[err_invalid_choice]="Invalid choice"
            MSG[err_lang]="Invalid language: %s (use en|zh|ru)"
            MSG[warn_musl]="System may be using musl libc"
            MSG[prompt_musl]="Switch to musl build? [y/N]: "
            MSG[warn_glibc_musl]="System glibc %s is older than %s required by GNU Nowhere builds; using the musl binary"
            MSG[warn_gnu_unusable]="GNU Nowhere binary cannot run on this system (%s); retrying with musl"
            MSG[err_binary_unusable]="nowhere binary cannot run: %s"
            MSG[warn_binary_unusable]="Installed nowhere binary cannot run (%s). Use Upgrade to install a compatible musl build."
            MSG[info_os]="OS: %s %s, Init: %s"
            MSG[info_arch]="Arch: %s, libc: %s"
            MSG[info_install_deps]="Installing dependencies: %s"
            MSG[info_install_openssl]="Installing openssl for the self-signed certificate"
            MSG[info_query_version]="Fetching latest version..."
            MSG[info_download]="Downloading nowhere %s (%s)"
            MSG[info_install_to]="Installing to %s"
            MSG[ok_upgraded]="Nowhere upgraded to %s"
            MSG[ok_installed]="Nowhere %s installed"
            MSG[warn_uninstall]="About to uninstall Nowhere..."
            MSG[prompt_uninstall]="Confirm uninstall? [y/N]: "
            MSG[info_cancelled]="Cancelled"
            MSG[prompt_del_config]="Delete config %s? [y/N]: "
            MSG[ok_uninstalled]="Nowhere uninstalled"
            MSG[warn_svc_missing]="Service not running or not installed"
            MSG[warn_svc_detect]="Unable to detect service status"
            MSG[info_configure]="Configure Nowhere service"
            MSG[prompt_config_intro]="Enter config (press Enter for defaults):"
            MSG[prompt_key]="Shared key [%s]: "
            MSG[prompt_port]="Listen port [%s]: "
            MSG[prompt_alpn]="ALPN [%s]: "
            MSG[prompt_host]="Public hostname for share/SNI (optional) [%s]: "
            MSG[prompt_name]="Node name [%s]: "
            MSG[prompt_net]="Carrier mode (mix/tcp/udp) [%s]: "
            MSG[prompt_morph]="Morph wire mask (0/1) [%s]: "
            MSG[prompt_tcp_port]="TLS/TCP port [%s]: "
            MSG[prompt_udp_port]="QUIC/UDP port [%s]: "
            MSG[prompt_tls]="TLS mode (set by the certificate choice above) [%s]: "
            MSG[prompt_cert_mode]="Certificate source (1=program self-signed, 2=openssl self-signed, 3=custom PEM paths, 4=acme.sh) [%s]: "
            MSG[info_cert_mode_program]="Program self-signed (tls=1): the binary mints the certificate itself, SAN is fixed to localhost, and it is regenerated on every start - the pin changes with it, so redistribute the share URI after each restart."
            MSG[info_cert_mode_openssl]="openssl self-signed (tls=2): this script writes cert.pem/key.pem with a validity you pick and pins the share URI to it. The pin is stable across restarts."
            MSG[info_cert_mode_custom]="Custom certificate (tls=2): point crt=/key= at your own PEM files. Clients verify through sni=, so a public hostname is required."
            MSG[prompt_self_sign_days]="Self-signed validity in days [%s]: "
            MSG[prompt_cert_san]="Certificate SAN list (comma-separated DNS:/IP:) [%s]: "
            MSG[prompt_cert]="Certificate path [%s]: "
            MSG[prompt_keyfile]="Private key path [%s]: "
            MSG[warn_spec_removed]="spec was removed in Nowhere 1.5; ignoring --spec"
            MSG[warn_migrated_spec]="Removed deprecated spec= from %s (Nowhere 1.5)"
            MSG[warn_pool_removed]="pool was removed in Nowhere 1.8 (replaced by mux); ignoring --pool"
            MSG[warn_migrated_pool]="Removed deprecated pool= from %s; added mux=1 where applicable (Nowhere 1.8)"
            MSG[warn_v15_incompat]="Nowhere 1.5+ uses a new wire protocol; upgrade Portal and clients together. 1.6 adds a read-only TUI (Linux-only). 1.7 adds native Portal chaining (next=); every hop must be 1.7.0+. 1.8 replaces the tcp/tcp warm pool with mux=0|1 TLS Mux (pool= removed). 1.8.3 adds mixed carrier policy: up/down accept tcp|udp|mix."
            MSG[warn_v20_incompat]="Nowhere 2.0 is a breaking change: ALPN is fixed to nw2 (alpn= ignored), Portal net= is ignored (carriers are selected by the endpoint path), and 1.x peers cannot connect. Upgrade Portal and clients together. Use --version v1.x.x to keep a 1.x node."
            MSG[warn_v22_incompat]="Nowhere 2.2+ requires Portal keys of 32-64 lowercase hexadecimal characters and verifies Portal certificates by default: tls=1 (self-signed) clients must set pin=<sha256>. A non-conforming stored Portal key is regenerated automatically; redistribute the share URI."
            MSG[warn_key_regenerated]="Stored Portal key in %s did not meet Nowhere 2.2 requirements; a new key was generated. All clients must be updated with the new share URI."
            MSG[warn_next_key_invalid]="next= upstream key in %s does not meet Nowhere 2.2 requirements (32-64 lowercase hex); update the upstream Portal."
            MSG[prompt_v20_upgrade]="Cross-major upgrade/downgrade detected. Continue? [y/N]: "
            MSG[warn_migrated_v20]="Migrated %s to Nowhere 2.0 endpoint syntax (net=/alpn= removed)"
            MSG[warn_migrated_v1]="Migrated %s back to Nowhere 1.x URL syntax (net= restored, morph= removed)"
            MSG[warn_split_ports_v1]="Independent TCP/UDP ports cannot be represented in Nowhere 1.x; collapsing to a single port"
            MSG[warn_alpn_ignored]="Nowhere 2.x uses fixed ALPN nw2 and nw3 does not accept alpn=; ignoring --alpn"
            MSG[err_opt_v2_only]="%s requires Nowhere 2.0+ (use --version v2.x or a 2.x install)"
            MSG[err_freebsd_v1]="FreeBSD packages exist only for Nowhere 2.0+; refusing to install %s"
            MSG[err_freebsd_asset]="No FreeBSD package for %s (expected %s). FreeBSD assets require Nowhere 2.0+ and must be published on that tag"
            MSG[err_vector_star_host]="Vector host cannot be * (use a concrete hostname or IP)"
            MSG[err_net_port_conflict]="--net %s conflicts with the opposite --tcp-port/--udp-port"
            MSG[err_carrier_undeclared]="Carrier policy %s/%s is not available on the declared endpoint"
            MSG[err_invalid_port]="Invalid port: %s"
            MSG[err_invalid_key]="Invalid Portal key: Nowhere 2.2+ requires 32-64 lowercase hexadecimal characters (generate one with: nowhere generate-key)"
            MSG[err_invalid_next_key]="Invalid next= upstream key: Nowhere 2.2+ requires 32-64 lowercase hexadecimal characters on both ends"
            MSG[err_invalid_morph]="Invalid morph: %s (use 0 or 1)"
            MSG[err_invalid_net]="Invalid carrier mode: %s (use mix|tcp|udp)"
            MSG[err_next_removed]="nw3 removed next= chaining: the Portal exits direct, through a SOCKS5 upstream (out=endpoint) or via a registered Egress (out=egress)"
            MSG[err_invalid_out]="Invalid Portal exit: %s (use direct|socks|egress)"
            MSG[err_egress_needs_udp]="out=egress requires a QUIC (UDP) listener on the Portal endpoint"
            MSG[err_egress_requires_nw3]="The egress role requires Nowhere 3 (nw3); this node is on another protocol line"
            MSG[err_preflight_next]="Migration to nw3 would drop next= chaining in %s; reconfigure the Portal exit (out=) first"
            MSG[err_preflight_egress]="Migration back to Nowhere 2.x would drop the egress role in %s; reconfigure as a Portal or Vector first"
            MSG[err_migrate_requires_flag]="Cross-line upgrade requires --allow-protocol-breaking-upgrade or an interactive MIGRATE confirmation"
            MSG[err_out_socks_required]="out=socks requires a SOCKS5 upstream endpoint (use --socks <addr>)"
            MSG[prompt_migrate_confirm]="Type MIGRATE to confirm the protocol-line switch: "
            MSG[info_migrate_flag_accepted]="--allow-protocol-breaking-upgrade accepted; stored URLs will be migrated"
            MSG[warn_url_backed_up]="Existing config backed up to %s"
            MSG[warn_protocol_switch]="Protocol line switch: Nowhere %s -> %s"
            MSG[warn_nw3_protocol]="Nowhere 3 (nw3) is a new protocol line: keys are exactly 32 lowercase hex, Portal exits use out=, Vector uses in=, and unknown parameters are ignored"
            MSG[warn_migrated_nw3]="Migrated %s to nw3 endpoint syntax (socks=/next= -> out=, single carrier, morph stated explicitly)"
            MSG[warn_migrated_nw2]="Migrated %s back to Nowhere 2.2 endpoint syntax (out= -> socks=/next=)"
            MSG[warn_vector_carrier_fallback]="up/down carriers differ; nw3 Vector supports one carrier, using tcp"
            MSG[warn_vector_key_peer]="nw3 requires the Vector key to match the Portal key exactly; verify the peer before starting"
            MSG[label_out]="Out:       %s"
            MSG[label_in]="In:        %s"
            MSG[info_launching_status]="Launching nowhere status (read-only snapshot; Ctrl+C to exit)..."
            MSG[info_configure_egress]="Configuring a Nowhere 3 Egress (outbound QUIC to a Portal with out=egress)"
            MSG[info_egress_no_inbound]="Egress makes an outbound QUIC connection; no inbound firewall port is required on this host."
            MSG[prompt_outbound_mode_nw3]="Portal exit (direct/socks/egress) [%s]: "
            MSG[prompt_carrier_single]="Carrier (tcp/udp) [%s]: "
            MSG[label_share_link_tcp]="Import link (TLS/TCP):"
            MSG[label_share_link_udp]="Import link (QUIC/UDP):"
            MSG[help_opt_out]="      --out <direct|socks|egress>  Portal exit mode (nw3)"
            MSG[help_opt_allow_breaking]="      --allow-protocol-breaking-upgrade  Confirm an nw2<->nw3 protocol-line switch"
            MSG[mf_out]="Portal exit"
            MSG[mf_out_socks]="SOCKS upstream"
            MSG[mf_in]="SOCKS listener (in)"
            MSG[mf_carrier]="Carrier"
            MSG[help_opt_next]="      --next <key@host:port>  Portal native upstream (mutually exclusive with --socks)"
            MSG[prompt_outbound_mode]="Portal outbound (none/socks/next) [%s]: "
            MSG[prompt_next]="Native upstream Portal next=<key@host:port> [%s]: "
            MSG[err_next_socks_mutex]="Portal next= and outbound socks= are mutually exclusive"
            MSG[err_next_required]="Native upstream requires next=<key@host:port>"
            MSG[label_next]="Next:       %s"
            MSG[warn_share_chain]="Chained Portal: next= is server-side only and is not included in the client share URI."
            MSG[warn_sni_missing]="TLS=2 but no public hostname set; share URI omits sni (clients need a certificate covering the share address, or use pin=)."
            MSG[label_generated_url]="Generated URL:"
            MSG[ok_config_updated]="Config updated and service restarted"
            MSG[prompt_save_config]="Save this config? [Y/n]: "
            MSG[ok_config_saved]="Config saved to %s"
            MSG[prompt_install_svc]="Install/update system service? [Y/n]: "
            MSG[warn_no_init]="systemd/openrc/rc.d not detected, skipping service install"
            MSG[ok_svc_installed]="Service installed"
            MSG[prompt_start_svc]="Start/restart service now? [Y/n]: "
            MSG[ok_svc_started]="Service started"
            MSG[info_config_not_saved]="Config not saved"
            MSG[label_current_ver]="Current version: %s"
            MSG[label_latest_ver]="GitHub latest: %s"
            MSG[not_installed]="not installed"
            MSG[info_already_latest]="Already at latest version %s"
            MSG[info_already_target]="Already at target version %s"
            MSG[label_target_ver]="Target version: %s"
            MSG[prompt_force_reinstall]="Force reinstall? [y/N]: "
            MSG[info_skip_force]="One-shot mode: skipping force reinstall"
            MSG[info_svc_restarted]="Service restarted"
            MSG[warn_already_installed]="Installed version detected: %s"
            MSG[prompt_overwrite]="Overwrite install/upgrade? [y/N]: "
            MSG[prompt_config_now]="Configure service now? [Y/n]: "
            MSG[info_skip_config]="Skipped config; choose \"Configure service\" later"
            MSG[info_gen_config]="Generating Nowhere service config..."
            MSG[info_random_key]="Generated random shared key: %s"
            MSG[info_key_hint]="Press Enter to keep it, or type a custom key:"
            MSG[ok_config_written]="Config written to %s"
            MSG[label_run_url]="Run URL: %s"
            MSG[info_share_key]="Shared key: %s"
            MSG[ok_systemd_started]="systemd service started"
            MSG[ok_openrc_started]="openrc service started"
            MSG[ok_rc_started]="FreeBSD rc.d service started"
            MSG[warn_manual_start]="systemd/openrc/rc.d not detected, start manually"
            MSG[warn_no_config]="Config not found; install and configure Nowhere first"
            MSG[share_title]="========== Nowhere Client Share =========="
            MSG[label_qr]="QR code:"
            MSG[label_client_uri]="Client URI:"
            MSG[warn_tls_skip]="TLS=1 (self-signed) on Nowhere 1.x. Clients must skip certificate verification."
            MSG[warn_pin_required]="TLS=1 (self-signed): Nowhere 2.2+ verifies certificates by default, so clients must set pin=<sha256>. Skipping certificate verification is no longer possible."
            MSG[warn_pin_unavailable]="Could not determine the certificate fingerprint. Get it from the Portal startup log (line \"TLS certificate SHA-256 fingerprint: ...\") or run: nowhere fingerprint <nowhere-url>"
            MSG[warn_pin_changes]="The self-signed certificate (and its pin) is regenerated on every Portal restart; redistribute the share URI after restarts."
            MSG[info_pin_fetched]="Certificate pin fetched automatically: %s"
            MSG[label_fingerprint]="Cert pin:   %s"
            MSG[prompt_fetch_pin]="Fetch the Portal certificate fingerprint automatically? [Y/n]: "
            MSG[err_cert_mode_invalid]="Invalid certificate source %s (expected program, openssl, custom or acme)"
            MSG[err_not_configured]="Nowhere is not configured yet; run --config or --install first"
            MSG[err_openssl_missing]="openssl is not available and could not be installed; install it manually or pick another certificate source"
            MSG[err_self_sign_failed]="Failed to generate the self-signed certificate"
            MSG[ok_self_signed]="Self-signed certificate written to %s and %s (valid %s days), pin %s"
            MSG[info_cert_mode_acme]="acme.sh certificate (tls=2): this script drives acme.sh to obtain a real CA-signed certificate for your domain. Clients verify through sni=, so a public hostname and reachable port 80 (or a DNS plugin) are required."
            MSG[prompt_acme_domain]="Domain to issue the certificate for [%s]: "
            MSG[prompt_acme_email]="acme.sh account email (optional, for expiry notices): "
            MSG[prompt_acme_renew_days]="Renew when this many days of validity are left [%s]: "
            MSG[prompt_acme_challenge]="ACME challenge type (http/dns) [%s]: "
            MSG[prompt_acme_dns]="acme.sh DNS plugin (e.g. dns_cf, dns_ali; needs its credentials exported first): "
            MSG[prompt_acme_auto_renew]="Install an auto-renew job for the certificate? (yes/no) [%s]: "
            MSG[err_acme_domain_invalid]="Invalid ACME domain %s (expected a public hostname like relay.example.com)"
            MSG[err_acme_dns_missing]="The dns challenge needs a plugin name via --acme-dns"
            MSG[err_acme_challenge_invalid]="Invalid ACME challenge %s (expected http or dns)"
            MSG[err_acme_auto_renew_invalid]="Invalid auto-renew value %s (expected yes or no)"
            MSG[err_acme_port_busy]="Port %s is in use; the http challenge needs it free. Free the port, or use --acme-challenge dns with a --acme-dns plugin"
            MSG[err_acme_standalone_missing]="socat is required for the http challenge and could not be installed; install socat, or use --acme-challenge dns"
            MSG[err_acme_install_failed]="Could not install acme.sh into %s; check the network and curl, then retry"
            MSG[err_acme_issue_failed]="acme.sh failed to issue a certificate for %s; see the acme.sh log for the reason"
            MSG[err_acme_renew_failed]="acme.sh failed to renew the certificate for %s"
            MSG[err_acme_not_installed]="acme.sh is not installed at %s"
            MSG[err_acme_domain_missing]="The recorded ACME domain is missing; re-run the certificate step with --cert-mode acme"
            MSG[err_acme_renew_days_invalid]="Invalid renewal window: %s (use 1-89 days)"
            MSG[info_acme_cert_kept]="Certificate for %s is valid until %s, more than %s days out; keeping it"
            MSG[warn_acme_renew_failed]="Renewal for %s failed; keeping the existing certificate and letting the auto-renew job retry"
            MSG[warn_acme_cron_unavailable]="No cron daemon found; auto-renew was not scheduled. Renew manually with --renew-cert"
            MSG[info_acme_cron_installed]="Auto-renew scheduled: %s (renews inside the last %s days of validity)"
            MSG[info_install_acme]="Installing acme.sh..."
            MSG[info_install_socat]="Installing socat for the acme.sh standalone challenge..."
            MSG[ok_acme_cert]="acme.sh certificate for %s ready: %s and %s"
            MSG[ok_acme_renew]="Certificate for %s renewed (%s)"
            MSG[info_renew_not_needed]="Nothing to renew in %s mode (the binary mints a new certificate on every start)"
            MSG[err_renew_not_portal]="--renew-cert only applies to a Portal configuration"
            MSG[label_acme_domain]="ACME domain: %s"
            MSG[label_acme_renewal]="ACME renew:  %s"
            MSG[acme_renewal_on]="on (%s, renews inside the last %s days of validity)"
            MSG[acme_renewal_off]="off - renew with --renew-cert"
            MSG[label_cert_mode]="Cert:       %s"
            MSG[label_cert_expires]="Cert until: %s"
            MSG[warn_cert_expired]="The Portal certificate has expired (%s); clients will refuse it. Re-issue it from the configuration menu."
            MSG[warn_cert_expiring]="The Portal certificate expires in %s days (%s)."
            MSG[warn_cert_file_missing]="The Portal certificate file %s is missing; the Portal cannot start with tls=2 until it exists"
            MSG[status_title]="========== Nowhere Status =========="
            MSG[label_binary]="Binary:     %s"
            MSG[label_script]="Script:     %s"
            MSG[label_version]="Nowhere:    %s"
            MSG[label_system]="OS:         %s %s"
            MSG[label_arch_libc]="Arch/libc:  %s/%s"
            MSG[label_config_file]="Config:     %s"
            MSG[label_run_url_status]="Run URL:    %s"
            MSG[not_configured]="not configured"
            MSG[label_svc_status]="Service status:"
            MSG[menu_title]="      Nowhere Manager"
            MSG[menu_script]="  Script:   %s"
            MSG[menu_version]="  Nowhere:  %s"
            MSG[menu_system]="  OS:       %s %s"
            MSG[menu_arch]="  Arch:     %s/%s"
            MSG[menu_install]="One-click install"
            MSG[menu_upgrade]="Upgrade Nowhere"
            MSG[menu_pin_version]="Install specific version"
            MSG[menu_configure]="Configure service"
            MSG[menu_modify]="Modify current configuration"
            MSG[menu_start]="Start service"
            MSG[menu_stop]="Stop service"
            MSG[menu_restart]="Restart service"
            MSG[menu_status]="Show status"
            MSG[menu_renew]="Renew certificate now"
            MSG[menu_tui]="TUI / instance status"
            MSG[menu_share]="Show share URI"
            MSG[menu_qr]="Install QR code support"
            MSG[menu_lang]="Change language"
            MSG[menu_upgrade_script]="Upgrade oh-nowhere script"
            MSG[menu_uninstall]="Uninstall Nowhere"
            MSG[menu_exit]="Exit"
            MSG[menu_service]="Service: %s"
            MSG[menu_svc_running]="running"
            MSG[menu_svc_stopped]="stopped"
            MSG[menu_svc_not_installed]="not installed"
            MSG[modify_title]="Modify Nowhere configuration (role: %s)"
            MSG[modify_hint]="Enter a field number to edit; empty or q saves and applies."
            MSG[prompt_modify_choice]="Field to edit [1-%s] (empty/q = apply): "
            MSG[modify_none]="-"
            MSG[modify_new_url]="New run URL: %s"
            MSG[info_configure_first]="No existing configuration; run one-click install or interactive configuration first."
            MSG[err_invalid_tls]="Invalid TLS mode %s (expected 0, 1, or 2)"
            MSG[err_invalid_mux]="Invalid mux value %s (expected 0 or 1)"
            MSG[warn_port_in_use]="Port %s is already in use"
            MSG[prompt_port_conflict]="Use port %s anyway? [y/N]: "
            MSG[info_port_unchanged]="Keeping current port %s"
            MSG[err_port_in_use]="Port %s is in use; enter a different port"
            MSG[mf_key]="Key"
            MSG[mf_port]="Port"
            MSG[mf_net]="Carrier (net)"
            MSG[mf_tcp_port]="TCP port"
            MSG[mf_udp_port]="UDP port"
            MSG[mf_tls]="TLS mode"
            MSG[mf_cert_mode]="Certificate source"
            MSG[mf_cert]="Cert file"
            MSG[mf_keyfile]="Private key file"
            MSG[mf_alpn]="ALPN"
            MSG[mf_morph]="Morph"
            MSG[mf_up]="Up carrier"
            MSG[mf_down]="Down carrier"
            MSG[mf_mux]="Mux"
            MSG[mf_socks]="SOCKS"
            MSG[mf_next]="Next hop"
            MSG[mf_sni]="SNI"
            MSG[mf_pin]="SPKI pin"
            MSG[mf_outbound]="Outbound mode"
            MSG[mf_share_host]="Share host"
            MSG[mf_name]="Node name"
            MSG[prompt_menu]="Enter option [0-%s]: "
            MSG[ok_start_sent]="Start command sent"
            MSG[ok_stop_sent]="Stop command sent"
            MSG[ok_restart_sent]="Restart command sent"
            MSG[info_exit]="Exit"
            MSG[prompt_continue]="Press Enter to continue..."
            MSG[qr_ready]="QR support already available (%s)"
            MSG[qr_warn_apt]="Will install qrencode via apt. Extra disk use is usually a few MB."
            MSG[qr_warn_apk]="Alpine has no qrencode package. Will install python3 + py3-qrcode instead. This may use tens of MB of disk."
            MSG[qr_warn_pkg]="Will install libqrencode via pkg."
            MSG[prompt_qr_confirm]="Continue install? [y/N]: "
            MSG[info_qr_installing]="Installing QR dependencies..."
            MSG[ok_qr_installed]="QR support installed. Use \"%s\" to show the QR code."
            MSG[err_qr_install]="Failed to install QR dependencies"
            MSG[info_target_version]="Target version: %s"
            MSG[prompt_version]="Enter version (e.g. v1.2.3): "
            MSG[err_version_empty]="Version cannot be empty"
            MSG[ok_target_version_set]="Will install version: %s"
            MSG[info_fetch_versions]="Fetching available versions..."
            MSG[prompt_select_version]="Select version [0=latest, 1-%s]: "
            MSG[err_no_versions]="No releases found"
            MSG[err_invalid_version_choice]="Invalid choice"
            MSG[label_latest_version]="latest"
            MSG[info_lang_set]="Language set to: %s"
            MSG[help_title]="Nowhere one-click install script"
            MSG[help_usage]="Usage:"
            MSG[help_options]="Options:"
            MSG[help_no_opt]="No options: enter interactive menu."
            MSG[help_examples]="Examples:"
            MSG[help_opt_install]="  -i, --install          One-shot install/upgrade and start"
            MSG[help_opt_upgrade]="  -u, --upgrade          One-shot upgrade"
            MSG[help_opt_config]="  -c, --config           Configure service"
            MSG[help_opt_status]="  -s, --status           Show status"
            MSG[help_opt_share]="  -q, --share            Show share URI"
            MSG[help_opt_tui]="      --tui              Launch Nowhere TUI dashboard"
            MSG[help_opt_uninstall]="  --uninstall            One-shot uninstall"
            MSG[help_opt_type]="      --type <portal|vector|egress>  Service role (default portal; egress needs nw3)"
            MSG[help_opt_url]="      --url <uri>       Import portal://, vector://, or nowhere:// URI"
            MSG[help_opt_key]="  -k, --key <key>        Shared key (Nowhere 2.2+ Portal keys: 32-64 lowercase hex)"
            MSG[help_opt_port]="  -p, --port <port>      Listen port (default 2077)"
            MSG[help_opt_alpn]="      --alpn <alpn>      1.x TLS/QUIC ALPN (default now/1); ignored on Nowhere 2.0 (fixed nw2)"
            MSG[help_opt_host]="      --host <hostname>  Public hostname for share URI / SNI"
            MSG[help_opt_name]="      --name <name>      Node name for share URI #fragment (default Nowhere-<country>-<ip octet>)"
            MSG[help_opt_net]="      --net <mix|tcp|udp>  Carrier mode (1.x writes net=; 2.0 maps to endpoint path; default mix)"
            MSG[help_opt_tls]="      --tls <1|2>        TLS mode (default 1)"
            MSG[help_opt_cert]="      --cert <path>      Cert path when TLS=2"
            MSG[help_opt_keyfile]="      --keyfile <path>   Key path when TLS=2"
            MSG[help_opt_cert_mode]="      --cert-mode <m>    program|openssl|custom|acme certificate source (default program)"
            MSG[help_opt_self_sign_days]="      --self-sign-days <n>  openssl self-signed validity in days (default %s)"
            MSG[help_opt_cert_san]="      --cert-san <list>  openssl self-signed SAN, comma-separated DNS:/IP:"
            MSG[help_opt_acme_domain]="      --acme-domain <fqdn>  Domain for the acme.sh certificate (implies --cert-mode acme)"
            MSG[help_opt_acme_email]="      --acme-email <mail>  acme.sh account email (optional)"
            MSG[help_opt_acme_challenge]="      --acme-challenge <http|dns>  ACME challenge type (default http; http needs port 80 free)"
            MSG[help_opt_acme_dns]="      --acme-dns <plugin>  acme.sh DNS plugin; implies --acme-challenge dns"
            MSG[help_opt_acme_auto_renew]="      --acme-auto-renew <yes|no>  Auto-renew job (default yes)"
            MSG[help_opt_acme_renew_days]="      --acme-renew-days <n>  Renew inside the last n days of validity (default 30)"
            MSG[help_opt_renew_cert]="      --renew-cert       Renew the live acme.sh/openssl certificate now"
            MSG[help_opt_socks]="      --socks <addr>    Portal outbound or Vector inbound SOCKS"
            MSG[help_opt_up]="      --up <tcp|udp|mix>  Uplink carrier (default tcp on 2.x, udp on 1.x)"
            MSG[help_opt_down]="      --down <tcp|udp|mix>  Downlink carrier (default tcp on 2.x, udp on 1.x)"
            MSG[help_opt_mux]="      --mux <0|1>       TLS Mux when a direction is tcp or mix (2.x omits/default 0; 1.x tcp/tcp defaults to 1)"
            MSG[help_opt_tcp_port]="      --tcp-port <port> TLS/TCP port (Nowhere 2.0+; independent of --udp-port)"
            MSG[help_opt_udp_port]="      --udp-port <port> QUIC/UDP port (Nowhere 2.0+; independent of --tcp-port)"
            MSG[help_opt_morph]="      --morph <0|1>    Keyed TLS/QUIC wire mask (Nowhere 2.0+; default 0, omitted)"
            MSG[help_opt_sni]="      --sni <name>      Certificate name (Vector or Portal next upstream)"
            MSG[help_opt_pin]="      --pin <sha256>    Certificate pin (Nowhere 2.2+: required for tls=1 self-signed Portal; otherwise Vector or Portal next upstream)"
            MSG[help_opt_version]="  -v, --version <ver>    Install specific version (e.g. v2.0.0 or v1.8.3)"
            MSG[help_opt_lang]="  -l, --lang <en|zh|ru>  Script language (default zh)"
            MSG[prompt_type]="Service type (portal/vector) or paste nowhere:// [%s]: "
            MSG[prompt_type_hint]="Enter portal, vector, or paste a nowhere:// / vector:// / portal:// URL"
            MSG[prompt_portal_host]="Portal host [%s]: "
            MSG[prompt_up]="Uplink carrier (tcp/udp/mix) [%s]: "
            MSG[prompt_down]="Downlink carrier (tcp/udp/mix) [%s]: "
            MSG[prompt_mux]="Use TLS Mux (0/1) [%s]: "
            MSG[prompt_socks_in]="Inbound SOCKS listen [%s]: "
            MSG[prompt_socks_out_enable]="Enable Portal outbound SOCKS? [%s]: "
            MSG[prompt_socks_out]="Outbound SOCKS endpoint [%s]: "
            MSG[prompt_sni]="SNI / cert name (optional, - to clear) [%s]: "
            MSG[prompt_pin]="Cert pin SHA-256 (optional, - to clear) [%s]: "
            MSG[info_configure_portal]="Configuring Portal"
            MSG[info_configure_vector]="Configuring Vector"
            MSG[info_converted_nowhere]="Converted nowhere:// share URI to vector://"
            MSG[warn_migrated_nowhere]="Migrated nowhere:// to vector:// in %s"
            MSG[warn_share_vector]="Current role is Vector; nowhere:// share URI applies to Portal only. Showing run URL:"
            MSG[label_role]="Role:       %s"
            MSG[label_socks]="SOCKS:      %s"
            MSG[err_binary_missing]="nowhere binary not installed; install first"
            MSG[err_invalid_type]="Invalid type: %s (use portal|vector|egress)"
            MSG[err_invalid_carrier]="Invalid carrier: %s (use tcp|udp|mix)"
            MSG[err_invalid_url]="Invalid URL: %s"
            MSG[err_socks_required]="Vector requires an inbound SOCKS listen address"
            MSG[err_portal_host_required]="Vector requires a Portal host"
            MSG[info_launching_tui]="Launching Nowhere TUI (read-only; Ctrl+C to exit)..."
            MSG[info_upgrading_script]="Upgrading oh-nowhere management script..."
            MSG[info_script_already_latest]="Script is already up to date"
            MSG[info_script_versions]="Script version: %s -> %s"
            MSG[warn_script_older]="Remote script %s is older than this copy %s"
            MSG[info_script_restart_hint]="Restart this script to use the new version"
            MSG[prompt_script_upgrade_confirm]="Download and replace the current script? [y/N]: "
            MSG[label_script_path]="Script path: %s"
            MSG[ok_script_upgraded]="Script upgraded (backup: %s)"
            MSG[err_script_download]="Failed to download latest script"
            MSG[err_script_verify]="Downloaded script failed syntax check"
            MSG[err_script_install]="Failed to install updated script"
            MSG[help_opt_upgrade_script]="      --upgrade-script     Upgrade this oh-nowhere script from GitHub"
            MSG[help_opt_script_version]="      --script-version     Print this oh-nowhere version and exit"
            MSG[help_opt_help]="  -h, --help             Show help"
            ;;
        ru)
            MSG[err_root]="Скрипт нужно запускать от root"
            MSG[err_os_unknown]="Не удалось определить ОС"
            MSG[err_os_unsupported]="Поддерживаются только Debian/Ubuntu/Alpine/FreeBSD, обнаружено: %s"
            MSG[err_arch]="Неподдерживаемая архитектура: %s"
            MSG[err_github]="Не удалось получить последний релиз GitHub"
            MSG[err_github_parse]="Ошибка разбора ответа GitHub API"
            MSG[err_download]="Ошибка загрузки: %s"
            MSG[err_binary]="Бинарный файл nowhere не найден в архиве"
            MSG[err_unknown_opt]="Неизвестный параметр: %s"
            MSG[err_invalid_choice]="Неверный выбор"
            MSG[err_lang]="Неверный язык: %s (en|zh|ru)"
            MSG[warn_musl]="Система, возможно, использует musl libc"
            MSG[prompt_musl]="Переключиться на сборку musl? [y/N]: "
            MSG[warn_glibc_musl]="Системный glibc %s старше %s, требуемого GNU-сборками Nowhere; используется musl"
            MSG[warn_gnu_unusable]="GNU-бинарник Nowhere не запускается на этой системе (%s); повтор с musl"
            MSG[err_binary_unusable]="Бинарный файл nowhere не запускается: %s"
            MSG[warn_binary_unusable]="Установленный nowhere не запускается (%s). Выберите обновление, чтобы поставить musl-сборку."
            MSG[info_os]="ОС: %s %s, Init: %s"
            MSG[info_arch]="Архитектура: %s, libc: %s"
            MSG[info_install_deps]="Установка зависимостей: %s"
            MSG[info_install_openssl]="Установка openssl для самоподписанного сертификата"
            MSG[info_query_version]="Получение последней версии..."
            MSG[info_download]="Загрузка nowhere %s (%s)"
            MSG[info_install_to]="Установка в %s"
            MSG[ok_upgraded]="Nowhere обновлён до %s"
            MSG[ok_installed]="Nowhere %s установлен"
            MSG[warn_uninstall]="Будет удален Nowhere..."
            MSG[prompt_uninstall]="Подтвердить удаление? [y/N]: "
            MSG[info_cancelled]="Отменено"
            MSG[prompt_del_config]="Удалить конфиг %s? [y/N]: "
            MSG[ok_uninstalled]="Nowhere удалён"
            MSG[warn_svc_missing]="Служба не запущена или не установлена"
            MSG[warn_svc_detect]="Не удалось определить статус службы"
            MSG[info_configure]="Настройка службы Nowhere"
            MSG[prompt_config_intro]="Введите параметры (Enter — значение по умолчанию):"
            MSG[prompt_key]="Общий ключ [%s]: "
            MSG[prompt_port]="Порт [%s]: "
            MSG[prompt_alpn]="ALPN [%s]: "
            MSG[prompt_host]="Публичное имя для share/SNI (необязательно) [%s]: "
            MSG[prompt_name]="Имя узла [%s]: "
            MSG[prompt_net]="Носитель (mix/tcp/udp) [%s]: "
            MSG[prompt_morph]="Morph (0/1) [%s]: "
            MSG[prompt_tcp_port]="Порт TLS/TCP [%s]: "
            MSG[prompt_udp_port]="Порт QUIC/UDP [%s]: "
            MSG[prompt_tls]="TLS (задаётся выбором сертификата выше) [%s]: "
            MSG[prompt_cert_mode]="Источник сертификата (1=самоподписанный программой, 2=самоподписанный openssl, 3=свои PEM-файлы, 4=acme.sh) [%s]: "
            MSG[info_cert_mode_program]="Самоподписанный программой (tls=1): сертификат создаёт сам бинарник, SAN зафиксирован на localhost, и он пересоздаётся при каждом запуске — pin меняется вместе с ним, поэтому пересылайте share URI после каждого перезапуска."
            MSG[info_cert_mode_openssl]="Самоподписанный openssl (tls=2): скрипт запишет cert.pem/key.pem с выбранным сроком действия и зафиксирует pin в share URI. Pin стабилен между перезапусками."
            MSG[info_cert_mode_custom]="Свой сертификат (tls=2): укажите свои PEM-файлы в crt=/key=. Клиенты проверяют через sni=, поэтому нужно публичное имя."
            MSG[prompt_self_sign_days]="Срок действия самоподписанного сертификата в днях [%s]: "
            MSG[prompt_cert_san]="Список SAN сертификата (через запятую DNS:/IP:) [%s]: "
            MSG[prompt_cert]="Путь к сертификату [%s]: "
            MSG[prompt_keyfile]="Путь к ключу [%s]: "
            MSG[warn_spec_removed]="Параметр spec удалён в Nowhere 1.5; --spec игнорируется"
            MSG[warn_migrated_spec]="Удалён устаревший spec= из %s (Nowhere 1.5)"
            MSG[warn_pool_removed]="Параметр pool удалён в Nowhere 1.8 (заменён на mux); --pool игнорируется"
            MSG[warn_migrated_pool]="Удалён устаревший pool= из %s; при необходимости добавлен mux=1 (Nowhere 1.8)"
            MSG[warn_v15_incompat]="Nowhere 1.5+ использует новый wire-протокол; обновляйте Portal и клиенты вместе. 1.6 добавляет только для чтения TUI (только Linux). 1.7 добавляет цепочку Portal (next=); каждый узел должен быть 1.7.0+. 1.8 заменяет тёплый пул tcp/tcp на TLS Mux mux=0|1 (pool= удалён). 1.8.3 добавляет смешанную политику носителей: up/down принимают tcp|udp|mix."
            MSG[warn_v20_incompat]="Nowhere 2.0 — ломающее изменение: ALPN фиксирован как nw2 (alpn= игнорируется), Portal net= игнорируется (носители задаёт путь endpoint), узлы 1.x не подключаются. Обновляйте Portal и клиенты вместе. Для узла 1.x укажите --version v1.x.x."
            MSG[warn_v22_incompat]="Nowhere 2.2+ требует ключи Portal из 32–64 строчных hex-символов и проверяет сертификаты Portal по умолчанию: клиенты tls=1 (самоподписанный) должны задать pin=<sha256>. Несоответствующий сохранённый ключ Portal будет перегенерирован; разошлите новый share URI."
            MSG[warn_key_regenerated]="Сохранённый ключ Portal в %s не отвечает требованиям Nowhere 2.2; сгенерирован новый ключ. Обновите все клиенты новым share URI."
            MSG[warn_next_key_invalid]="Ключ next= в %s не отвечает требованиям Nowhere 2.2 (32–64 строчных hex); обновите upstream Portal."
            MSG[prompt_v20_upgrade]="Обнаружено изменение мажорной версии. Продолжить? [y/N]: "
            MSG[warn_migrated_v20]="%s мигрирован на синтаксис endpoint Nowhere 2.0 (net=/alpn= удалены)"
            MSG[warn_migrated_v1]="%s возвращён к синтаксису URL Nowhere 1.x (net= восстановлен, morph= удалён)"
            MSG[warn_split_ports_v1]="Раздельные порты TCP/UDP нельзя выразить в Nowhere 1.x; сведены к одному порту"
            MSG[warn_alpn_ignored]="Nowhere 2.x использует фиксированный ALPN nw2, а nw3 не принимает alpn=; --alpn игнорируется"
            MSG[err_opt_v2_only]="%s требует Nowhere 2.0+ (укажите --version v2.x или установите 2.x)"
            MSG[err_freebsd_v1]="Пакеты FreeBSD есть только для Nowhere 2.0+; установка %s отклонена"
            MSG[err_freebsd_asset]="Нет пакета FreeBSD для %s (ожидался %s). Пакеты FreeBSD есть только в Nowhere 2.0+, и этот tag должен содержать freebsd-архив"
            MSG[err_vector_star_host]="Хост Vector не может быть * (укажите конкретное имя или IP)"
            MSG[err_net_port_conflict]="--net %s конфликтует с противоположным --tcp-port/--udp-port"
            MSG[err_carrier_undeclared]="Политика носителей %s/%s недоступна на объявленном endpoint"
            MSG[err_invalid_port]="Неверный порт: %s"
            MSG[err_invalid_key]="Неверный ключ Portal: Nowhere 2.2+ требует 32–64 строчных hex-символа (создайте: nowhere generate-key)"
            MSG[err_invalid_next_key]="Неверный ключ next=: Nowhere 2.2+ требует 32–64 строчных hex-символа с обеих сторон"
            MSG[err_invalid_morph]="Неверный morph: %s (0 или 1)"
            MSG[err_invalid_net]="Неверный режим носителя: %s (mix|tcp|udp)"
            MSG[err_next_removed]="nw3 убрал цепочки next=: Portal выходит напрямую, через SOCKS5-апстрим (out=endpoint) или через зарегистрированный Egress (out=egress)"
            MSG[err_invalid_out]="Неверный выход Portal: %s (direct|socks|egress)"
            MSG[err_egress_needs_udp]="out=egress требует QUIC (UDP) приёмник на endpoint Portal"
            MSG[err_egress_requires_nw3]="Роль egress требует Nowhere 3 (nw3); этот узел на другой линии протокола"
            MSG[err_preflight_next]="Миграция на nw3 отбросит цепочку next= в %s; сначала перенастройте выход Portal (out=)"
            MSG[err_preflight_egress]="Возврат на Nowhere 2.x отбросит роль egress в %s; перенастройте как Portal или Vector"
            MSG[err_migrate_requires_flag]="Переход между линиями требует --allow-protocol-breaking-upgrade или интерактивного подтверждения MIGRATE"
            MSG[err_out_socks_required]="out=socks требует адрес SOCKS5-апстрима (используйте --socks <addr>)"
            MSG[prompt_migrate_confirm]="Введите MIGRATE для подтверждения перехода на другую линию протокола: "
            MSG[info_migrate_flag_accepted]="--allow-protocol-breaking-upgrade принят; сохранённые URL будут мигрированы"
            MSG[warn_url_backed_up]="Существующий конфиг сохранён в %s"
            MSG[warn_protocol_switch]="Смена линии протокола: Nowhere %s -> %s"
            MSG[warn_nw3_protocol]="Nowhere 3 (nw3) — новая линия протокола: ключи ровно 32 строчных hex, выход Portal через out=, Vector через in=, неизвестные параметры игнорируются"
            MSG[warn_migrated_nw3]="%s мигрирован в синтаксис endpoint nw3 (socks=/next= -> out=, один носитель, morph указан явно)"
            MSG[warn_migrated_nw2]="%s мигрирован обратно в синтаксис Nowhere 2.2 (out= -> socks=/next=)"
            MSG[warn_vector_carrier_fallback]="носители up/down различаются; nw3 Vector поддерживает один носитель, используется tcp"
            MSG[warn_vector_key_peer]="nw3 требует точного совпадения ключа Vector с ключом Portal; проверьте peer перед запуском"
            MSG[label_out]="Выход:     %s"
            MSG[label_in]="Вход:      %s"
            MSG[info_launching_status]="Запуск nowhere status (снимок только для чтения; Ctrl+C для выхода)..."
            MSG[info_configure_egress]="Настройка Egress Nowhere 3 (исходящий QUIC к Portal с out=egress)"
            MSG[info_egress_no_inbound]="Egress устанавливает исходящее QUIC-соединение; входящий порт файрвола на этом хосте не нужен."
            MSG[prompt_outbound_mode_nw3]="Выход Portal (direct/socks/egress) [%s]: "
            MSG[prompt_carrier_single]="Носитель (tcp/udp) [%s]: "
            MSG[label_share_link_tcp]="Ссылка импорта (TLS/TCP):"
            MSG[label_share_link_udp]="Ссылка импорта (QUIC/UDP):"
            MSG[help_opt_out]="      --out <direct|socks|egress>  Режим выхода Portal (nw3)"
            MSG[help_opt_allow_breaking]="      --allow-protocol-breaking-upgrade  Подтвердить переход линии протокола nw2<->nw3"
            MSG[mf_out]="Выход Portal"
            MSG[mf_out_socks]="SOCKS-апстрим"
            MSG[mf_in]="SOCKS-приёмник (in)"
            MSG[mf_carrier]="Носитель"
            MSG[help_opt_next]="      --next <key@host:port>  Следующий Portal (next=; несовместимо с --socks)"
            MSG[prompt_outbound_mode]="Исходящий Portal (none/socks/next) [%s]: "
            MSG[prompt_next]="Следующий Portal next=<key@host:port> [%s]: "
            MSG[err_next_socks_mutex]="Portal next= и исходящий socks= несовместимы"
            MSG[err_next_required]="Для native upstream нужен next=<key@host:port>"
            MSG[label_next]="Next:       %s"
            MSG[warn_share_chain]="Цепочка Portal: next= только на сервере и не попадает в share URI клиента."
            MSG[warn_sni_missing]="TLS=2, но публичное имя не задано; в share URI нет sni (клиенту нужен сертификат, покрывающий адрес шаринга, или pin=)."
            MSG[label_generated_url]="Сгенерированный URL:"
            MSG[ok_config_updated]="Конфиг обновлён, служба перезапущена"
            MSG[prompt_save_config]="Сохранить конфиг? [Y/n]: "
            MSG[ok_config_saved]="Конфиг сохранён в %s"
            MSG[prompt_install_svc]="Установить/обновить системную службу? [Y/n]: "
            MSG[warn_no_init]="systemd/openrc/rc.d не найдены, установка службы пропущена"
            MSG[ok_svc_installed]="Служба установлена"
            MSG[prompt_start_svc]="Запустить/перезапустить службу сейчас? [Y/n]: "
            MSG[ok_svc_started]="Служба запущена"
            MSG[info_config_not_saved]="Конфиг не сохранён"
            MSG[label_current_ver]="Текущая версия: %s"
            MSG[label_latest_ver]="Последняя на GitHub: %s"
            MSG[not_installed]="не установлен"
            MSG[info_already_latest]="Уже последняя версия %s"
            MSG[info_already_target]="Уже целевая версия %s"
            MSG[label_target_ver]="Целевая версия: %s"
            MSG[prompt_force_reinstall]="Принудительно переустановить? [y/N]: "
            MSG[info_skip_force]="Одноразовый режим: принудительная переустановка пропущена"
            MSG[info_svc_restarted]="Служба перезапущена"
            MSG[warn_already_installed]="Обнаружена установленная версия: %s"
            MSG[prompt_overwrite]="Переустановить/обновить? [y/N]: "
            MSG[prompt_config_now]="Настроить службу сейчас? [Y/n]: "
            MSG[info_skip_config]="Настройка пропущена; позже выберите «Настройка службы»"
            MSG[info_gen_config]="Создание конфига службы Nowhere..."
            MSG[info_random_key]="Сгенерирован случайный ключ: %s"
            MSG[info_key_hint]="Enter — оставить, или введите свой ключ:"
            MSG[ok_config_written]="Конфиг записан в %s"
            MSG[label_run_url]="URL запуска: %s"
            MSG[info_share_key]="Общий ключ: %s"
            MSG[ok_systemd_started]="Служба systemd запущена"
            MSG[ok_openrc_started]="Служба openrc запущена"
            MSG[ok_rc_started]="Служба FreeBSD rc.d запущена"
            MSG[warn_manual_start]="systemd/openrc/rc.d не найдены, запустите вручную"
            MSG[warn_no_config]="Конфиг не найден; сначала установите и настройте Nowhere"
            MSG[share_title]="========== Поделиться клиентом Nowhere =========="
            MSG[label_qr]="QR-код:"
            MSG[label_client_uri]="URI клиента:"
            MSG[warn_tls_skip]="TLS=1 (самоподписанный сертификат) на Nowhere 1.x. Клиенту нужно пропустить проверку сертификата."
            MSG[warn_pin_required]="TLS=1 (самоподписанный): Nowhere 2.2+ проверяет сертификаты по умолчанию — клиенты должны задать pin=<sha256>. Пропустить проверку сертификата больше нельзя."
            MSG[warn_pin_unavailable]="Не удалось определить отпечаток сертификата. Возьмите его из лога запуска Portal (строка «TLS certificate SHA-256 fingerprint: ...») или выполните: nowhere fingerprint <nowhere-url>"
            MSG[warn_pin_changes]="Самоподписанный сертификат (и его pin) пересоздаётся при каждом перезапуске Portal; пересылайте share URI после перезапусков."
            MSG[info_pin_fetched]="Отпечаток сертификата получен автоматически: %s"
            MSG[label_fingerprint]="Pin серта:  %s"
            MSG[prompt_fetch_pin]="Получить отпечаток сертификата Portal автоматически? [Y/n]: "
            MSG[err_cert_mode_invalid]="Неверный источник сертификата %s (ожидалось program, openssl, custom или acme)"
            MSG[err_not_configured]="Nowhere ещё не настроен; сначала запустите --config или --install"
            MSG[err_openssl_missing]="openssl недоступен и не удалось его установить; установите вручную или выберите другой источник сертификата"
            MSG[err_self_sign_failed]="Не удалось создать самоподписанный сертификат"
            MSG[ok_self_signed]="Самоподписанный сертификат записан в %s и %s (срок %s дней), pin %s"
            MSG[info_cert_mode_acme]="Сертификат acme.sh (tls=2): скрипт запускает acme.sh для получения настоящего сертификата от CA для вашего домена. Клиенты проверяют через sni=, поэтому нужны публичное имя и доступный порт 80 (или DNS-плагин)."
            MSG[prompt_acme_domain]="Домен для выпуска сертификата [%s]: "
            MSG[prompt_acme_email]="Email аккаунта acme.sh (необязательно, для уведомлений об истечении): "
            MSG[prompt_acme_challenge]="Тип проверки ACME (http/dns) [%s]: "
            MSG[prompt_acme_dns]="DNS-плагин acme.sh (например dns_cf, dns_ali; его учётные данные должны быть экспортированы заранее): "
            MSG[prompt_acme_auto_renew]="Установить задание автообновления сертификата? (yes/no) [%s]: "
            MSG[prompt_acme_renew_days]="Обновлять, когда остаётся столько дней действия [%s]: "
            MSG[err_acme_domain_invalid]="Неверный домен ACME %s (ожидалось публичное имя вида relay.example.com)"
            MSG[err_acme_dns_missing]="Для проверки dns нужно имя плагина через --acme-dns"
            MSG[err_acme_challenge_invalid]="Неверный тип проверки ACME %s (ожидалось http или dns)"
            MSG[err_acme_auto_renew_invalid]="Неверное значение автообновления %s (ожидалось yes или no)"
            MSG[err_acme_port_busy]="Порт %s занят; для проверки http он должен быть свободен. Освободите порт или используйте --acme-challenge dns с плагином --acme-dns"
            MSG[err_acme_standalone_missing]="Для проверки http нужен socat, установить его не удалось; установите socat или используйте --acme-challenge dns"
            MSG[err_acme_install_failed]="Не удалось установить acme.sh в %s; проверьте сеть и curl, затем повторите"
            MSG[err_acme_issue_failed]="acme.sh не смог выпустить сертификат для %s; причину смотрите в журнале acme.sh"
            MSG[err_acme_renew_failed]="acme.sh не смог обновить сертификат для %s"
            MSG[err_acme_not_installed]="acme.sh не установлен по пути %s"
            MSG[err_acme_domain_missing]="Записанный домен ACME отсутствует; повторите шаг сертификата с --cert-mode acme"
            MSG[err_acme_renew_days_invalid]="Неверное окно обновления: %s (допустимо 1-89 дней)"
            MSG[info_acme_cert_kept]="Сертификат для %s действителен до %s, это больше %s дней; оставляем как есть"
            MSG[warn_acme_renew_failed]="Обновление для %s не удалось; оставляем текущий сертификат, задание автообновления повторит попытку"
            MSG[warn_acme_cron_unavailable]="Демон cron не найден; автообновление не запланировано. Обновляйте вручную через --renew-cert"
            MSG[info_acme_cron_installed]="Автообновление запланировано: %s (обновление в последние %s дня действия)"
            MSG[info_install_acme]="Установка acme.sh..."
            MSG[info_install_socat]="Установка socat для standalone-проверки acme.sh..."
            MSG[ok_acme_cert]="Сертификат acme.sh для %s готов: %s и %s"
            MSG[ok_acme_renew]="Сертификат для %s обновлён (%s)"
            MSG[info_renew_not_needed]="В режиме %s обновлять нечего (бинарник создаёт новый сертификат при каждом запуске)"
            MSG[err_renew_not_portal]="--renew-cert применяется только к конфигурации Portal"
            MSG[label_acme_domain]="Домен ACME:  %s"
            MSG[label_acme_renewal]="Обновление:  %s"
            MSG[acme_renewal_on]="включено (%s, обновление в последние %s дней действия)"
            MSG[acme_renewal_off]="выключено - обновите через --renew-cert"
            MSG[label_cert_mode]="Сертификат: %s"
            MSG[label_cert_expires]="Действует до: %s"
            MSG[warn_cert_expired]="Срок действия сертификата Portal истёк (%s); клиенты его отклонят. Перевыпустите его в меню конфигурации."
            MSG[warn_cert_expiring]="Срок действия сертификата Portal истекает через %s дней (%s)."
            MSG[warn_cert_file_missing]="Файл сертификата Portal %s отсутствует; с tls=2 Portal не запустится, пока он не появится"
            MSG[status_title]="========== Статус Nowhere =========="
            MSG[label_binary]="Бинарник:   %s"
            MSG[label_script]="Скрипт:     %s"
            MSG[label_version]="Nowhere:    %s"
            MSG[label_system]="ОС:         %s %s"
            MSG[label_arch_libc]="Arch/libc:  %s/%s"
            MSG[label_config_file]="Конфиг:     %s"
            MSG[label_run_url_status]="URL:        %s"
            MSG[not_configured]="не настроен"
            MSG[label_svc_status]="Статус службы:"
            MSG[menu_title]="      Менеджер Nowhere"
            MSG[menu_script]="  Скрипт:   %s"
            MSG[menu_version]="  Nowhere:  %s"
            MSG[menu_system]="  ОС:       %s %s"
            MSG[menu_arch]="  Arch:     %s/%s"
            MSG[menu_install]="Однократная установка"
            MSG[menu_upgrade]="Обновить Nowhere"
            MSG[menu_pin_version]="Установить указанную версию"
            MSG[menu_configure]="Настроить службу"
            MSG[menu_modify]="Изменить текущую конфигурацию"
            MSG[menu_start]="Запустить службу"
            MSG[menu_stop]="Остановить службу"
            MSG[menu_restart]="Перезапустить службу"
            MSG[menu_status]="Показать статус"
            MSG[menu_renew]="Обновить сертификат сейчас"
            MSG[menu_tui]="TUI / статус инстанса"
            MSG[menu_share]="Показать URI для шаринга"
            MSG[menu_qr]="Установить поддержку QR"
            MSG[menu_lang]="Сменить язык"
            MSG[menu_upgrade_script]="Обновить скрипт oh-nowhere"
            MSG[menu_uninstall]="Удалить Nowhere"
            MSG[menu_exit]="Выход"
            MSG[menu_service]="Служба: %s"
            MSG[menu_svc_running]="работает"
            MSG[menu_svc_stopped]="остановлена"
            MSG[menu_svc_not_installed]="не установлена"
            MSG[modify_title]="Изменение конфигурации Nowhere (роль: %s)"
            MSG[modify_hint]="Введите номер поля для изменения; пусто или q — сохранить и применить."
            MSG[prompt_modify_choice]="Поле для изменения [1-%s] (пусто/q — применить): "
            MSG[modify_none]="-"
            MSG[modify_new_url]="Новый URL запуска: %s"
            MSG[info_configure_first]="Существующая конфигурация не найдена; сначала выполните установку в один клик или интерактивную настройку."
            MSG[err_invalid_tls]="Неверный режим TLS %s (ожидалось 0, 1 или 2)"
            MSG[err_invalid_mux]="Неверное значение mux %s (ожидалось 0 или 1)"
            MSG[warn_port_in_use]="Порт %s уже занят"
            MSG[prompt_port_conflict]="Всё равно использовать порт %s? [y/N]: "
            MSG[info_port_unchanged]="Текущий порт %s сохранён"
            MSG[err_port_in_use]="Порт %s занят; введите другой порт"
            MSG[mf_key]="Ключ"
            MSG[mf_port]="Порт"
            MSG[mf_net]="Носитель (net)"
            MSG[mf_tcp_port]="Порт TCP"
            MSG[mf_udp_port]="Порт UDP"
            MSG[mf_tls]="Режим TLS"
            MSG[mf_cert_mode]="Источник сертификата"
            MSG[mf_cert]="Файл сертификата"
            MSG[mf_keyfile]="Файл закрытого ключа"
            MSG[mf_alpn]="ALPN"
            MSG[mf_morph]="Morph"
            MSG[mf_up]="Носитель up"
            MSG[mf_down]="Носитель down"
            MSG[mf_mux]="Mux"
            MSG[mf_socks]="SOCKS"
            MSG[mf_next]="Следующий узел"
            MSG[mf_sni]="SNI"
            MSG[mf_pin]="SPKI pin"
            MSG[mf_outbound]="Исходящий режим"
            MSG[mf_share_host]="Адрес для шаринга"
            MSG[mf_name]="Имя узла"
            MSG[prompt_menu]="Введите пункт [0-%s]: "
            MSG[ok_start_sent]="Команда запуска отправлена"
            MSG[ok_stop_sent]="Команда остановки отправлена"
            MSG[ok_restart_sent]="Команда перезапуска отправлена"
            MSG[info_exit]="Выход"
            MSG[prompt_continue]="Нажмите Enter для продолжения..."
            MSG[qr_ready]="Поддержка QR уже доступна (%s)"
            MSG[qr_warn_apt]="Будет установлен qrencode через apt. Обычно занимает несколько МБ."
            MSG[qr_warn_apk]="В Alpine нет пакета qrencode. Будут установлены python3 + py3-qrcode. Может занять десятки МБ."
            MSG[qr_warn_pkg]="Будет установлен libqrencode через pkg."
            MSG[prompt_qr_confirm]="Продолжить установку? [y/N]: "
            MSG[info_qr_installing]="Установка зависимостей QR..."
            MSG[ok_qr_installed]="Поддержка QR установлена. Пункт «%s» покажет QR-код."
            MSG[err_qr_install]="Не удалось установить зависимости QR"
            MSG[info_target_version]="Целевая версия: %s"
            MSG[prompt_version]="Введите версию (например v1.2.3): "
            MSG[err_version_empty]="Версия не может быть пустой"
            MSG[ok_target_version_set]="Будет установлена версия: %s"
            MSG[info_fetch_versions]="Получение доступных версий..."
            MSG[prompt_select_version]="Выберите версию [0=последняя, 1-%s]: "
            MSG[err_no_versions]="Релизы не найдены"
            MSG[err_invalid_version_choice]="Неверный выбор"
            MSG[label_latest_version]="последняя"
            MSG[info_lang_set]="Язык установлен: %s"
            MSG[help_title]="Скрипт однократной установки Nowhere"
            MSG[help_usage]="Использование:"
            MSG[help_options]="Параметры:"
            MSG[help_no_opt]="Без параметров: интерактивное меню."
            MSG[help_examples]="Примеры:"
            MSG[help_opt_install]="  -i, --install          Установка/обновление и запуск"
            MSG[help_opt_upgrade]="  -u, --upgrade          Обновление"
            MSG[help_opt_config]="  -c, --config           Настройка службы"
            MSG[help_opt_status]="  -s, --status           Статус"
            MSG[help_opt_share]="  -q, --share            URI для шаринга"
            MSG[help_opt_tui]="      --tui              Запустить панель Nowhere TUI"
            MSG[help_opt_uninstall]="  --uninstall            Удаление"
            MSG[help_opt_type]="      --type <portal|vector|egress>  Роль службы (по умолчанию portal; egress требует nw3)"
            MSG[help_opt_url]="      --url <uri>       Импорт portal://, vector:// или nowhere:// URI"
            MSG[help_opt_key]="  -k, --key <ключ>       Общий ключ (ключи Portal в Nowhere 2.2+: 32–64 строчных hex)"
            MSG[help_opt_port]="  -p, --port <порт>      Порт (по умолчанию 2077)"
            MSG[help_opt_alpn]="      --alpn <alpn>      ALPN для 1.x (по умолчанию now/1); в Nowhere 2.0 игнорируется (nw2)"
            MSG[help_opt_host]="      --host <hostname>  Публичное имя для share URI / SNI"
            MSG[help_opt_name]="      --name <имя>       Имя узла для #фрагмента share URI (по умолчанию Nowhere-<страна>-<октет IP>)"
            MSG[help_opt_net]="      --net <mix|tcp|udp>  Носитель (1.x пишет net=; 2.0 — путь endpoint; по умолчанию mix)"
            MSG[help_opt_tls]="      --tls <1|2>        Режим TLS (по умолчанию 1)"
            MSG[help_opt_cert]="      --cert <путь>      Сертификат при TLS=2"
            MSG[help_opt_keyfile]="      --keyfile <путь>   Ключ при TLS=2"
            MSG[help_opt_cert_mode]="      --cert-mode <реж>   program|openssl|custom|acme — источник сертификата (по умолчанию program)"
            MSG[help_opt_self_sign_days]="      --self-sign-days <n>  срок самоподписанного openssl в днях (по умолчанию %s)"
            MSG[help_opt_cert_san]="      --cert-san <список>  SAN самоподписанного openssl, через запятую DNS:/IP:"
            MSG[help_opt_acme_domain]="      --acme-domain <fqdn>  Домен для сертификата acme.sh (включает --cert-mode acme)"
            MSG[help_opt_acme_email]="      --acme-email <почта>  Email аккаунта acme.sh (необязательно)"
            MSG[help_opt_acme_challenge]="      --acme-challenge <http|dns>  Тип проверки ACME (по умолчанию http; http требует свободный порт 80)"
            MSG[help_opt_acme_dns]="      --acme-dns <плагин>  DNS-плагин acme.sh; включает --acme-challenge dns"
            MSG[help_opt_acme_auto_renew]="      --acme-auto-renew <yes|no>  Задание автообновления (по умолчанию yes)"
            MSG[help_opt_acme_renew_days]="      --acme-renew-days <n>  Обновлять в последние n дней действия (по умолчанию 30)"
            MSG[help_opt_renew_cert]="      --renew-cert       Обновить текущий сертификат acme.sh/openssl сейчас"
            MSG[help_opt_socks]="      --socks <addr>    Исходящий SOCKS Portal или входящий SOCKS Vector"
            MSG[help_opt_up]="      --up <tcp|udp|mix>  Uplink (по умолчанию tcp на 2.x, udp на 1.x)"
            MSG[help_opt_down]="      --down <tcp|udp|mix>  Downlink (по умолчанию tcp на 2.x, udp на 1.x)"
            MSG[help_opt_mux]="      --mux <0|1>       TLS Mux, если направление tcp или mix (2.x по умолчанию 0; 1.x tcp/tcp → 1)"
            MSG[help_opt_tcp_port]="      --tcp-port <порт> Порт TLS/TCP (Nowhere 2.0+)"
            MSG[help_opt_udp_port]="      --udp-port <порт> Порт QUIC/UDP (Nowhere 2.0+)"
            MSG[help_opt_morph]="      --morph <0|1>    Маскировка TLS/QUIC (Nowhere 2.0+; по умолчанию 0)"
            MSG[help_opt_sni]="      --sni <имя>       Имя сертификата (Vector или Portal next)"
            MSG[help_opt_pin]="      --pin <sha256>    Pin сертификата (Nowhere 2.2+: обязателен для самоподписанного Portal tls=1; иначе Vector или next)"
            MSG[help_opt_version]="  -v, --version <ver>    Установить указанную версию (например v2.0.0 или v1.8.3)"
            MSG[help_opt_lang]="  -l, --lang <en|zh|ru>  Язык скрипта (по умолчанию zh)"
            MSG[prompt_type]="Тип службы (portal/vector) или вставьте nowhere:// [%s]: "
            MSG[prompt_type_hint]="Введите portal, vector или вставьте nowhere:// / vector:// / portal:// URL"
            MSG[prompt_portal_host]="Хост Portal [%s]: "
            MSG[prompt_up]="Uplink (tcp/udp/mix) [%s]: "
            MSG[prompt_down]="Downlink (tcp/udp/mix) [%s]: "
            MSG[prompt_mux]="TLS Mux (0/1) [%s]: "
            MSG[prompt_socks_in]="Входящий SOCKS [%s]: "
            MSG[prompt_socks_out_enable]="Включить исходящий SOCKS Portal? [%s]: "
            MSG[prompt_socks_out]="Исходящий SOCKS [%s]: "
            MSG[prompt_sni]="SNI (необязательно, - очистить) [%s]: "
            MSG[prompt_pin]="Pin SHA-256 (необязательно, - очистить) [%s]: "
            MSG[info_configure_portal]="Настройка Portal"
            MSG[info_configure_vector]="Настройка Vector"
            MSG[info_converted_nowhere]="nowhere:// преобразован в vector://"
            MSG[warn_migrated_nowhere]="nowhere:// мигрирован в vector:// в %s"
            MSG[warn_share_vector]="Текущая роль — Vector; nowhere:// только для Portal. Текущий URL:"
            MSG[label_role]="Роль:       %s"
            MSG[label_socks]="SOCKS:      %s"
            MSG[err_binary_missing]="Бинарник nowhere не установлен"
            MSG[err_invalid_type]="Неверный тип: %s (portal|vector|egress)"
            MSG[err_invalid_carrier]="Неверный носитель: %s (tcp|udp|mix)"
            MSG[err_invalid_url]="Неверный URL: %s"
            MSG[err_socks_required]="Vector требует адрес входящего SOCKS"
            MSG[err_portal_host_required]="Vector требует хост Portal"
            MSG[info_launching_tui]="Запуск Nowhere TUI (только чтение; Ctrl+C для выхода)..."
            MSG[info_upgrading_script]="Обновление скрипта управления oh-nowhere..."
            MSG[info_script_already_latest]="Скрипт уже актуален"
            MSG[info_script_versions]="Версия скрипта: %s -> %s"
            MSG[warn_script_older]="Удалённый скрипт %s старше этой копии %s"
            MSG[info_script_restart_hint]="Перезапустите скрипт, чтобы использовать новую версию"
            MSG[prompt_script_upgrade_confirm]="Скачать и заменить текущий скрипт? [y/N]: "
            MSG[label_script_path]="Путь к скрипту: %s"
            MSG[ok_script_upgraded]="Скрипт обновлён (резервная копия: %s)"
            MSG[err_script_download]="Не удалось скачать последнюю версию скрипта"
            MSG[err_script_verify]="Скачанный скрипт не прошёл проверку синтаксиса"
            MSG[err_script_install]="Не удалось установить обновлённый скрипт"
            MSG[help_opt_upgrade_script]="      --upgrade-script     Обновить этот скрипт oh-nowhere с GitHub"
            MSG[help_opt_script_version]="      --script-version     Показать версию oh-nowhere и выйти"
            MSG[help_opt_help]="  -h, --help             Справка"
            ;;
        *)
            # zh (default)
            MSG[err_root]="此脚本需要 root 权限运行"
            MSG[err_os_unknown]="无法识别系统"
            MSG[err_os_unsupported]="仅支持 Debian/Ubuntu/Alpine/FreeBSD，检测到: %s"
            MSG[err_arch]="不支持的架构: %s"
            MSG[err_github]="无法获取 GitHub 最新版本"
            MSG[err_github_parse]="解析 GitHub API 失败"
            MSG[err_download]="下载失败: %s"
            MSG[err_binary]="压缩包中未找到 nowhere 二进制"
            MSG[err_unknown_opt]="未知选项: %s"
            MSG[err_invalid_choice]="无效选择"
            MSG[err_lang]="无效语言: %s（使用 en|zh|ru）"
            MSG[warn_musl]="检测到系统可能使用 musl libc"
            MSG[prompt_musl]="是否切换到 musl 构建版本? [y/N]: "
            MSG[warn_glibc_musl]="系统 glibc %s 低于 GNU 构建所需的 %s，改用 musl 二进制"
            MSG[warn_gnu_unusable]="GNU 构建无法在本机运行（%s）；改下 musl 版本"
            MSG[err_binary_unusable]="nowhere 二进制无法运行: %s"
            MSG[warn_binary_unusable]="已安装的 nowhere 无法运行（%s）。请选择「升级 Nowhere」安装兼容的 musl 构建。"
            MSG[info_os]="系统: %s %s, Init: %s"
            MSG[info_arch]="架构: %s, libc: %s"
            MSG[info_install_deps]="安装依赖: %s"
            MSG[info_install_openssl]="正在安装 openssl 用于自签证书"
            MSG[info_query_version]="查询最新版本..."
            MSG[info_download]="下载 nowhere %s (%s)"
            MSG[info_install_to]="安装到 %s"
            MSG[ok_upgraded]="Nowhere 已升级至 %s"
            MSG[ok_installed]="Nowhere %s 安装完成"
            MSG[warn_uninstall]="即将卸载 Nowhere..."
            MSG[prompt_uninstall]="确认卸载? [y/N]: "
            MSG[info_cancelled]="已取消"
            MSG[prompt_del_config]="删除配置文件 %s? [y/N]: "
            MSG[ok_uninstalled]="Nowhere 已卸载"
            MSG[warn_svc_missing]="服务未运行或未安装"
            MSG[warn_svc_detect]="无法检测服务状态"
            MSG[info_configure]="配置 Nowhere 服务"
            MSG[prompt_config_intro]="请输入配置参数（直接回车使用默认值）："
            MSG[prompt_key]="共享密钥 [%s]: "
            MSG[prompt_port]="监听端口 [%s]: "
            MSG[prompt_alpn]="ALPN [%s]: "
            MSG[prompt_host]="分享/SNI 用的公网主机名（可选）[%s]: "
            MSG[prompt_name]="节点名称 [%s]: "
            MSG[prompt_net]="载体模式 (mix/tcp/udp) [%s]: "
            MSG[prompt_morph]="Morph 线形伪装 (0/1) [%s]: "
            MSG[prompt_tcp_port]="TLS/TCP 端口 [%s]: "
            MSG[prompt_udp_port]="QUIC/UDP 端口 [%s]: "
            MSG[prompt_tls]="TLS 模式（由上方的证书抉择决定）[%s]: "
            MSG[prompt_cert_mode]="证书来源 (1=程序自签, 2=openssl 自签, 3=自定义 PEM 路径, 4=acme.sh) [%s]: "
            MSG[info_cert_mode_program]="程序自签（tls=1）：证书由二进制自己生成，SAN 固定为 localhost，且每次启动都会重新生成 —— pin 随之改变，重启后需重新分发分享 URI。"
            MSG[info_cert_mode_openssl]="openssl 自签（tls=2）：由本脚本生成 cert.pem/key.pem，有效期自选，并把 pin 固定进分享 URI。pin 跨重启保持稳定。"
            MSG[info_cert_mode_custom]="自定义证书（tls=2）：crt=/key= 指向你自己的 PEM 文件。客户端通过 sni= 校验，因此需要公网主机名。"
            MSG[prompt_self_sign_days]="自签证书有效期（天）[%s]: "
            MSG[prompt_cert_san]="证书 SAN 列表（逗号分隔，DNS:/IP:）[%s]: "
            MSG[prompt_cert]="证书路径 [%s]: "
            MSG[prompt_keyfile]="私钥路径 [%s]: "
            MSG[warn_spec_removed]="Nowhere 1.5 已移除 spec；忽略 --spec"
            MSG[warn_migrated_spec]="已从 %s 移除废弃的 spec=（Nowhere 1.5）"
            MSG[warn_pool_removed]="Nowhere 1.8 已移除 pool（由 mux 取代）；忽略 --pool"
            MSG[warn_migrated_pool]="已从 %s 移除废弃的 pool=，并在适用时写入 mux=1（Nowhere 1.8）"
            MSG[warn_v15_incompat]="Nowhere 1.5+ 使用新线协议，请一并升级 Portal 与客户端。1.6 新增只读 TUI（仅 Linux）。1.7 新增 Portal 原生链式转发（next=），链路上各节点须 ≥1.7.0。1.8 以 mux=0|1 TLS Mux 取代 tcp/tcp 预热连接池（pool= 已移除）。1.8.3 新增混合载体策略：up/down 可为 tcp|udp|mix。"
            MSG[warn_v20_incompat]="Nowhere 2.0 为破坏性变更：ALPN 固定为 nw2（忽略 alpn=），Portal 的 net= 已失效（载体由端点路径选择），1.x 节点无法互通。请一并升级 Portal 与客户端。维护 1.x 节点请使用 --version v1.x.x。"
            MSG[warn_v22_incompat]="Nowhere 2.2+ 要求 Portal 密钥为 32-64 位小写十六进制字符，并默认强制校验 Portal 证书：tls=1（自签）客户端必须设置 pin=<sha256>。不符合要求的已存储 Portal 密钥将被自动重新生成，请重新分发分享 URI。"
            MSG[warn_key_regenerated]="%s 中存储的 Portal 密钥不符合 Nowhere 2.2 要求，已生成新密钥。请使用新的分享 URI 更新所有客户端。"
            MSG[warn_next_key_invalid]="%s 中的 next= 上游密钥不符合 Nowhere 2.2 要求（32-64 位小写十六进制）；请更新上游 Portal。"
            MSG[prompt_v20_upgrade]="检测到跨主版本升级/降级，是否继续? [y/N]: "
            MSG[warn_migrated_v20]="已将 %s 迁移为 Nowhere 2.0 端点语法（已移除 net=/alpn=）"
            MSG[warn_migrated_v1]="已将 %s 还原为 Nowhere 1.x URL 语法（已恢复 net=，已移除 morph=）"
            MSG[warn_split_ports_v1]="Nowhere 1.x 无法表达独立 TCP/UDP 端口，已折叠为单一端口"
            MSG[warn_alpn_ignored]="Nowhere 2.x 固定 ALPN 为 nw2，nw3 不接受 alpn=；忽略 --alpn"
            MSG[err_opt_v2_only]="%s 需要 Nowhere 2.0+（请使用 --version v2.x 或安装 2.x）"
            MSG[err_freebsd_v1]="FreeBSD 安装包仅适用于 Nowhere 2.0+；拒绝安装 %s"
            MSG[err_freebsd_asset]="版本 %s 没有 FreeBSD 安装包（期望文件 %s）。FreeBSD 资产仅适用于 Nowhere 2.0+，且该 tag 必须已发布 freebsd 包"
            MSG[err_vector_star_host]="Vector 主机不能为 *（请填写具体主机名或 IP）"
            MSG[err_net_port_conflict]="--net %s 与对向的 --tcp-port/--udp-port 冲突"
            MSG[err_carrier_undeclared]="载体策略 %s/%s 不在当前端点声明的载体内"
            MSG[err_invalid_port]="无效端口: %s"
            MSG[err_invalid_key]="无效的 Portal 密钥: Nowhere 2.2+ 要求 32-64 位小写十六进制字符（可用 nowhere generate-key 生成）"
            MSG[err_invalid_next_key]="无效的 next= 上游密钥: Nowhere 2.2+ 要求两端均为 32-64 位小写十六进制字符"
            MSG[err_invalid_morph]="无效 morph: %s（使用 0 或 1）"
            MSG[err_invalid_net]="无效载体模式: %s（使用 mix|tcp|udp）"
            MSG[err_next_removed]="nw3 已移除 next= 链式转发：Portal 出口改为 direct、SOCKS5 上游（out=端点）或已注册的 Egress（out=egress）"
            MSG[err_invalid_out]="无效的 Portal 出口: %s（使用 direct|socks|egress）"
            MSG[err_egress_needs_udp]="out=egress 需要 Portal 端点具备 QUIC（UDP）监听"
            MSG[err_egress_requires_nw3]="egress 角色需要 Nowhere 3（nw3）；当前节点位于另一协议线"
            MSG[err_preflight_next]="迁移到 nw3 会丢弃 %s 中的 next= 链式配置；请先重新配置 Portal 出口（out=）"
            MSG[err_preflight_egress]="迁移回 Nowhere 2.x 会丢弃 %s 中的 egress 角色；请先改为 Portal 或 Vector"
            MSG[err_migrate_requires_flag]="跨协议线升级需要 --allow-protocol-breaking-upgrade 或交互输入 MIGRATE 确认"
            MSG[err_out_socks_required]="out=socks 需要 SOCKS5 上游地址（使用 --socks <addr>）"
            MSG[prompt_migrate_confirm]="输入 MIGRATE 确认切换协议线: "
            MSG[info_migrate_flag_accepted]="已接受 --allow-protocol-breaking-upgrade；将迁移已保存的 URL"
            MSG[warn_url_backed_up]="现有配置已备份到 %s"
            MSG[warn_protocol_switch]="协议线切换: Nowhere %s -> %s"
            MSG[warn_nw3_protocol]="Nowhere 3（nw3）是新协议线：密钥须恰好 32 位小写 hex，Portal 出口用 out=，Vector 用 in=，未知参数会被忽略"
            MSG[warn_migrated_nw3]="已将 %s 迁移为 nw3 端点语法（socks=/next= → out=，单载体，morph 显式声明）"
            MSG[warn_migrated_nw2]="已将 %s 迁移回 Nowhere 2.2 端点语法（out= → socks=/next=）"
            MSG[warn_vector_carrier_fallback]="up/down 载体不一致；nw3 Vector 仅支持单载体，使用 tcp"
            MSG[warn_vector_key_peer]="nw3 要求 Vector 密钥与 Portal 密钥完全一致；启动前请核实对端"
            MSG[label_out]="出口:     %s"
            MSG[label_in]="入口:     %s"
            MSG[info_launching_status]="正在启动 nowhere status（只读快照；Ctrl+C 退出）..."
            MSG[info_configure_egress]="正在配置 Nowhere 3 Egress（向 out=egress 的 Portal 发起出站 QUIC 连接）"
            MSG[info_egress_no_inbound]="Egress 只发起出站 QUIC 连接；本机无需开放任何入站防火墙端口。"
            MSG[prompt_outbound_mode_nw3]="Portal 出口 (direct/socks/egress) [%s]: "
            MSG[prompt_carrier_single]="载体 (tcp/udp) [%s]: "
            MSG[label_share_link_tcp]="导入链接 (TLS/TCP):"
            MSG[label_share_link_udp]="导入链接 (QUIC/UDP):"
            MSG[help_opt_out]="      --out <direct|socks|egress>  Portal 出口模式 (nw3)"
            MSG[help_opt_allow_breaking]="      --allow-protocol-breaking-upgrade  确认 nw2<->nw3 协议线切换"
            MSG[mf_out]="Portal 出口"
            MSG[mf_out_socks]="SOCKS 上游"
            MSG[mf_in]="SOCKS 监听 (in)"
            MSG[mf_carrier]="载体"
            MSG[help_opt_next]="      --next <key@host:port>  Portal 原生上游（与 --socks 互斥）"
            MSG[prompt_outbound_mode]="Portal 出站模式 (none/socks/next) [%s]: "
            MSG[prompt_next]="原生上游 Portal next=<key@host:port> [%s]: "
            MSG[err_next_socks_mutex]="Portal 的 next= 与出站 socks= 不能同时启用"
            MSG[err_next_required]="原生上游需要 next=<key@host:port>"
            MSG[label_next]="Next:       %s"
            MSG[warn_share_chain]="当前为链式 Portal：next= 仅服务端配置，不会写入客户端分享 URI。"
            MSG[warn_sni_missing]="TLS=2 但未设置公网主机名；分享 URI 将省略 sni（客户端需要覆盖分享地址的证书，或改用 pin=）。"
            MSG[label_generated_url]="生成的 URL："
            MSG[ok_config_updated]="配置已更新并重启服务"
            MSG[prompt_save_config]="是否保存此配置? [Y/n]: "
            MSG[ok_config_saved]="配置已保存到 %s"
            MSG[prompt_install_svc]="是否安装/更新系统服务? [Y/n]: "
            MSG[warn_no_init]="未检测到 systemd/openrc/rc.d，跳过服务安装"
            MSG[ok_svc_installed]="服务已安装"
            MSG[prompt_start_svc]="是否立即启动/重启服务? [Y/n]: "
            MSG[ok_svc_started]="服务已启动"
            MSG[info_config_not_saved]="配置未保存"
            MSG[label_current_ver]="当前版本: %s"
            MSG[label_latest_ver]="GitHub 最新版本: %s"
            MSG[not_installed]="未安装"
            MSG[info_already_latest]="当前已是最新版本 %s"
            MSG[info_already_target]="当前已是目标版本 %s"
            MSG[label_target_ver]="目标版本: %s"
            MSG[prompt_force_reinstall]="是否强制重新安装? [y/N]: "
            MSG[info_skip_force]="远程一键模式：跳过强制重装"
            MSG[info_svc_restarted]="服务已重新启动"
            MSG[warn_already_installed]="检测到已安装版本: %s"
            MSG[prompt_overwrite]="是否覆盖安装/升级? [y/N]: "
            MSG[prompt_config_now]="是否立即配置服务? [Y/n]: "
            MSG[info_skip_config]="跳过配置，之后可运行脚本选择“配置/重新配置服务”"
            MSG[info_gen_config]="生成 Nowhere 服务配置..."
            MSG[info_random_key]="已生成随机共享密钥: %s"
            MSG[info_key_hint]="直接回车使用随机密钥，或输入自定义密钥："
            MSG[ok_config_written]="配置已写入 %s"
            MSG[label_run_url]="运行 URL: %s"
            MSG[info_share_key]="共享密钥: %s"
            MSG[ok_systemd_started]="systemd 服务已启动"
            MSG[ok_openrc_started]="openrc 服务已启动"
            MSG[ok_rc_started]="FreeBSD rc.d 服务已启动"
            MSG[warn_manual_start]="未检测到 systemd/openrc/rc.d，请手动启动"
            MSG[warn_no_config]="未找到配置文件，请先安装并配置 Nowhere"
            MSG[share_title]="========== Nowhere 客户端分享 =========="
            MSG[label_qr]="二维码："
            MSG[label_client_uri]="客户端 URI："
            MSG[warn_tls_skip]="Nowhere 1.x 下为 TLS=1（自签证书），客户端连接时需跳过证书验证。"
            MSG[warn_pin_required]="TLS=1（自签证书）：Nowhere 2.2+ 默认强制校验证书，客户端必须设置 pin=<sha256>。现已无法跳过证书验证。"
            MSG[warn_pin_unavailable]="无法自动获取证书指纹。请从 Portal 启动日志（行 “TLS certificate SHA-256 fingerprint: ...”）获取，或运行: nowhere fingerprint <nowhere-url>"
            MSG[warn_pin_changes]="自签证书（及其 pin）会在 Portal 每次重启时重新生成；重启后请重新分发分享 URI。"
            MSG[info_pin_fetched]="已自动获取证书 pin: %s"
            MSG[label_fingerprint]="证书 pin:  %s"
            MSG[prompt_fetch_pin]="是否自动获取 Portal 证书指纹? [Y/n]: "
            MSG[err_cert_mode_invalid]="无效的证书来源 %s（应为 program、openssl、custom 或 acme）"
            MSG[err_not_configured]="Nowhere 尚未配置；请先运行 --config 或 --install"
            MSG[err_openssl_missing]="openssl 不可用且无法自动安装；请手动安装或改选其他证书来源"
            MSG[err_self_sign_failed]="自签证书生成失败"
            MSG[ok_self_signed]="自签证书已写入 %s 与 %s（有效期 %s 天），pin %s"
            MSG[info_cert_mode_acme]="acme.sh 证书（tls=2）：由本脚本驱动 acme.sh 为你的域名申请真实 CA 签发证书。客户端通过 sni= 校验，因此需要公网主机名以及可达的 80 端口（或使用 DNS 插件）。"
            MSG[prompt_acme_domain]="申请证书的域名 [%s]： "
            MSG[prompt_acme_email]="acme.sh 账户邮箱（可选，用于到期提醒）： "
            MSG[prompt_acme_challenge]="ACME 验证方式（http/dns）[%s]： "
            MSG[prompt_acme_dns]="acme.sh DNS 插件（例如 dns_cf、dns_ali；需先导出其凭据）： "
            MSG[prompt_acme_auto_renew]="是否安装证书自动续期任务？（yes/no）[%s]： "
            MSG[prompt_acme_renew_days]="剩余多少天有效期时续期 [%s]： "
            MSG[err_acme_domain_invalid]="无效的 ACME 域名 %s（应为类似 relay.example.com 的公网主机名）"
            MSG[err_acme_dns_missing]="dns 验证方式需要通过 --acme-dns 指定插件名"
            MSG[err_acme_challenge_invalid]="无效的 ACME 验证方式 %s（应为 http 或 dns）"
            MSG[err_acme_auto_renew_invalid]="无效的自动续期取值 %s（应为 yes 或 no）"
            MSG[err_acme_port_busy]="端口 %s 已被占用；http 验证方式需要该端口空闲。请释放该端口，或改用 --acme-challenge dns 配合 --acme-dns 插件"
            MSG[err_acme_standalone_missing]="http 验证方式需要 socat，但无法自动安装；请手动安装 socat，或改用 --acme-challenge dns"
            MSG[err_acme_install_failed]="无法将 acme.sh 安装到 %s；请检查网络与 curl 后重试"
            MSG[err_acme_issue_failed]="acme.sh 为 %s 签发证书失败；具体原因见 acme.sh 日志"
            MSG[err_acme_renew_failed]="acme.sh 为 %s 续期证书失败"
            MSG[err_acme_not_installed]="acme.sh 未安装于 %s"
            MSG[err_acme_domain_missing]="缺失已记录的 ACME 域名；请用 --cert-mode acme 重新执行证书步骤"
            MSG[err_acme_renew_days_invalid]="续期窗口无效：%s（请填 1-89 天）"
            MSG[info_acme_cert_kept]="%s 的证书有效期至 %s，剩余超过 %s 天；沿用现有证书"
            MSG[warn_acme_renew_failed]="%s 续期失败；保留现有证书，交由自动续期任务稍后重试"
            MSG[warn_acme_cron_unavailable]="未找到 cron 守护进程；未设置自动续期。请用 --renew-cert 手动续期"
            MSG[info_acme_cron_installed]="已设置自动续期：%s（剩余有效期 %s 天内时才续期）"
            MSG[info_install_acme]="正在安装 acme.sh..."
            MSG[info_install_socat]="正在为 acme.sh standalone 验证安装 socat..."
            MSG[ok_acme_cert]="%s 的 acme.sh 证书已就绪：%s 与 %s"
            MSG[ok_acme_renew]="%s 的证书已续期（%s）"
            MSG[info_renew_not_needed]="%s 模式下无需续期（二进制每次启动都会重新生成证书）"
            MSG[err_renew_not_portal]="--renew-cert 仅适用于 Portal 配置"
            MSG[label_acme_domain]="ACME 域名: %s"
            MSG[label_acme_renewal]="ACME 续期: %s"
            MSG[acme_renewal_on]="开启（%s，剩余有效期 %s 天内时续期）"
            MSG[acme_renewal_off]="关闭 — 请用 --renew-cert 手动续期"
            MSG[label_cert_mode]="证书:      %s"
            MSG[label_cert_expires]="证书至:    %s"
            MSG[warn_cert_expired]="Portal 证书已过期（%s）；客户端会拒绝连接。请在配置菜单中重新签发。"
            MSG[warn_cert_expiring]="Portal 证书将于 %s 天后过期（%s）。"
            MSG[warn_cert_file_missing]="Portal 证书文件 %s 不存在；tls=2 下证书缺失时 Portal 无法启动"
            MSG[status_title]="========== Nowhere 状态 =========="
            MSG[label_binary]="二进制位置: %s"
            MSG[label_script]="脚本版本:   %s"
            MSG[label_version]="Nowhere:    %s"
            MSG[label_system]="系统:       %s %s"
            MSG[label_arch_libc]="架构/libc:  %s/%s"
            MSG[label_config_file]="配置文件:   %s"
            MSG[label_run_url_status]="运行 URL:   %s"
            MSG[not_configured]="未配置"
            MSG[label_svc_status]="服务状态："
            MSG[menu_title]="      Nowhere 管理脚本"
            MSG[menu_script]="  脚本版本: %s"
            MSG[menu_version]="  Nowhere:  %s"
            MSG[menu_system]="  系统:     %s %s"
            MSG[menu_arch]="  架构:     %s/%s"
            MSG[menu_install]="一键安装"
            MSG[menu_upgrade]="升级 Nowhere"
            MSG[menu_pin_version]="安装指定版本"
            MSG[menu_configure]="配置/重新配置服务"
            MSG[menu_modify]="修改当前配置"
            MSG[menu_start]="启动服务"
            MSG[menu_stop]="停止服务"
            MSG[menu_restart]="重启服务"
            MSG[menu_status]="查看状态"
            MSG[menu_renew]="立即续期证书"
            MSG[menu_tui]="TUI / 实例状态"
            MSG[menu_share]="显示分享 URI"
            MSG[menu_qr]="安装二维码支持库"
            MSG[menu_lang]="切换语言"
            MSG[menu_upgrade_script]="升级 oh-nowhere 管理脚本"
            MSG[menu_uninstall]="卸载 Nowhere"
            MSG[menu_exit]="退出"
            MSG[menu_service]="服务状态: %s"
            MSG[menu_svc_running]="运行中"
            MSG[menu_svc_stopped]="已停止"
            MSG[menu_svc_not_installed]="未安装"
            MSG[modify_title]="修改 Nowhere 配置（角色: %s）"
            MSG[modify_hint]="输入编号修改对应项；直接回车或 q 保存并应用。"
            MSG[prompt_modify_choice]="要修改的项 [1-%s]（回车/q = 应用）: "
            MSG[modify_none]="-"
            MSG[modify_new_url]="新的运行 URL: %s"
            MSG[info_configure_first]="尚无现有配置；请先执行“一键安装”或“交互配置”。"
            MSG[err_invalid_tls]="无效的 TLS 模式 %s（应为 0、1 或 2）"
            MSG[err_invalid_mux]="无效的 mux 值 %s（应为 0 或 1）"
            MSG[warn_port_in_use]="端口 %s 已被占用"
            MSG[prompt_port_conflict]="仍要使用端口 %s 吗? [y/N]: "
            MSG[info_port_unchanged]="保留当前端口 %s"
            MSG[err_port_in_use]="端口 %s 已被占用，请输入其他端口"
            MSG[mf_key]="密钥"
            MSG[mf_port]="端口"
            MSG[mf_net]="承载方式 (net)"
            MSG[mf_tcp_port]="TCP 端口"
            MSG[mf_udp_port]="UDP 端口"
            MSG[mf_tls]="TLS 模式"
            MSG[mf_cert_mode]="证书来源"
            MSG[mf_cert]="证书文件"
            MSG[mf_keyfile]="私钥文件"
            MSG[mf_alpn]="ALPN"
            MSG[mf_morph]="Morph"
            MSG[mf_up]="上行载体"
            MSG[mf_down]="下行载体"
            MSG[mf_mux]="Mux"
            MSG[mf_socks]="SOCKS"
            MSG[mf_next]="下一跳"
            MSG[mf_sni]="SNI"
            MSG[mf_pin]="SPKI pin"
            MSG[mf_outbound]="出站方式"
            MSG[mf_share_host]="分享地址"
            MSG[mf_name]="节点名称"
            MSG[prompt_menu]="请输入选项 [0-%s]: "
            MSG[ok_start_sent]="启动命令已发送"
            MSG[ok_stop_sent]="停止命令已发送"
            MSG[ok_restart_sent]="重启命令已发送"
            MSG[info_exit]="退出"
            MSG[prompt_continue]="按 Enter 键继续..."
            MSG[qr_ready]="二维码支持已可用（%s）"
            MSG[qr_warn_apt]="将通过 apt 安装 qrencode，额外磁盘占用通常约数 MB。"
            MSG[qr_warn_apk]="Alpine 官方源无 qrencode，将改用 python3 + py3-qrcode，体积明显更大（可能数十 MB）。"
            MSG[qr_warn_pkg]="将通过 pkg 安装 libqrencode。"
            MSG[prompt_qr_confirm]="是否继续安装? [y/N]: "
            MSG[info_qr_installing]="正在安装二维码依赖..."
            MSG[ok_qr_installed]="二维码支持已安装。可使用「%s」显示二维码。"
            MSG[err_qr_install]="二维码依赖安装失败"
            MSG[info_target_version]="目标版本: %s"
            MSG[prompt_version]="请输入版本号 (例如 v1.2.3): "
            MSG[err_version_empty]="版本号不能为空"
            MSG[ok_target_version_set]="将要安装版本: %s"
            MSG[info_fetch_versions]="正在获取可用版本..."
            MSG[prompt_select_version]="请选择版本 [0=最新版, 1-%s]: "
            MSG[err_no_versions]="未找到任何 release"
            MSG[err_invalid_version_choice]="选择无效"
            MSG[label_latest_version]="最新版"
            MSG[info_lang_set]="语言已设置为: %s"
            MSG[help_title]="Nowhere 一键安装脚本"
            MSG[help_usage]="用法:"
            MSG[help_options]="选项:"
            MSG[help_no_opt]="无选项时进入交互式菜单。"
            MSG[help_examples]="示例:"
            MSG[help_opt_install]="  -i, --install          一键安装/升级并启动服务"
            MSG[help_opt_upgrade]="  -u, --upgrade          一键升级"
            MSG[help_opt_config]="  -c, --config           交互式配置服务"
            MSG[help_opt_status]="  -s, --status           查看状态"
            MSG[help_opt_share]="  -q, --share            显示分享 URI"
            MSG[help_opt_tui]="      --tui              启动 Nowhere TUI 面板"
            MSG[help_opt_uninstall]="  --uninstall            一键卸载"
            MSG[help_opt_type]="      --type <portal|vector|egress>  服务角色 (默认 portal; egress 需要 nw3)"
            MSG[help_opt_url]="      --url <uri>       导入 portal://、vector:// 或 nowhere:// URI"
            MSG[help_opt_key]="  -k, --key <密钥>       指定共享密钥（Nowhere 2.2+ Portal 密钥: 32-64 位小写十六进制）"
            MSG[help_opt_port]="  -p, --port <端口>      指定监听端口 (默认 2077)"
            MSG[help_opt_alpn]="      --alpn <alpn>      1.x TLS/QUIC ALPN (默认 now/1)；Nowhere 2.0 忽略（固定 nw2）"
            MSG[help_opt_host]="      --host <hostname>  分享 URI / SNI 用的公网主机名"
            MSG[help_opt_name]="      --name <名称>      节点名称，作为分享 URI 的 # 片段 (默认 Nowhere-位置-IP首段)"
            MSG[help_opt_net]="      --net <mix|tcp|udp>  载体模式 (1.x 写入 net=；2.0 映射为端点路径；默认 mix)"
            MSG[help_opt_tls]="      --tls <1|2>        指定 TLS 模式 (默认 1)"
            MSG[help_opt_cert]="      --cert <路径>      TLS=2 时的证书路径"
            MSG[help_opt_keyfile]="      --keyfile <路径>   TLS=2 时的私钥路径"
            MSG[help_opt_cert_mode]="      --cert-mode <模式> program|openssl|custom|acme 证书来源（默认 program）"
            MSG[help_opt_self_sign_days]="      --self-sign-days <n>  openssl 自签有效期（天），默认 %s"
            MSG[help_opt_cert_san]="      --cert-san <列表>   openssl 自签 SAN，逗号分隔 DNS:/IP:"
            MSG[help_opt_acme_domain]="      --acme-domain <域名>  acme.sh 证书域名（隐含 --cert-mode acme）"
            MSG[help_opt_acme_email]="      --acme-email <邮箱>  acme.sh 账户邮箱（可选）"
            MSG[help_opt_acme_challenge]="      --acme-challenge <http|dns>  ACME 验证方式（默认 http；http 需要 80 端口空闲）"
            MSG[help_opt_acme_dns]="      --acme-dns <插件>   acme.sh DNS 插件；隐含 --acme-challenge dns"
            MSG[help_opt_acme_auto_renew]="      --acme-auto-renew <yes|no>  自动续期任务（默认 yes）"
            MSG[help_opt_acme_renew_days]="      --acme-renew-days <n>  剩余有效期 n 天内时才续期（默认 30）"
            MSG[help_opt_renew_cert]="      --renew-cert       立即续期当前的 acme.sh/openssl 证书"
            MSG[help_opt_socks]="      --socks <地址>    Portal 出站或 Vector 入站 SOCKS"
            MSG[help_opt_up]="      --up <tcp|udp|mix>  上行载体（2.x 默认 tcp，1.x 默认 udp）"
            MSG[help_opt_down]="      --down <tcp|udp|mix>  下行载体（2.x 默认 tcp，1.x 默认 udp）"
            MSG[help_opt_mux]="      --mux <0|1>       方向为 tcp 或 mix 时使用 TLS Mux（2.x 默认省略/0；1.x 的 tcp/tcp 默认 1）"
            MSG[help_opt_tcp_port]="      --tcp-port <端口> TLS/TCP 端口（Nowhere 2.0+，可与 UDP 不同）"
            MSG[help_opt_udp_port]="      --udp-port <端口> QUIC/UDP 端口（Nowhere 2.0+，可与 TCP 不同）"
            MSG[help_opt_morph]="      --morph <0|1>    TLS/QUIC 线形伪装（Nowhere 2.0+；默认 0，不写入）"
            MSG[help_opt_sni]="      --sni <名称>      证书名（Vector 或 Portal next 上游）"
            MSG[help_opt_pin]="      --pin <sha256>    证书固定（Nowhere 2.2+: tls=1 自签 Portal 必需；否则用于 Vector 或 next 上游）"
            MSG[help_opt_version]="  -v, --version <版本>   安装指定版本 (例如 v2.0.0 或 v1.8.3)"
            MSG[help_opt_lang]="  -l, --lang <en|zh|ru>  脚本语言 (默认 zh)"
            MSG[prompt_type]="服务类型 (portal/vector) 或粘贴 nowhere:// [%s]: "
            MSG[prompt_type_hint]="输入 portal、vector，或粘贴 nowhere:// / vector:// / portal:// URL"
            MSG[prompt_portal_host]="Portal 主机 [%s]: "
            MSG[prompt_up]="上行载体 (tcp/udp/mix) [%s]: "
            MSG[prompt_down]="下行载体 (tcp/udp/mix) [%s]: "
            MSG[prompt_mux]="使用 TLS Mux (0/1) [%s]: "
            MSG[prompt_socks_in]="入站 SOCKS 监听 [%s]: "
            MSG[prompt_socks_out_enable]="启用 Portal 出站 SOCKS? [%s]: "
            MSG[prompt_socks_out]="出站 SOCKS 地址 [%s]: "
            MSG[prompt_sni]="SNI / 证书名（可选，- 清除）[%s]: "
            MSG[prompt_pin]="证书 pin SHA-256（可选，- 清除）[%s]: "
            MSG[info_configure_portal]="配置 Portal"
            MSG[info_configure_vector]="配置 Vector"
            MSG[info_converted_nowhere]="已将 nowhere:// 分享 URI 转换为 vector://"
            MSG[warn_migrated_nowhere]="已将 %s 中的 nowhere:// 迁移为 vector://"
            MSG[warn_share_vector]="当前角色为 Vector；nowhere:// 分享仅适用于 Portal。当前运行 URL："
            MSG[label_role]="角色:       %s"
            MSG[label_socks]="SOCKS:      %s"
            MSG[err_binary_missing]="未安装 nowhere 二进制，请先安装"
            MSG[err_invalid_type]="无效类型: %s（使用 portal|vector|egress）"
            MSG[err_invalid_carrier]="无效载体: %s（使用 tcp|udp|mix）"
            MSG[err_invalid_url]="无效 URL: %s"
            MSG[err_socks_required]="Vector 需要入站 SOCKS 监听地址"
            MSG[err_portal_host_required]="Vector 需要 Portal 主机"
            MSG[info_launching_tui]="正在启动 Nowhere TUI（只读；Ctrl+C 退出）..."
            MSG[info_upgrading_script]="正在升级 oh-nowhere 管理脚本..."
            MSG[info_script_already_latest]="脚本已是最新版本"
            MSG[info_script_versions]="脚本版本: %s -> %s"
            MSG[warn_script_older]="远端脚本 %s 比当前副本 %s 更旧"
            MSG[info_script_restart_hint]="请重新运行脚本以使用新版本"
            MSG[prompt_script_upgrade_confirm]="下载并替换当前脚本? [y/N]: "
            MSG[label_script_path]="脚本路径: %s"
            MSG[ok_script_upgraded]="脚本已升级（备份: %s）"
            MSG[err_script_download]="下载最新脚本失败"
            MSG[err_script_verify]="下载的脚本未通过语法检查"
            MSG[err_script_install]="安装更新脚本失败"
            MSG[help_opt_upgrade_script]="      --upgrade-script     从 GitHub 升级本 oh-nowhere 脚本"
            MSG[help_opt_script_version]="      --script-version     打印本 oh-nowhere 版本后退出"
            MSG[help_opt_help]="  -h, --help             显示帮助"
            ;;
    esac
}

set_language "zh"

# ==================== Logging ====================
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

# ==================== System detection ====================
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "$(t err_root)"
        exit 1
    fi
}

detect_os() {
    if [[ "$(uname -s)" == "FreeBSD" ]]; then
        OS_ID="freebsd"
        OS_VERSION_ID="$(uname -r)"
        PKG_MANAGER="pkg"
        INIT_SYSTEM="rc"
        log_info "$(t info_os "$OS_ID" "$OS_VERSION_ID" "$INIT_SYSTEM")"
        return
    fi

    if [[ ! -f /etc/os-release ]]; then
        log_error "$(t err_os_unknown)"
        exit 1
    fi

    OS_ID=$(grep -E '^ID=' /etc/os-release | head -n1 | cut -d'=' -f2 | tr -d '"')
    OS_VERSION_ID=$(grep -E '^VERSION_ID=' /etc/os-release | head -n1 | cut -d'=' -f2 | tr -d '"')

    case "$OS_ID" in
        debian|ubuntu) PKG_MANAGER="apt" ;;
        alpine)        PKG_MANAGER="apk" ;;
        *)
            log_error "$(t err_os_unsupported "$OS_ID")"
            exit 1
            ;;
    esac

    if [[ -d /run/systemd/system ]] || command -v systemctl &>/dev/null; then
        INIT_SYSTEM="systemd"
    elif command -v rc-service &>/dev/null || [[ -d /etc/init.d ]]; then
        INIT_SYSTEM="openrc"
    else
        INIT_SYSTEM="unknown"
    fi

    log_info "$(t info_os "$OS_ID" "$OS_VERSION_ID" "$INIT_SYSTEM")"
}

detect_arch() {
    local machine
    machine=$(uname -m)
    case "$machine" in
        x86_64|amd64)  ARCH="x86_64" ;;
        aarch64|arm64) ARCH="aarch64" ;;
        *)
            log_error "$(t err_arch "$machine")"
            exit 1
            ;;
    esac

    if [[ "$OS_ID" == "freebsd" ]]; then
        LIBC="freebsd"
    elif [[ "$OS_ID" == "alpine" ]]; then
        LIBC="musl"
    else
        LIBC="gnu"
    fi

    log_info "$(t info_arch "$ARCH" "$LIBC")"
}

get_system_glibc_version() {
    ldd --version 2>/dev/null | head -n1 | grep -oE '[0-9]+\.[0-9]+' | head -n1
}

# Compare dotted major.minor versions: success if $1 >= $2.
version_ge_dot() {
    local have="$1" need="$2"
    local h1 h2 n1 n2
    h1="${have%%.*}"
    h2="${have#*.}"
    h2="${h2%%.*}"
    n1="${need%%.*}"
    n2="${need#*.}"
    n2="${n2%%.*}"
    h1="${h1:-0}"
    h2="${h2:-0}"
    n1="${n1:-0}"
    n2="${n2:-0}"
    if ((10#$h1 != 10#$n1)); then
        ((10#$h1 > 10#$n1))
        return
    fi
    ((10#$h2 >= 10#$n2))
}

detect_libc_runtime() {
    if [[ "$OS_ID" == "alpine" || "$OS_ID" == "freebsd" ]]; then
        return
    fi
    if ldd --version 2>/dev/null | grep -qi musl; then
        log_warn "$(t warn_musl)"
        read -rp "$(t prompt_musl)" use_musl
        if [[ "$use_musl" =~ ^[Yy]$ ]]; then
            LIBC="musl"
            log_info "$(t info_arch "$ARCH" "$LIBC")"
        fi
        return
    fi
    if [[ "$LIBC" == "gnu" ]]; then
        local glibc
        glibc=$(get_system_glibc_version)
        if [[ -n "$glibc" ]] && ! version_ge_dot "$glibc" "$GNU_MIN_GLIBC"; then
            log_warn "$(t warn_glibc_musl "$glibc" "$GNU_MIN_GLIBC")"
            LIBC="musl"
            log_info "$(t info_arch "$ARCH" "$LIBC")"
        fi
    fi
}

binary_probe_error() {
    local bin="$1"
    "$bin" --version 2>&1 | head -n1
}

binary_runs() {
    local bin="$1"
    [[ -n "$bin" && -x "$bin" ]] || return 1
    "$bin" --version >/dev/null 2>&1
}

# Downloads and extracts the current LIBC asset into dest. Sets FETCHED_BINARY.
FETCHED_BINARY=""
extract_nowhere_to() {
    local version="$1"
    local dest="$2"
    local download_url asset_name
    FETCHED_BINARY=""
    download_url=$(get_download_url "$version")
    asset_name=$(get_asset_name)

    log_info "$(t info_download "$version" "$asset_name")"
    if ! curl -fL --connect-timeout 15 --max-time 120 -o "${dest}/${asset_name}" "$download_url"; then
        if [[ "$OS_ID" == "freebsd" ]]; then
            log_error "$(t err_freebsd_asset "$version" "$asset_name")"
        fi
        log_error "$(t err_download "$download_url")"
        return 1
    fi

    tar -xzf "${dest}/${asset_name}" -C "$dest"
    FETCHED_BINARY=$(find "$dest" -name "nowhere" -type f | head -n1)
    if [[ -z "$FETCHED_BINARY" ]]; then
        log_error "$(t err_binary)"
        return 1
    fi
    return 0
}

# ==================== Dependencies ====================
check_dependencies() {
    local deps=("curl" "tar")
    local missing=()

    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            missing+=("$dep")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_info "$(t info_install_deps "${missing[*]}")"
        if [[ "$PKG_MANAGER" == "apt" ]]; then
            apt-get update -qq && apt-get install -y -qq curl tar
        elif [[ "$PKG_MANAGER" == "apk" ]]; then
            apk add --no-cache curl tar
        elif [[ "$PKG_MANAGER" == "pkg" ]]; then
            pkg install -y curl
        fi
    fi
}

# ==================== Helpers ====================
generate_random_key() {
    # Nowhere 2.2+ and Nowhere 3 both require exactly 32 lowercase hexadecimal
    # characters; prefer the binary's own generator when it is available, fall
    # back to /dev/urandom. 1.x accepts any non-empty key and keeps the
    # historical random word.
    if is_v2_profile; then
        local key=""
        if command -v nowhere &>/dev/null; then
            key=$(nowhere generate-key 2>/dev/null | head -n1 | tr -d '\r\n ' | grep -E '^[0-9a-f]{32,64}$' || true)
        fi
        if [[ -z "$key" ]]; then
            key=$(tr -dc '0-9a-f' </dev/urandom | head -c 32)
        fi
        printf '%s' "$key"
        return 0
    fi
    tr -dc 'a-zA-Z0-9' </dev/urandom | head -c 16
}

get_public_ip() {
    local ip=""
    for api in "https://api.ipify.org" "https://ipv4.icanhazip.com" "https://ifconfig.me"; do
        ip=$(curl -fsSL --connect-timeout 5 "$api" 2>/dev/null | head -n1 | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$')
        [[ -n "$ip" ]] && break
    done
    if [[ -z "$ip" ]]; then
        ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    fi
    if [[ -z "$ip" ]]; then
        ip=$(ifconfig 2>/dev/null | awk '/inet / && $2 != "127.0.0.1" {print $2; exit}')
    fi
    echo "$ip"
}

url_encode_alpn() {
    local value="$1"
    # Encode reserved characters commonly present in ALPN values.
    value="${value//'/'/%2F}"
    value="${value//' '/%20}"
    value="${value//'#'/%23}"
    value="${value//'?'/%3F}"
    value="${value//'&'/%26}"
    value="${value//'='/%3D}"
    printf '%s' "$value"
}

url_decode_simple() {
    local value="${1//+/+}"
    printf '%b' "${value//%/\\x}"
}

load_share_host() {
    if [[ -n "$ARG_HOST" ]]; then
        echo "$ARG_HOST"
        return
    fi
    if [[ -f "$HOST_FILE" ]]; then
        tr -d '\n' < "$HOST_FILE"
    fi
}

save_share_host() {
    local host="$1"
    mkdir -p "$CONFIG_DIR"
    if [[ -n "$host" ]]; then
        echo "$host" > "$HOST_FILE"
    else
        rm -f "$HOST_FILE"
    fi
}

# Certificate modes ====================
# The Portal binary only understands tls=1 (it generates the certificate) and
# tls=2 (it loads PEM files from crt=/key=). The certificate *source* is a
# manager-level choice made before the TLS question:
#   program -> tls=1, certificate regenerated on every start, pin changes too
#   openssl -> tls=2, manager self-signs with openssl, stable pin in pin.conf
#   custom  -> tls=2, operator-supplied PEM files, clients verify via sni=
#   acme    -> tls=2, acme.sh-issued PEM files, clients verify via sni=
# pin= and sni= are client-side (vector/nowhere://) parameters only: the Portal
# URL whitelist rejects both, so the pin lives in a sidecar file and is only
# ever written into share links.
CERT_MODES="program openssl custom acme"

normalize_cert_mode() {
    local raw="${1:-}"
    case "$raw" in
        ""|program|1) echo "program" ;;
        openssl|2)    echo "openssl" ;;
        custom|3)     echo "custom" ;;
        acme|4)       echo "acme" ;;
        *)            return 1 ;;
    esac
}

cert_mode_tls() {
    case "$1" in
        openssl|custom|acme) echo "2" ;;
        *)                   echo "1" ;;
    esac
}

# Inverse of the above: recover the certificate source from a stored run URL.
# The sidecar wins when present because tls=2 without a pin is ambiguous
# between custom and acme; a missing sidecar with tls=2 means an install that
# predates the acme mode.
detect_cert_mode() {
    local url="$1" tls
    tls=$(get_query_param "$url" "tls")
    tls=${tls:-1}
    if [[ "$tls" != "2" ]]; then
        echo "program"
        return
    fi
    local sidecar
    sidecar=$(load_cert_mode_field mode)
    if [[ -n "$sidecar" ]]; then
        echo "$sidecar"
        return
    fi
    if [[ -n "$(load_pin)" ]]; then
        echo "openssl"
    else
        echo "custom"
    fi
}

# ==================== certmode.conf sidecar ====================
# Records which tls=2 certificate source is live. Needed because the run URL
# only carries tls=2 for both custom and acme, and only this file knows the
# difference. Four fields, one per line: mode=, domain=, autorenew=, renewdays=.
save_cert_mode() {
    local mode="$1" domain="$2" autorenew="$3" renewdays="${4:-}"
    mkdir -p "$CONFIG_DIR"
    {
        printf 'mode=%s\n' "$mode"
        [[ -n "$domain" ]] && printf 'domain=%s\n' "$domain"
        [[ -n "$autorenew" ]] && printf 'autorenew=%s\n' "$autorenew"
        [[ -n "$renewdays" ]] && printf 'renewdays=%s\n' "$renewdays"
    } > "$CERT_MODE_FILE"
}

load_cert_mode_field() {
    local field="$1"
    [[ -f "$CERT_MODE_FILE" ]] || return 0
    sed -n "s/^${field}=//p" "$CERT_MODE_FILE" | head -n 1
}

clear_cert_mode() {
    rm -f "$CERT_MODE_FILE"
}

save_pin() {
    local pin="$1"
    mkdir -p "$CONFIG_DIR"
    if [[ -n "$pin" ]]; then
        printf '%s\n' "$pin" > "$PIN_FILE"
    else
        rm -f "$PIN_FILE"
    fi
}

load_pin() {
    if [[ -f "$PIN_FILE" ]]; then
        tr -d '\n\r' < "$PIN_FILE"
    fi
}

clear_pin() {
    rm -f "$PIN_FILE"
}

# SHA-256 of the leaf certificate DER, lowercase hex — the exact form the
# binary prints as "certificate fingerprint" and compares against pin=.
cert_pin_from_file() {
    local crt="$1" pin=""
    [[ -f "$crt" ]] || return 1
    pin=$(openssl x509 -in "$crt" -outform DER 2>/dev/null | sha256sum | cut -d' ' -f1)
    [[ "$pin" =~ ^[0-9a-f]{64}$ ]] || return 1
    printf '%s' "$pin"
}

cert_not_after() {
    local crt="$1" end=""
    [[ -f "$crt" ]] || return 1
    end=$(openssl x509 -in "$crt" -noout -enddate 2>/dev/null | cut -d= -f2-)
    [[ -n "$end" ]] || return 1
    printf '%s' "$end"
}

# Default SAN list: the address clients dial (share host), the server's public
# address, and loopback so local probes keep working. A pin-verified client
# ignores the hostname entirely, so this is hygiene rather than a requirement.
default_cert_san() {
    local host="$1" san="" entry prefixed ip
    ip=$(get_public_ip)
    for entry in "$host" "$ip" "localhost" "127.0.0.1"; do
        [[ -z "$entry" ]] && continue
        if [[ "$entry" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ || "$entry" == "::1" ]]; then
            prefixed="IP:$entry"
        else
            prefixed="DNS:$entry"
        fi
        case ",$san," in
            *",$prefixed,"*) continue ;;
        esac
        san="${san:+$san,}${prefixed}"
    done
    printf '%s' "$san"
}

# Normalizes a SAN CSV (DNS:a,IP:1.2.3.4 or bare a,1.2.3.4) into the form
# openssl -addext wants. Echoes the normalized list; fails on an empty or
# unusable entry.
normalize_cert_san() {
    local raw="$1" out="" entry kind value
    local IFS=','
    for entry in $raw; do
        entry="${entry#"${entry%%[![:space:]]*}"}"
        entry="${entry%"${entry##*[![:space:]]}"}"
        [[ -z "$entry" ]] && continue
        kind="DNS"
        value="$entry"
        case "$entry" in
            DNS:*|IP:*) kind="${entry%%:*}"; value="${entry#*:}" ;;
        esac
        [[ -z "$value" ]] && continue
        if [[ "$value" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ || "$value" == "::1" ]]; then
            kind="IP"
        elif [[ "$kind" == "IP" ]]; then
            return 1
        fi
        if [[ ! "$value" =~ ^[A-Za-z0-9._*-]+$ ]]; then
            return 1
        fi
        out="${out:+$out,}${kind}:${value}"
    done
    [[ -n "$out" ]] || return 1
    printf '%s' "$out"
}

# Self-signs a certificate with openssl and echoes its pin. The private key is
# written with mode 600; both files replace whatever was there before.
openssl_self_sign() {
    local crt="$1" keyfile="$2" days="$3" san="$4" cn="$5" pin=""
    [[ "$days" =~ ^[0-9]+$ ]] || return 1
    (( days >= 1 && days <= 36500 )) || return 1
    mkdir -p "$(dirname "$crt")" "$(dirname "$keyfile")"
    if ! openssl req -x509 -newkey "ec" \
        -pkeyopt "ec_paramgen_curve:${SELF_SIGN_KEY_CURVE}" \
        -days "$days" -nodes -sha256 \
        -keyout "$keyfile" -out "$crt" \
        -subj "/CN=${cn}" \
        -addext "subjectAltName=${san}" \
        -addext "basicConstraints=critical,CA:FALSE" \
        -addext "keyUsage=critical,digitalSignature,keyEncipherment" \
        -addext "extendedKeyUsage=serverAuth" >/dev/null 2>&1; then
        rm -f "$crt" "$keyfile"
        return 1
    fi
    chmod 600 "$keyfile"
    chmod 644 "$crt"
    pin=$(cert_pin_from_file "$crt") || { rm -f "$crt" "$keyfile"; return 1; }
    printf '%s' "$pin"
}

ensure_openssl() {
    command -v openssl &>/dev/null && return 0
    log_info "$(t info_install_openssl)"
    set +e
    if [[ "$PKG_MANAGER" == "apt" ]]; then
        apt-get update -qq && apt-get install -y -qq openssl
    elif [[ "$PKG_MANAGER" == "apk" ]]; then
        apk add --no-cache openssl
    elif [[ "$PKG_MANAGER" == "pkg" ]]; then
        pkg install -y openssl
    else
        restore_errexit
        return 1
    fi
    local rc=$?
    restore_errexit
    [[ $rc -eq 0 ]] && command -v openssl &>/dev/null
}

# ==================== acme.sh certificate mode ====================
# ACME_BIN/ACME_DIR/ACME_RELOAD_HOOK/ACME_RENEW_HOOK/ACME_RENEW_LOG are
# variables (not literals) so the test suite can re-point them at a sandbox.
# acme.sh itself is installed on demand into $HOME/.acme.sh; the manager only
# drives it, never wraps it, and never touches DNS provider credentials — the
# operator exports those into acme.sh's own environment beforehand.

# Puts errexit back the way the caller had it. The install flow runs under
# `set -e`, but the same helpers are called from the test suite and from
# interactive paths where it is off; assuming either state breaks the caller.
restore_errexit() {
    [[ "$-" == *e* ]] || return 0
    set -e
}

ensure_acme() {
    if [[ -x "$ACME_BIN" ]]; then
        return 0
    fi
    local email="${1:-${ACME_EMAIL:-}}"
    log_info "$(t info_install_acme)"
    set +e
    curl -fsSL https://get.acme.sh | sh -s email="$email" >/dev/null 2>&1
    local rc=$?
    restore_errexit
    [[ $rc -eq 0 ]] && [[ -x "$ACME_BIN" ]]
}

# acme.sh's standalone server is socat or python; without either it refuses to
# run at all. python3 is common enough on servers that it is accepted as-is,
# socat is installed on demand because it is small and present in every repo.
ensure_standalone_tool() {
    command -v socat >/dev/null 2>&1 && return 0
    command -v python3 >/dev/null 2>&1 && return 0
    log_info "$(t info_install_socat)"
    set +e
    if [[ "$PKG_MANAGER" == "apt" ]]; then
        apt-get update -qq && apt-get install -y -qq socat
    elif [[ "$PKG_MANAGER" == "apk" ]]; then
        apk add --no-cache socat
    elif [[ "$PKG_MANAGER" == "pkg" ]]; then
        pkg install -y socat
    else
        restore_errexit
        return 1
    fi
    local rc=$?
    restore_errexit
    [[ $rc -eq 0 ]] && command -v socat &>/dev/null
}

# Echoes the crt/key paths acme.sh installs for a domain, and exports the same
# pair through ACME_CRT/ACME_KEY so callers can feed build_portal_url directly.
acme_paths() {
    local domain="$1"
    ACME_CRT="${ACME_DIR}/${domain}_ecc/fullchain.cer"
    ACME_KEY="${ACME_DIR}/${domain}_ecc/${domain}.key"
    printf '%s\n%s' "$ACME_CRT" "$ACME_KEY"
}

# RFC 1035 hostname: labels of alphanumerics and inner hyphens, at least one
# dot, no leading/trailing hyphen per label. Deliberately rejects wildcards,
# underscores, bare labels and all-numeric names (IPv4 literals) — acme.sh
# needs a resolvable public name.
acme_valid_domain() {
    local domain="$1"
    [[ "$domain" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$ ]] || return 1
    [[ "$domain" =~ ^[0-9.]+$ ]] && return 1
    return 0
}

# Runs after a successful (re)issue. The Portal reloads tls=2 files every 15
# seconds on its own; this is the belt-and-braces path for the rare case where
# the socket must be reopened. Paths are expanded at write time so the hook
# stays valid even if this script is later removed.
write_acme_reload_hook() {
    mkdir -p "$CONFIG_DIR"
    cat > "$ACME_RELOAD_HOOK" <<HOOK
#!/bin/sh
# Installed by oh-nowhere: reload the Portal after acme.sh renews the cert.
if command -v systemctl >/dev/null 2>&1; then
    systemctl restart ${SERVICE_NAME} 2>/dev/null \\
        || service ${SERVICE_NAME} restart 2>/dev/null || true
elif command -v service >/dev/null 2>&1; then
    service ${SERVICE_NAME} restart 2>/dev/null || true
fi
exit 0
HOOK
    chmod 755 "$ACME_RELOAD_HOOK"
}

# The cron entry. Kept separate from the reload hook so a failed renewal leaves
# a log the operator can read, and so the schedule lives in exactly one place.
# The window check is the point of the whole entry: the job fires every day, but
# acme.sh is only invoked once the issued chain is inside ACME_RENEW_DAYS, so a
# healthy certificate costs one local openssl call and no network traffic.
write_acme_renew_hook() {
    local domain="$1" renew_days="$2"
    mkdir -p "$CONFIG_DIR"
    cat > "$ACME_RENEW_HOOK" <<HOOK
#!/bin/sh
# Installed by oh-nowhere: renew the acme.sh certificate when it enters its
# renewal window, and log the result.
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ACME_HOME="$(dirname "$ACME_BIN")"
LOG_FILE="$ACME_RENEW_LOG"
DOMAIN="$domain"
RENEW_DAYS="$renew_days"
CRT="${ACME_DIR}/${domain}_ecc/fullchain.cer"
{
    echo "===== \$(date '+%Y-%m-%d %H:%M:%S') ====="
    if [ ! -x "\$ACME_HOME/acme.sh" ]; then
        echo "acme.sh not found at \$ACME_HOME/acme.sh"
    elif [ -f "\$CRT" ] && openssl x509 -in "\$CRT" -noout \\
            -checkend "\$((RENEW_DAYS * 86400))" >/dev/null 2>&1; then
        echo "certificate valid until \$(openssl x509 -in "\$CRT" -noout -enddate | cut -d= -f2-); more than \$RENEW_DAYS days left, skipping"
    else
        "\$ACME_HOME/acme.sh" --renew -d "\$DOMAIN" --ecc --home "\$ACME_HOME" 2>&1
    fi
} >> "\$LOG_FILE" 2>&1
exit 0
HOOK
    chmod 755 "$ACME_RENEW_HOOK"
}

acme_issue_cert() {
    local domain="$1" email="$2" challenge="$3" dns="$4"
    local -a cmd=("$ACME_BIN" --issue -d "$domain" --keylength "$ACME_KEY_LENGTH"
                  --server "$ACME_CA_SERVER" --reloadcmd "$ACME_RELOAD_HOOK")
    [[ -n "$email" ]] && cmd+=(--accountemail "$email")
    if [[ "$challenge" == "dns" ]]; then
        [[ -n "$dns" ]] || return 1
        cmd+=(--dns "$dns")
    else
        cmd+=(--standalone)
    fi
    set +e
    "${cmd[@]}" >/dev/null 2>&1
    local rc=$?
    restore_errexit
    [[ $rc -eq 0 ]]
}

acme_renew_cert() {
    local domain="$1"
    set +e
    "$ACME_BIN" --renew -d "$domain" --ecc >/dev/null 2>&1
    local rc=$?
    restore_errexit
    [[ $rc -eq 0 ]]
}

# Is the issued chain inside its renewal window? An absent or unreadable file
# counts as due, because "renew" is also the only way to repair that state.
# openssl -checkend answers in seconds without any date parsing, so it behaves
# the same on GNU and BSD userlands.
acme_renew_due() {
    local crt="$1" days="$2"
    [[ -f "$crt" ]] || return 0
    ! openssl x509 -in "$crt" -noout -checkend "$((days * 86400))" >/dev/null 2>&1
}

# Is a cron daemon actually able to run our entry? crontab(1) existing is the
# strong signal; a bare /etc/cron.d is accepted because several minimal images
# ship the spool without the client.
cron_daemon_available() {
    command -v crontab >/dev/null 2>&1 && return 0
    [[ -d /etc/cron.d ]] && return 0
    return 1
}

install_acme_auto_renew() {
    local schedule="$ACME_CRON_SCHEDULE"
    if command -v crontab >/dev/null 2>&1; then
        local current
        current=$(crontab -l 2>/dev/null || true)
        if ! printf '%s\n' "$current" | grep -qF "$ACME_CRON_MARK"; then
            # Append rather than rewrite, so the operator's own jobs survive.
            if [[ -n "$current" ]]; then
                printf '%s\n%s %s %s\n' \
                    "$current" "$ACME_CRON_MARK" "$schedule" "$ACME_RENEW_HOOK" \
                    | crontab -
            else
                printf '%s %s %s\n' \
                    "$ACME_CRON_MARK" "$schedule" "$ACME_RENEW_HOOK" | crontab -
            fi
        fi
        return 0
    fi
    if [[ -d /etc/cron.d ]]; then
        printf '%s %s root %s\n' "$ACME_CRON_MARK" "$schedule" "$ACME_RENEW_HOOK" \
            > "$ACME_CRON_D_FILE"
        chmod 644 "$ACME_CRON_D_FILE"
        return 0
    fi
    return 1
}

remove_acme_auto_renew() {
    if command -v crontab >/dev/null 2>&1; then
        local current
        current=$(crontab -l 2>/dev/null || true)
        if printf '%s\n' "$current" | grep -qF "$ACME_CRON_MARK"; then
            # Keep everything except our two lines, then drop the blank line the
            # removal can leave at the end.
            printf '%s\n' "$current" | grep -vF "$ACME_CRON_MARK" \
                | grep -vF "$ACME_RENEW_HOOK" | grep -v '^$' | crontab -
        fi
    fi
    rm -f "$ACME_CRON_D_FILE"
}

acme_auto_renew_active() {
    if command -v crontab >/dev/null 2>&1; then
        crontab -l 2>/dev/null | grep -qF "$ACME_RENEW_HOOK" && return 0
    fi
    [[ -f "$ACME_CRON_D_FILE" ]] && grep -qF "$ACME_RENEW_HOOK" "$ACME_CRON_D_FILE" && return 0
    return 1
}

# --renew-cert: refresh the live file-backed certificate in place.
#   acme    -> acme.sh --renew for the recorded domain, then reload the Portal
#   openssl -> re-self-sign with the default validity (the pin changes, so the
#              share URI has to be redistributed)
#   program -> nothing to do, the binary mints a new certificate on every start
renew_cert_action() {
    if [[ ! -f "$URL_FILE" ]]; then
        log_error "$(t err_not_configured)"
        return 1
    fi
    local run_url cert_mode host
    run_url=$(tr -d '\n' < "$URL_FILE")
    if [[ "$(detect_url_role "$run_url")" != "portal" ]]; then
        log_error "$(t err_renew_not_portal)"
        return 1
    fi
    cert_mode=$(detect_cert_mode "$run_url")
    host=$(load_share_host)
    case "$cert_mode" in
        acme)
            local domain
            domain=$(load_cert_mode_field domain)
            if [[ -z "$domain" ]]; then
                log_error "$(t err_acme_domain_missing)"
                return 1
            fi
            if [[ ! -x "$ACME_BIN" ]]; then
                log_error "$(t err_acme_not_installed)"
                return 1
            fi
            acme_paths "$domain" >/dev/null
            if ! acme_renew_cert "$domain"; then
                log_error "$(t err_acme_renew_failed "$domain")"
                return 1
            fi
            log_success "$(t ok_acme_renew "$domain" "$ACME_CRT")"
            ;;
        openssl)
            if ! ensure_openssl; then
                log_error "$(t err_openssl_missing)"
                return 1
            fi
            local san pin cn
            san=$(default_cert_san "$host")
            san=$(normalize_cert_san "$san") || san=$(default_cert_san "$host") || {
                log_error "$(t err_self_sign_failed)"
                return 1
            }
            case "$host" in
                ""|*:*) cn="nowhere-self-signed" ;;
                *)      cn="$host" ;;
            esac
            if ! pin=$(openssl_self_sign "$DEFAULT_CERT" "$DEFAULT_KEYFILE" \
                        "$SELF_SIGN_DAYS_DEFAULT" "$san" "$cn"); then
                log_error "$(t err_self_sign_failed)"
                return 1
            fi
            save_pin "$pin"
            log_success "$(t ok_self_signed "$DEFAULT_CERT" "$DEFAULT_KEYFILE" \
                "$SELF_SIGN_DAYS_DEFAULT" "$pin")"
            log_warn "$(t warn_pin_changes)"
            ;;
        *)
            log_info "$(t info_renew_not_needed "$cert_mode")"
            return 0
            ;;
    esac
    if service_is_active; then
        restart_service
    fi
    return 0
}

# Shared certificate resolution for the install flows. Prompts for what it
# needs, writes files for the openssl mode, and reports through CERT_* globals
# so callers keep a single build_portal_url call.
#   in : $1 cert_mode, $2 host, $3 skip_prompts(true/false)
#   out: CERT_TLS, CERT_CRT, CERT_KEYFILE, CERT_PIN (empty when not applicable)
resolve_cert_mode() {
    local mode="$1" host="$2" skip="$3"
    CERT_TLS="1"; CERT_CRT="$DEFAULT_CERT"; CERT_KEYFILE="$DEFAULT_KEYFILE"; CERT_PIN=""

    case "$mode" in
        program)
            clear_pin
            ;;
        custom)
            if [[ "$skip" == true ]]; then
                CERT_CRT="${ARG_CERT:-$DEFAULT_CERT}"
                CERT_KEYFILE="${ARG_KEYFILE:-$DEFAULT_KEYFILE}"
            else
                local crt_input keyfile_input
                read -rp "$(t prompt_cert "$DEFAULT_CERT")" crt_input
                [[ -n "$crt_input" ]] && CERT_CRT="$crt_input"
                read -rp "$(t prompt_keyfile "$DEFAULT_KEYFILE")" keyfile_input
                [[ -n "$keyfile_input" ]] && CERT_KEYFILE="$keyfile_input"
            fi
            clear_pin
            CERT_TLS="2"
            ;;
        openssl)
            if ! ensure_openssl; then
                log_error "$(t err_openssl_missing)"
                return 1
            fi
            local days="$SELF_SIGN_DAYS_DEFAULT" san cn days_input san_input
            san=$(default_cert_san "$host")
            if [[ "$skip" == true ]]; then
                days="${ARG_SELF_SIGN_DAYS:-$SELF_SIGN_DAYS_DEFAULT}"
                [[ -n "$ARG_CERT_SAN" ]] && san="$ARG_CERT_SAN"
            else
                read -rp "$(t prompt_self_sign_days "$days")" days_input
                [[ -n "$days_input" ]] && days="$days_input"
                read -rp "$(t prompt_cert_san "$san")" san_input
                [[ -n "$san_input" ]] && san="$san_input"
            fi
            san=$(normalize_cert_san "$san") || san=$(default_cert_san "$host") || {
                log_error "$(t err_self_sign_failed)"
                return 1
            }
            # An IPv6 literal cannot be a CN; fall back to a fixed subject.
            case "$host" in
                ""|*:*) cn="nowhere-self-signed" ;;
                *)      cn="$host" ;;
            esac
            if ! CERT_PIN=$(openssl_self_sign "$DEFAULT_CERT" "$DEFAULT_KEYFILE" "$days" "$san" "$cn"); then
                log_error "$(t err_self_sign_failed)"
                return 1
            fi
            save_pin "$CERT_PIN"
            CERT_CRT="$DEFAULT_CERT"
            CERT_KEYFILE="$DEFAULT_KEYFILE"
            CERT_TLS="2"
            log_success "$(t ok_self_signed "$DEFAULT_CERT" "$DEFAULT_KEYFILE" "$days" "$CERT_PIN")"
            ;;
        acme)
            # --acme-domain wins; otherwise the share host is the domain the
            # certificate is for, which is what an operator almost always means.
            local domain="$ARG_ACME_DOMAIN" email="$ARG_ACME_EMAIL"
            local challenge="$ARG_ACME_CHALLENGE" dns="$ARG_ACME_DNS"
            local autorenew="$ARG_ACME_AUTO_RENEW"
            # A previous acme install already chose a window; keep it unless this
            # run says otherwise, so re-configuring does not silently reset it.
            local renew_days
            renew_days=$(load_cert_mode_field renewdays)
            [[ -z "$renew_days" ]] && renew_days="$ACME_RENEW_DAYS"
            [[ "$skip" == true ]] && [[ -n "$ARG_ACME_RENEW_DAYS" ]] && \
                renew_days="$ARG_ACME_RENEW_DAYS"
            [[ -z "$domain" ]] && domain="$host"
            if [[ "$skip" != true ]]; then
                local domain_input email_input challenge_input dns_input renew_input days_input
                read -rp "$(t prompt_acme_domain "$domain")" domain_input
                [[ -n "$domain_input" ]] && domain="$domain_input"
                read -rp "$(t prompt_acme_email)" email_input
                [[ -n "$email_input" ]] && email="$email_input"
                read -rp "$(t prompt_acme_challenge "http")" challenge_input
                [[ -n "$challenge_input" ]] && challenge="$challenge_input"
                if [[ "$challenge" == "dns" ]]; then
                    read -rp "$(t prompt_acme_dns)" dns_input
                    [[ -n "$dns_input" ]] && dns="$dns_input"
                fi
                read -rp "$(t prompt_acme_auto_renew "yes")" renew_input
                [[ -n "$renew_input" ]] && autorenew="$renew_input"
                read -rp "$(t prompt_acme_renew_days "$renew_days")" days_input
                [[ -n "$days_input" ]] && renew_days="$days_input"
            fi
            if ! acme_valid_domain "$domain"; then
                log_error "$(t err_acme_domain_invalid "$domain")"
                return 1
            fi
            [[ "$challenge" == "dns" ]] && [[ -z "$dns" ]] && {
                log_error "$(t err_acme_dns_missing)"
                return 1
            }
            case "$autorenew" in
                yes|no) ;;
                *) log_error "$(t err_acme_auto_renew_invalid "$autorenew")"; return 1 ;;
            esac
            if [[ ! "$renew_days" =~ ^[0-9]+$ ]] || \
               (( renew_days < 1 || renew_days > 89 )); then
                log_error "$(t err_acme_renew_days_invalid "$renew_days")"
                return 1
            fi
            if [[ "$challenge" != "dns" ]]; then
                # standalone binds port 80 itself; anything already listening on
                # it makes validation fail with an opaque acme.sh error, so say
                # it plainly and point at the DNS escape hatch.
                if port_in_use "$ACME_HTTP_PORT"; then
                    log_error "$(t err_acme_port_busy "$ACME_HTTP_PORT")"
                    return 1
                fi
                if ! ensure_standalone_tool; then
                    log_error "$(t err_acme_standalone_missing)"
                    return 1
                fi
            fi
            if ! ensure_acme "$email"; then
                log_error "$(t err_acme_install_failed)"
                return 1
            fi
            acme_paths "$domain" >/dev/null
            if [[ ! -f "$ACME_CRT" || ! -f "$ACME_KEY" ]]; then
                if ! acme_issue_cert "$domain" "$email" "$challenge" "$dns"; then
                    log_error "$(t err_acme_issue_failed "$domain")"
                    return 1
                fi
            elif acme_renew_due "$ACME_CRT" "$renew_days"; then
                if ! acme_renew_cert "$domain"; then
                    # A failed renewal of a still-valid certificate is not fatal:
                    # keep serving the existing one and let cron retry later.
                    log_warn "$(t warn_acme_renew_failed "$domain")"
                fi
            else
                # Outside the window the live chain is kept as-is. Renewing here
                # would burn a duplicate-certificate allowance for nothing.
                log_info "$(t info_acme_cert_kept "$domain" \
                    "$(cert_not_after "$ACME_CRT")" "$renew_days")"
            fi
            write_acme_reload_hook
            write_acme_renew_hook "$domain" "$renew_days"
            if [[ "$autorenew" == "yes" ]]; then
                if ! install_acme_auto_renew; then
                    log_warn "$(t warn_acme_cron_unavailable)"
                else
                    log_info "$(t info_acme_cron_installed "$ACME_CRON_SCHEDULE" "$renew_days")"
                fi
            else
                remove_acme_auto_renew
            fi
            save_cert_mode acme "$domain" "$autorenew" "$renew_days"
            clear_pin
            CERT_CRT="$ACME_CRT"
            CERT_KEYFILE="$ACME_KEY"
            CERT_TLS="2"
            log_success "$(t ok_acme_cert "$domain" "$ACME_CRT" "$ACME_KEY")"
            ;;
        *)
            log_error "$(t err_cert_mode_invalid "$mode")"
            return 1
            ;;
    esac
    return 0
}

url_encode_name() {
    # Percent-encode a node name for use as a URI fragment.
    local LC_ALL=C
    local value="$1" encoded="" c i
    for (( i=0; i<${#value}; i++ )); do
        c="${value:i:1}"
        case "$c" in
            [a-zA-Z0-9._~-]) encoded+="$c" ;;
            *) printf -v c '%%%02X' "'$c"; encoded+="$c" ;;
        esac
    done
    printf '%s' "$encoded"
}

get_server_location() {
    # Best-effort country code of the server (e.g. US, JP); empty on failure.
    local loc=""
    for api in "https://ipinfo.io/country" "https://ipapi.co/country"; do
        loc=$(curl -fsSL --connect-timeout 5 "$api" 2>/dev/null | tr -d '[:space:]' | tr '[:lower:]' '[:upper:]' | grep -oE '^[A-Z]{2}$' | head -n1 || true)
        [[ -n "$loc" ]] && break
    done
    echo "$loc"
}

default_node_name() {
    # Default: Nowhere-<country>-<first IP octet>, e.g. Nowhere-US-203
    local ip loc octet=""
    ip=$(get_public_ip)
    if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        octet="${ip%%.*}"
    fi
    loc=$(get_server_location)
    local name="Nowhere"
    [[ -n "$loc" ]] && name="${name}-${loc}"
    [[ -n "$octet" ]] && name="${name}-${octet}"
    echo "$name"
}

load_node_name() {
    if [[ -n "$ARG_NAME" ]]; then
        echo "$ARG_NAME"
        return
    fi
    if [[ -f "$NAME_FILE" ]]; then
        tr -d '\n' < "$NAME_FILE"
        return
    fi
    default_node_name
}

save_node_name() {
    local name="$1"
    mkdir -p "$CONFIG_DIR"
    # An empty name is kept as an empty file: no #fragment in the share URI.
    echo "$name" > "$NAME_FILE"
}

# ==================== Version profile ====================
version_major() {
    local v="${1#v}"
    v="${v%%[!0-9]*}"
    if [[ -z "$v" ]]; then
        echo ""
        return
    fi
    echo "$v"
}

config_major() {
    if [[ -n "$ARG_VERSION" ]]; then
        version_major "$ARG_VERSION"
        return
    fi
    if [[ -n "$TARGET_VERSION" ]]; then
        version_major "$TARGET_VERSION"
        return
    fi
    local inst
    inst=$(get_installed_version)
    if [[ -n "$inst" ]]; then
        version_major "$inst"
        return
    fi
    # Fresh installs (and any undetermined state) follow the current line: nw3.
    echo 3
}

is_v2_profile() {
    local major
    major=$(config_major)
    [[ -n "$major" && "$major" -ge 2 ]]
}

# Protocol generation of the current or planned configuration: nw1|nw2|nw3.
# nw2 and nw3 share the v2 endpoint-path syntax but are wire-incompatible.
proto_profile() {
    case "$(config_major)" in
        1) echo nw1 ;;
        2) echo nw2 ;;
        *) echo nw3 ;;
    esac
}

is_nw3_profile() {
    [[ "$(proto_profile)" == "nw3" ]]
}

is_nw2_profile() {
    [[ "$(proto_profile)" == "nw2" ]]
}

# Effective Nowhere version string for the current/planned operation.
# Empty means "latest" (default install/upgrade target).
effective_version() {
    if [[ -n "$ARG_VERSION" ]]; then
        echo "$ARG_VERSION"
        return
    fi
    if [[ -n "$TARGET_VERSION" ]]; then
        echo "$TARGET_VERSION"
        return
    fi
    case "$AUTO_MODE" in
        install|upgrade)
            echo ""
            return
            ;;
    esac
    get_installed_version
}

# Compare semantic major.minor.patch versions: success if $1 >= $2.
version_ge() {
    local have="$1" need="$2"
    local i hv nv
    for i in 1 2 3; do
        hv=$(version_part "$have" "$i")
        nv=$(version_part "$need" "$i")
        if (( 10#$hv != 10#$nv )); then
            (( 10#$hv > 10#$nv ))
            return
        fi
    done
    return 0
}

version_part() {
    local v="${1#v}"
    local part
    part=$(echo "$v" | cut -d'.' -f "$2")
    part="${part%%[!0-9]*}"
    echo "${part:-0}"
}

# Nowhere 2.2+ enforces 32-64 lowercase hex Portal keys and mandatory
# certificate verification. Empty version counts as latest (2.2+). Key rules
# themselves are resolved per protocol profile (valid_key_for_profile).
is_v22_profile() {
    local v
    v=$(effective_version)
    [[ -z "$v" ]] && return 0
    version_ge "$v" "2.2.0"
}

valid_v22_key() {
    [[ "$1" =~ ^[0-9a-f]{32,64}$ ]]
}

# Shared-key rules per protocol generation and role. nw3 requires exactly 32
# lowercase hex characters for Portal, Vector and Egress alike; nw2.2 tightens
# Portal keys to 32-64 hex while Vector keys stay free text; nw1 takes any key.
valid_key_for_profile() {
    local key="$1" role="${2:-portal}"
    case "$(proto_profile)" in
        nw3)
            [[ "$key" =~ ^[0-9a-f]{32}$ ]]
            ;;
        nw2)
            if [[ "$role" == "portal" ]] && is_v22_profile; then
                valid_v22_key "$key"
            else
                [[ -n "$key" ]]
            fi
            ;;
        *)
            [[ -n "$key" ]]
            ;;
    esac
}

default_carrier() {
    if is_v2_profile; then
        echo tcp
    else
        echo udp
    fi
}

validate_port_value() {
    local port="$1"
    if [[ ! "$port" =~ ^[1-9][0-9]{0,4}$ ]] || (( port > 65535 )); then
        log_error "$(t err_invalid_port "$port")"
        return 1
    fi
    return 0
}

validate_morph_value() {
    case "$1" in
        ""|0|1) return 0 ;;
        *)
            log_error "$(t err_invalid_morph "$1")"
            return 1
            ;;
    esac
}

validate_net_value() {
    case "$1" in
        mix|tcp|udp) return 0 ;;
        *)
            log_error "$(t err_invalid_net "$1")"
            return 1
            ;;
    esac
}

validate_mux_value() {
    case "$1" in
        ""|0|1) return 0 ;;
        *)
            log_error "$(t err_invalid_mux "$1")"
            return 1
            ;;
    esac
}

# Returns 0 when the port is already bound (TCP or UDP listener) by any process.
port_in_use() {
    local port="$1"
    [[ -z "$port" ]] && return 1
    if command -v ss >/dev/null 2>&1; then
        ss -H -tuln 2>/dev/null | awk '{print $5}' | grep -qE "[:.]${port}$"
    elif command -v sockstat >/dev/null 2>&1; then
        sockstat -46ln 2>/dev/null | awk 'NR>1 {print $6}' | grep -qE "[:.]${port}$"
    elif command -v netstat >/dev/null 2>&1; then
        netstat -tuln 2>/dev/null | awk 'NR>2 {print $4}' | grep -qE "[:.]${port}$"
    else
        # No tool available to check; assume the port is free.
        return 1
    fi
}

# Warns and asks for confirmation when the port is occupied; returns 0 if usable.
# Logs go to stderr so command substitutions capturing the chosen port stay clean.
confirm_port_conflict() {
    local port="$1"
    port_in_use "$port" || return 0
    log_warn "$(t warn_port_in_use "$port")" >&2
    local ans=""
    read -rp "$(t prompt_port_conflict "$port")" ans
    [[ "$ans" =~ ^[Yy]$ ]]
}

# Reads a port with validation and conflict detection.
# $1: prompt key, $2: default value, $3: previous value (skip check when unchanged).
# Falls back to the previous value when a conflict is declined; without a
# previous value it keeps asking until a free port is confirmed.
read_port_checked() {
    local prompt_key="$1" default="$2" previous="${3:-}"
    local value=""
    while true; do
        read -rp "$(t "$prompt_key" "$default")" value
        [[ -z "$value" ]] && value="$default"
        if ! validate_port_value "$value"; then
            continue
        fi
        if [[ -n "$previous" && "$value" == "$previous" ]] || confirm_port_conflict "$value"; then
            printf '%s' "$value"
            return 0
        fi
        if [[ -n "$previous" ]]; then
            log_info "$(t info_port_unchanged "$previous")" >&2
            printf '%s' "$previous"
            return 0
        fi
        log_error "$(t err_port_in_use "$value")" >&2
    done
}

# Reads a shared key interactively. Key rules follow the protocol profile:
# nw3 demands exactly 32 lowercase hex for every role, nw2.2 demands 32-64 hex
# for Portal keys. Invalid input is reported and the prompt repeats. Empty
# input keeps the current key. Sets ENTERED_KEY.
read_key_checked() {
    local role="$1" current="$2" input=""
    while true; do
        read -rp "$(t prompt_key "$current")" input
        [[ -z "$input" ]] && break
        if ! valid_key_for_profile "$input" "$role"; then
            log_error "$(t err_invalid_key)"
            continue
        fi
        ENTERED_KEY="$input"
        return 0
    done
    ENTERED_KEY="$current"
    return 0
}

enforce_v2_only_options() {
    local opt=""
    if [[ -n "$ARG_TCP_PORT" ]]; then
        opt="--tcp-port"
    elif [[ -n "$ARG_UDP_PORT" ]]; then
        opt="--udp-port"
    elif [[ -n "$ARG_MORPH" ]]; then
        opt="--morph"
    fi
    if [[ -n "$opt" ]] && ! is_v2_profile; then
        log_error "$(t err_opt_v2_only "$opt")"
        exit 1
    fi
    # alpn is a 1.x-only parameter: ignored on both v2+ lines.
    if is_v2_profile && [[ -n "$ARG_ALPN" ]]; then
        log_warn "$(t warn_alpn_ignored)"
        ARG_ALPN=""
    fi
    # nw3 removed next= chaining; Portal exits through out= instead.
    if is_nw3_profile && [[ -n "$ARG_NEXT" ]]; then
        log_error "$(t err_next_removed)"
        exit 1
    fi
}

strip_query_param() {
    local url="$1"
    local key="$2"
    echo "$url" | sed -E \
        -e "s/([?&])${key}=[^&]*(&|$)/\1/" \
        -e 's/\?&/?/' \
        -e 's/&&+/\&/g' \
        -e 's/\?$//' \
        -e 's/&$//'
}

append_query_param() {
    local url="$1"
    local pair="$2"
    if [[ "$url" == *\?* ]]; then
        echo "${url}&${pair}"
    else
        echo "${url}?${pair}"
    fi
}

get_query_param() {
    local url="$1"
    local key="$2"
    echo "$url" | sed -n "s/.*[?&]${key}=\([^&#]*\).*/\1/p" | head -n1
}

url_encode_component() {
    local LC_ALL=C
    local value="$1" encoded="" c i
    for (( i=0; i<${#value}; i++ )); do
        c="${value:i:1}"
        case "$c" in
            [a-zA-Z0-9._~-]) encoded+="$c" ;;
            *) printf -v c '%%%02X' "'$c"; encoded+="$c" ;;
        esac
    done
    printf '%s' "$encoded"
}

encode_socks_endpoint() {
    # Encode user:pass@host:port so reserved chars in credentials are safe in URLs.
    local socks="$1"
    if [[ "$socks" != *@* ]]; then
        printf '%s' "$socks"
        return
    fi
    local creds="${socks%@*}"
    local hostport="${socks##*@}"
    local user="${creds%%:*}"
    local pass=""
    if [[ "$creds" == *:* ]]; then
        pass="${creds#*:}"
    fi
    if [[ -n "$pass" ]]; then
        printf '%s:%s@%s' "$(url_encode_component "$user")" "$(url_encode_component "$pass")" "$hostport"
    else
        printf '%s@%s' "$(url_encode_component "$user")" "$hostport"
    fi
}

encode_next_endpoint() {
    # Encode shared-key@host:port for Portal next= query values.
    local next="$1"
    if [[ "$next" != *@* ]]; then
        printf '%s' "$(url_encode_component "$next")"
        return
    fi
    local shared_key="${next%@*}"
    local hostport="${next##*@}"
    printf '%s@%s' "$(url_encode_component "$shared_key")" "$hostport"
}

rewrite_url_key() {
    # Replaces the userinfo key of a portal:// / vector:// URL.
    local url="$1"
    local newkey="$2"
    echo "$url" | sed -E "s#^([a-z]+://)[^@]*@#\\1${newkey}@#"
}

run_with_timeout() {
    # FreeBSD has no timeout(1) by default; run the command unbounded there.
    local secs="$1"
    shift
    if command -v timeout &>/dev/null; then
        timeout "$secs" "$@"
    else
        "$@"
    fi
}

portal_outbound_mode() {
    local socks="$1"
    local next="$2"
    if [[ -n "$next" && "$next" != "none" ]]; then
        echo "next"
    elif [[ -n "$socks" && "$socks" != "none" ]]; then
        echo "socks"
    else
        echo "none"
    fi
}

validate_portal_outbound() {
    local socks="$1"
    local next="$2"
    if [[ -n "$next" && "$next" != "none" && -n "$socks" && "$socks" != "none" ]]; then
        log_error "$(t err_next_socks_mutex)"
        return 1
    fi
    return 0
}

validate_carrier() {
    case "$1" in
        tcp|udp|mix) return 0 ;;
        *)
            log_error "$(t err_invalid_carrier "$1")"
            return 1
            ;;
    esac
}

mux_applies() {
    local up="$1" down="$2"
    # Mux applies when at least one direction is tcp or mix (Nowhere 1.8.3).
    [[ "$up" != "udp" || "$down" != "udp" ]]
}

append_mux_query() {
    local url="$1" up="$2" down="$3" mux="$4"
    if [[ "$up" == "udp" && "$down" == "udp" ]]; then
        printf '%s' "$url"
        return
    fi
    if ! is_v2_profile && [[ "$up" == "tcp" && "$down" == "tcp" ]]; then
        mux="${mux:-1}"
    fi
    if [[ -n "$mux" ]]; then
        url="${url}&mux=${mux}"
    fi
    printf '%s' "$url"
}

append_morph_query() {
    local url="$1" morph="$2"
    if is_v2_profile && [[ "$morph" == "1" ]]; then
        url="${url}&morph=1"
    fi
    printf '%s' "$url"
}

format_url_host() {
    local host="$1"
    if [[ -z "$host" || "$host" == "*" ]]; then
        printf '%s' "$host"
        return
    fi
    if [[ "$host" == *:* && "$host" != \[* ]]; then
        printf '[%s]' "$host"
    else
        printf '%s' "$host"
    fi
}

# Sets RESOLVED_TCP RESOLVED_UDP from net/port and optional explicit ports.
resolve_carrier_ports() {
    local net="${1:-mix}"
    local port="$2"
    local tcp_port="$3"
    local udp_port="$4"
    RESOLVED_TCP=""
    RESOLVED_UDP=""

    if ! validate_net_value "$net"; then
        return 1
    fi
    if [[ -n "$port" ]] && ! validate_port_value "$port"; then
        return 1
    fi
    if [[ -n "$tcp_port" ]] && ! validate_port_value "$tcp_port"; then
        return 1
    fi
    if [[ -n "$udp_port" ]] && ! validate_port_value "$udp_port"; then
        return 1
    fi

    if [[ -n "$tcp_port" || -n "$udp_port" ]]; then
        if [[ "$net" == "tcp" && -n "$udp_port" ]]; then
            log_error "$(t err_net_port_conflict "$net")"
            return 1
        fi
        if [[ "$net" == "udp" && -n "$tcp_port" ]]; then
            log_error "$(t err_net_port_conflict "$net")"
            return 1
        fi
        RESOLVED_TCP="$tcp_port"
        RESOLVED_UDP="$udp_port"
        return 0
    fi

    case "$net" in
        tcp) RESOLVED_TCP="$port" ;;
        udp) RESOLVED_UDP="$port" ;;
        mix) RESOLVED_TCP="$port"; RESOLVED_UDP="$port" ;;
    esac
    return 0
}

validate_policy_on_endpoint() {
    local up="$1" down="$2" tcp_port="$3" udp_port="$4"
    if [[ "$up" == "mix" || "$down" == "mix" ]]; then
        if [[ -z "$tcp_port" || -z "$udp_port" ]]; then
            log_error "$(t err_carrier_undeclared "$up" "$down")"
            return 1
        fi
    fi
    if [[ "$up" == "tcp" || "$down" == "tcp" ]]; then
        if [[ -z "$tcp_port" ]]; then
            log_error "$(t err_carrier_undeclared "$up" "$down")"
            return 1
        fi
    fi
    if [[ "$up" == "udp" || "$down" == "udp" ]]; then
        if [[ -z "$udp_port" ]]; then
            log_error "$(t err_carrier_undeclared "$up" "$down")"
            return 1
        fi
    fi
    return 0
}

# role=portal|vector|egress, host, tcp_port, udp_port → endpoint without scheme/key
build_endpoint_hostpart() {
    local role="$1"
    local host="$2"
    local tcp_port="$3"
    local udp_port="$4"
    local host_fmt

    if [[ "$role" == "portal" ]]; then
        if [[ -z "$host" || "$host" == "*" ]]; then
            host="*"
        fi
    fi
    host_fmt=$(format_url_host "$host")

    if is_nw3_profile; then
        # nw3 rejects empty hosts outright, so the Portal wildcard is explicit.
        # Vector and Egress declare exactly one carrier per endpoint.
        if [[ "$role" == "portal" ]]; then
            if [[ -n "$tcp_port" && -n "$udp_port" && "$tcp_port" == "$udp_port" ]]; then
                printf '*:%s' "$tcp_port"
            elif [[ -n "$tcp_port" && -n "$udp_port" ]]; then
                printf '*/tcp:%s/udp:%s' "$tcp_port" "$udp_port"
            elif [[ -n "$tcp_port" ]]; then
                printf '*/tcp:%s' "$tcp_port"
            elif [[ -n "$udp_port" ]]; then
                printf '*/udp:%s' "$udp_port"
            else
                printf '*'
            fi
            return
        fi
        if [[ -n "$tcp_port" ]]; then
            printf '%s/tcp:%s' "$host_fmt" "$tcp_port"
        elif [[ -n "$udp_port" ]]; then
            printf '%s/udp:%s' "$host_fmt" "$udp_port"
        else
            return 1
        fi
        return
    fi

    if [[ -n "$tcp_port" && -n "$udp_port" && "$tcp_port" == "$udp_port" ]]; then
        if [[ "$role" == "portal" && "$host" == "*" ]]; then
            printf ':%s' "$tcp_port"
        else
            printf '%s:%s' "$host_fmt" "$tcp_port"
        fi
        return
    fi
    if [[ "$role" == "portal" && "$host" == "*" ]]; then
        host_fmt="*"
    fi
    if [[ -n "$tcp_port" && -n "$udp_port" ]]; then
        printf '%s/tcp:%s/udp:%s' "$host_fmt" "$tcp_port" "$udp_port"
    elif [[ -n "$tcp_port" ]]; then
        printf '%s/tcp:%s' "$host_fmt" "$tcp_port"
    elif [[ -n "$udp_port" ]]; then
        printf '%s/udp:%s' "$host_fmt" "$udp_port"
    else
        printf '%s' "$host_fmt"
    fi
}

rewrite_url_endpoint() {
    local url="$1"
    local new_ep="$2"
    local prefix query="" frag=""
    if [[ "$url" == *#* ]]; then
        frag="#${url#*#}"
        url="${url%%#*}"
    fi
    if [[ "$url" == *\?* ]]; then
        query="?${url#*\?}"
        url="${url%%\?*}"
    fi
    prefix=$(echo "$url" | sed -n 's#^\([a-z]*://[^@]*@\).*#\1#p')
    printf '%s%s%s%s' "$prefix" "$new_ep" "$query" "$frag"
}

url_has_carrier_path() {
    echo "$1" | grep -qE '@[^?#]*/(tcp|udp)[46]?:'
}

load_portal_outbound_from_url() {
    local url="$1"
    local dc
    dc=$(default_carrier)
    PORTAL_SOCKS=""
    PORTAL_NEXT=""
    PORTAL_UP="$dc"
    PORTAL_DOWN="$dc"
    PORTAL_MUX="0"
    PORTAL_SNI=""
    PORTAL_PIN=""
    PORTAL_MORPH=""

    local raw
    raw=$(get_query_param "$url" "socks")
    if [[ -n "$raw" ]]; then PORTAL_SOCKS=$(url_decode_simple "$raw"); fi
    raw=$(get_query_param "$url" "next")
    if [[ -n "$raw" ]]; then PORTAL_NEXT=$(url_decode_simple "$raw"); fi
    raw=$(get_query_param "$url" "up")
    if [[ -n "$raw" ]]; then PORTAL_UP="$raw"; fi
    raw=$(get_query_param "$url" "down")
    if [[ -n "$raw" ]]; then PORTAL_DOWN="$raw"; fi
    raw=$(get_query_param "$url" "mux")
    if [[ -n "$raw" ]]; then PORTAL_MUX="$raw"; fi
    raw=$(get_query_param "$url" "sni")
    if [[ -n "$raw" ]]; then PORTAL_SNI=$(url_decode_simple "$raw"); fi
    raw=$(get_query_param "$url" "pin")
    if [[ -n "$raw" ]]; then PORTAL_PIN=$(url_decode_simple "$raw"); fi
    raw=$(get_query_param "$url" "morph")
    if [[ -n "$raw" ]]; then PORTAL_MORPH="$raw"; fi
    return 0
}

collect_portal_outbound_interactive() {
    local socks="$1"
    local next="$2"
    local up="$3"
    local down="$4"
    local mux="$5"
    local sni="$6"
    local pin="$7"

    local dc
    dc=$(default_carrier)

    if is_nw3_profile; then
        # nw3 Portal exits direct (default), through a SOCKS5 upstream or via a
        # registered Egress. sni/pin and the carrier options do not apply.
        local default_socks="${socks:-proxy.example:1080}"
        local mode_input=""
        read -rp "$(t prompt_outbound_mode_nw3 "direct")" mode_input
        mode_input="${mode_input:-direct}"

        socks=""
        next=""
        case "$mode_input" in
            direct|none|"")
                OUT_OUTBOUND="direct"
                ;;
            socks)
                OUT_OUTBOUND="socks"
                read -rp "$(t prompt_socks_out "$default_socks")" socks_input
                [[ -n "$socks_input" ]] && socks="$socks_input"
                [[ -z "$socks" ]] && socks="$default_socks"
                ;;
            egress)
                OUT_OUTBOUND="egress"
                ;;
            *)
                log_error "$(t err_invalid_type "$mode_input")"
                return 1
                ;;
        esac

        OUT_SOCKS="$socks"
        OUT_NEXT=""
        OUT_UP=""
        OUT_DOWN=""
        OUT_MUX=""
        OUT_SNI=""
        OUT_PIN=""
        return 0
    fi

    local default_socks="${socks:-proxy.example:1080}"
    local default_next="${next:-origin-key@origin.example:2077}"
    local outbound_mode
    outbound_mode=$(portal_outbound_mode "$socks" "$next")
    local mode_input=""
    read -rp "$(t prompt_outbound_mode "$outbound_mode")" mode_input
    mode_input="${mode_input:-$outbound_mode}"

    socks=""
    next=""
    up="${up:-$dc}"
    down="${down:-$dc}"
    mux="${mux:-0}"
    sni="${sni:-}"
    pin="${pin:-}"

    case "$mode_input" in
        socks)
            read -rp "$(t prompt_socks_out "$default_socks")" socks_input
            [[ -n "$socks_input" ]] && socks="$socks_input"
            ;;
        next)
            read -rp "$(t prompt_next "$default_next")" next_input
            [[ -n "$next_input" ]] && next="$next_input"
            if [[ -z "$next" ]]; then
                log_error "$(t err_next_required)"
                return 1
            fi

            read -rp "$(t prompt_up "$up")" up_input
            [[ -n "$up_input" ]] && up="$up_input"

            read -rp "$(t prompt_down "$down")" down_input
            [[ -n "$down_input" ]] && down="$down_input"

            if mux_applies "$up" "$down"; then
                read -rp "$(t prompt_mux "$mux")" mux_input
                [[ -n "$mux_input" ]] && mux="$mux_input"
            else
                mux=""
            fi

            read -rp "$(t prompt_sni "$sni")" sni_input
            if [[ "$sni_input" == "-" ]]; then
                sni=""
            elif [[ -n "$sni_input" ]]; then
                sni="$sni_input"
            fi

            read -rp "$(t prompt_pin "$pin")" pin_input
            if [[ "$pin_input" == "-" ]]; then
                pin=""
            elif [[ -n "$pin_input" ]]; then
                pin="$pin_input"
            fi
            ;;
        none|"")
            ;;
        *)
            log_error "$(t err_invalid_type "$mode_input")"
            return 1
            ;;
    esac

    OUT_SOCKS="$socks"
    OUT_NEXT="$next"
    OUT_UP="$up"
    OUT_DOWN="$down"
    OUT_MUX="$mux"
    OUT_SNI="$sni"
    OUT_PIN="$pin"
    OUT_OUTBOUND=""
    return 0
}

prompt_v2_carrier_ports() {
    local net="$1"
    local port="$2"
    local tcp_port="$3"
    local udp_port="$4"
    local tcp_input udp_input

    case "$net" in
        tcp)
            tcp_port="${tcp_port:-$port}"
            while true; do
                read -rp "$(t prompt_tcp_port "$tcp_port")" tcp_input
                [[ -z "$tcp_input" ]] && break
                validate_port_value "$tcp_input" || continue
                if [[ "$tcp_input" == "$tcp_port" ]] || confirm_port_conflict "$tcp_input"; then
                    tcp_port="$tcp_input"
                fi
                break
            done
            udp_port=""
            ;;
        udp)
            udp_port="${udp_port:-$port}"
            while true; do
                read -rp "$(t prompt_udp_port "$udp_port")" udp_input
                [[ -z "$udp_input" ]] && break
                validate_port_value "$udp_input" || continue
                if [[ "$udp_input" == "$udp_port" ]] || confirm_port_conflict "$udp_input"; then
                    udp_port="$udp_input"
                fi
                break
            done
            tcp_port=""
            ;;
        *)
            tcp_port="${tcp_port:-$port}"
            udp_port="${udp_port:-$port}"
            while true; do
                read -rp "$(t prompt_tcp_port "$tcp_port")" tcp_input
                [[ -z "$tcp_input" ]] && break
                validate_port_value "$tcp_input" || continue
                if [[ "$tcp_input" == "$tcp_port" ]] || confirm_port_conflict "$tcp_input"; then
                    tcp_port="$tcp_input"
                fi
                break
            done
            while true; do
                read -rp "$(t prompt_udp_port "$udp_port")" udp_input
                [[ -z "$udp_input" ]] && break
                validate_port_value "$udp_input" || continue
                if [[ "$udp_input" == "$udp_port" ]] || confirm_port_conflict "$udp_input"; then
                    udp_port="$udp_input"
                fi
                break
            done
            ;;
    esac
    OUT_TCP_PORT="$tcp_port"
    OUT_UDP_PORT="$udp_port"
}

detect_url_role() {
    local url="$1"
    case "$url" in
        portal://*) echo "portal" ;;
        vector://*|nowhere://*) echo "vector" ;;
        egress://*) echo "egress" ;;
        *) echo "" ;;
    esac
}

get_service_description() {
    local url=""
    [[ -f "$URL_FILE" ]] && url=$(tr -d '\n' < "$URL_FILE")
    case "$(detect_url_role "$url")" in
        vector) echo "Nowhere Vector" ;;
        egress) echo "Nowhere Egress" ;;
        *) echo "Nowhere Portal" ;;
    esac
}

parse_url_authority() {
    # Sets PARSE_KEY PARSE_HOST PARSE_PORT PARSE_TCP_PORT PARSE_UDP_PORT PARSE_CARRIERS.
    local url="${1%%#*}"
    url="${url%%\?*}"
    PARSE_KEY=""
    PARSE_HOST=""
    PARSE_PORT=""
    PARSE_TCP_PORT=""
    PARSE_UDP_PORT=""
    PARSE_CARRIERS=""
    PARSE_KEY=$(echo "$url" | sed -n 's#^[a-z]*://\([^@]*\)@.*#\1#p')
    local rest path="" authority=""
    rest=$(echo "$url" | sed -n 's#^[a-z]*://[^@]*@##p')

    if [[ "$rest" == \[*\]* ]]; then
        PARSE_HOST=$(echo "$rest" | sed -n 's/^\[\([^]]*\)\].*/\1/p')
        local after
        after=$(echo "$rest" | sed -n 's/^\[[^]]*\]\(.*\)/\1/p')
        if [[ "$after" == :* ]]; then
            PARSE_PORT="${after#:}"
            PARSE_PORT="${PARSE_PORT%%/*}"
            if [[ "$after" == */* ]]; then
                path="/${after#*/}"
            fi
        elif [[ "$after" == /* ]]; then
            path="$after"
        fi
    else
        if [[ "$rest" == */* ]]; then
            authority="${rest%%/*}"
            path="/${rest#*/}"
            if [[ "$authority" == *:* ]]; then
                PARSE_PORT="${authority##*:}"
                PARSE_HOST="${authority%:$PARSE_PORT}"
            else
                PARSE_HOST="$authority"
            fi
        elif [[ "$rest" == *:* ]]; then
            PARSE_PORT="${rest##*:}"
            PARSE_HOST="${rest%:$PARSE_PORT}"
        else
            PARSE_HOST="$rest"
        fi
    fi

    if [[ -n "$path" ]]; then
        local seg name p
        IFS='/' read -ra segs <<< "${path#/}"
        for seg in "${segs[@]}"; do
            [[ -z "$seg" ]] && continue
            name="${seg%%:*}"
            p="${seg#*:}"
            case "$name" in
                tcp|tcp4|tcp6) PARSE_TCP_PORT="$p" ;;
                udp|udp4|udp6) PARSE_UDP_PORT="$p" ;;
            esac
        done
    fi

    if [[ -n "$PARSE_PORT" && -z "$PARSE_TCP_PORT" && -z "$PARSE_UDP_PORT" ]]; then
        PARSE_TCP_PORT="$PARSE_PORT"
        PARSE_UDP_PORT="$PARSE_PORT"
        PARSE_CARRIERS="mix"
    elif [[ -n "$PARSE_TCP_PORT" && -n "$PARSE_UDP_PORT" ]]; then
        PARSE_CARRIERS="mix"
        PARSE_PORT="${PARSE_PORT:-$PARSE_TCP_PORT}"
    elif [[ -n "$PARSE_TCP_PORT" ]]; then
        PARSE_CARRIERS="tcp"
        PARSE_PORT="${PARSE_PORT:-$PARSE_TCP_PORT}"
    elif [[ -n "$PARSE_UDP_PORT" ]]; then
        PARSE_CARRIERS="udp"
        PARSE_PORT="${PARSE_PORT:-$PARSE_UDP_PORT}"
    fi
}

build_portal_url() {
    local key="$1"
    local port="$2"
    local tls="$3"
    local net="$4"
    local alpn="$5"
    local crt="$6"
    local keyfile="$7"
    local socks="${8:-}"
    local next="${9:-}"
    local up="${10:-}"
    local down="${11:-}"
    local mux="${12:-}"
    local sni="${13:-}"
    local pin="${14:-}"
    local morph="${15:-}"
    local tcp_port="${16:-}"
    local udp_port="${17:-}"
    # nw3 only: "" | direct | socks | egress (Portal exit selection).
    local out_mode="${18:-}"

    if ! validate_portal_outbound "$socks" "$next"; then
        return 1
    fi
    if ! validate_morph_value "$morph"; then
        return 1
    fi
    if ! valid_key_for_profile "$key" "portal"; then
        log_error "$(t err_invalid_key)"
        return 1
    fi
    if [[ -n "$next" && "$next" != "none" && "$next" == *@* ]]; then
        local next_key="${next%@*}"
        if ! valid_key_for_profile "$next_key" "portal"; then
            log_error "$(t err_invalid_next_key)"
            return 1
        fi
    fi

    local dc hostpart url
    dc=$(default_carrier)
    net="${net:-mix}"

    if is_nw3_profile; then
        if ! resolve_carrier_ports "$net" "$port" "$tcp_port" "$udp_port"; then
            return 1
        fi
        if [[ "$tls" != "1" && "$tls" != "2" ]]; then
            log_error "$(t err_invalid_tls "$tls")"
            return 1
        fi
        # nw3 has no next= chaining: the Portal exits direct, through a SOCKS5
        # upstream (out=endpoint) or through a registered Egress (out=egress).
        if [[ -n "$next" && "$next" != "none" ]]; then
            log_error "$(t err_next_removed)"
            return 1
        fi
        local out_exit="direct"
        if [[ "$out_mode" == "egress" ]]; then
            if [[ -z "$RESOLVED_UDP" ]]; then
                log_error "$(t err_egress_needs_udp)"
                return 1
            fi
            out_exit="egress"
        elif [[ -n "$socks" && "$socks" != "none" ]]; then
            out_exit="$socks"
        fi
        hostpart=$(build_endpoint_hostpart "portal" "*" "$RESOLVED_TCP" "$RESOLVED_UDP")
        url="portal://${key}@${hostpart}?tls=${tls}"
        if [[ "$tls" == "2" ]]; then
            url="${url}&crt=${crt}&key=${keyfile}"
        fi
        if [[ "$out_exit" == "egress" ]]; then
            url="${url}&out=egress"
        elif [[ "$out_exit" != "direct" ]]; then
            url="${url}&out=$(encode_socks_endpoint "$out_exit")"
        else
            url="${url}&out=direct"
        fi
        # nw3 defaults morph to 1; state it explicitly so peers cannot disagree.
        url="${url}&morph=${morph:-1}"
        echo "$url"
        return
    fi

    if is_v2_profile; then
        if ! resolve_carrier_ports "$net" "$port" "$tcp_port" "$udp_port"; then
            return 1
        fi
        hostpart=$(build_endpoint_hostpart "portal" "*" "$RESOLVED_TCP" "$RESOLVED_UDP")
        url="portal://${key}@${hostpart}?tls=${tls}"
        url=$(append_morph_query "$url" "$morph")
    else
        url="portal://${key}@:${port}?tls=${tls}&net=${net}"
        if [[ -n "$alpn" && "$alpn" != "$DEFAULT_ALPN" ]]; then
            url="${url}&alpn=$(url_encode_alpn "$alpn")"
        fi
    fi

    if [[ "$tls" == "2" ]]; then
        url="${url}&crt=${crt}&key=${keyfile}"
    fi
    if [[ -n "$socks" && "$socks" != "none" ]]; then
        url="${url}&socks=$(encode_socks_endpoint "$socks")"
    fi
    if [[ -n "$next" && "$next" != "none" ]]; then
        up="${up:-$dc}"
        down="${down:-$dc}"
        if ! validate_carrier "$up" || ! validate_carrier "$down"; then
            return 1
        fi
        if is_v2_profile; then
            if ! validate_policy_on_endpoint "$up" "$down" "$RESOLVED_TCP" "$RESOLVED_UDP"; then
                return 1
            fi
        fi
        url="${url}&next=$(encode_next_endpoint "$next")"
        url="${url}&up=${up}&down=${down}"
        url=$(append_mux_query "$url" "$up" "$down" "$mux")
        if [[ -n "$sni" && "$sni" != "none" ]]; then
            url="${url}&sni=${sni}"
        fi
        if [[ -n "$pin" && "$pin" != "none" ]]; then
            url="${url}&pin=${pin}"
        fi
    fi
    echo "$url"
}

build_vector_url() {
    local key="$1"
    local host="$2"
    local port="$3"
    local up="$4"
    local down="$5"
    local socks="$6"
    local alpn="${7:-}"
    local mux="${8:-}"
    local sni="${9:-}"
    local pin="${10:-}"
    local morph="${11:-}"
    local tcp_port="${12:-}"
    local udp_port="${13:-}"
    local net="${14:-mix}"

    local dc hostpart url
    dc=$(default_carrier)
    up="${up:-$dc}"
    down="${down:-$dc}"
    if ! validate_carrier "$up" || ! validate_carrier "$down"; then
        return 1
    fi
    if [[ -z "$host" || "$host" == "*" ]]; then
        if [[ "$host" == "*" ]]; then
            log_error "$(t err_vector_star_host)"
        else
            log_error "$(t err_portal_host_required)"
        fi
        return 1
    fi
    if ! validate_morph_value "$morph"; then
        return 1
    fi

    if is_nw3_profile; then
        # nw3 Vector: one carrier, local SOCKS5 listener via in=, no up/down/mux.
        if ! valid_key_for_profile "$key" "vector"; then
            log_error "$(t err_invalid_key)"
            return 1
        fi
        if [[ -z "$socks" || "$socks" == "none" ]]; then
            log_error "$(t err_socks_required)"
            return 1
        fi
        local carrier="$net"
        if [[ "$carrier" != "tcp" && "$carrier" != "udp" ]]; then
            # Compatibility shim: fold the v2-style up/down pair onto one carrier.
            if [[ "$up" == "$down" ]]; then
                carrier="$up"
                [[ "$carrier" == "mix" ]] && carrier="tcp"
            else
                carrier="tcp"
                log_warn "$(t warn_vector_carrier_fallback)"
            fi
        fi
        local carrier_port=""
        if [[ "$carrier" == "tcp" ]]; then
            carrier_port="${tcp_port:-$port}"
        else
            carrier_port="${udp_port:-$port}"
        fi
        if [[ -z "$carrier_port" ]] || ! validate_port_value "$carrier_port"; then
            return 1
        fi
        if [[ "$carrier" == "tcp" ]]; then
            hostpart=$(build_endpoint_hostpart "vector" "$host" "$carrier_port" "")
        else
            hostpart=$(build_endpoint_hostpart "vector" "$host" "" "$carrier_port")
        fi
        url="vector://${key}@${hostpart}?in=$(encode_socks_endpoint "$socks")"
        if [[ -n "$sni" && "$sni" != "none" ]]; then
            url="${url}&sni=${sni}"
        fi
        if [[ -n "$pin" && "$pin" != "none" ]]; then
            url="${url}&pin=${pin}"
        fi
        url="${url}&morph=${morph:-1}"
        echo "$url"
        return
    fi

    if is_v2_profile; then
        if ! resolve_carrier_ports "$net" "$port" "$tcp_port" "$udp_port"; then
            return 1
        fi
        if ! validate_policy_on_endpoint "$up" "$down" "$RESOLVED_TCP" "$RESOLVED_UDP"; then
            return 1
        fi
        hostpart=$(build_endpoint_hostpart "vector" "$host" "$RESOLVED_TCP" "$RESOLVED_UDP")
        url="vector://${key}@${hostpart}?up=${up}&down=${down}&socks=$(encode_socks_endpoint "$socks")"
        url=$(append_mux_query "$url" "$up" "$down" "$mux")
        url=$(append_morph_query "$url" "$morph")
    else
        url="vector://${key}@${host}:${port}?up=${up}&down=${down}&socks=$(encode_socks_endpoint "$socks")"
        url=$(append_mux_query "$url" "$up" "$down" "$mux")
        if [[ -n "$alpn" && "$alpn" != "$DEFAULT_ALPN" ]]; then
            url="${url}&alpn=$(url_encode_alpn "$alpn")"
        fi
    fi
    if [[ -n "$sni" && "$sni" != "none" ]]; then
        url="${url}&sni=${sni}"
    fi
    if [[ -n "$pin" && "$pin" != "none" ]]; then
        url="${url}&pin=${pin}"
    fi
    echo "$url"
}

# nw3 Egress: egress://KEY@HOST/udp:PORT?morph=N[&sni&pin]. Egress dials out to a
# Portal configured with out=egress and needs no inbound firewall port.
build_egress_url() {
    local key="$1"
    local host="$2"
    local udp_port="$3"
    local sni="${4:-}"
    local pin="${5:-}"
    local morph="${6:-}"

    if ! valid_key_for_profile "$key" "egress"; then
        log_error "$(t err_invalid_key)"
        return 1
    fi
    if [[ -z "$host" || "$host" == "*" ]]; then
        log_error "$(t err_portal_host_required)"
        return 1
    fi
    if [[ -z "$udp_port" ]] || ! validate_port_value "$udp_port"; then
        return 1
    fi
    if ! validate_morph_value "$morph"; then
        return 1
    fi

    local hostpart url
    hostpart=$(build_endpoint_hostpart "egress" "$host" "" "$udp_port") || return 1
    # morph is always stated (nw3 defaults to 1) and leads the query, mirroring
    # the upstream egress:// form; sni/pin follow.
    url="egress://${key}@${hostpart}?morph=${morph:-1}"
    if [[ -n "$sni" && "$sni" != "none" ]]; then
        url="${url}&sni=${sni}"
    fi
    if [[ -n "$pin" && "$pin" != "none" ]]; then
        url="${url}&pin=${pin}"
    fi
    echo "$url"
}

# Populates CONVERTED_URL and CONVERTED_FRAGMENT (fragment may be empty).
CONVERTED_URL=""
CONVERTED_FRAGMENT=""
convert_nowhere_to_vector() {
    local url="$1"
    local socks="${2:-$DEFAULT_SOCKS_IN}"
    CONVERTED_URL=""
    CONVERTED_FRAGMENT=""

    if [[ "$url" == *#* ]]; then
        CONVERTED_FRAGMENT="${url#*#}"
        CONVERTED_FRAGMENT=$(url_decode_simple "$CONVERTED_FRAGMENT")
        url="${url%%#*}"
    fi

    case "$url" in
        nowhere://*)
            url="vector://${url#nowhere://}"
            ;;
        vector://*)
            ;;
        *)
            CONVERTED_URL="$url"
            return 1
            ;;
    esac

    local existing_socks
    existing_socks=$(get_query_param "$url" "socks")
    if [[ -z "$existing_socks" ]]; then
        url=$(append_query_param "$url" "socks=$(encode_socks_endpoint "$socks")")
    elif [[ -n "$2" ]]; then
        url=$(strip_query_param "$url" "socks")
        url=$(append_query_param "$url" "socks=$(encode_socks_endpoint "$socks")")
    fi

    CONVERTED_URL="$url"
    echo "$url"
}

migrate_portal_url_for_v15() {
    if [[ ! -f "$URL_FILE" ]]; then
        return 0
    fi

    local url migrated=false
    url=$(tr -d '\n' < "$URL_FILE")
    [[ -z "$url" ]] && return 0

    if echo "$url" | grep -qE '[?&]spec='; then
        url=$(strip_query_param "$url" "spec")
        migrated=true
    fi

    if [[ "$migrated" == "true" ]]; then
        echo "$url" > "$URL_FILE"
        log_warn "$(t warn_migrated_spec "$URL_FILE")"
    fi
}

migrate_portal_url_for_v18() {
    if [[ ! -f "$URL_FILE" ]]; then
        return 0
    fi

    local url migrated=false
    url=$(tr -d '\n' < "$URL_FILE")
    [[ -z "$url" ]] && return 0

    if echo "$url" | grep -qE '[?&]pool='; then
        local up down
        up=$(get_query_param "$url" "up")
        down=$(get_query_param "$url" "down")
        url=$(strip_query_param "$url" "pool")
        if [[ "$up" == "tcp" && "$down" == "tcp" ]] && ! echo "$url" | grep -qE '[?&]mux='; then
            url=$(append_query_param "$url" "mux=1")
        fi
        migrated=true
    fi

    if [[ "$migrated" == "true" ]]; then
        echo "$url" > "$URL_FILE"
        log_warn "$(t warn_migrated_pool "$URL_FILE")"
    fi
}

migrate_stored_url() {
    migrate_portal_url_for_v15
    migrate_portal_url_for_v18
    if [[ ! -f "$URL_FILE" ]]; then
        return 0
    fi

    local url
    url=$(tr -d '\n' < "$URL_FILE")
    [[ -z "$url" ]] && return 0

    if [[ "$url" == nowhere://* ]]; then
        local converted socks="${ARG_SOCKS:-$DEFAULT_SOCKS_IN}"
        convert_nowhere_to_vector "$url" "$socks" >/dev/null
        converted="$CONVERTED_URL"
        echo "$converted" > "$URL_FILE"
        if [[ -n "$CONVERTED_FRAGMENT" && ! -f "$NAME_FILE" ]]; then
            save_node_name "$CONVERTED_FRAGMENT"
        fi
        log_warn "$(t warn_migrated_nowhere "$URL_FILE")"
        url="$converted"
    fi

    if is_nw3_profile; then
        # 1.x URLs are first normalized onto v2 syntax (net= -> carrier path),
        # then rewritten onto the nw3 line. nw2.2 key rules do not apply.
        migrate_url_to_v2
        migrate_url_to_nw3
        return
    fi

    if is_v2_profile; then
        migrate_url_to_v2
    else
        migrate_url_to_v1
    fi

    migrate_portal_url_for_v22
}

# Nowhere 2.2+ refuses to start a Portal whose shared key (or next= upstream
# key) is not 32-64 lowercase hexadecimal characters. A non-conforming Portal
# key is regenerated automatically (the old key cannot be used anyway); next=
# belongs to the upstream Portal and is only reported.
migrate_portal_url_for_v22() {
    [[ -f "$URL_FILE" ]] || return 0
    is_v22_profile || return 0

    local url migrated=false newkey next next_key
    url=$(tr -d '\n' < "$URL_FILE")
    [[ -z "$url" ]] && return 0
    [[ "$(detect_url_role "$url")" == "portal" ]] || return 0

    parse_url_authority "$url"
    if [[ -n "$PARSE_KEY" ]] && ! valid_v22_key "$PARSE_KEY"; then
        newkey=$(generate_random_key)
        url=$(rewrite_url_key "$url" "$newkey")
        migrated=true
    fi

    next=$(get_query_param "$url" "next")
    if [[ -n "$next" ]]; then
        next_key=$(url_decode_simple "$next")
        next_key="${next_key%@*}"
        if ! valid_v22_key "$next_key"; then
            log_warn "$(t warn_next_key_invalid "$URL_FILE")"
        fi
    fi

    if [[ "$migrated" == "true" ]]; then
        echo "$url" > "$URL_FILE"
        log_warn "$(t warn_key_regenerated "$URL_FILE")"
    fi
}

# Read-only check run before any cross-line (nw2 <-> nw3) switch. Returns 1
# and logs the reason when the stored configuration cannot be carried over, so
# the caller can abort with the current binary and config untouched.
preflight_profile_switch() {
    local from_major="$1" to_major="$2"
    [[ "$from_major" == "$to_major" ]] && return 0
    [[ -f "$URL_FILE" ]] || return 0

    local url role
    url=$(tr -d '\n' < "$URL_FILE")
    [[ -z "$url" ]] && return 0
    role=$(detect_url_role "$url")

    if [[ "$to_major" == "3" ]]; then
        # nw3 removed next= chaining; Portal exits via out= instead.
        local next_val
        next_val=$(get_query_param "$url" "next")
        if [[ -n "$next_val" && "$next_val" != "none" ]]; then
            log_error "$(t err_preflight_next)"
            return 1
        fi
        return 0
    fi

    # Downgrade: the Egress role and out=egress have no nw2 representation.
    if [[ "$role" == "egress" ]]; then
        log_error "$(t err_preflight_egress)"
        return 1
    fi
    if [[ "$(get_query_param "$url" "out")" == "egress" ]]; then
        log_error "$(t err_preflight_egress)"
        return 1
    fi
    return 0
}

# nw2/nw1 Portal -> nw3 Portal. socks= becomes out= (direct when absent), morph
# is stated explicitly (nw3 defaults to 1 while nw2 defaulted to 0), up/down/
# mux/sni/pin/alpn/net/log are dropped, and a non-conforming key is regenerated
# because nw3 demands exactly 32 lowercase hex. rate/etar/dial* survive as-is.
# Idempotent: a URL already carrying out= is left untouched.
migrate_portal_url_to_nw3() {
    [[ -f "$URL_FILE" ]] || return 0
    local url
    url=$(tr -d '\n' < "$URL_FILE")
    [[ -z "$url" ]] && return 0
    [[ "$(detect_url_role "$url")" == "portal" ]] || return 0
    [[ -n "$(get_query_param "$url" "out")" ]] && return 0

    parse_url_authority "$url"

    local socks_raw out_exit="direct"
    socks_raw=$(get_query_param "$url" "socks")
    [[ -n "$socks_raw" ]] && out_exit="$socks_raw"

    local tcp_port udp_port
    if url_has_carrier_path "$url"; then
        tcp_port="$PARSE_TCP_PORT"
        udp_port="$PARSE_UDP_PORT"
    else
        tcp_port="$PARSE_PORT"
        udp_port="$PARSE_PORT"
    fi
    local hostpart
    hostpart=$(build_endpoint_hostpart "portal" "*" "$tcp_port" "$udp_port") || return 1

    local tls crt keyfile
    tls=$(get_query_param "$url" "tls")
    [[ "$tls" == "1" || "$tls" == "2" ]] || tls="1"
    crt=$(get_query_param "$url" "crt")
    keyfile=$(get_query_param "$url" "key")

    local morph
    morph=$(get_query_param "$url" "morph")
    [[ "$morph" == "1" ]] || morph="0"

    # Keep parameters nw3 also understands but this migration does not manage.
    local leftover="$url" p
    for p in tls crt key net alpn socks next up down mux sni pin morph out in; do
        leftover=$(strip_query_param "$leftover" "$p")
    done
    if [[ "$leftover" == *\?* ]]; then
        leftover="${leftover#*\?}"
    else
        leftover=""
    fi

    local newurl="portal://${PARSE_KEY}@${hostpart}?tls=${tls}"
    if [[ "$tls" == "2" && -n "$crt" ]]; then
        newurl="${newurl}&crt=${crt}&key=${keyfile}"
    fi
    if [[ "$out_exit" == "direct" ]]; then
        newurl="${newurl}&out=direct"
    else
        newurl="${newurl}&out=${out_exit}"
    fi
    newurl="${newurl}&morph=${morph}"
    [[ -n "$leftover" ]] && newurl="${newurl}&${leftover}"

    local newkey=""
    if [[ -n "$PARSE_KEY" ]] && ! valid_key_for_profile "$PARSE_KEY" "portal"; then
        newkey=$(generate_random_key)
        newurl=$(rewrite_url_key "$newurl" "$newkey")
    fi

    echo "$newurl" > "$URL_FILE"
    log_warn "$(t warn_migrated_nw3 "$URL_FILE")"
    if [[ -n "$newkey" ]]; then
        log_warn "$(t warn_key_regenerated "$URL_FILE")"
    fi
}

# nw2/nw1 Vector -> nw3 Vector. socks= becomes in=, the up/down pair converges
# onto one carrier (mix and mismatched directions fold to tcp with a warning),
# up/down/mux/alpn/net are dropped and sni/pin/morph/rate/etar are preserved.
# The key belongs to the peer Portal, so a non-conforming key is only reported.
# Idempotent: a URL already carrying in= is left untouched.
migrate_vector_url_to_nw3() {
    [[ -f "$URL_FILE" ]] || return 0
    local url
    url=$(tr -d '\n' < "$URL_FILE")
    [[ -z "$url" ]] && return 0
    [[ "$(detect_url_role "$url")" == "vector" ]] || return 0
    [[ -n "$(get_query_param "$url" "in")" ]] && return 0

    parse_url_authority "$url"

    local dc
    dc=$(default_carrier)
    local socks_raw up down carrier carrier_port
    socks_raw=$(get_query_param "$url" "socks")
    [[ -z "$socks_raw" ]] && socks_raw="$DEFAULT_SOCKS_IN"
    up=$(get_query_param "$url" "up"); up="${up:-$dc}"
    down=$(get_query_param "$url" "down"); down="${down:-$dc}"
    if [[ "$up" == "$down" ]]; then
        carrier="$up"
        [[ "$carrier" == "mix" ]] && carrier="tcp"
    else
        carrier="tcp"
        log_warn "$(t warn_vector_carrier_fallback)"
    fi
    if url_has_carrier_path "$url"; then
        if [[ "$carrier" == "tcp" ]]; then
            carrier_port="${PARSE_TCP_PORT:-$PARSE_PORT}"
        else
            carrier_port="${PARSE_UDP_PORT:-$PARSE_PORT}"
        fi
    else
        carrier_port="$PARSE_PORT"
    fi
    if [[ -z "$PARSE_HOST" ]]; then
        log_error "$(t err_portal_host_required)"
        return 1
    fi
    if [[ -z "$carrier_port" ]] || ! validate_port_value "$carrier_port"; then
        return 1
    fi

    local morph sni pin
    morph=$(get_query_param "$url" "morph")
    [[ "$morph" == "1" ]] || morph="0"
    sni=$(get_query_param "$url" "sni")
    pin=$(get_query_param "$url" "pin")

    local leftover="$url" p
    for p in socks next up down mux alpn net morph in out tls crt key sni pin; do
        leftover=$(strip_query_param "$leftover" "$p")
    done
    if [[ "$leftover" == *\?* ]]; then
        leftover="${leftover#*\?}"
    else
        leftover=""
    fi

    local newurl="vector://${PARSE_KEY}@${PARSE_HOST}/${carrier}:${carrier_port}?in=${socks_raw}"
    if [[ -n "$sni" && "$sni" != "none" ]]; then
        newurl="${newurl}&sni=${sni}"
    fi
    if [[ -n "$pin" && "$pin" != "none" ]]; then
        newurl="${newurl}&pin=${pin}"
    fi
    newurl="${newurl}&morph=${morph}"
    [[ -n "$leftover" ]] && newurl="${newurl}&${leftover}"

    if [[ -n "$PARSE_KEY" ]] && ! valid_key_for_profile "$PARSE_KEY" "vector"; then
        log_warn "$(t warn_vector_key_peer)"
    fi

    echo "$newurl" > "$URL_FILE"
    log_warn "$(t warn_migrated_nw3 "$URL_FILE")"
}

# Dispatches the stored URL onto the nw3 line. next= chaining cannot be
# migrated (preflight blocks the switch before this runs); on that input the
# URL is left untouched and 1 is returned so callers can fail-stop.
migrate_url_to_nw3() {
    [[ -f "$URL_FILE" ]] || return 0
    is_nw3_profile || return 0

    local url role
    url=$(tr -d '\n' < "$URL_FILE")
    [[ -z "$url" ]] && return 0
    role=$(detect_url_role "$url")
    [[ "$role" == "egress" ]] && return 0

    local next_val
    next_val=$(get_query_param "$url" "next")
    if [[ -n "$next_val" && "$next_val" != "none" ]]; then
        log_error "$(t err_preflight_next)"
        return 1
    fi

    if [[ "$role" == "portal" ]]; then
        migrate_portal_url_to_nw3
    else
        migrate_vector_url_to_nw3
    fi
}

# nw3 -> nw2 downgrade migration. out= becomes socks= (direct is dropped, the
# nw2 default), in= becomes socks=, a single carrier expands to up=down=carrier
# and morph=1 is kept while morph=0 is dropped. Egress configurations have no
# nw2 representation and abort (preflight blocks them earlier). Idempotent: a
# URL without out=/in= is left untouched.
migrate_url_to_nw2() {
    [[ -f "$URL_FILE" ]] || return 0
    local url role
    url=$(tr -d '\n' < "$URL_FILE")
    [[ -z "$url" ]] && return 0
    role=$(detect_url_role "$url")

    if [[ "$role" == "egress" ]]; then
        log_error "$(t err_preflight_egress)"
        return 1
    fi

    local out_val in_val
    out_val=$(get_query_param "$url" "out")
    in_val=$(get_query_param "$url" "in")
    if [[ -z "$out_val" && -z "$in_val" ]]; then
        return 0
    fi
    if [[ "$out_val" == "egress" ]]; then
        log_error "$(t err_preflight_egress)"
        return 1
    fi

    parse_url_authority "$url"
    local ep
    ep="${url%%\?*}"
    ep="${ep%%#*}"
    ep="${ep#*@}"

    local morph tls crt keyfile
    morph=$(get_query_param "$url" "morph")
    tls=$(get_query_param "$url" "tls"); tls="${tls:-1}"
    crt=$(get_query_param "$url" "crt")
    keyfile=$(get_query_param "$url" "key")

    local leftover="$url" p
    for p in out in morph tls crt key socks next up down mux sni pin net alpn; do
        leftover=$(strip_query_param "$leftover" "$p")
    done
    if [[ "$leftover" == *\?* ]]; then
        leftover="${leftover#*\?}"
    else
        leftover=""
    fi

    local newurl
    if [[ "$role" == "portal" ]]; then
        newurl="portal://${PARSE_KEY}@${ep}?tls=${tls}"
        if [[ "$tls" == "2" && -n "$crt" ]]; then
            newurl="${newurl}&crt=${crt}&key=${keyfile}"
        fi
        if [[ -n "$out_val" && "$out_val" != "direct" ]]; then
            newurl="${newurl}&socks=${out_val}"
        fi
        [[ "$morph" == "1" ]] && newurl="${newurl}&morph=1"
    else
        # Single nw3 carrier expands to the nw2 up/down pair.
        local carrier up_down
        if [[ "$ep" == */udp:* ]]; then
            carrier="udp"
        else
            carrier="tcp"
        fi
        up_down="${carrier}"
        newurl="vector://${PARSE_KEY}@${ep}?up=${up_down}&down=${up_down}"
        if [[ -n "$in_val" ]]; then
            newurl="${newurl}&socks=${in_val}"
        fi
        [[ "$morph" == "1" ]] && newurl="${newurl}&morph=1"
    fi
    [[ -n "$leftover" ]] && newurl="${newurl}&${leftover}"

    echo "$newurl" > "$URL_FILE"
    log_warn "$(t warn_migrated_nw2 "$URL_FILE")"
}

migrate_url_to_v2() {
    [[ -f "$URL_FILE" ]] || return 0
    local url migrated=false net hostpart
    url=$(tr -d '\n' < "$URL_FILE")
    [[ -z "$url" ]] && return 0

    parse_url_authority "$url"
    if echo "$url" | grep -qE '[?&]alpn='; then
        url=$(strip_query_param "$url" "alpn")
        migrated=true
    fi
    net=$(get_query_param "$url" "net")
    if [[ "$(detect_url_role "$url")" == "portal" ]]; then
        if [[ -n "$net" ]] && ! url_has_carrier_path "$url"; then
            case "$net" in
                tcp) hostpart=$(build_endpoint_hostpart "portal" "*" "$PARSE_PORT" "") ;;
                udp) hostpart=$(build_endpoint_hostpart "portal" "*" "" "$PARSE_PORT") ;;
                *) hostpart=$(build_endpoint_hostpart "portal" "*" "$PARSE_PORT" "$PARSE_PORT") ;;
            esac
            url=$(rewrite_url_endpoint "$url" "$hostpart")
            migrated=true
        fi
        if [[ -n "$net" ]]; then
            url=$(strip_query_param "$url" "net")
            migrated=true
        fi
    elif [[ -n "$net" ]]; then
        url=$(strip_query_param "$url" "net")
        migrated=true
    fi

    if [[ "$migrated" == "true" ]]; then
        echo "$url" > "$URL_FILE"
        log_warn "$(t warn_migrated_v20 "$URL_FILE")"
    fi
}

migrate_url_to_v1() {
    [[ -f "$URL_FILE" ]] || return 0
    local url migrated=false net hostpart port
    url=$(tr -d '\n' < "$URL_FILE")
    [[ -z "$url" ]] && return 0

    parse_url_authority "$url"
    if echo "$url" | grep -qE '[?&]morph='; then
        url=$(strip_query_param "$url" "morph")
        migrated=true
    fi
    if echo "$url" | grep -qE '[?&]alpn='; then
        url=$(strip_query_param "$url" "alpn")
        migrated=true
    fi

    if [[ "$(detect_url_role "$url")" == "portal" ]]; then
        net=$(get_query_param "$url" "net")
        if url_has_carrier_path "$url"; then
            if [[ -n "$PARSE_TCP_PORT" && -n "$PARSE_UDP_PORT" && "$PARSE_TCP_PORT" != "$PARSE_UDP_PORT" ]]; then
                log_warn "$(t warn_split_ports_v1)"
                port="$PARSE_TCP_PORT"
                net="mix"
            elif [[ -n "$PARSE_TCP_PORT" && -n "$PARSE_UDP_PORT" ]]; then
                port="$PARSE_TCP_PORT"
                net="mix"
            elif [[ -n "$PARSE_TCP_PORT" ]]; then
                port="$PARSE_TCP_PORT"
                net="tcp"
            else
                port="$PARSE_UDP_PORT"
                net="udp"
            fi
            hostpart=":${port}"
            url=$(rewrite_url_endpoint "$url" "$hostpart")
            migrated=true
        else
            port="${PARSE_PORT:-2077}"
            net="${net:-mix}"
        fi
        if [[ -z "$(get_query_param "$url" "net")" ]]; then
            url=$(append_query_param "$url" "net=${net:-mix}")
            migrated=true
        fi
    elif [[ "$(detect_url_role "$url")" == "vector" ]] && url_has_carrier_path "$url"; then
        if [[ -n "$PARSE_TCP_PORT" && -n "$PARSE_UDP_PORT" && "$PARSE_TCP_PORT" != "$PARSE_UDP_PORT" ]]; then
            log_warn "$(t warn_split_ports_v1)"
            port="$PARSE_TCP_PORT"
        else
            port="${PARSE_TCP_PORT:-$PARSE_UDP_PORT}"
        fi
        hostpart="$(format_url_host "$PARSE_HOST"):${port}"
        url=$(rewrite_url_endpoint "$url" "$hostpart")
        migrated=true
    fi

    if [[ "$migrated" == "true" ]]; then
        echo "$url" > "$URL_FILE"
        log_warn "$(t warn_migrated_v1 "$URL_FILE")"
    fi
}

qr_support_available() {
    if command -v qrencode &>/dev/null; then
        echo "qrencode"
        return 0
    fi
    if command -v python3 &>/dev/null && python3 -c "import qrcode" 2>/dev/null; then
        echo "python3-qrcode"
        return 0
    fi
    return 1
}

# Best-effort SHA-256 fingerprint (64 lowercase hex) of the running Portal's
# TLS certificate. $1 is a local nowhere:// probe URL with a TCP carrier.
# Sources: service log (journal or file), otherwise a local fingerprint probe.
get_portal_fingerprint() {
    local probe_url="$1"
    local fp=""

    if [[ "$INIT_SYSTEM" == "systemd" ]] && command -v journalctl &>/dev/null; then
        fp=$(journalctl -u ${SERVICE_NAME} --no-pager -n 500 2>/dev/null \
            | grep -oE 'fingerprint: [0-9a-f]{64}' | tail -n1 | grep -oE '[0-9a-f]{64}' || true)
    elif [[ -f "$PORTAL_LOG" ]]; then
        fp=$(grep -oE 'fingerprint: [0-9a-f]{64}' "$PORTAL_LOG" 2>/dev/null \
            | tail -n1 | grep -oE '[0-9a-f]{64}' || true)
    fi

    if [[ -z "$fp" ]] && command -v nowhere &>/dev/null && service_is_active; then
        fp=$(run_with_timeout 10 nowhere fingerprint "$probe_url" 2>/dev/null \
            | head -n1 | grep -oE '^[0-9a-f]{64}$' || true)
    fi

    printf '%s' "$fp"
}

# Builds a local nowhere:// probe URL for fingerprinting.
# Sets FINGERPRINT_PROBE_URL; fails when no TCP carrier or host is available.
build_fingerprint_probe_url() {
    local key="$1" host="$2" port="$3" net="$4" tcp_port="$5" udp_port="$6" sni="$7" morph="$8"
    FINGERPRINT_PROBE_URL=""
    [[ -z "$host" || "$host" == "*" ]] && return 1
    validate_net_value "$net" >/dev/null 2>&1 || return 1
    if ! resolve_carrier_ports "$net" "$port" "$tcp_port" "$udp_port" >/dev/null 2>&1; then
        return 1
    fi
    [[ -z "$RESOLVED_TCP" ]] && return 1
    local url
    if is_nw3_profile; then
        # nw3 fingerprints over the compact host:port form with an explicit net=.
        url="nowhere://${key}@${host}:${RESOLVED_TCP}?net=tcp"
    else
        url="nowhere://${key}@${host}/tcp:${RESOLVED_TCP}"
    fi
    [[ -n "$sni" && "$sni" != "none" ]] && url=$(append_query_param "$url" "sni=${sni}")
    [[ "$morph" == "1" ]] && url=$(append_query_param "$url" "morph=1")
    FINGERPRINT_PROBE_URL="$url"
    return 0
}

# Fetches the Portal certificate fingerprint with the nowhere binary.
# Sets FETCHED_PIN (empty on failure); silent about the reason.
fetch_pin_via_binary() {
    local key="$1" host="$2" port="$3" net="$4" tcp_port="$5" udp_port="$6" sni="$7" morph="$8"
    FETCHED_PIN=""
    command -v nowhere &>/dev/null || return 1
    build_fingerprint_probe_url "$key" "$host" "$port" "$net" "$tcp_port" "$udp_port" "$sni" "$morph" || return 1
    FETCHED_PIN=$(run_with_timeout 10 nowhere fingerprint "$FINGERPRINT_PROBE_URL" 2>/dev/null \
        | head -n1 | grep -oE '^[0-9a-f]{64}$' || true)
    [[ -n "$FETCHED_PIN" ]]
}

# ==================== Version lookup ====================
get_latest_version() {
    local response
    response=$(curl -fsSL --connect-timeout 15 "$GITHUB_API" 2>/dev/null)
    if [[ -z "$response" ]]; then
        log_error "$(t err_github)"
        exit 1
    fi

    local version
    version=$(echo "$response" | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -n1)
    if [[ -z "$version" ]]; then
        log_error "$(t err_github_parse)"
        exit 1
    fi

    echo "$version"
}

# Resolves the upgrade target without --version. An installed nw2/1.x node
# stays on its own line (newest v2.* from the recent releases, falling back to
# the v2.2.1 LTS baseline); an nw3 node or a fresh install follows the latest
# stable release. Prints the target version, or an empty line for "latest".
# --allow-protocol-breaking-upgrade without --version jumps to latest (nw3).
NW2_LTS_VERSION="v2.2.1"
resolve_upgrade_target() {
    if [[ -n "$ARG_VERSION" ]]; then
        echo "$ARG_VERSION"
        return 0
    fi
    if [[ -n "$TARGET_VERSION" ]]; then
        echo "$TARGET_VERSION"
        return 0
    fi
    if [[ -n "$ARG_ALLOW_BREAKING" ]]; then
        echo ""
        return 0
    fi

    local inst major v latest2=""
    inst=$(get_installed_version)
    if [[ -n "$inst" ]]; then
        major=$(version_major "$inst")
        if [[ "$major" == "1" || "$major" == "2" ]]; then
            while IFS= read -r v; do
                [[ "$v" == v2.* ]] && { latest2="$v"; break; }
            done < <(list_github_versions)
            echo "${latest2:-$NW2_LTS_VERSION}"
            return 0
        fi
    fi
    echo ""
}

get_asset_name() {
    if [[ "$OS_ID" == "freebsd" ]]; then
        echo "nowhere-${ARCH}-unknown-freebsd.tar.gz"
    else
        echo "nowhere-${ARCH}-unknown-linux-${LIBC}.tar.gz"
    fi
}

get_download_url() {
    local version="$1"
    echo "https://github.com/${GITHUB_REPO}/releases/download/${version}/$(get_asset_name)"
}

get_installed_version() {
    if command -v nowhere &>/dev/null; then
        local version
        version=$(nowhere --version 2>/dev/null | head -n1 | grep -oE 'v?[0-9]+\.[0-9]+\.[0-9]+' || true)
        echo "${version#v}"
    fi
}

# ==================== Install core ====================
install_nowhere() {
    local version="$1"
    local is_upgrade="${2:-false}"

    if [[ -z "$version" ]]; then
        if [[ -n "$ARG_VERSION" ]]; then
            version="$ARG_VERSION"
        else
            log_info "$(t info_query_version)"
            version=$(get_latest_version)
        fi
    fi
    TARGET_VERSION="$version"

    if [[ "$OS_ID" == "freebsd" ]] && [[ "$(version_major "$version")" -lt 2 ]]; then
        log_error "$(t err_freebsd_v1 "$version")"
        exit 1
    fi

    local tmp_dir binary probe_err
    tmp_dir=$(mktemp -d)

    if ! extract_nowhere_to "$version" "$tmp_dir"; then
        rm -rf "$tmp_dir"
        exit 1
    fi
    binary="$FETCHED_BINARY"

    if ! binary_runs "$binary"; then
        probe_err=$(binary_probe_error "$binary")
        if [[ "$LIBC" == "gnu" ]]; then
            log_warn "$(t warn_gnu_unusable "${probe_err:-unknown}")"
            LIBC="musl"
            rm -rf "$tmp_dir"
            tmp_dir=$(mktemp -d)
            if ! extract_nowhere_to "$version" "$tmp_dir"; then
                rm -rf "$tmp_dir"
                exit 1
            fi
            binary="$FETCHED_BINARY"
        fi
        if ! binary_runs "$binary"; then
            log_error "$(t err_binary_unusable "$(binary_probe_error "$binary")")"
            rm -rf "$tmp_dir"
            exit 1
        fi
    fi

    log_info "$(t info_install_to "$INSTALL_DIR")"

    chmod +x "$binary"
    mv -f "$binary" "${INSTALL_DIR}/nowhere"
    rm -rf "$tmp_dir"

    mkdir -p "$CONFIG_DIR"
    migrate_portal_url_for_v15

    if [[ "$is_upgrade" == "true" ]]; then
        if [[ "$(version_major "$version")" -lt 2 ]]; then
            log_warn "$(t warn_v15_incompat)"
        fi
        log_success "$(t ok_upgraded "$version")"
    else
        log_success "$(t ok_installed "$version")"
        if [[ "$(version_major "$version")" -ge 3 ]]; then
            log_warn "$(t warn_nw3_protocol)"
        fi
    fi
}

uninstall_nowhere() {
    if [[ "$AUTO_MODE" != "uninstall" ]]; then
        log_warn "$(t warn_uninstall)"
        read -rp "$(t prompt_uninstall)" confirm
        [[ "$confirm" =~ ^[Yy]$ ]] || { log_info "$(t info_cancelled)"; return; }
    fi

    stop_service
    disable_service
    remove_acme_auto_renew

    rm -f "${INSTALL_DIR}/nowhere"
    rm -f "$LAUNCHER"

    if [[ "$INIT_SYSTEM" == "systemd" ]]; then
        rm -f "$SYSTEMD_UNIT_FILE"
        if [[ "$SYSTEMD_UNIT_FILE" == "/etc/systemd/system/${SERVICE_NAME}.service" ]]; then
            systemctl daemon-reload 2>/dev/null || true
        fi
    elif [[ "$INIT_SYSTEM" == "openrc" ]]; then
        rm -f "/etc/init.d/${SERVICE_NAME}"
        rc-update delete ${SERVICE_NAME} default 2>/dev/null || true
    elif [[ "$INIT_SYSTEM" == "rc" ]]; then
        rm -f "$RC_SCRIPT"
        sysrc -x nowhere_enable >/dev/null 2>&1 || true
    fi

    if [[ "$AUTO_MODE" != "uninstall" ]]; then
        read -rp "$(t prompt_del_config "$CONFIG_DIR")" del_config
        [[ "$del_config" =~ ^[Yy]$ ]] && rm -rf "$CONFIG_DIR"
    else
        rm -rf "$CONFIG_DIR"
    fi

    log_success "$(t ok_uninstalled)"
}

# ==================== Service setup ====================
# The launcher resolves the installed binary's protocol generation at start
# time (a later upgrade may replace the binary), converts legacy nowhere://
# share URLs accordingly, and refuses to start when url.conf still carries
# Nowhere 2.x-only parameters that Nowhere 3 would silently ignore.
write_launcher() {
    migrate_stored_url
    cat > "$LAUNCHER" <<'EOF'
#!/usr/bin/env bash
URL_FILE="/etc/nowhere/url.conf"
[[ -f "$URL_FILE" ]] || { echo "error: missing ${URL_FILE}" >&2; exit 1; }
NOWHERE_URL=$(tr -d '\n' < "$URL_FILE")
[[ -n "$NOWHERE_URL" ]] || { echo "error: ${URL_FILE} is empty" >&2; exit 1; }
NOWHERE_BIN="/usr/local/bin/nowhere"
MAJOR=$("$NOWHERE_BIN" --version 2>/dev/null | grep -oE '[0-9]+' | head -n1)
if [[ "$MAJOR" == "3" ]]; then
    if [[ "$NOWHERE_URL" == portal://* || "$NOWHERE_URL" == vector://* ]]; then
        if echo "$NOWHERE_URL" | grep -qE '[?&](up|down|mux|next|socks|net|alpn|log|pool|spec)='; then
            echo "error: ${URL_FILE} still uses Nowhere 2.x parameters (up/down/mux/next/socks/net/alpn) that Nowhere 3 silently ignores; re-run oh-nowhere to migrate this node" >&2
            exit 1
        fi
    fi
    if [[ "$NOWHERE_URL" == nowhere://* ]]; then
        BASE="$NOWHERE_URL"
        if [[ "$BASE" == *#* ]]; then
            BASE="${BASE%%#*}"
        fi
        NOWHERE_URL="vector://${BASE#nowhere://}"
        if ! echo "$NOWHERE_URL" | grep -qE '[?&]in='; then
            if [[ "$NOWHERE_URL" == *\?* ]]; then
                NOWHERE_URL="${NOWHERE_URL}&in=127.0.0.1:1080"
            else
                NOWHERE_URL="${NOWHERE_URL}?in=127.0.0.1:1080"
            fi
        fi
        printf '%s\n' "$NOWHERE_URL" > "$URL_FILE"
    fi
else
    if [[ "$NOWHERE_URL" == nowhere://* ]]; then
        FRAG=""
        BASE="$NOWHERE_URL"
        if [[ "$BASE" == *#* ]]; then
            FRAG="${BASE#*#}"
            BASE="${BASE%%#*}"
        fi
        NOWHERE_URL="vector://${BASE#nowhere://}"
        if ! echo "$NOWHERE_URL" | grep -qE '[?&]socks='; then
            if [[ "$NOWHERE_URL" == *\?* ]]; then
                NOWHERE_URL="${NOWHERE_URL}&socks=127.0.0.1:1080"
            else
                NOWHERE_URL="${NOWHERE_URL}?socks=127.0.0.1:1080"
            fi
        fi
        printf '%s\n' "$NOWHERE_URL" > "$URL_FILE"
    fi
fi
exec "$NOWHERE_BIN" "$NOWHERE_URL"
EOF
    chmod +x "$LAUNCHER"
}

install_systemd_service() {
    local desc
    desc=$(get_service_description)
    cat > "$SYSTEMD_UNIT_FILE" <<EOF
[Unit]
Description=${desc}
Documentation=https://github.com/${GITHUB_REPO}
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${LAUNCHER}
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=nowhere

[Install]
WantedBy=multi-user.target
EOF
    # daemon-reload/enable only make sense for the real unit path; a redirected
    # one is a test artifact and must not reach the host's systemd.
    if [[ "$SYSTEMD_UNIT_FILE" == "/etc/systemd/system/${SERVICE_NAME}.service" ]]; then
        systemctl daemon-reload
        systemctl enable ${SERVICE_NAME}
    fi
}

install_openrc_service() {
    local desc
    desc=$(get_service_description)
    cat > "/etc/init.d/${SERVICE_NAME}" <<EOF
#!/sbin/openrc-run
description="${desc}"
command="/usr/local/bin/nowhere-launch.sh"
command_background=true
pidfile="/run/\${RC_SVCNAME}.pid"
output_log="${PORTAL_LOG}"
error_log="${PORTAL_LOG}"
depend() {
    need net
    after firewall
}
EOF
    chmod +x "/etc/init.d/${SERVICE_NAME}"
    rc-update add ${SERVICE_NAME} default 2>/dev/null || true
}

install_rc_service() {
    local desc
    desc=$(get_service_description)
    mkdir -p "$(dirname "$RC_SCRIPT")"
    cat > "$RC_SCRIPT" <<EOF
#!/bin/sh
# PROVIDE: nowhere
# REQUIRE: NETWORKING
# KEYWORD: shutdown

. /etc/rc.subr

name="nowhere"
rcvar="nowhere_enable"
desc="${desc}"
pidfile="/var/run/\${name}.pid"
procname="/usr/local/bin/nowhere"
command="/usr/sbin/daemon"
command_args="-P \${pidfile} -o ${PORTAL_LOG} ${LAUNCHER}"

load_rc_config \$name
: \${nowhere_enable:=NO}

run_rc_command "\$1"
EOF
    chmod 755 "$RC_SCRIPT"
    sysrc nowhere_enable=YES >/dev/null
}

install_init_service() {
    case "$INIT_SYSTEM" in
        systemd) install_systemd_service ;;
        openrc)  install_openrc_service ;;
        rc)      install_rc_service ;;
        *)       return 1 ;;
    esac
}

log_service_started() {
    case "$INIT_SYSTEM" in
        systemd) log_success "$(t ok_systemd_started)" ;;
        openrc)  log_success "$(t ok_openrc_started)" ;;
        rc)      log_success "$(t ok_rc_started)" ;;
        *)       log_warn "$(t warn_manual_start)" ;;
    esac
}

maybe_install_and_start_service() {
    if install_init_service; then
        start_service
        log_service_started
    else
        log_warn "$(t warn_manual_start)"
    fi
}

start_service() {
    [[ "$INIT_SYSTEM" == "systemd" ]] && systemctl start ${SERVICE_NAME} || true
    [[ "$INIT_SYSTEM" == "openrc" ]] && rc-service ${SERVICE_NAME} start || true
    [[ "$INIT_SYSTEM" == "rc" ]] && service ${SERVICE_NAME} start || true
}

stop_service() {
    [[ "$INIT_SYSTEM" == "systemd" ]] && systemctl stop ${SERVICE_NAME} 2>/dev/null || true
    [[ "$INIT_SYSTEM" == "openrc" ]] && rc-service ${SERVICE_NAME} stop 2>/dev/null || true
    [[ "$INIT_SYSTEM" == "rc" ]] && service ${SERVICE_NAME} stop 2>/dev/null || true
}

# Returns 0 when the Nowhere service unit exists and is running.
service_is_active() {
    case "$INIT_SYSTEM" in
        systemd)
            systemctl is-active --quiet ${SERVICE_NAME} 2>/dev/null
            ;;
        openrc)
            rc-service ${SERVICE_NAME} status 2>/dev/null | grep -qiE 'started|running'
            ;;
        rc)
            service ${SERVICE_NAME} status 2>/dev/null | grep -qi 'running'
            ;;
        *)
            return 1
            ;;
    esac
}

restart_service() {
    [[ "$INIT_SYSTEM" == "systemd" ]] && systemctl restart ${SERVICE_NAME} || true
    [[ "$INIT_SYSTEM" == "openrc" ]] && rc-service ${SERVICE_NAME} restart || true
    [[ "$INIT_SYSTEM" == "rc" ]] && service ${SERVICE_NAME} restart || true
}

disable_service() {
    [[ "$INIT_SYSTEM" == "systemd" ]] && systemctl disable ${SERVICE_NAME} 2>/dev/null || true
    [[ "$INIT_SYSTEM" == "openrc" ]] && rc-update delete ${SERVICE_NAME} default 2>/dev/null || true
    [[ "$INIT_SYSTEM" == "rc" ]] && sysrc -x nowhere_enable >/dev/null 2>&1 || true
}

service_status() {
    if [[ "$INIT_SYSTEM" == "systemd" ]]; then
        systemctl status ${SERVICE_NAME} --no-pager 2>/dev/null || log_warn "$(t warn_svc_missing)"
    elif [[ "$INIT_SYSTEM" == "openrc" ]]; then
        rc-service ${SERVICE_NAME} status 2>/dev/null || log_warn "$(t warn_svc_missing)"
    elif [[ "$INIT_SYSTEM" == "rc" ]]; then
        service ${SERVICE_NAME} status 2>/dev/null || log_warn "$(t warn_svc_missing)"
    else
        log_warn "$(t warn_svc_detect)"
    fi
}

# ==================== Version list ====================
list_github_versions() {
    local response
    response=$(curl -fsSL --connect-timeout 15 "https://api.github.com/repos/${GITHUB_REPO}/releases?per_page=30" 2>/dev/null)
    if [[ -z "$response" ]]; then
        return 1
    fi
    echo "$response" | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -n 30
}

# ==================== Interactive specific version install ====================
install_specific_version() {
    log_info "$(t info_fetch_versions)"
    local versions=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && versions+=("$line")
    done < <(list_github_versions)

    if [[ ${#versions[@]} -eq 0 ]]; then
        log_error "$(t err_no_versions)"
        return 1
    fi

    echo ""
    echo -e "${CYAN}  0) $(t label_latest_version)${NC}"
    local i
    for i in "${!versions[@]}"; do
        echo -e "  ${YELLOW}$((i + 1)))${NC} ${versions[$i]}"
    done
    echo ""

    local choice
    read -rp "$(t prompt_select_version "${#versions[@]}")" choice
    choice="$(echo "$choice" | tr -d '[:space:]')"

    local version=""
    if [[ "$choice" == "0" || -z "$choice" ]]; then
        version=""
    elif [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 && "$choice" -le ${#versions[@]} ]]; then
        version="${versions[$((choice - 1))]}"
    else
        log_error "$(t err_invalid_version_choice)"
        return 1
    fi

    if [[ -n "$version" ]]; then
        log_info "$(t ok_target_version_set "$version")"
        ARG_VERSION="$version"
    else
        ARG_VERSION=""
    fi

    if command -v nowhere &>/dev/null; then
        upgrade_nowhere
    else
        auto_install_nowhere
    fi
    ARG_VERSION=""
}

# ==================== Interactive configure ====================
apply_imported_url() {
    # Sets IMPORTED_ROLE / IMPORTED_URL from portal://, vector://, egress://
    # or nowhere://.
    local raw="$1"
    local socks_override="${2:-}"
    IMPORTED_URL=""
    IMPORTED_ROLE=""

    case "$raw" in
        nowhere://*|vector://*)
            IMPORTED_ROLE="vector"
            local socks="${socks_override:-${ARG_SOCKS:-$DEFAULT_SOCKS_IN}}"
            convert_nowhere_to_vector "$raw" "$socks" >/dev/null
            IMPORTED_URL="$CONVERTED_URL"
            if [[ -n "$CONVERTED_FRAGMENT" ]]; then
                ARG_NAME="${ARG_NAME:-$CONVERTED_FRAGMENT}"
            fi
            if [[ "$raw" == nowhere://* ]]; then
                log_info "$(t info_converted_nowhere)"
            fi
            ;;
        portal://*)
            IMPORTED_ROLE="portal"
            IMPORTED_URL="$raw"
            ;;
        egress://*)
            IMPORTED_ROLE="egress"
            IMPORTED_URL="$raw"
            ;;
        *)
            return 1
            ;;
    esac
    return 0
}

save_and_install_config() {
    local url="$1"
    local host="$2"
    local name="$3"
    local auto_restart="${4:-false}"

    echo "$url" > "$URL_FILE"
    save_share_host "$host"
    save_node_name "$name"
    write_launcher

    if [[ "$auto_restart" == "true" ]]; then
        install_init_service || log_warn "$(t warn_no_init)"
        restart_service
        log_success "$(t ok_config_updated)"
        return
    fi

    log_success "$(t ok_config_saved "$URL_FILE")"

    read -rp "$(t prompt_install_svc)" install_svc
    if [[ ! "$install_svc" =~ ^[Nn]$ ]]; then
        if ! install_init_service; then
            log_warn "$(t warn_no_init)"
            return
        fi
        log_success "$(t ok_svc_installed)"

        read -rp "$(t prompt_start_svc)" start_svc
        if [[ ! "$start_svc" =~ ^[Nn]$ ]]; then
            restart_service
            log_success "$(t ok_svc_started)"
        fi
    fi
}

configure_nowhere() {
    log_info "$(t info_configure)"
    mkdir -p "$CONFIG_DIR"
    migrate_stored_url

    local existing_url=""
    [[ -f "$URL_FILE" ]] && existing_url=$(tr -d '\n' < "$URL_FILE")

    local ROLE="portal"
    local imported=false
    IMPORTED_URL=""

    # CLI --url import takes priority.
    if [[ -n "$ARG_URL" ]]; then
        if apply_imported_url "$ARG_URL" "$ARG_SOCKS"; then
            imported=true
            ROLE="$IMPORTED_ROLE"
            existing_url="$IMPORTED_URL"
        else
            log_error "$(t err_invalid_url "$ARG_URL")"
            return 1
        fi
    elif [[ -n "$ARG_TYPE" ]]; then
        case "$ARG_TYPE" in
            portal|vector|egress) ROLE="$ARG_TYPE" ;;
            *)
                log_error "$(t err_invalid_type "$ARG_TYPE")"
                return 1
                ;;
        esac
    elif [[ -n "$existing_url" ]]; then
        ROLE=$(detect_url_role "$existing_url")
        ROLE="${ROLE:-portal}"
    fi

    if [[ "$ROLE" == "egress" ]] && ! is_nw3_profile; then
        log_error "$(t err_egress_requires_nw3)"
        return 1
    fi

    local skip_prompts=false
    if [[ "$AUTO_MODE" == "config" && ( -n "$ARG_KEY" || -n "$ARG_URL" ) ]]; then
        skip_prompts=true
    fi

    if [[ "$skip_prompts" == false && "$imported" == false ]]; then
        echo -e "${CYAN}$(t prompt_config_intro)${NC}"
        echo -e "${CYAN}$(t prompt_type_hint)${NC}"
        local type_input=""
        read -rp "$(t prompt_type "$ROLE")" type_input
        type_input="$(echo "$type_input" | tr -d '[:space:]')"
        if [[ -n "$type_input" ]]; then
            case "$type_input" in
                portal|vector|egress)
                    ROLE="$type_input"
                    if [[ "$ROLE" == "egress" ]] && ! is_nw3_profile; then
                        log_error "$(t err_egress_requires_nw3)"
                        return 1
                    fi
                    ;;
                nowhere://*|vector://*|portal://*|egress://*)
                    if apply_imported_url "$type_input" "$ARG_SOCKS"; then
                        imported=true
                        ROLE="$IMPORTED_ROLE"
                        existing_url="$IMPORTED_URL"
                    else
                        log_error "$(t err_invalid_url "$type_input")"
                        return 1
                    fi
                    ;;
                *)
                    log_error "$(t err_invalid_type "$type_input")"
                    return 1
                    ;;
            esac
        fi
    fi

    local dc
    dc=$(default_carrier)
    local default_key default_port="2077" default_alpn="$DEFAULT_ALPN"
    local default_net="mix" default_tls="1"
    local default_host="" default_socks="" default_next="" default_up="$dc" default_down="$dc"
    local default_mux="0" default_sni="" default_pin="" default_morph=""
    local default_tcp_port="" default_udp_port=""
    local default_outbound="direct"
    local default_cert_mode="$CERT_MODE_DEFAULT"
    local morph_default="0"
    is_nw3_profile && morph_default="1"
    default_key=$(generate_random_key)
    default_host=$(load_share_host)

    if [[ -n "$existing_url" ]]; then
        parse_url_authority "$existing_url"
        [[ -n "$PARSE_KEY" ]] && default_key="$PARSE_KEY"
        [[ -n "$PARSE_PORT" ]] && default_port="$PARSE_PORT"
        if url_has_carrier_path "$existing_url"; then
            default_tcp_port="$PARSE_TCP_PORT"
            default_udp_port="$PARSE_UDP_PORT"
            [[ -n "$PARSE_CARRIERS" ]] && default_net="$PARSE_CARRIERS"
        fi
        local existing_role
        existing_role=$(detect_url_role "$existing_url")
        if [[ "$existing_role" == "vector" ]]; then
            [[ -n "$PARSE_HOST" ]] && default_host="$PARSE_HOST"
            default_socks=$(get_query_param "$existing_url" "in")
            [[ -z "$default_socks" ]] && default_socks=$(get_query_param "$existing_url" "socks")
            default_socks=$(url_decode_simple "${default_socks:-$DEFAULT_SOCKS_IN}")
            default_sni=$(get_query_param "$existing_url" "sni")
            default_pin=$(get_query_param "$existing_url" "pin")
            default_morph=$(get_query_param "$existing_url" "morph")
            if is_nw3_profile; then
                # nw3 Vector declares exactly one carrier through its endpoint.
                if [[ "$existing_url" == */udp:* ]]; then
                    default_net="udp"
                else
                    default_net="tcp"
                fi
            else
                default_up=$(get_query_param "$existing_url" "up"); default_up=${default_up:-$dc}
                default_down=$(get_query_param "$existing_url" "down"); default_down=${default_down:-$dc}
                default_mux=$(get_query_param "$existing_url" "mux"); default_mux=${default_mux:-0}
            fi
        elif [[ "$existing_role" == "egress" ]]; then
            [[ -n "$PARSE_HOST" ]] && default_host="$PARSE_HOST"
            default_udp_port="${PARSE_UDP_PORT:-$PARSE_PORT}"
            default_net="udp"
            default_sni=$(get_query_param "$existing_url" "sni")
            default_pin=$(get_query_param "$existing_url" "pin")
            default_morph=$(get_query_param "$existing_url" "morph")
        elif is_nw3_profile; then
            # nw3 Portal exit replaces socks=/next= with out=.
            local existing_out
            existing_out=$(get_query_param "$existing_url" "out")
            case "$existing_out" in
                egress) default_outbound="egress" ;;
                ""|direct) default_outbound="direct" ;;
                *) default_outbound="socks"; default_socks="$existing_out" ;;
            esac
            default_morph=$(get_query_param "$existing_url" "morph")
            default_tls=$(get_query_param "$existing_url" "tls"); default_tls=${default_tls:-1}
            default_cert_mode=$(detect_cert_mode "$existing_url")
        else
            local existing_net
            existing_net=$(get_query_param "$existing_url" "net")
            default_net="${existing_net:-${PARSE_CARRIERS:-mix}}"
            default_tls=$(get_query_param "$existing_url" "tls"); default_tls=${default_tls:-1}
            default_cert_mode=$(detect_cert_mode "$existing_url")
            load_portal_outbound_from_url "$existing_url"
            default_socks="$PORTAL_SOCKS"
            default_next="$PORTAL_NEXT"
            default_up="$PORTAL_UP"
            default_down="$PORTAL_DOWN"
            default_mux="$PORTAL_MUX"
            default_sni="$PORTAL_SNI"
            default_pin="$PORTAL_PIN"
            default_morph="$PORTAL_MORPH"
        fi
        local existing_alpn
        existing_alpn=$(get_query_param "$existing_url" "alpn")
        if [[ -n "$existing_alpn" ]]; then
            default_alpn=$(url_decode_simple "$existing_alpn")
        fi
    fi

    [[ -n "$ARG_KEY" ]] && default_key="$ARG_KEY"
    [[ -n "$ARG_PORT" ]] && default_port="$ARG_PORT"
    [[ -n "$ARG_ALPN" ]] && default_alpn="$ARG_ALPN"
    [[ -n "$ARG_NET" ]] && default_net="$ARG_NET"
    [[ -n "$ARG_TLS" ]] && default_tls="$ARG_TLS"
    [[ -n "$ARG_HOST" ]] && default_host="$ARG_HOST"
    [[ -n "$ARG_SOCKS" ]] && default_socks="$ARG_SOCKS"
    [[ -n "$ARG_NEXT" ]] && default_next="$ARG_NEXT"
    [[ -n "$ARG_UP" ]] && default_up="$ARG_UP"
    [[ -n "$ARG_DOWN" ]] && default_down="$ARG_DOWN"
    [[ -n "$ARG_MUX" ]] && default_mux="$ARG_MUX"
    [[ -n "$ARG_SNI" ]] && default_sni="$ARG_SNI"
    [[ -n "$ARG_PIN" ]] && default_pin="$ARG_PIN"
    [[ -n "$ARG_MORPH" ]] && default_morph="$ARG_MORPH"
    [[ -n "$ARG_TCP_PORT" ]] && default_tcp_port="$ARG_TCP_PORT"
    [[ -n "$ARG_UDP_PORT" ]] && default_udp_port="$ARG_UDP_PORT"
    [[ -n "$ARG_OUT" ]] && default_outbound="$ARG_OUT"
    if [[ -n "$ARG_CERT_MODE" ]]; then
        if ! default_cert_mode=$(normalize_cert_mode "$ARG_CERT_MODE"); then
            log_error "$(t err_cert_mode_invalid "$ARG_CERT_MODE")"
            return 1
        fi
    fi
    # --acme-domain is shorthand for --cert-mode acme; the explicit flag wins if
    # both are given, so the two never disagree.
    if [[ -n "$ARG_ACME_DOMAIN" && -z "$ARG_CERT_MODE" ]]; then
        default_cert_mode="acme"
    fi
    # On nw3, --socks is the compatibility alias for out=<SOCKS5 upstream>.
    if is_nw3_profile && [[ -z "$ARG_OUT" && -n "$ARG_SOCKS" ]]; then
        default_outbound="socks"
    fi

    local default_name
    default_name=$(load_node_name)

    local key="$default_key" port="$default_port" alpn="$default_alpn"
    local net="$default_net" tls="$default_tls" host="$default_host" name="$default_name"
    local socks="$default_socks" next="$default_next" up="$default_up" down="$default_down"
    local mux="$default_mux" sni="$default_sni" pin="$default_pin"
    local morph="$default_morph" tcp_port="$default_tcp_port" udp_port="$default_udp_port"
    local outbound="$default_outbound"
    local cert_mode="$default_cert_mode"
    local crt="$DEFAULT_CERT" keyfile="$DEFAULT_KEYFILE"
    local cli_overrides="$ARG_SOCKS$ARG_NEXT$ARG_UP$ARG_DOWN$ARG_MUX$ARG_SNI$ARG_PIN$ARG_ALPN$ARG_HOST$ARG_PORT$ARG_NET$ARG_TLS$ARG_MORPH$ARG_TCP_PORT$ARG_UDP_PORT$ARG_OUT$ARG_CERT_MODE$ARG_CERT$ARG_KEYFILE$ARG_ACME_DOMAIN"

    if [[ "$skip_prompts" == true ]]; then
        key="${ARG_KEY:-$default_key}"
        port="${ARG_PORT:-$default_port}"
        alpn="${ARG_ALPN:-$default_alpn}"
        net="${ARG_NET:-$default_net}"
        tls="${ARG_TLS:-$default_tls}"
        host="${ARG_HOST:-$default_host}"
        name="${ARG_NAME:-$default_name}"
        socks="${ARG_SOCKS:-$default_socks}"
        next="${ARG_NEXT:-$default_next}"
        up="${ARG_UP:-$default_up}"
        down="${ARG_DOWN:-$default_down}"
        mux="${ARG_MUX:-$default_mux}"
        sni="${ARG_SNI:-$default_sni}"
        pin="${ARG_PIN:-$default_pin}"
        morph="${ARG_MORPH:-$default_morph}"
        tcp_port="${ARG_TCP_PORT:-$default_tcp_port}"
        udp_port="${ARG_UDP_PORT:-$default_udp_port}"
        if [[ "$imported" == true && -n "$IMPORTED_URL" && -z "$ARG_KEY" ]]; then
            if [[ "$ROLE" == "egress" ]]; then
                if [[ -z "$cli_overrides" ]]; then
                    echo -e "\n${CYAN}$(t label_generated_url)${NC}\n${GREEN}${IMPORTED_URL}${NC}\n"
                    save_and_install_config "$IMPORTED_URL" "$host" "$name" "true"
                    return
                fi
                parse_url_authority "$IMPORTED_URL"
                key="${ARG_KEY:-$PARSE_KEY}"
                host="${ARG_HOST:-$PARSE_HOST}"
                udp_port="${ARG_UDP_PORT:-${PARSE_UDP_PORT:-$PARSE_PORT}}"
                sni="${ARG_SNI:-$(get_query_param "$IMPORTED_URL" "sni")}"
                pin="${ARG_PIN:-$(get_query_param "$IMPORTED_URL" "pin")}"
                morph="${ARG_MORPH:-$(get_query_param "$IMPORTED_URL" "morph")}"
            elif [[ "$ROLE" == "vector" ]]; then
                if [[ -z "$cli_overrides" ]]; then
                    echo -e "\n${CYAN}$(t label_generated_url)${NC}\n${GREEN}${IMPORTED_URL}${NC}\n"
                    save_and_install_config "$IMPORTED_URL" "$host" "$name" "true"
                    return
                fi
                parse_url_authority "$IMPORTED_URL"
                key="${ARG_KEY:-$PARSE_KEY}"
                host="${ARG_HOST:-$PARSE_HOST}"
                port="${ARG_PORT:-$PARSE_PORT}"
                socks="${ARG_SOCKS:-$(url_decode_simple "$(get_query_param "$IMPORTED_URL" "in")")}"
                socks="${socks:-$(url_decode_simple "$(get_query_param "$IMPORTED_URL" "socks")")}"
                socks="${socks:-$DEFAULT_SOCKS_IN}"
                sni="${ARG_SNI:-$(get_query_param "$IMPORTED_URL" "sni")}"
                pin="${ARG_PIN:-$(get_query_param "$IMPORTED_URL" "pin")}"
                morph="${ARG_MORPH:-$(get_query_param "$IMPORTED_URL" "morph")}"
                if is_nw3_profile; then
                    if [[ "$IMPORTED_URL" == */udp:* ]]; then
                        net="${ARG_NET:-udp}"
                    else
                        net="${ARG_NET:-tcp}"
                    fi
                    if [[ "$net" == "udp" ]]; then
                        udp_port="${ARG_UDP_PORT:-${PARSE_UDP_PORT:-$PARSE_PORT}}"
                        tcp_port=""
                    else
                        tcp_port="${ARG_TCP_PORT:-${PARSE_TCP_PORT:-$PARSE_PORT}}"
                        udp_port=""
                    fi
                    up=""; down=""; mux=""
                else
                    up="${ARG_UP:-$(get_query_param "$IMPORTED_URL" "up")}"
                    up="${up:-$dc}"
                    down="${ARG_DOWN:-$(get_query_param "$IMPORTED_URL" "down")}"
                    down="${down:-$dc}"
                    mux="${ARG_MUX:-$(get_query_param "$IMPORTED_URL" "mux")}"
                    if url_has_carrier_path "$IMPORTED_URL"; then
                        tcp_port="${ARG_TCP_PORT:-$PARSE_TCP_PORT}"
                        udp_port="${ARG_UDP_PORT:-$PARSE_UDP_PORT}"
                        net="${ARG_NET:-${PARSE_CARRIERS:-mix}}"
                    else
                        tcp_port="${ARG_TCP_PORT:-}"
                        udp_port="${ARG_UDP_PORT:-}"
                        net="${ARG_NET:-mix}"
                    fi
                fi
                local ia
                ia=$(get_query_param "$IMPORTED_URL" "alpn")
                [[ -n "$ia" ]] && alpn=$(url_decode_simple "$ia")
                [[ -n "$ARG_ALPN" ]] && alpn="$ARG_ALPN"
            else
                if [[ -z "$cli_overrides" ]]; then
                    echo -e "\n${CYAN}$(t label_generated_url)${NC}\n${GREEN}${IMPORTED_URL}${NC}\n"
                    save_and_install_config "$IMPORTED_URL" "$host" "$name" "true"
                    return
                fi
                parse_url_authority "$IMPORTED_URL"
                load_portal_outbound_from_url "$IMPORTED_URL"
                key="${ARG_KEY:-$PARSE_KEY}"
                port="${ARG_PORT:-$PARSE_PORT}"
                net="${ARG_NET:-$(get_query_param "$IMPORTED_URL" "net")}"
                net="${net:-${PARSE_CARRIERS:-mix}}"
                tls="${ARG_TLS:-$(get_query_param "$IMPORTED_URL" "tls")}"
                tls="${tls:-1}"
                socks="${ARG_SOCKS:-$PORTAL_SOCKS}"
                next="${ARG_NEXT:-$PORTAL_NEXT}"
                up="${ARG_UP:-$PORTAL_UP}"
                down="${ARG_DOWN:-$PORTAL_DOWN}"
                mux="${ARG_MUX:-$PORTAL_MUX}"
                sni="${ARG_SNI:-$PORTAL_SNI}"
                pin="${ARG_PIN:-$PORTAL_PIN}"
                morph="${ARG_MORPH:-$PORTAL_MORPH}"
                if url_has_carrier_path "$IMPORTED_URL"; then
                    tcp_port="${ARG_TCP_PORT:-$PARSE_TCP_PORT}"
                    udp_port="${ARG_UDP_PORT:-$PARSE_UDP_PORT}"
                else
                    tcp_port="${ARG_TCP_PORT:-}"
                    udp_port="${ARG_UDP_PORT:-}"
                fi
                local ia
                ia=$(get_query_param "$IMPORTED_URL" "alpn")
                [[ -n "$ia" ]] && alpn=$(url_decode_simple "$ia")
                [[ -n "$ARG_ALPN" ]] && alpn="$ARG_ALPN"
                # An imported URL carries no certificate source; recover it from
                # what is on disk so the openssl pin survives a re-configure.
                cert_mode=$(detect_cert_mode "$IMPORTED_URL")
            fi
        fi
    fi

    local url=""
    if [[ "$ROLE" == "egress" ]]; then
        log_info "$(t info_configure_egress)"
        if [[ "$skip_prompts" == false ]]; then
            echo -e "${CYAN}$(t prompt_config_intro)${NC}"

            read_key_checked "egress" "$key" || return 1
            key="$ENTERED_KEY"

            read -rp "$(t prompt_portal_host "$host")" host_input
            if [[ "$host_input" == "-" ]]; then
                host=""
            elif [[ -n "$host_input" ]]; then
                host="$host_input"
            fi

            local prev_port=""
            [[ -n "$existing_url" ]] && prev_port="$udp_port"
            udp_port=$(read_port_checked prompt_udp_port "${udp_port:-2077}" "$prev_port")

            read -rp "$(t prompt_sni "$sni")" sni_input
            if [[ "$sni_input" == "-" ]]; then
                sni=""
            elif [[ -n "$sni_input" ]]; then
                sni="$sni_input"
            fi

            read -rp "$(t prompt_pin "$pin")" pin_input
            if [[ "$pin_input" == "-" ]]; then
                pin=""
            elif [[ -n "$pin_input" ]]; then
                pin="$pin_input"
            fi

            if [[ -z "$pin" ]]; then
                log_warn "$(t warn_pin_required)"
            fi

            read -rp "$(t prompt_morph "${morph:-$morph_default}")" morph_input
            [[ -n "$morph_input" ]] && morph="$morph_input"

            read -rp "$(t prompt_name "$name")" name_input
            if [[ "$name_input" == "-" ]]; then
                name=""
            elif [[ -n "$name_input" ]]; then
                name="$name_input"
            fi
        fi

        if [[ -z "$host" ]]; then
            log_error "$(t err_portal_host_required)"
            return 1
        fi

        url=$(build_egress_url "$key" "$host" "${udp_port:-$port}" "$sni" "$pin" "$morph") || return 1
    elif [[ "$ROLE" == "vector" ]]; then
        log_info "$(t info_configure_vector)"
        if [[ "$skip_prompts" == false ]]; then
            echo -e "${CYAN}$(t prompt_config_intro)${NC}"

            read -rp "$(t prompt_key "$key")" key_input
            [[ -n "$key_input" ]] && key="$key_input"

            read -rp "$(t prompt_portal_host "$host")" host_input
            if [[ "$host_input" == "-" ]]; then
                host=""
            elif [[ -n "$host_input" ]]; then
                host="$host_input"
            fi

            local prev_port=""
            [[ -n "$existing_url" ]] && prev_port="$port"
            port=$(read_port_checked prompt_port "$port" "$prev_port")

            if is_nw3_profile; then
                # nw3 Vector declares exactly one carrier through its endpoint.
                read -rp "$(t prompt_carrier_single "$net")" carrier_input
                if [[ -n "$carrier_input" ]]; then
                    case "$carrier_input" in
                        tcp|udp) net="$carrier_input" ;;
                        *)
                            log_error "$(t err_invalid_carrier "$carrier_input")"
                            return 1
                            ;;
                    esac
                fi
                [[ "$net" == "udp" ]] || net="tcp"
                if [[ "$net" == "udp" ]]; then
                    tcp_port=""
                    udp_port="$port"
                else
                    tcp_port="$port"
                    udp_port=""
                fi
            else
                if is_v2_profile; then
                    read -rp "$(t prompt_net "$net")" net_input
                    [[ -n "$net_input" ]] && net="$net_input"
                    prompt_v2_carrier_ports "$net" "$port" "$tcp_port" "$udp_port"
                    tcp_port="$OUT_TCP_PORT"
                    udp_port="$OUT_UDP_PORT"
                fi

                read -rp "$(t prompt_up "$up")" up_input
                [[ -n "$up_input" ]] && up="$up_input"

                read -rp "$(t prompt_down "$down")" down_input
                [[ -n "$down_input" ]] && down="$down_input"

                if mux_applies "$up" "$down"; then
                    read -rp "$(t prompt_mux "$mux")" mux_input
                    [[ -n "$mux_input" ]] && mux="$mux_input"
                else
                    mux=""
                fi
            fi

            socks="${socks:-$DEFAULT_SOCKS_IN}"
            read -rp "$(t prompt_socks_in "$socks")" socks_input
            [[ -n "$socks_input" ]] && socks="$socks_input"

            read -rp "$(t prompt_sni "$sni")" sni_input
            if [[ "$sni_input" == "-" ]]; then
                sni=""
            elif [[ -n "$sni_input" ]]; then
                sni="$sni_input"
            fi

            read -rp "$(t prompt_pin "$pin")" pin_input
            if [[ "$pin_input" == "-" ]]; then
                pin=""
            elif [[ -n "$pin_input" ]]; then
                pin="$pin_input"
            fi

            if [[ -z "$pin" ]] && { is_v22_profile || is_nw3_profile; }; then
                log_warn "$(t warn_pin_required)"
                if command -v nowhere &>/dev/null; then
                    local fetch_ans=""
                    read -rp "$(t prompt_fetch_pin)" fetch_ans
                    if [[ -z "$fetch_ans" || "$fetch_ans" =~ ^[Yy]$ ]]; then
                        if fetch_pin_via_binary "$key" "$host" "$port" "$net" "$tcp_port" "$udp_port" "$sni" "${morph:-$morph_default}"; then
                            pin="$FETCHED_PIN"
                            log_success "$(t info_pin_fetched "$pin")"
                        else
                            log_warn "$(t warn_pin_unavailable)"
                        fi
                    fi
                fi
            fi

            if is_v2_profile; then
                read -rp "$(t prompt_morph "${morph:-$morph_default}")" morph_input
                [[ -n "$morph_input" ]] && morph="$morph_input"
            else
                read -rp "$(t prompt_alpn "$alpn")" alpn_input
                [[ -n "$alpn_input" ]] && alpn="$alpn_input"
            fi

            read -rp "$(t prompt_name "$name")" name_input
            if [[ "$name_input" == "-" ]]; then
                name=""
            elif [[ -n "$name_input" ]]; then
                name="$name_input"
            fi
        fi

        if [[ -z "$host" ]]; then
            log_error "$(t err_portal_host_required)"
            return 1
        fi
        socks="${socks:-$DEFAULT_SOCKS_IN}"
        if [[ -z "$socks" || "$socks" == "none" ]]; then
            log_error "$(t err_socks_required)"
            return 1
        fi

        url=$(build_vector_url "$key" "$host" "$port" "$up" "$down" "$socks" "$alpn" "$mux" "$sni" "$pin" "$morph" "$tcp_port" "$udp_port" "$net") || return 1
    else
        log_info "$(t info_configure_portal)"
        if [[ "$skip_prompts" == false ]]; then
            echo -e "${CYAN}$(t prompt_config_intro)${NC}"

            read_key_checked "portal" "$key" || return 1
            key="$ENTERED_KEY"

            local prev_port=""
            [[ -n "$existing_url" ]] && prev_port="$port"
            port=$(read_port_checked prompt_port "$port" "$prev_port")

            read -rp "$(t prompt_net "$net")" net_input
            [[ -n "$net_input" ]] && net="$net_input"

            if is_v2_profile; then
                prompt_v2_carrier_ports "$net" "$port" "$tcp_port" "$udp_port"
                tcp_port="$OUT_TCP_PORT"
                udp_port="$OUT_UDP_PORT"
            fi

            read -rp "$(t prompt_cert_mode "$cert_mode")" cert_mode_input
            [[ -n "$cert_mode_input" ]] && cert_mode="$cert_mode_input"
            if ! cert_mode=$(normalize_cert_mode "$cert_mode"); then
                log_error "$(t err_cert_mode_invalid "$cert_mode_input")"
                return 1
            fi
            case "$cert_mode" in
                program) log_info "$(t info_cert_mode_program)" ;;
                openssl) log_info "$(t info_cert_mode_openssl)" ;;
                custom)  log_info "$(t info_cert_mode_custom)" ;;
                acme)    log_info "$(t info_cert_mode_acme)" ;;
            esac
            tls=$(cert_mode_tls "$cert_mode")

            read -rp "$(t prompt_tls "$tls")" tls_input
            [[ -n "$tls_input" ]] && tls="$tls_input"

            if is_v2_profile; then
                read -rp "$(t prompt_morph "${morph:-$morph_default}")" morph_input
                [[ -n "$morph_input" ]] && morph="$morph_input"
            else
                read -rp "$(t prompt_alpn "$alpn")" alpn_input
                [[ -n "$alpn_input" ]] && alpn="$alpn_input"
            fi

            read -rp "$(t prompt_host "$host")" host_input
            if [[ "$host_input" == "-" ]]; then
                host=""
            elif [[ -n "$host_input" ]]; then
                host="$host_input"
            fi

            read -rp "$(t prompt_name "$name")" name_input
            if [[ "$name_input" == "-" ]]; then
                name=""
            elif [[ -n "$name_input" ]]; then
                name="$name_input"
            fi

            if ! collect_portal_outbound_interactive "$socks" "$next" "$up" "$down" "$mux" "$sni" "$pin"; then
                return 1
            fi
            outbound="$OUT_OUTBOUND"
            socks="$OUT_SOCKS"
            next="$OUT_NEXT"
            up="$OUT_UP"
            down="$OUT_DOWN"
            mux="$OUT_MUX"
            sni="$OUT_SNI"
            pin="$OUT_PIN"
        fi

        if [[ "$outbound" == "socks" && -z "$socks" ]]; then
            log_error "$(t err_out_socks_required)"
            return 1
        fi

        # The certificate source decides tls=; the tls= prompt above is a
        # read-only echo of that decision (kept for backward compatibility).
        tls=$(cert_mode_tls "$cert_mode")
        if ! resolve_cert_mode "$cert_mode" "$host" "$skip_prompts"; then
            return 1
        fi
        tls="$CERT_TLS"; crt="$CERT_CRT"; keyfile="$CERT_KEYFILE"

        url=$(build_portal_url "$key" "$port" "$tls" "$net" "$alpn" "$crt" "$keyfile" "$socks" "$next" "$up" "$down" "$mux" "$sni" "$pin" "$morph" "$tcp_port" "$udp_port" "$outbound") || return 1
    fi

    echo -e "\n${CYAN}$(t label_generated_url)${NC}\n${GREEN}${url}${NC}\n"

    if [[ "$AUTO_MODE" == "config" ]]; then
        save_and_install_config "$url" "$host" "$name" "true"
        return
    fi

    read -rp "$(t prompt_save_config)" save
    if [[ ! "$save" =~ ^[Nn]$ ]]; then
        save_and_install_config "$url" "$host" "$name" "false"
    else
        log_info "$(t info_config_not_saved)"
    fi
}

# ==================== Modify configuration ====================
mf_add_field() {
    MF_LABELS+=("$1")
    MF_VARS+=("$2")
    MF_PROMPTS+=("$3")
}

# Builds the editable field list for the current role into MF_LABELS/MF_VARS/MF_PROMPTS.
# Reads the caller's variables (key, port, socks, next, ...) through dynamic scoping.
mf_build_fields() {
    local role="$1"
    MF_LABELS=(); MF_VARS=(); MF_PROMPTS=()
    mf_add_field mf_key key prompt_key
    if [[ "$role" == "egress" ]]; then
        mf_add_field mf_host host prompt_portal_host
        mf_add_field mf_port port prompt_udp_port
        mf_add_field mf_sni sni prompt_sni
        mf_add_field mf_pin pin prompt_pin
        mf_add_field mf_morph morph prompt_morph
        mf_add_field mf_name name prompt_name
        return
    fi
    if [[ "$role" == "vector" ]]; then
        mf_add_field mf_host host prompt_portal_host
    fi
    mf_add_field mf_port port prompt_port
    if is_nw3_profile && [[ "$role" == "vector" ]]; then
        # nw3 Vector endpoints carry exactly one carrier: tcp or udp.
        mf_add_field mf_carrier net prompt_carrier_single
    else
        mf_add_field mf_net net prompt_net
    fi
    if is_v2_profile; then
        mf_add_field mf_tcp_port tcp_port prompt_tcp_port
        mf_add_field mf_udp_port udp_port prompt_udp_port
    fi
    if [[ "$role" == "portal" ]]; then
        # The certificate source replaces the raw tls= question: tls= follows
        # from it, so only the source is editable here.
        mf_add_field mf_cert_mode cert_mode prompt_cert_mode
        if [[ "$cert_mode" == "custom" ]]; then
            mf_add_field mf_cert crt prompt_cert
            mf_add_field mf_keyfile keyfile prompt_keyfile
        fi
    fi
    if is_v2_profile || is_nw3_profile; then
        mf_add_field mf_morph morph prompt_morph
    else
        mf_add_field mf_alpn alpn prompt_alpn
    fi
    if [[ "$role" == "vector" ]]; then
        if is_nw3_profile; then
            # nw3 Vector: single carrier, in= replaces up/down/mux.
            mf_add_field mf_in socks prompt_socks_in
        else
            mf_add_field mf_up up prompt_up
            mf_add_field mf_down down prompt_down
            if mux_applies "$up" "$down"; then
                mf_add_field mf_mux mux prompt_mux
            fi
            mf_add_field mf_socks socks prompt_socks_in
        fi
        mf_add_field mf_sni sni prompt_sni
        mf_add_field mf_pin pin prompt_pin
        mf_add_field mf_name name prompt_name
    else
        mf_add_field mf_share_host host prompt_host
        mf_add_field mf_name name prompt_name
        if is_nw3_profile; then
            # nw3 Portal exit is a first-class choice: direct, a SOCKS5 upstream
            # or a registered Egress. It is stored, not derived from socks/next.
            mf_add_field mf_outbound outbound prompt_outbound_mode_nw3
            if [[ "${outbound:-direct}" == "socks" ]]; then
                mf_add_field mf_out_socks socks prompt_socks_out
            fi
        else
            mf_add_field mf_outbound outbound prompt_outbound_mode
            case "$(portal_outbound_mode "$socks" "$next")" in
                socks)
                    mf_add_field mf_socks socks prompt_socks_out
                    ;;
                next)
                    mf_add_field mf_next next prompt_next
                    mf_add_field mf_up up prompt_up
                    mf_add_field mf_down down prompt_down
                    if mux_applies "$up" "$down"; then
                        mf_add_field mf_mux mux prompt_mux
                    fi
                    mf_add_field mf_sni sni prompt_sni
                    mf_add_field mf_pin pin prompt_pin
                    ;;
            esac
        fi
    fi
}

# Prints the display value of an editable field.
mf_display_value() {
    local vname="$1"
    if [[ "$vname" == "outbound" ]]; then
        if is_nw3_profile; then
            printf '%s' "${outbound:-direct}"
        else
            portal_outbound_mode "$socks" "$next"
        fi
        return
    fi
    if [[ "$vname" == "cert_mode" ]]; then
        # tls= is derived from the source, so show both for context.
        printf '%s (tls=%s)' "${!vname}" "$(cert_mode_tls "${!vname}")"
        return
    fi
    local val="${!vname}"
    if [[ -n "$val" ]]; then
        printf '%s' "$val"
    else
        t modify_none
    fi
}

# Prompts for a new value of one field and assigns it in the caller's scope.
mf_edit_field() {
    local role="$1" vname="$2" prompt_key="$3"
    local current="" input=""
    # "outbound" is derived from socks/next, not a stored variable.
    if [[ "$vname" != "outbound" ]]; then
        current="${!vname}"
    fi
    case "$vname" in
        cert_mode)
            read -rp "$(t prompt_cert_mode "${current:-$CERT_MODE_DEFAULT}")" input
            [[ -z "$input" ]] && return 0
            if ! cert_mode=$(normalize_cert_mode "$input"); then
                log_error "$(t err_cert_mode_invalid "$input")"
                return 1
            fi
            tls=$(cert_mode_tls "$cert_mode")
            if ! resolve_cert_mode "$cert_mode" "$host" false; then
                return 1
            fi
            tls="$CERT_TLS"; crt="$CERT_CRT"; keyfile="$CERT_KEYFILE"
            ;;
        outbound)
            if is_nw3_profile; then
                # nw3 Portal exit: direct / SOCKS5 upstream / Egress, stored in out=.
                local nw3_mode="${outbound:-direct}"
                read -rp "$(t prompt_outbound_mode_nw3 "$nw3_mode")" input
                input="${input:-$nw3_mode}"
                case "$input" in
                    direct|socks|egress)
                        outbound="$input"
                        ;;
                    *)
                        log_error "$(t err_invalid_out "$input")"
                        return 1
                        ;;
                esac
                if [[ "$outbound" != "socks" ]]; then
                    socks=""
                fi
                return 0
            fi
            local mode
            mode=$(portal_outbound_mode "$socks" "$next")
            read -rp "$(t prompt_outbound_mode "$mode")" input
            input="${input:-$mode}"
            case "$input" in
                none)
                    socks=""
                    next=""
                    ;;
                socks)
                    next=""
                    local ds="${socks:-proxy.example:1080}"
                    read -rp "$(t prompt_socks_out "$ds")" input
                    socks="${input:-$ds}"
                    ;;
                next)
                    socks=""
                    local dn="${next:-origin-key@origin.example:2077}"
                    read -rp "$(t prompt_next "$dn")" input
                    next="${input:-$dn}"
                    ;;
                *)
                    log_error "$(t err_invalid_type "$input")"
                    return 1
                    ;;
            esac
            return 0
            ;;
        key)
            read -rp "$(t "$prompt_key" "$current")" input
            if [[ -n "$input" ]]; then
                if [[ "$role" == "portal" ]] && is_v22_profile && ! valid_v22_key "$input"; then
                    log_error "$(t err_invalid_key)"
                    return 1
                fi
                key="$input"
            fi
            ;;
        port|tcp_port|udp_port)
            # Empty carrier ports inherit the shared port; the previous effective
            # value is what the running service actually binds, so compare against it.
            local eff_port="${current:-$port}"
            local new_port
            new_port=$(read_port_checked "$prompt_key" "$eff_port" "$eff_port")
            printf -v "$vname" '%s' "$new_port"
            ;;
        net)
            read -rp "$(t "$prompt_key" "$current")" input
            [[ -z "$input" ]] && return 0
            if is_nw3_profile && [[ "$role" == "vector" ]]; then
                # nw3 Vector endpoints carry exactly one carrier.
                if [[ "$input" != "tcp" && "$input" != "udp" ]]; then
                    log_error "$(t err_invalid_carrier "$input")"
                    return 1
                fi
                net="$input"
                return 0
            fi
            validate_net_value "$input" || return 1
            net="$input"
            if is_v2_profile; then
                # A single-carrier policy cannot keep the opposite explicit port.
                case "$net" in
                    tcp) udp_port="" ;;
                    udp) tcp_port="" ;;
                esac
            fi
            ;;
        tls)
            read -rp "$(t "$prompt_key" "$current")" input
            [[ -z "$input" ]] && return 0
            case "$input" in
                0|1|2) tls="$input" ;;
                *)
                    log_error "$(t err_invalid_tls "$input")"
                    return 1
                    ;;
            esac
            ;;
        morph)
            read -rp "$(t "$prompt_key" "${current:-$morph_default}")" input
            [[ -z "$input" ]] && return 0
            validate_morph_value "$input" || return 1
            morph="$input"
            ;;
        alpn)
            read -rp "$(t "$prompt_key" "$current")" input
            if [[ "$input" == "-" ]]; then
                alpn=""
            elif [[ -n "$input" ]]; then
                alpn="$input"
            fi
            ;;
        up|down)
            read -rp "$(t "$prompt_key" "$current")" input
            [[ -z "$input" ]] && return 0
            validate_carrier "$input" || return 1
            printf -v "$vname" '%s' "$input"
            ;;
        mux)
            read -rp "$(t "$prompt_key" "$current")" input
            [[ -z "$input" ]] && return 0
            validate_mux_value "$input" || return 1
            mux="$input"
            ;;
        socks)
            read -rp "$(t "$prompt_key" "$current")" input
            [[ -z "$input" ]] && return 0
            if [[ "$role" == "vector" && "$input" == "-" ]]; then
                log_error "$(t err_socks_required)"
                return 1
            fi
            [[ "$input" == "-" && "$role" == "portal" ]] && input=""
            socks="$input"
            ;;
        next)
            read -rp "$(t "$prompt_key" "$current")" input
            [[ -n "$input" ]] && next="$input"
            ;;
        sni|pin)
            read -rp "$(t "$prompt_key" "$current")" input
            if [[ "$input" == "-" ]]; then
                printf -v "$vname" '%s' ""
            elif [[ -n "$input" ]]; then
                printf -v "$vname" '%s' "$input"
            fi
            ;;
        crt|keyfile)
            read -rp "$(t "$prompt_key" "$current")" input
            if [[ -n "$input" ]]; then
                printf -v "$vname" '%s' "$input"
                # Taking over the certificate files drops the openssl pin: the
                # share URI falls back to sni= verification.
                clear_pin
            fi
            ;;
        host)
            read -rp "$(t "$prompt_key" "$current")" input
            if [[ "$input" == "-" && "$role" == "portal" ]]; then
                host=""
            elif [[ -n "$input" ]]; then
                host="$input"
            fi
            ;;
        name)
            read -rp "$(t "$prompt_key" "$current")" input
            if [[ "$input" == "-" ]]; then
                name=""
            elif [[ -n "$input" ]]; then
                name="$input"
            fi
            ;;
        *)
            read -rp "$(t "$prompt_key" "$current")" input
            [[ -n "$input" ]] && printf -v "$vname" '%s' "$input"
            ;;
    esac
    return 0
}

# Interactive per-field editor for the stored run URL. Rebuilds the URL with the
# existing builders, preserves parameters this editor does not manage (rate/etar/
# dial/log, future keys), then saves and restarts the service so changes apply.
modify_configuration() {
    migrate_stored_url
    if [[ ! -f "$URL_FILE" ]]; then
        log_warn "$(t warn_no_config)"
        log_info "$(t info_configure_first)"
        return 1
    fi

    local url role
    url=$(tr -d '\n' < "$URL_FILE")
    role=$(detect_url_role "$url")
    role="${role:-portal}"

    local dc
    dc=$(default_carrier)

    parse_url_authority "$url"
    local key="$PARSE_KEY" port="${PARSE_PORT:-2077}" host=""
    local net="mix" tls="1" alpn="" socks="" next="" outbound="direct"
    local up="$dc" down="$dc" mux="0" sni="" pin="" morph=""
    local tcp_port="" udp_port=""
    local crt="$DEFAULT_CERT" keyfile="$DEFAULT_KEYFILE"
    local cert_mode="$CERT_MODE_DEFAULT"
    local morph_default="0"
    is_nw3_profile && morph_default="1"
    if url_has_carrier_path "$url"; then
        tcp_port="$PARSE_TCP_PORT"
        udp_port="$PARSE_UDP_PORT"
        [[ -n "$PARSE_CARRIERS" ]] && net="$PARSE_CARRIERS"
    fi
    if [[ "$role" == "vector" ]]; then
        host="$PARSE_HOST"
        sni=$(get_query_param "$url" "sni")
        pin=$(get_query_param "$url" "pin")
        morph=$(get_query_param "$url" "morph")
        if is_nw3_profile; then
            # nw3 Vector: one carrier, in= replaces up/down/mux/socks=.
            socks=$(url_decode_simple "$(get_query_param "$url" "in")")
            if [[ "$net" != "tcp" && "$net" != "udp" ]]; then
                net="tcp"
            fi
            port="${PARSE_TCP_PORT:-${PARSE_UDP_PORT:-$port}}"
            tcp_port=""
            udp_port=""
        else
            up=$(get_query_param "$url" "up"); up="${up:-$dc}"
            down=$(get_query_param "$url" "down"); down="${down:-$dc}"
            mux=$(get_query_param "$url" "mux"); mux="${mux:-0}"
            socks=$(url_decode_simple "$(get_query_param "$url" "socks")")
        fi
    elif [[ "$role" == "egress" ]]; then
        host="$PARSE_HOST"
        port="${PARSE_UDP_PORT:-$PARSE_PORT}"
        sni=$(get_query_param "$url" "sni")
        pin=$(get_query_param "$url" "pin")
        morph=$(get_query_param "$url" "morph")
    else
        local existing_net
        existing_net=$(get_query_param "$url" "net")
        [[ -n "$existing_net" ]] && net="$existing_net"
        tls=$(get_query_param "$url" "tls"); tls="${tls:-1}"
        if is_nw3_profile; then
            # nw3 Portal exit is stored in out=; socks=/next= no longer exist.
            local raw_out
            raw_out=$(url_decode_simple "$(get_query_param "$url" "out")")
            case "$raw_out" in
                egress) outbound="egress" ;;
                direct|"") outbound="direct" ;;
                *) outbound="socks"; socks="$raw_out" ;;
            esac
        else
            load_portal_outbound_from_url "$url"
            socks="$PORTAL_SOCKS"
            next="$PORTAL_NEXT"
            up="$PORTAL_UP"
            down="$PORTAL_DOWN"
            mux="$PORTAL_MUX"
            sni="$PORTAL_SNI"
            pin="$PORTAL_PIN"
        fi
        morph=$(get_query_param "$url" "morph")
        crt=$(get_query_param "$url" "crt"); crt="${crt:-$DEFAULT_CERT}"
        keyfile=$(get_query_param "$url" "key"); keyfile="${keyfile:-$DEFAULT_KEYFILE}"
        cert_mode=$(detect_cert_mode "$url")
    fi
    local existing_alpn
    existing_alpn=$(get_query_param "$url" "alpn")
    [[ -n "$existing_alpn" ]] && alpn=$(url_decode_simple "$existing_alpn")
    host="${host:-$(load_share_host)}"
    local name
    name=$(load_node_name)

    # Keep parameters this editor does not manage (rate/etar/dial/log, future keys).
    local leftover="$url" p
    for p in tls crt key net alpn socks next up down mux sni pin morph out in; do
        leftover=$(strip_query_param "$leftover" "$p")
    done
    if [[ "$leftover" == *\?* ]]; then
        leftover="${leftover#*\?}"
    else
        leftover=""
    fi

    while true; do
        mf_build_fields "$role"
        echo -e "\n${CYAN}$(t modify_title "${GREEN}${role}${NC}")${NC}"
        echo -e "${CYAN}$(t label_run_url_status "${GREEN}${url}${NC}")${NC}"
        echo -e "${CYAN}$(t modify_hint)${NC}"
        local i total="${#MF_VARS[@]}"
        for (( i=0; i<total; i++ )); do
            printf "  ${YELLOW}%2d)${NC} %-18s: ${GREEN}%s${NC}\n" "$((i+1))" "$(t "${MF_LABELS[$i]}")" "$(mf_display_value "${MF_VARS[$i]}")"
        done
        local sel=""
        read -rp "$(t prompt_modify_choice "$total")" sel
        case "$sel" in
            ""|q|Q)
                break
                ;;
            *[!0-9]*)
                log_error "$(t err_invalid_choice)"
                ;;
            *)
                if (( sel >= 1 && sel <= total )); then
                    mf_edit_field "$role" "${MF_VARS[$((sel-1))]}" "${MF_PROMPTS[$((sel-1))]}" || true
                else
                    log_error "$(t err_invalid_choice)"
                fi
                ;;
        esac
    done

    local new_url
    if [[ "$role" == "vector" ]]; then
        if [[ -z "$host" ]]; then
            log_error "$(t err_portal_host_required)"
            return 1
        fi
        socks="${socks:-$DEFAULT_SOCKS_IN}"
        new_url=$(build_vector_url "$key" "$host" "$port" "$up" "$down" "$socks" "$alpn" "$mux" "$sni" "$pin" "$morph" "$tcp_port" "$udp_port" "$net") || return 1
    elif [[ "$role" == "egress" ]]; then
        if [[ -z "$host" ]]; then
            log_error "$(t err_portal_host_required)"
            return 1
        fi
        new_url=$(build_egress_url "$key" "$host" "$port" "$sni" "$pin" "$morph") || return 1
    else
        if is_nw3_profile && [[ "$outbound" == "socks" && -z "$socks" ]]; then
            log_error "$(t err_out_socks_required)"
            return 1
        fi
        new_url=$(build_portal_url "$key" "$port" "$tls" "$net" "$alpn" "$crt" "$keyfile" "$socks" "$next" "$up" "$down" "$mux" "$sni" "$pin" "$morph" "$tcp_port" "$udp_port" "$outbound") || return 1
    fi
    if [[ -n "$leftover" ]]; then
        if [[ "$new_url" == *\?* ]]; then
            new_url="${new_url}&${leftover}"
        else
            new_url="${new_url}?${leftover}"
        fi
    fi

    echo -e "\n${CYAN}$(t modify_new_url "${GREEN}${new_url}${NC}")${NC}\n"
    save_and_install_config "$new_url" "$host" "$name" "true"
}

# ==================== Upgrade ====================
upgrade_nowhere() {
    local installed_version latest_version
    installed_version=$(get_installed_version)

    echo -e "${CYAN}$(t label_current_ver "${installed_version:-$(t not_installed)}")${NC}"

    local resolved
    resolved=$(resolve_upgrade_target)
    if [[ -n "$resolved" ]]; then
        latest_version="$resolved"
        echo -e "${CYAN}$(t label_target_ver "${latest_version#v}")${NC}"
        if [[ -n "$installed_version" && "$installed_version" == "${latest_version#v}" ]]; then
            log_info "$(t info_already_target "${latest_version#v}")"
        fi
    else
        latest_version=$(get_latest_version)
        echo -e "${CYAN}$(t label_latest_ver "${latest_version#v}")${NC}"

        if [[ -n "$installed_version" && "$installed_version" == "${latest_version#v}" ]]; then
            log_info "$(t info_already_latest "${latest_version#v}")"
            if [[ "$AUTO_MODE" != "upgrade" ]]; then
                read -rp "$(t prompt_force_reinstall)" force
                [[ "$force" =~ ^[Yy]$ ]] || return
            else
                log_info "$(t info_skip_force)"
                return
            fi
        fi
    fi

    if [[ -n "$installed_version" ]]; then
        local old_major new_major
        old_major=$(version_major "$installed_version")
        new_major=$(version_major "$latest_version")
        if [[ -n "$old_major" && -n "$new_major" && "$old_major" != "$new_major" ]]; then
            if [[ "$old_major" == "1" && "$new_major" == "2" ]]; then
                # Legacy 1.x -> 2.x notice keeps its own lighter confirmation.
                log_warn "$(t warn_v20_incompat)"
                if [[ "$AUTO_MODE" != "upgrade" && "$AUTO_MODE" != "install" ]]; then
                    local confirm=""
                    read -rp "$(t prompt_v20_upgrade)" confirm
                    [[ "$confirm" =~ ^[Yy]$ ]] || { log_info "$(t info_cancelled)"; return; }
                fi
            else
                # nw2 <-> nw3 wire cutover: preflight first, then explicit
                # consent. An explicit --version does not bypass the gate.
                if ! preflight_profile_switch "$old_major" "$new_major"; then
                    return 1
                fi
                log_warn "$(t warn_protocol_switch "$old_major" "$new_major")"
                if [[ -n "$ARG_ALLOW_BREAKING" ]]; then
                    log_info "$(t info_migrate_flag_accepted)"
                elif [[ -t 0 && "$AUTO_MODE" != "upgrade" && "$AUTO_MODE" != "install" ]]; then
                    local migrate_confirm=""
                    read -rp "$(t prompt_migrate_confirm)" migrate_confirm
                    [[ "$migrate_confirm" == "MIGRATE" ]] || { log_info "$(t info_cancelled)"; return; }
                else
                    log_error "$(t err_migrate_requires_flag)"
                    return 1
                fi
                if [[ -f "$URL_FILE" ]]; then
                    local url_backup
                    url_backup="${URL_FILE}.nw${old_major}.bak.$(date +%Y%m%d_%H%M%S)"
                    if cp "$URL_FILE" "$url_backup"; then
                        log_info "$(t warn_url_backed_up "$url_backup")"
                    fi
                fi
            fi
        fi
        # Nowhere 2.2+ enforces hex Portal keys and mandatory certificate
        # verification; existing Portal configs are migrated automatically.
        if ! version_ge "$installed_version" "2.2.0" && version_ge "$latest_version" "2.2.0"; then
            log_warn "$(t warn_v22_incompat)"
        fi
    fi

    if command -v nowhere &>/dev/null; then
        cp "${INSTALL_DIR}/nowhere" "${INSTALL_DIR}/nowhere.bak.$(date +%Y%m%d_%H%M%S)"
    fi

    local was_running=false
    if [[ "$INIT_SYSTEM" == "systemd" ]] && systemctl is-active --quiet ${SERVICE_NAME} 2>/dev/null; then
        was_running=true; stop_service
    elif [[ "$INIT_SYSTEM" == "openrc" ]] && rc-service ${SERVICE_NAME} status 2>/dev/null | grep -q started; then
        was_running=true; stop_service
    elif [[ "$INIT_SYSTEM" == "rc" ]] && service ${SERVICE_NAME} status >/dev/null 2>&1; then
        was_running=true; stop_service
    fi

    install_nowhere "$latest_version" true
    migrate_stored_url

    if [[ "$was_running" == "true" ]]; then
        start_service
        log_info "$(t info_svc_restarted)"
    fi
}

# ==================== One-click install (args + interactive) ====================
auto_install_nowhere() {
    if command -v nowhere &>/dev/null; then
        log_info "$(t warn_already_installed "$(get_installed_version)")"
        upgrade_nowhere
        return
    fi

    install_nowhere

    # Import nowhere:// / vector:// / portal:// / egress:// via --url and finish.
    if [[ -n "$ARG_URL" ]]; then
        log_info "$(t info_gen_config)"
        mkdir -p "$CONFIG_DIR"
        if ! apply_imported_url "$ARG_URL" "$ARG_SOCKS"; then
            log_error "$(t err_invalid_url "$ARG_URL")"
            return 1
        fi
        local ROLE="$IMPORTED_ROLE"
        if [[ "$ROLE" == "egress" ]] && ! is_nw3_profile; then
            log_error "$(t err_egress_requires_nw3)"
            return 1
        fi
        local url="$IMPORTED_URL" host="" name
        name=$(load_node_name)
        parse_url_authority "$url"
        if [[ "$ROLE" == "egress" ]]; then
            host="${ARG_HOST:-$PARSE_HOST}"
            if [[ -n "$ARG_KEY$ARG_HOST$ARG_UDP_PORT$ARG_SNI$ARG_PIN$ARG_MORPH" ]]; then
                local ekey eport esni epin emorph
                ekey="${ARG_KEY:-$PARSE_KEY}"
                eport="${ARG_UDP_PORT:-${PARSE_UDP_PORT:-$PARSE_PORT}}"
                esni="${ARG_SNI:-$(get_query_param "$url" "sni")}"
                epin="${ARG_PIN:-$(get_query_param "$url" "pin")}"
                emorph="${ARG_MORPH:-$(get_query_param "$url" "morph")}"
                url=$(build_egress_url "$ekey" "$host" "$eport" "$esni" "$epin" "$emorph") || return 1
            fi
        elif [[ "$ROLE" == "vector" ]]; then
            host="$PARSE_HOST"
            [[ -n "$ARG_HOST" ]] && host="$ARG_HOST"
            # Rebuild if CLI overrides present.
            if [[ -n "$ARG_KEY$ARG_HOST$ARG_PORT$ARG_SOCKS$ARG_UP$ARG_DOWN$ARG_MUX$ARG_SNI$ARG_PIN$ARG_ALPN$ARG_MORPH$ARG_TCP_PORT$ARG_UDP_PORT$ARG_NET$ARG_OUT" ]]; then
                local dc key port socks up down mux sni pin alpn morph tcp_port udp_port net ia
                dc=$(default_carrier)
                key="${ARG_KEY:-$PARSE_KEY}"
                port="${ARG_PORT:-$PARSE_PORT}"
                socks="${ARG_SOCKS:-$(url_decode_simple "$(get_query_param "$url" "in")")}"
                socks="${socks:-$(url_decode_simple "$(get_query_param "$url" "socks")")}"
                socks="${socks:-$DEFAULT_SOCKS_IN}"
                sni="${ARG_SNI:-$(get_query_param "$url" "sni")}"
                pin="${ARG_PIN:-$(get_query_param "$url" "pin")}"
                morph="${ARG_MORPH:-$(get_query_param "$url" "morph")}"
                alpn="$DEFAULT_ALPN"
                ia=$(get_query_param "$url" "alpn")
                [[ -n "$ia" ]] && alpn=$(url_decode_simple "$ia")
                [[ -n "$ARG_ALPN" ]] && alpn="$ARG_ALPN"
                host="${ARG_HOST:-$PARSE_HOST}"
                if is_nw3_profile; then
                    if [[ "$url" == */udp:* ]]; then
                        net="${ARG_NET:-udp}"
                    else
                        net="${ARG_NET:-tcp}"
                    fi
                    if [[ "$net" == "udp" ]]; then
                        udp_port="${ARG_UDP_PORT:-${PARSE_UDP_PORT:-$PARSE_PORT}}"
                        tcp_port=""
                    else
                        tcp_port="${ARG_TCP_PORT:-${PARSE_TCP_PORT:-$PARSE_PORT}}"
                        udp_port=""
                    fi
                    up=""; down=""; mux=""
                else
                    up="${ARG_UP:-$(get_query_param "$url" "up")}"
                    up="${up:-$dc}"
                    down="${ARG_DOWN:-$(get_query_param "$url" "down")}"
                    down="${down:-$dc}"
                    mux="${ARG_MUX:-$(get_query_param "$url" "mux")}"
                    if url_has_carrier_path "$url"; then
                        tcp_port="${ARG_TCP_PORT:-$PARSE_TCP_PORT}"
                        udp_port="${ARG_UDP_PORT:-$PARSE_UDP_PORT}"
                        net="${ARG_NET:-${PARSE_CARRIERS:-mix}}"
                    else
                        tcp_port="${ARG_TCP_PORT:-}"
                        udp_port="${ARG_UDP_PORT:-}"
                        net="${ARG_NET:-mix}"
                    fi
                fi
                url=$(build_vector_url "$key" "$host" "$port" "$up" "$down" "$socks" "$alpn" "$mux" "$sni" "$pin" "$morph" "$tcp_port" "$udp_port" "$net") || return 1
            fi
        else
            host="${ARG_HOST:-}"
            if [[ -n "$ARG_KEY$ARG_HOST$ARG_PORT$ARG_SOCKS$ARG_NEXT$ARG_UP$ARG_DOWN$ARG_MUX$ARG_SNI$ARG_PIN$ARG_ALPN$ARG_NET$ARG_TLS$ARG_MORPH$ARG_TCP_PORT$ARG_UDP_PORT$ARG_OUT" ]]; then
                local key="${ARG_KEY:-$PARSE_KEY}"
                local port="${ARG_PORT:-$PARSE_PORT}"
                local tls="${ARG_TLS:-$(get_query_param "$url" "tls")}"
                tls="${tls:-1}"
                local morph="${ARG_MORPH:-$(get_query_param "$url" "morph")}"
                local tcp_port udp_port
                if url_has_carrier_path "$url"; then
                    tcp_port="${ARG_TCP_PORT:-$PARSE_TCP_PORT}"
                    udp_port="${ARG_UDP_PORT:-$PARSE_UDP_PORT}"
                else
                    tcp_port="${ARG_TCP_PORT:-}"
                    udp_port="${ARG_UDP_PORT:-}"
                fi
                local alpn="$DEFAULT_ALPN"
                local ia
                ia=$(get_query_param "$url" "alpn")
                [[ -n "$ia" ]] && alpn=$(url_decode_simple "$ia")
                [[ -n "$ARG_ALPN" ]] && alpn="$ARG_ALPN"
                local crt="$DEFAULT_CERT" keyfile="$DEFAULT_KEYFILE"
                if [[ "$tls" == "2" ]]; then
                    crt="${ARG_CERT:-$(get_query_param "$url" "crt")}"
                    crt="${crt:-$DEFAULT_CERT}"
                    keyfile="${ARG_KEYFILE:-$(get_query_param "$url" "key")}"
                    keyfile="${keyfile:-$DEFAULT_KEYFILE}"
                fi
                local socks next up down mux sni pin net outbound
                if is_nw3_profile; then
                    # nw3 Portal exit replaces socks=/next= with out=.
                    local imported_out
                    imported_out=$(get_query_param "$url" "out")
                    if [[ -n "$ARG_OUT" ]]; then
                        outbound="$ARG_OUT"
                    else
                        case "$imported_out" in
                            egress) outbound="egress" ;;
                            direct|"") outbound="direct" ;;
                            *) outbound="socks" ;;
                        esac
                    fi
                    if [[ "$outbound" == "socks" ]]; then
                        socks="${ARG_SOCKS:-}"
                        if [[ -z "$socks" && -n "$imported_out" \
                              && "$imported_out" != "direct" && "$imported_out" != "egress" ]]; then
                            socks="$imported_out"
                        fi
                        if [[ -z "$socks" ]]; then
                            log_error "$(t err_out_socks_required)"
                            return 1
                        fi
                    else
                        socks=""
                    fi
                    next=""; up=""; down=""; mux=""; sni=""; pin=""; net="${ARG_NET:-mix}"
                else
                    load_portal_outbound_from_url "$url"
                    net="${ARG_NET:-$(get_query_param "$url" "net")}"
                    net="${net:-${PARSE_CARRIERS:-mix}}"
                    socks="${ARG_SOCKS:-$PORTAL_SOCKS}"
                    next="${ARG_NEXT:-$PORTAL_NEXT}"
                    up="${ARG_UP:-$PORTAL_UP}"
                    down="${ARG_DOWN:-$PORTAL_DOWN}"
                    mux="${ARG_MUX:-$PORTAL_MUX}"
                    sni="${ARG_SNI:-$PORTAL_SNI}"
                    pin="${ARG_PIN:-$PORTAL_PIN}"
                    outbound=""
                fi
                url=$(build_portal_url "$key" "$port" "$tls" "$net" "$alpn" "$crt" "$keyfile" "$socks" "$next" "$up" "$down" "$mux" "$sni" "$pin" "$morph" "$tcp_port" "$udp_port" "$outbound") || return 1
            fi
        fi
        echo "$url" > "$URL_FILE"
        save_share_host "$host"
        save_node_name "$name"
        write_launcher
        log_success "$(t ok_config_written "$URL_FILE")"
        echo -e "${CYAN}$(t label_run_url "${GREEN}${url}${NC}")${NC}"
        maybe_install_and_start_service
        return
    fi

    local ROLE="${ARG_TYPE:-portal}"
    case "$ROLE" in
        portal|vector|egress) ;;
        *)
            log_error "$(t err_invalid_type "$ROLE")"
            return 1
            ;;
    esac
    if [[ "$ROLE" == "egress" ]] && ! is_nw3_profile; then
        log_error "$(t err_egress_requires_nw3)"
        return 1
    fi

    log_info "$(t info_gen_config)"
    mkdir -p "$CONFIG_DIR"

    local dc key port alpn net tls host name url socks next up down mux sni pin morph tcp_port udp_port outbound
    dc=$(default_carrier)
    port=${ARG_PORT:-2077}
    alpn=${ARG_ALPN:-$DEFAULT_ALPN}
    net=${ARG_NET:-mix}
    tls=${ARG_TLS:-1}
    local cert_mode="$CERT_MODE_DEFAULT"
    if [[ -n "$ARG_CERT_MODE" ]]; then
        if ! cert_mode=$(normalize_cert_mode "$ARG_CERT_MODE"); then
            log_error "$(t err_cert_mode_invalid "$ARG_CERT_MODE")"
            return 1
        fi
    fi
    # --acme-domain is shorthand for --cert-mode acme.
    if [[ -n "$ARG_ACME_DOMAIN" && -z "$ARG_CERT_MODE" ]]; then
        cert_mode="acme"
    fi
    host=${ARG_HOST:-}
    name=$(load_node_name)
    socks=${ARG_SOCKS:-}
    next=${ARG_NEXT:-}
    up=${ARG_UP:-$dc}
    down=${ARG_DOWN:-$dc}
    mux=${ARG_MUX:-}
    sni=${ARG_SNI:-}
    pin=${ARG_PIN:-}
    morph=${ARG_MORPH:-}
    tcp_port=${ARG_TCP_PORT:-}
    udp_port=${ARG_UDP_PORT:-}
    outbound=${ARG_OUT:-direct}
    local morph_default="0"
    is_nw3_profile && morph_default="1"
    # On nw3, --socks is the compatibility alias for out=<SOCKS5 upstream>.
    if is_nw3_profile && [[ -z "$ARG_OUT" && -n "$ARG_SOCKS" ]]; then
        outbound="socks"
    fi

    if [[ -n "$ARG_KEY" ]]; then
        key="$ARG_KEY"
    else
        key=$(generate_random_key)
    fi

    if [[ "$ROLE" == "vector" ]]; then
        socks="${socks:-$DEFAULT_SOCKS_IN}"
        if [[ -t 0 && -z "$ARG_KEY" ]]; then
            echo -e "${CYAN}$(t info_random_key "${GREEN}${key}${NC}${CYAN}")${NC}"
            echo -e "${CYAN}$(t info_key_hint)${NC}"
            read -rp "$(t prompt_key "$key")" key_input
            [[ -n "$key_input" ]] && key="$key_input"

            read -rp "$(t prompt_portal_host "$host")" host_input
            [[ -n "$host_input" ]] && host="$host_input"

            if is_nw3_profile; then
                local carrier_input=""
                read -rp "$(t prompt_carrier_single "${net:-tcp}")" carrier_input
                carrier_input="${carrier_input:-${net:-tcp}}"
                if [[ "$carrier_input" != "tcp" && "$carrier_input" != "udp" ]]; then
                    log_error "$(t err_invalid_carrier "$carrier_input")"
                    return 1
                fi
                net="$carrier_input"
                local prev_port=""
                [[ -n "$existing_url" ]] && prev_port="$port"
                if [[ "$net" == "tcp" ]]; then
                    port=$(read_port_checked prompt_port "$port" "$prev_port")
                    tcp_port="$port"
                    udp_port=""
                else
                    port=$(read_port_checked prompt_udp_port "$port" "$prev_port")
                    udp_port="$port"
                    tcp_port=""
                fi
            else
                local prev_port=""
                [[ -n "$existing_url" ]] && prev_port="$port"
                port=$(read_port_checked prompt_port "$port" "$prev_port")

                if is_v2_profile; then
                    read -rp "$(t prompt_net "$net")" net_input
                    [[ -n "$net_input" ]] && net="$net_input"
                    prompt_v2_carrier_ports "$net" "$port" "$tcp_port" "$udp_port"
                    tcp_port="$OUT_TCP_PORT"
                    udp_port="$OUT_UDP_PORT"
                fi
            fi

            if is_nw3_profile; then
                read -rp "$(t prompt_socks_in "$socks")" socks_input
                [[ -n "$socks_input" ]] && socks="$socks_input"

                read -rp "$(t prompt_sni "$sni")" sni_input
                [[ -n "$sni_input" ]] && sni="$sni_input"

                read -rp "$(t prompt_morph "${morph:-$morph_default}")" morph_input
                [[ -n "$morph_input" ]] && morph="$morph_input"
            else
                read -rp "$(t prompt_up "$up")" up_input
                [[ -n "$up_input" ]] && up="$up_input"

                read -rp "$(t prompt_down "$down")" down_input
                [[ -n "$down_input" ]] && down="$down_input"

                if mux_applies "$up" "$down"; then
                    read -rp "$(t prompt_mux "${mux:-0}")" mux_input
                    [[ -n "$mux_input" ]] && mux="$mux_input"
                else
                    mux=""
                fi

                read -rp "$(t prompt_socks_in "$socks")" socks_input
                [[ -n "$socks_input" ]] && socks="$socks_input"

                read -rp "$(t prompt_sni "$sni")" sni_input
                [[ -n "$sni_input" ]] && sni="$sni_input"

                if is_v2_profile; then
                    read -rp "$(t prompt_morph "${morph:-$morph_default}")" morph_input
                    [[ -n "$morph_input" ]] && morph="$morph_input"
                else
                    read -rp "$(t prompt_alpn "$alpn")" alpn_input
                    [[ -n "$alpn_input" ]] && alpn="$alpn_input"
                fi
            fi

            read -rp "$(t prompt_name "$name")" name_input
            if [[ "$name_input" == "-" ]]; then
                name=""
            elif [[ -n "$name_input" ]]; then
                name="$name_input"
            fi
        fi
        if [[ -z "$host" ]]; then
            log_error "$(t err_portal_host_required)"
            return 1
        fi
        url=$(build_vector_url "$key" "$host" "$port" "$up" "$down" "$socks" "$alpn" "$mux" "$sni" "$pin" "$morph" "$tcp_port" "$udp_port" "$net") || return 1
    elif [[ "$ROLE" == "egress" ]]; then
        if [[ -t 0 && -z "$ARG_KEY" ]]; then
            echo -e "${CYAN}$(t info_configure_egress)${NC}"
            echo -e "${CYAN}$(t info_random_key "${GREEN}${key}${NC}${CYAN}")${NC}"
            echo -e "${CYAN}$(t info_key_hint)${NC}"
            read_key_checked "egress" "$key" || return 1
            key="$ENTERED_KEY"

            read -rp "$(t prompt_portal_host "$host")" host_input
            [[ -n "$host_input" ]] && host="$host_input"
            if [[ -z "$host" ]]; then
                log_error "$(t err_portal_host_required)"
                return 1
            fi

            local prev_port=""
            [[ -n "$existing_url" ]] && prev_port="$port"
            port=$(read_port_checked prompt_udp_port "$port" "$prev_port")
            udp_port="$port"

            read -rp "$(t prompt_sni "$sni")" sni_input
            [[ -n "$sni_input" ]] && sni="$sni_input"

            read -rp "$(t prompt_pin "$pin")" pin_input
            if [[ "$pin_input" == "-" ]]; then
                pin=""
            elif [[ -n "$pin_input" ]]; then
                pin="$pin_input"
            fi
            if [[ -z "$pin" ]]; then
                log_warn "$(t warn_pin_required)"
            fi

            read -rp "$(t prompt_morph "${morph:-$morph_default}")" morph_input
            [[ -n "$morph_input" ]] && morph="$morph_input"

            read -rp "$(t prompt_name "$name")" name_input
            if [[ "$name_input" == "-" ]]; then
                name=""
            elif [[ -n "$name_input" ]]; then
                name="$name_input"
            fi
        fi
        if [[ -z "$host" ]]; then
            log_error "$(t err_portal_host_required)"
            return 1
        fi
        url=$(build_egress_url "$key" "$host" "${udp_port:-$port}" "$sni" "$pin" "$morph") || return 1
    else
        if [[ -t 0 && -z "$ARG_KEY" ]]; then
            echo -e "${CYAN}$(t info_random_key "${GREEN}${key}${NC}${CYAN}")${NC}"
            echo -e "${CYAN}$(t info_key_hint)${NC}"
            read_key_checked "portal" "$key" || return 1
            key="$ENTERED_KEY"

            local prev_port=""
            [[ -n "$existing_url" ]] && prev_port="$port"
            port=$(read_port_checked prompt_port "$port" "$prev_port")

            read -rp "$(t prompt_net "$net")" net_input
            [[ -n "$net_input" ]] && net="$net_input"

            if is_v2_profile; then
                prompt_v2_carrier_ports "$net" "$port" "$tcp_port" "$udp_port"
                tcp_port="$OUT_TCP_PORT"
                udp_port="$OUT_UDP_PORT"
            fi

            read -rp "$(t prompt_cert_mode "$cert_mode")" cert_mode_input
            [[ -n "$cert_mode_input" ]] && cert_mode="$cert_mode_input"
            if ! cert_mode=$(normalize_cert_mode "$cert_mode"); then
                log_error "$(t err_cert_mode_invalid "$cert_mode_input")"
                return 1
            fi
            case "$cert_mode" in
                program) log_info "$(t info_cert_mode_program)" ;;
                openssl) log_info "$(t info_cert_mode_openssl)" ;;
                custom)  log_info "$(t info_cert_mode_custom)" ;;
                acme)    log_info "$(t info_cert_mode_acme)" ;;
            esac
            tls=$(cert_mode_tls "$cert_mode")

            read -rp "$(t prompt_tls "$tls")" tls_input
            [[ -n "$tls_input" ]] && tls="$tls_input"

            if is_v2_profile || is_nw3_profile; then
                read -rp "$(t prompt_morph "${morph:-$morph_default}")" morph_input
                [[ -n "$morph_input" ]] && morph="$morph_input"
            else
                read -rp "$(t prompt_alpn "$alpn")" alpn_input
                [[ -n "$alpn_input" ]] && alpn="$alpn_input"
            fi

            read -rp "$(t prompt_host "$host")" host_input
            if [[ "$host_input" == "-" ]]; then
                host=""
            elif [[ -n "$host_input" ]]; then
                host="$host_input"
            fi

            read -rp "$(t prompt_name "$name")" name_input
            if [[ "$name_input" == "-" ]]; then
                name=""
            elif [[ -n "$name_input" ]]; then
                name="$name_input"
            fi

            if ! collect_portal_outbound_interactive "$socks" "$next" "$up" "$down" "$mux" "$sni" "$pin"; then
                return 1
            fi
            socks="$OUT_SOCKS"
            next="$OUT_NEXT"
            up="$OUT_UP"
            down="$OUT_DOWN"
            mux="$OUT_MUX"
            sni="$OUT_SNI"
            pin="$OUT_PIN"
            outbound="$OUT_OUTBOUND"
        elif [[ -n "$ARG_NEXT" ]]; then
            next="$ARG_NEXT"
        fi
        if is_nw3_profile && [[ "$outbound" == "socks" && -z "$socks" ]]; then
            log_error "$(t err_out_socks_required)"
            return 1
        fi

        # The certificate source decides tls=; the tls= prompt above is a
        # read-only echo of that decision (kept for backward compatibility).
        tls=$(cert_mode_tls "$cert_mode")
        local interactive=false
        [[ -t 0 ]] && interactive=true
        if ! resolve_cert_mode "$cert_mode" "$host" "$([[ $interactive == true ]] && echo false || echo true)"; then
            return 1
        fi
        tls="$CERT_TLS"; crt="$CERT_CRT"; keyfile="$CERT_KEYFILE"

        url=$(build_portal_url "$key" "$port" "$tls" "$net" "$alpn" "$crt" "$keyfile" "$socks" "$next" "$up" "$down" "$mux" "$sni" "$pin" "$morph" "$tcp_port" "$udp_port" "$outbound") || return 1
    fi

    echo "$url" > "$URL_FILE"
    save_share_host "$host"
    save_node_name "$name"
    write_launcher
    log_success "$(t ok_config_written "$URL_FILE")"
    echo -e "${CYAN}$(t label_run_url "${GREEN}${url}${NC}")${NC}"
    log_info "$(t info_share_key "${GREEN}${key}${NC}")"
    maybe_install_and_start_service
}

# ==================== Share URI ====================
# nw3 share output: a Portal endpoint binds * with one or two carriers, so each
# carrier gets its own anywhere:// import link (net=tcp / net=udp) and the QR
# encodes the TCP link when one exists. Self-signed Portals (tls=1) still need
# pin=, fetched from the running service exactly like the v2 path.
show_share_uri_nw3() {
    local server_url="$1"
    local key morph_mode tls_mode tcp_port udp_port
    parse_url_authority "$server_url"
    key="$PARSE_KEY"
    morph_mode=$(get_query_param "$server_url" "morph")
    tls_mode=$(get_query_param "$server_url" "tls")
    tls_mode=${tls_mode:-1}
    if url_has_carrier_path "$server_url"; then
        tcp_port="$PARSE_TCP_PORT"
        udp_port="$PARSE_UDP_PORT"
    else
        tcp_port="${PARSE_PORT:-2077}"
        udp_port="$tcp_port"
    fi

    local share_host
    share_host=$(load_share_host)
    [[ -z "$share_host" ]] && share_host=$(get_public_ip)
    [[ -z "$share_host" ]] && share_host="127.0.0.1"

    local node_name frag=""
    node_name=$(load_node_name)
    [[ -n "$node_name" ]] && frag="#$(url_encode_name "$node_name")"

    # tls=2 splits two ways: an openssl self-signed Portal is pinned (the client
    # verifies the exact certificate and ignores the hostname), while a custom
    # certificate is verified through sni= against the system trust store.
    local sni_param="" pin_param=""
    if [[ "$tls_mode" == "2" ]]; then
        local stored_pin
        stored_pin=$(load_pin)
        if [[ -n "$stored_pin" ]]; then
            pin_param="&pin=${stored_pin}"
            fingerprint="$stored_pin"
        else
            local stored_host
            stored_host=$(load_share_host)
            if [[ -n "$stored_host" ]]; then
                sni_param="&sni=${stored_host}"
            else
                log_warn "$(t warn_sni_missing)"
            fi
        fi
    fi

    if [[ "$tls_mode" == "1" && -n "$tcp_port" ]]; then
        local probe_url="nowhere://${key}@127.0.0.1:${tcp_port}?net=tcp"
        [[ -n "$morph_mode" ]] && probe_url="${probe_url}&morph=${morph_mode}"
        fingerprint=$(get_portal_fingerprint "$probe_url")
    fi

    local tcp_link="" udp_link="" qr_link="" link
    if [[ -n "$tcp_port" ]]; then
        link="nowhere://${key}@${share_host}:${tcp_port}?net=tcp"
        [[ -n "$morph_mode" ]] && link="${link}&morph=${morph_mode}"
        link="${link}${sni_param}${pin_param}"
        [[ -n "$fingerprint" && -z "$pin_param" ]] && link="${link}&pin=${fingerprint}"
        tcp_link="${link}${frag}"
        qr_link="$tcp_link"
    fi
    if [[ -n "$udp_port" ]]; then
        link="nowhere://${key}@${share_host}:${udp_port}?net=udp"
        [[ -n "$morph_mode" ]] && link="${link}&morph=${morph_mode}"
        link="${link}${sni_param}${pin_param}"
        [[ -n "$fingerprint" && -z "$pin_param" ]] && link="${link}&pin=${fingerprint}"
        udp_link="${link}${frag}"
        [[ -z "$qr_link" ]] || qr_link="$udp_link"
    fi

    echo -e "\n${CYAN}$(t share_title)${NC}"
    if [[ -n "$tcp_link" ]]; then
        echo -e "${CYAN}$(t label_share_link_tcp)${NC}\n${GREEN}${tcp_link}${NC}\n"
    fi
    if [[ -n "$udp_link" ]]; then
        echo -e "${CYAN}$(t label_share_link_udp)${NC}\n${GREEN}${udp_link}${NC}\n"
    fi
    if [[ -n "$fingerprint" ]]; then
        echo -e "${CYAN}$(t label_fingerprint "${GREEN}${fingerprint}${NC}")${NC}\n"
    fi

    local qr_tool
    qr_tool=$(qr_support_available || true)
    if [[ -n "$qr_link" && "$qr_tool" == "qrencode" ]]; then
        echo -e "${CYAN}$(t label_qr)${NC}\n"
        qrencode -t ANSI -m 2 "$qr_link" || true
        echo ""
    elif [[ -n "$qr_link" && "$qr_tool" == "python3-qrcode" ]]; then
        echo -e "${CYAN}$(t label_qr)${NC}\n"
        python3 -c "import qrcode,sys; qr=qrcode.QRCode(border=2); qr.add_data(sys.argv[1]); qr.make(); qr.print_tty()" "$qr_link" || true
        echo ""
    fi

    if [[ "$tls_mode" == "1" ]]; then
        if [[ -n "$fingerprint" ]]; then
            log_warn "$(t warn_pin_changes)"
        else
            log_warn "$(t warn_pin_required)"
            log_warn "$(t warn_pin_unavailable)"
        fi
    elif [[ "$tls_mode" == "2" && -z "$pin_param" ]]; then
        # Custom certificate without a share host: clients cannot verify it.
        if [[ -z "$(load_share_host)" ]]; then
            log_warn "$(t warn_sni_missing)"
        fi
    fi

    echo -e "${CYAN}========================================${NC}\n"
}

show_share_uri() {
    if [[ ! -f "$URL_FILE" ]]; then
        log_warn "$(t warn_no_config)"
        return
    fi

    migrate_stored_url

    local server_url client_uri share_host tls_mode net_mode alpn_raw qr_tool key port node_name
    server_url=$(tr -d '\n' < "$URL_FILE")

    local role
    role=$(detect_url_role "$server_url")
    if [[ "$role" == "egress" ]]; then
        # nw3 Egress dials out to the Portal; there is no inbound port and no
        # client-side import link, so only the run URL is shared.
        echo -e "\n${CYAN}$(t share_title)${NC}"
        echo -e "${CYAN}$(t label_run_url_status "${GREEN}${server_url}${NC}")${NC}"
        log_info "$(t info_egress_no_inbound)"
        echo -e "${CYAN}========================================${NC}\n"
        return
    fi
    if [[ "$role" == "vector" ]]; then
        echo -e "\n${CYAN}$(t share_title)${NC}"
        log_warn "$(t warn_share_vector)"
        echo -e "${CYAN}$(t label_run_url_status "${GREEN}${server_url}${NC}")${NC}"
        echo -e "${CYAN}========================================${NC}\n"
        return
    fi
    if is_nw3_profile; then
        show_share_uri_nw3 "$server_url"
        return
    fi

    parse_url_authority "$server_url"
    key="$PARSE_KEY"
    port="${PARSE_PORT:-2077}"

    tls_mode=$(get_query_param "$server_url" "tls")
    tls_mode=${tls_mode:-1}
    local morph_mode
    morph_mode=$(get_query_param "$server_url" "morph")
    local net_mode
    net_mode=$(get_query_param "$server_url" "net")
    net_mode="${net_mode:-${PARSE_CARRIERS:-mix}}"
    alpn_raw=$(get_query_param "$server_url" "alpn")

    if [[ -n "$(get_query_param "$server_url" "next")" ]]; then
        log_warn "$(t warn_share_chain)"
    fi

    share_host=$(load_share_host)
    if [[ -z "$share_host" ]]; then
        share_host=$(get_public_ip)
    fi
    if [[ -z "$share_host" ]]; then
        share_host="127.0.0.1"
    fi

    node_name=$(load_node_name)

    if is_v2_profile && { [[ -n "$PARSE_TCP_PORT" && -n "$PARSE_UDP_PORT" && "$PARSE_TCP_PORT" != "$PARSE_UDP_PORT" ]] || url_has_carrier_path "$server_url"; }; then
        client_uri="nowhere://${key}@$(build_endpoint_hostpart "vector" "$share_host" "$PARSE_TCP_PORT" "$PARSE_UDP_PORT")"
    else
        client_uri="nowhere://${key}@${share_host}:${port}"
    fi

    local share_up share_down
    case "$net_mode" in
        tcp) share_up="tcp"; share_down="tcp" ;;
        udp) share_up="udp"; share_down="udp" ;;
        *) share_up="$net_mode"; share_down="$net_mode" ;;
    esac
    # Clients do not accept mix. Rewrite each direction on its own:
    # up=mix becomes up=udp, down=mix becomes down=udp. tcp/udp stay.
    [[ "$share_up" == "mix" ]] && share_up="udp"
    [[ "$share_down" == "mix" ]] && share_down="udp"
    client_uri=$(append_query_param "$client_uri" "up=${share_up}")
    client_uri=$(append_query_param "$client_uri" "down=${share_down}")
    if ! is_v2_profile && [[ "$share_up" == "tcp" && "$share_down" == "tcp" ]]; then
        client_uri=$(append_query_param "$client_uri" "mux=1")
    fi

    if [[ "$morph_mode" == "1" ]]; then
        client_uri=$(append_query_param "$client_uri" "morph=1")
    fi

    # tls=2 splits two ways: an openssl self-signed Portal is pinned (the client
    # verifies the exact certificate and ignores the hostname), while a custom
    # certificate is verified through sni= against the system trust store.
    local stored_pin=""
    stored_pin=$(load_pin)
    if [[ "$tls_mode" == "2" && -n "$stored_pin" ]]; then
        client_uri=$(append_query_param "$client_uri" "pin=${stored_pin}")
        fingerprint="$stored_pin"
    elif [[ "$tls_mode" == "2" ]]; then
        local stored_host
        stored_host=$(load_share_host)
        if [[ -n "$stored_host" ]]; then
            client_uri=$(append_query_param "$client_uri" "sni=${stored_host}")
        else
            log_warn "$(t warn_sni_missing)"
        fi
    fi

    if [[ -n "$alpn_raw" ]] && ! is_v2_profile; then
        local decoded_alpn
        decoded_alpn=$(url_decode_simple "$alpn_raw")
        if [[ -n "$decoded_alpn" && "$decoded_alpn" != "$DEFAULT_ALPN" ]]; then
            client_uri=$(append_query_param "$client_uri" "alpn=${alpn_raw}")
        fi
    fi

    # Nowhere 2.2+ verifies Portal certificates by default: a self-signed Portal
    # (tls=1) requires pin= in the client URL. Embed the fingerprint when the
    # running service can provide it. An openssl self-signed Portal (tls=2)
    # already carries its stable pin above.
    local fingerprint=""
    local probe_tcp_port="${PARSE_TCP_PORT}"
    if [[ -z "$probe_tcp_port" ]] && ! url_has_carrier_path "$server_url" && [[ -n "$PARSE_PORT" ]]; then
        # Compact endpoint (host:port) listens on both carriers with one port.
        probe_tcp_port="$PARSE_PORT"
    fi
    if is_v22_profile && [[ -n "$probe_tcp_port" ]]; then
        local probe_url="nowhere://${key}@127.0.0.1/tcp:${probe_tcp_port}"
        [[ "$morph_mode" == "1" ]] && probe_url=$(append_query_param "$probe_url" "morph=1")
        fingerprint=$(get_portal_fingerprint "$probe_url")
        if [[ -n "$fingerprint" && "$tls_mode" == "1" ]]; then
            client_uri=$(append_query_param "$client_uri" "pin=${fingerprint}")
        fi
    fi

    if [[ -n "$node_name" ]]; then
        client_uri="${client_uri}#$(url_encode_name "$node_name")"
    fi

    echo -e "\n${CYAN}$(t share_title)${NC}"
    echo -e "${CYAN}$(t label_client_uri)${NC}\n${GREEN}${client_uri}${NC}\n"

    if is_v22_profile && [[ -n "$fingerprint" ]]; then
        echo -e "${CYAN}$(t label_fingerprint "${GREEN}${fingerprint}${NC}")${NC}\n"
    fi

    qr_tool=$(qr_support_available || true)
    if [[ "$qr_tool" == "qrencode" ]]; then
        echo -e "${CYAN}$(t label_qr)${NC}\n"
        qrencode -t ANSI -m 2 "$client_uri" || true
        echo ""
    elif [[ "$qr_tool" == "python3-qrcode" ]]; then
        echo -e "${CYAN}$(t label_qr)${NC}\n"
        python3 -c "import qrcode,sys; qr=qrcode.QRCode(border=2); qr.add_data(sys.argv[1]); qr.make(); qr.print_tty()" "$client_uri" || true
        echo ""
    fi

    if [[ "$tls_mode" == "1" ]]; then
        if is_v22_profile; then
            if [[ -n "$fingerprint" ]]; then
                log_warn "$(t warn_pin_changes)"
            else
                log_warn "$(t warn_pin_required)"
                log_warn "$(t warn_pin_unavailable)"
            fi
        else
            log_warn "$(t warn_tls_skip)"
        fi
    fi

    echo -e "${CYAN}========================================${NC}\n"
}

# ==================== QR dependency install ====================
install_qr_support() {
    local existing
    if existing=$(qr_support_available); then
        log_success "$(t qr_ready "$existing")"
        return 0
    fi

    if [[ "$PKG_MANAGER" == "apt" ]]; then
        log_warn "$(t qr_warn_apt)"
    elif [[ "$PKG_MANAGER" == "apk" ]]; then
        log_warn "$(t qr_warn_apk)"
    elif [[ "$PKG_MANAGER" == "pkg" ]]; then
        log_warn "$(t qr_warn_pkg)"
    else
        log_error "$(t err_qr_install)"
        return 1
    fi

    read -rp "$(t prompt_qr_confirm)" confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log_info "$(t info_cancelled)"
        return 0
    fi

    log_info "$(t info_qr_installing)"
    set +e
    if [[ "$PKG_MANAGER" == "apt" ]]; then
        apt-get update -qq && apt-get install -y qrencode
    elif [[ "$PKG_MANAGER" == "apk" ]]; then
        apk add --no-cache python3 py3-qrcode
    else
        pkg install -y libqrencode
    fi
    local rc=$?
    set -e

    if [[ $rc -ne 0 ]] || ! qr_support_available >/dev/null; then
        log_error "$(t err_qr_install)"
        return 1
    fi

    log_success "$(t ok_qr_installed "$(t menu_share)")"
}

# ==================== Language selection ====================
select_language() {
    local choice
    echo ""
    echo -e "${CYAN}Select language / 选择语言 / Выберите язык${NC}"
    echo -e "  ${YELLOW}1)${NC} English"
    echo -e "  ${YELLOW}2)${NC} 中文"
    echo -e "  ${YELLOW}3)${NC} Русский"
    read -rp "[1-3]: " choice
    case "$choice" in
        1) set_language "en" ;;
        3) set_language "ru" ;;
        *) set_language "zh" ;;
    esac
    log_info "$(t info_lang_set "$SCRIPT_LANG")"
}

# ==================== Status ====================
show_status() {
    migrate_stored_url
    echo -e "\n${CYAN}$(t status_title)${NC}"
    echo -e "$(t label_script "${GREEN}${SCRIPT_VERSION}${NC}")"
    if command -v nowhere &>/dev/null; then
        echo -e "$(t label_binary "${GREEN}${INSTALL_DIR}/nowhere${NC}")"
        local installed_ver
        installed_ver=$(get_installed_version)
        echo -e "$(t label_version "${GREEN}${installed_ver}${NC}")"
        if [[ -z "$installed_ver" ]]; then
            log_warn "$(t warn_binary_unusable "$(binary_probe_error "$(command -v nowhere)")")"
        fi
    else
        echo -e "$(t label_version "${RED}$(t not_installed)${NC}")"
    fi
    echo -e "$(t label_system "${GREEN}${OS_ID}" "${OS_VERSION_ID}${NC}")"
    echo -e "$(t label_arch_libc "${GREEN}${ARCH}" "${LIBC}${NC}")"
    if [[ -f "$URL_FILE" ]]; then
        local run_url role socks_val next_val cert_mode crt_path tls_mode
        run_url=$(tr -d '\n' < "$URL_FILE")
        role=$(detect_url_role "$run_url")
        role="${role:-unknown}"
        socks_val=$(get_query_param "$run_url" "socks")
        next_val=$(get_query_param "$run_url" "next")
        echo -e "$(t label_role "${GREEN}${role}${NC}")"
        echo -e "$(t label_config_file "${GREEN}${URL_FILE}${NC}")"
        echo -e "$(t label_run_url_status "${GREEN}${run_url}${NC}")"
        if [[ "$role" == "portal" ]]; then
            # Certificate source and, for a file-backed certificate, its expiry.
            cert_mode=$(detect_cert_mode "$run_url")
            tls_mode=$(get_query_param "$run_url" "tls"); tls_mode=${tls_mode:-1}
            crt_path=$(get_query_param "$run_url" "crt")
            if [[ -n "$crt_path" ]]; then
                local cert_desc="$cert_mode"
                if [[ -n "$(load_pin)" ]]; then
                    cert_desc="${cert_mode} (pin $(load_pin | cut -c1-8)…)"
                fi
                echo -e "$(t label_cert_mode "${GREEN}${cert_desc}${NC}")"
                if [[ "$cert_mode" == "acme" ]]; then
                    local acme_domain acme_autorenew acme_renewdays
                    acme_domain=$(load_cert_mode_field domain)
                    acme_autorenew=$(load_cert_mode_field autorenew)
                    acme_renewdays=$(load_cert_mode_field renewdays)
                    [[ -n "$acme_domain" ]] && \
                        echo -e "$(t label_acme_domain "${GREEN}${acme_domain}${NC}")"
                    if [[ "$acme_autorenew" == "yes" ]]; then
                        echo -e "$(t label_acme_renewal "${GREEN}$(t acme_renewal_on "$ACME_CRON_SCHEDULE" "$acme_renewdays")${NC}")"
                    else
                        echo -e "$(t label_acme_renewal "${YELLOW}$(t acme_renewal_off)${NC}")"
                    fi
                fi
                if [[ -f "$crt_path" ]]; then
                    local not_after days_left now_epoch end_epoch
                    not_after=$(cert_not_after "$crt_path") || not_after=""
                    if [[ -n "$not_after" ]]; then
                        echo -e "$(t label_cert_expires "${GREEN}${not_after}${NC}")"
                        now_epoch=$(date -u +%s)
                        end_epoch=$(date -u -d "$not_after" +%s 2>/dev/null || echo "")
                        if [[ -n "$end_epoch" ]]; then
                            days_left=$(( (end_epoch - now_epoch) / 86400 ))
                            if (( days_left < 0 )); then
                                log_warn "$(t warn_cert_expired "$not_after")"
                            elif (( days_left <= 30 )); then
                                log_warn "$(t warn_cert_expiring "$days_left" "$not_after")"
                            fi
                        fi
                    fi
                else
                    log_warn "$(t warn_cert_file_missing "$crt_path")"
                fi
            elif [[ "$tls_mode" == "1" ]]; then
                echo -e "$(t label_cert_mode "${GREEN}${cert_mode}${NC}")"
            fi
        fi
        if is_nw3_profile; then
            # nw3 Portal exits via out=; nw3 Vector listens via in=.
            local nw3_out nw3_in
            nw3_out=$(get_query_param "$run_url" "out")
            nw3_in=$(url_decode_simple "$(get_query_param "$run_url" "in")")
            if [[ -n "$nw3_out" ]]; then
                echo -e "$(t label_out "${GREEN}${nw3_out}${NC}")"
            fi
            if [[ -n "$nw3_in" ]]; then
                echo -e "$(t label_in "${GREEN}${nw3_in}${NC}")"
            fi
        else
            if [[ -n "$socks_val" ]]; then
                echo -e "$(t label_socks "${GREEN}$(url_decode_simple "$socks_val")${NC}")"
            fi
            if [[ -n "$next_val" ]]; then
                echo -e "$(t label_next "${GREEN}$(url_decode_simple "$next_val")${NC}")"
            fi
        fi
    else
        echo -e "$(t label_config_file "${YELLOW}$(t not_configured)${NC}")"
    fi
    echo -e "\n${CYAN}$(t label_svc_status)${NC}"
    service_status
    echo -e "${CYAN}==================================${NC}\n"
}

launch_tui() {
    if ! command -v nowhere &>/dev/null; then
        log_error "$(t err_binary_missing)"
        return 1
    fi
    local inst_major
    inst_major=$(version_major "$(get_installed_version)")
    if [[ "$inst_major" == "3" ]]; then
        # nw3 replaced the TUI with a read-only status snapshot.
        log_info "$(t info_launching_status)"
        nowhere status
        return
    fi
    log_info "$(t info_launching_tui)"
    # TUI is read-only and does not own service lifecycle.
    nowhere tui || nowhere
}

get_running_script_path() {
    local src="${BASH_SOURCE[0]}"
    while [[ -L "$src" ]]; do
        local link_dir
        link_dir=$(cd -P "$(dirname "$src")" && pwd)
        src=$(readlink "$src")
        [[ "$src" != /* ]] && src="$link_dir/$src"
    done
    local dir
    dir=$(cd -P "$(dirname "$src")" && pwd)
    echo "${dir}/$(basename "$src")"
}

# Reads a SCRIPT_VERSION="x.y.z" assignment without executing the file.
read_script_version_file() {
    local file="$1" ver=""
    [[ -f "$file" ]] || return 1
    ver=$(sed -n 's/^SCRIPT_VERSION="\([0-9][0-9.]*\)"$/\1/p' "$file" | head -n1)
    [[ -n "$ver" ]] || return 1
    printf '%s' "$ver"
}

upgrade_oh_nowhere_script() {
    local script_path tmp_new backup_path
    script_path=$(get_running_script_path)

    log_info "$(t info_upgrading_script)"
    echo -e "$(t label_script_path "${CYAN}${script_path}${NC}")"

    tmp_new=$(mktemp /tmp/oh-nowhere.XXXXXX.sh) || {
        log_error "$(t err_script_download)"
        return 1
    }

    if ! curl -fsSL --connect-timeout 15 --max-time 60 "$SCRIPT_RAW_URL" -o "$tmp_new"; then
        rm -f "$tmp_new"
        log_error "$(t err_script_download)"
        return 1
    fi

    if ! bash -n "$tmp_new"; then
        rm -f "$tmp_new"
        log_error "$(t err_script_verify)"
        return 1
    fi

    local remote_ver=""
    remote_ver=$(read_script_version_file "$tmp_new" || true)
    if [[ -n "$remote_ver" && "$remote_ver" != "$SCRIPT_VERSION" ]]; then
        log_info "$(t info_script_versions "$SCRIPT_VERSION" "$remote_ver")"
        if ! version_ge "$remote_ver" "$SCRIPT_VERSION"; then
            log_warn "$(t warn_script_older "$remote_ver" "$SCRIPT_VERSION")"
        fi
    fi

    if cmp -s "$script_path" "$tmp_new" 2>/dev/null; then
        rm -f "$tmp_new"
        log_info "$(t info_script_already_latest)"
        return 0
    fi

    if [[ "$AUTO_MODE" != "upgrade-script" ]]; then
        local confirm=""
        read -rp "$(t prompt_script_upgrade_confirm)" confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            rm -f "$tmp_new"
            log_info "$(t info_cancelled)"
            return 0
        fi
    fi

    backup_path="${script_path}.bak.$(date +%Y%m%d_%H%M%S)"
    if ! cp "$script_path" "$backup_path"; then
        rm -f "$tmp_new"
        log_error "$(t err_script_install)"
        return 1
    fi

    if ! install -m 755 "$tmp_new" "$script_path"; then
        rm -f "$tmp_new"
        log_error "$(t err_script_install)"
        return 1
    fi
    rm -f "$tmp_new"

    log_success "$(t ok_script_upgraded "$backup_path")"
    log_info "$(t info_script_restart_hint)"
    return 0
}

# ==================== Interactive menu ====================
# Single source for display order and dispatch. An empty entry prints a blank
# line between groups. Exit is always option 0 and is not part of this list.
MENU_ACTIONS=(
    install
    upgrade
    pin_version
    ""
    configure
    modify
    ""
    start
    stop
    restart
    status
    renew
    tui
    ""
    share
    qr
    ""
    lang
    upgrade_script
    uninstall
)

menu_action_count() {
    local n=0 id
    for id in "${MENU_ACTIONS[@]}"; do
        if [[ -n "$id" ]]; then
            n=$((n + 1))
        fi
    done
    printf '%s' "$n"
}

menu_action_at() {
    local want="$1" n=0 id
    for id in "${MENU_ACTIONS[@]}"; do
        [[ -z "$id" ]] && continue
        n=$((n + 1))
        if [[ "$n" == "$want" ]]; then
            printf '%s' "$id"
            return 0
        fi
    done
    return 1
}

run_menu_action() {
    case "$1" in
        install) auto_install_nowhere ;;
        upgrade) upgrade_nowhere ;;
        pin_version) install_specific_version ;;
        configure) configure_nowhere ;;
        modify) modify_configuration ;;
        start) start_service; log_success "$(t ok_start_sent)" ;;
        stop) stop_service; log_success "$(t ok_stop_sent)" ;;
        restart) restart_service; log_success "$(t ok_restart_sent)" ;;
        status) show_status ;;
        renew) renew_cert_action ;;
        tui) launch_tui ;;
        share) show_share_uri ;;
        qr) install_qr_support ;;
        lang) select_language ;;
        upgrade_script) upgrade_oh_nowhere_script ;;
        uninstall) uninstall_nowhere ;;
        *) log_error "$(t err_invalid_choice)" ;;
    esac
}

show_menu() {
    clear 2>/dev/null || true
    local version
    version="$(t not_installed)"
    command -v nowhere &>/dev/null && version=$(get_installed_version)

    local svc_label
    if ! command -v nowhere &>/dev/null; then
        svc_label="${YELLOW}$(t menu_svc_not_installed)${NC}"
    elif service_is_active; then
        svc_label="${GREEN}$(t menu_svc_running)${NC}"
    else
        svc_label="${RED}$(t menu_svc_stopped)${NC}"
    fi

    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}$(t menu_title)${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo -e "$(t menu_script "${CYAN}${SCRIPT_VERSION}${NC}")"
    echo -e "$(t menu_version "${CYAN}${version}${NC}")"
    echo -e "$(t menu_service "$svc_label")"
    echo -e "$(t menu_system "${CYAN}${OS_ID}" "${OS_VERSION_ID}${NC}")"
    echo -e "$(t menu_arch "${CYAN}${ARCH}" "${LIBC}${NC}")"
    echo -e "${GREEN}========================================${NC}"
    local n=0 id
    for id in "${MENU_ACTIONS[@]}"; do
        if [[ -z "$id" ]]; then
            echo ""
            continue
        fi
        n=$((n + 1))
        echo -e "  ${YELLOW}${n})${NC} $(t "menu_${id}")"
    done
    echo -e "  ${YELLOW}0)${NC} $(t menu_exit)"
    echo -e "${GREEN}========================================${NC}"
}

run_menu() {
    if [[ -z "$ARG_LANG" ]]; then
        select_language
    fi

    while true; do
        show_menu
        read -rp "$(t prompt_menu "$(menu_action_count)")" choice

        if [[ "$choice" == "0" ]]; then
            log_info "$(t info_exit)"
            exit 0
        fi

        local action=""
        if [[ "$choice" =~ ^[0-9]+$ ]]; then
            action=$(menu_action_at "$choice") || true
        fi
        if [[ -n "$action" ]]; then
            run_menu_action "$action"
        else
            log_error "$(t err_invalid_choice)"
        fi

        echo ""
        if [[ -t 0 ]]; then
            read -rp "$(t prompt_continue)"
        fi
    done
}

# ==================== Argument parsing ====================
show_help() {
    cat <<EOF
$(t help_title)  (oh-nowhere ${SCRIPT_VERSION})

$(t help_usage)
  bash oh-nowhere.sh [options]

$(t help_options)
$(t help_opt_install)
$(t help_opt_upgrade)
$(t help_opt_allow_breaking)
$(t help_opt_config)
$(t help_opt_status)
$(t help_opt_share)
$(t help_opt_tui)
$(t help_opt_upgrade_script)
$(t help_opt_uninstall)
$(t help_opt_type)
$(t help_opt_url)
$(t help_opt_key)
$(t help_opt_port)
$(t help_opt_alpn)
$(t help_opt_host)
$(t help_opt_name)
$(t help_opt_net)
$(t help_opt_tls)
$(t help_opt_cert)
$(t help_opt_keyfile)
$(t help_opt_cert_mode)
$(t help_opt_self_sign_days "$SELF_SIGN_DAYS_DEFAULT")
$(t help_opt_cert_san)
$(t help_opt_acme_domain)
$(t help_opt_acme_email)
$(t help_opt_acme_challenge)
$(t help_opt_acme_dns)
$(t help_opt_acme_auto_renew)
$(t help_opt_acme_renew_days)
$(t help_opt_renew_cert)
$(t help_opt_socks)
$(t help_opt_out)
$(t help_opt_next)
$(t help_opt_up)
$(t help_opt_down)
$(t help_opt_mux)
$(t help_opt_tcp_port)
$(t help_opt_udp_port)
$(t help_opt_morph)
$(t help_opt_sni)
$(t help_opt_pin)
$(t help_opt_version)
$(t help_opt_script_version)
$(t help_opt_lang)
$(t help_opt_help)

$(t help_no_opt)

$(t help_examples)
  bash oh-nowhere.sh --install --key a1b2c3d4e5f60718293a4b5c6d7e8f90 --port 2088
  bash oh-nowhere.sh --install --key a1b2c3d4e5f60718293a4b5c6d7e8f90 --cert-mode custom --cert /path/cert.pem --keyfile /path/key.pem --host relay.example
  bash oh-nowhere.sh --install --key a1b2c3d4e5f60718293a4b5c6d7e8f90 --cert-mode openssl --self-sign-days 398 --host relay.example
  bash oh-nowhere.sh --install --key a1b2c3d4e5f60718293a4b5c6d7e8f90 --acme-domain relay.example.com --acme-email me@example.com --host relay.example.com
  bash oh-nowhere.sh --install --key a1b2c3d4e5f60718293a4b5c6d7e8f90 --acme-domain relay.example.com --acme-dns dns_cf --host relay.example.com
  bash oh-nowhere.sh --renew-cert
  bash oh-nowhere.sh --install --type vector --key a1b2c3d4e5f60718293a4b5c6d7e8f90 --host relay.example --socks 127.0.0.1:1080
  bash oh-nowhere.sh --install --type vector --key a1b2c3d4e5f60718293a4b5c6d7e8f90 --host relay.example --up mix --down mix --socks 127.0.0.1:1080
  bash oh-nowhere.sh --install --tcp-port 2006 --udp-port 2017 --morph 1 --key a1b2c3d4e5f60718293a4b5c6d7e8f90
  bash oh-nowhere.sh --install --type portal --key a1b2c3d4e5f60718293a4b5c6d7e8f90 --next '00112233445566778899aabbccddeeff@origin.example:2077' --up udp --down udp
  bash oh-nowhere.sh --install --type egress --key a1b2c3d4e5f60718293a4b5c6d7e8f90 --host relay.example --udp-port 2077
  bash oh-nowhere.sh --install --out socks --socks 127.0.0.1:1080 --key a1b2c3d4e5f60718293a4b5c6d7e8f90
  bash oh-nowhere.sh --upgrade --allow-protocol-breaking-upgrade
  bash oh-nowhere.sh --config --url 'nowhere://a1b2c3d4e5f60718293a4b5c6d7e8f90@relay.example:2077?up=tcp&down=tcp'
  bash oh-nowhere.sh -l en --status
  bash oh-nowhere.sh --tui
  bash oh-nowhere.sh --upgrade-script --lang en
  bash oh-nowhere.sh --version v2.0.0 --install --key a1b2c3d4e5f60718293a4b5c6d7e8f90
  bash oh-nowhere.sh --version v1.8.3 --install --key mysecret
EOF
}

parse_args() {
    AUTO_MODE=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -i|--install)       AUTO_MODE="install" ;;
            -u|--upgrade)       AUTO_MODE="upgrade" ;;
            -c|--config)        AUTO_MODE="config" ;;
            -s|--status)        AUTO_MODE="status" ;;
            -q|--share)         AUTO_MODE="share" ;;
            --tui)              AUTO_MODE="tui" ;;
            --upgrade-script)   AUTO_MODE="upgrade-script" ;;
            --uninstall)        AUTO_MODE="uninstall" ;;
            --type)             ARG_TYPE="$2"; shift ;;
            --url)              ARG_URL="$2"; shift ;;
            --out)
                ARG_OUT="$2"
                case "$ARG_OUT" in
                    direct|socks|egress) ;;
                    *)
                        log_error "$(t err_invalid_out "$ARG_OUT")"
                        exit 1
                        ;;
                esac
                shift
                ;;
            --allow-protocol-breaking-upgrade)
                ARG_ALLOW_BREAKING="1"
                ;;
            -k|--key)           ARG_KEY="$2"; shift ;;
            -p|--port)          ARG_PORT="$2"; shift ;;
            --alpn)             ARG_ALPN="$2"; shift ;;
            --host)             ARG_HOST="$2"; shift ;;
            --name)             ARG_NAME="$2"; shift ;;
            --socks)            ARG_SOCKS="$2"; shift ;;
            --next)             ARG_NEXT="$2"; shift ;;
            --up)
                ARG_UP="$2"
                case "$ARG_UP" in
                    tcp|udp|mix) ;;
                    *)
                        log_error "$(t err_invalid_carrier "$ARG_UP")"
                        exit 1
                        ;;
                esac
                shift
                ;;
            --down)
                ARG_DOWN="$2"
                case "$ARG_DOWN" in
                    tcp|udp|mix) ;;
                    *)
                        log_error "$(t err_invalid_carrier "$ARG_DOWN")"
                        exit 1
                        ;;
                esac
                shift
                ;;
            --mux)              ARG_MUX="$2"; shift ;;
            --tcp-port)
                ARG_TCP_PORT="$2"
                if ! validate_port_value "$ARG_TCP_PORT"; then
                    exit 1
                fi
                shift
                ;;
            --udp-port)
                ARG_UDP_PORT="$2"
                if ! validate_port_value "$ARG_UDP_PORT"; then
                    exit 1
                fi
                shift
                ;;
            --morph)
                ARG_MORPH="$2"
                if ! validate_morph_value "$ARG_MORPH"; then
                    exit 1
                fi
                shift
                ;;
            --pool)
                # Kept for automation compatibility; Nowhere 1.8 replaced pool with mux.
                log_warn "$(t warn_pool_removed)"
                if [[ $# -ge 2 && "$2" != -* ]]; then
                    shift
                fi
                ;;
            --sni)              ARG_SNI="$2"; shift ;;
            --pin)              ARG_PIN="$2"; shift ;;
            --spec)
                # Kept for automation compatibility; Nowhere 1.5 removed spec.
                log_warn "$(t warn_spec_removed)"
                if [[ $# -ge 2 && "$2" != -* ]]; then
                    shift
                fi
                ;;
            --net)
                ARG_NET="$2"
                case "$ARG_NET" in
                    mix|tcp|udp) ;;
                    *)
                        log_error "$(t err_invalid_net "$ARG_NET")"
                        exit 1
                        ;;
                esac
                shift
                ;;
            --tls)              ARG_TLS="$2"; shift ;;
            --cert)             ARG_CERT="$2"; shift ;;
            --keyfile)          ARG_KEYFILE="$2"; shift ;;
            --cert-mode)
                ARG_CERT_MODE="$2"
                case "$ARG_CERT_MODE" in
                    program|openssl|custom|acme|1|2|3|4) ;;
                    *)
                        log_error "$(t err_cert_mode_invalid "$ARG_CERT_MODE")"
                        exit 1
                        ;;
                esac
                shift
                ;;
            --self-sign-days)
                ARG_SELF_SIGN_DAYS="$2"
                if [[ ! "$ARG_SELF_SIGN_DAYS" =~ ^[0-9]+$ ]] || (( ARG_SELF_SIGN_DAYS < 1 || ARG_SELF_SIGN_DAYS > 36500 )); then
                    log_error "$(t err_self_sign_failed)"
                    exit 1
                fi
                shift
                ;;
            --cert-san)         ARG_CERT_SAN="$2"; shift ;;
            --acme-domain)
                ARG_ACME_DOMAIN="$2"
                if ! acme_valid_domain "$ARG_ACME_DOMAIN"; then
                    log_error "$(t err_acme_domain_invalid "$ARG_ACME_DOMAIN")"
                    exit 1
                fi
                shift
                ;;
            --acme-email)       ARG_ACME_EMAIL="$2"; shift ;;
            --acme-challenge)
                ARG_ACME_CHALLENGE="$2"
                case "$ARG_ACME_CHALLENGE" in
                    http|dns) ;;
                    *) log_error "$(t err_acme_challenge_invalid "$ARG_ACME_CHALLENGE")"; exit 1 ;;
                esac
                shift
                ;;
            --acme-dns)
                ARG_ACME_CHALLENGE="dns"
                ARG_ACME_DNS="$2"
                [[ -z "$ARG_ACME_DNS" ]] && { log_error "$(t err_acme_dns_missing)"; exit 1; }
                shift
                ;;
            --acme-auto-renew)
                ARG_ACME_AUTO_RENEW="$2"
                case "$ARG_ACME_AUTO_RENEW" in
                    yes|no) ;;
                    *) log_error "$(t err_acme_auto_renew_invalid "$ARG_ACME_AUTO_RENEW")"; exit 1 ;;
                esac
                shift
                ;;
            --acme-renew-days)
                ARG_ACME_RENEW_DAYS="$2"
                if [[ ! "$ARG_ACME_RENEW_DAYS" =~ ^[0-9]+$ ]] || \
                   (( ARG_ACME_RENEW_DAYS < 1 || ARG_ACME_RENEW_DAYS > 89 )); then
                    log_error "$(t err_acme_renew_days_invalid "$ARG_ACME_RENEW_DAYS")"
                    exit 1
                fi
                shift
                ;;
            --renew-cert)       AUTO_MODE="renew" ;;
            -v|--version)       ARG_VERSION="$2"; shift ;;
            --script-version)
                printf '%s\n' "$SCRIPT_VERSION"
                exit 0
                ;;
            -l|--lang)
                ARG_LANG="$2"
                case "$ARG_LANG" in
                    en|zh|ru) set_language "$ARG_LANG" ;;
                    *)
                        log_error "$(t err_lang "$ARG_LANG")"
                        exit 1
                        ;;
                esac
                shift
                ;;
            -h|--help|help)
                set_language "${ARG_LANG:-zh}"
                show_help
                exit 0
                ;;
            *)
                log_error "$(t err_unknown_opt "$1")"
                show_help
                exit 1
                ;;
        esac
        shift
    done
    if [[ -z "$AUTO_MODE" ]]; then
        AUTO_MODE="menu"
    fi
}

# ==================== Main ====================
main() {
    parse_args "$@"
    set_language "${ARG_LANG:-zh}"
    check_root
    detect_os
    detect_arch
    detect_libc_runtime
    check_dependencies
    enforce_v2_only_options

    case "$AUTO_MODE" in
        install)    auto_install_nowhere ;;
        upgrade)    upgrade_nowhere ;;
        config)     configure_nowhere ;;
        status)     show_status ;;
        share)      show_share_uri ;;
        tui)        launch_tui ;;
        upgrade-script) upgrade_oh_nowhere_script ;;
        uninstall)  uninstall_nowhere ;;
        menu)       run_menu ;;
        renew)      renew_cert_action ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
