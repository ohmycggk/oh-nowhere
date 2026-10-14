#!/usr/bin/env bash
# Unit tests for the protocol-profile layer of oh-nowhere.sh (nw1 / nw2 / nw3).
#
# The script under test ends with a BASH_SOURCE guard, so it can be sourced
# without running main(). Every test runs against a throwaway CONFIG_DIR; no
# system path is touched and the network is never used.
#
# Usage: bash tests/profiles.sh [-v|--verbose]

# Variables assigned here are consumed by the sourced script under test.
# shellcheck disable=SC2034

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_UNDER_TEST="${TESTS_DIR}/../oh-nowhere.sh"

VERBOSE=0
case "${1:-}" in
    -v|--verbose) VERBOSE=1 ;;
    "") ;;
    *) echo "usage: $0 [-v|--verbose]" >&2; exit 2 ;;
esac

PASS=0
FAIL=0
FAILED_NAMES=()

ok() {
    PASS=$((PASS + 1))
    [[ "$VERBOSE" == "1" ]] && printf '  ok   %s\n' "$1"
    return 0
}

ko() {
    FAIL=$((FAIL + 1))
    FAILED_NAMES+=("$1")
    printf '  FAIL %s\n' "$1"
    shift
    local line
    for line in "$@"; do
        printf '       %s\n' "$line"
    done
    return 0
}

# assert_eq <name> <expected> <actual>
assert_eq() {
    local name="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        ok "$name"
    else
        ko "$name" "expected: ${expected}" "actual:   ${actual}"
    fi
}

# assert_match <name> <ERE> <actual>
assert_match() {
    local name="$1" pattern="$2" actual="$3"
    if [[ "$actual" =~ $pattern ]]; then
        ok "$name"
    else
        ko "$name" "expected match: ${pattern}" "actual:         ${actual}"
    fi
}

# assert_rc <name> <expected-rc> <actual-rc>
assert_rc() {
    local name="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        ok "$name"
    else
        ko "$name" "expected rc=${expected}" "actual rc=${actual}"
    fi
}

section() { printf '\n== %s ==\n' "$1"; }

# ==================== Sandbox ====================
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT

# shellcheck source=/dev/null
source "$SCRIPT_UNDER_TEST"
# The script enables errexit for its own main flow; tests exercise failing
# branches on purpose, so take it back off.
set +e
set +u

CONFIG_DIR="$SANDBOX/etc/nowhere"
URL_FILE="$CONFIG_DIR/url.conf"
HOST_FILE="$CONFIG_DIR/host.conf"
NAME_FILE="$CONFIG_DIR/name.conf"
PIN_FILE="$CONFIG_DIR/pin.conf"
DEFAULT_CERT="$CONFIG_DIR/cert.pem"
DEFAULT_KEYFILE="$CONFIG_DIR/key.pem"
# Sidecar recording the tls=2 certificate source (custom vs acme). Re-pointed
# here with the rest of the config files so no test can touch the real path.
CERT_MODE_FILE="$CONFIG_DIR/certmode.conf"
PORTAL_LOG="$SANDBOX/nowhere.log"
LAUNCHER="$SANDBOX/nowhere-launch.sh"
INIT_SYSTEM="none"
SCRIPT_LANG="en"
set_language en

mkdir -p "$CONFIG_DIR" "$SANDBOX/bin"

# Stubs: keep the tests hermetic (no network, no systemd, no service).
get_public_ip() { echo "203.0.113.7"; }
get_server_location() { echo "US"; }
service_is_active() { return 1; }
list_github_versions() { echo "v3.0.0"; echo "v2.2.1"; echo "v2.1.0"; }
# Deterministic stand-in for key generation inside migration tests.
generate_random_key() { printf 'a%.0s' {1..32}; }

write_url() { printf '%s\n' "$1" > "$URL_FILE"; }
read_url() { tr -d '\n' < "$URL_FILE"; }

# Force a protocol profile: 1 -> nw1, 2 -> nw2, 3 -> nw3.
use_profile() {
    ARG_VERSION=""
    case "$1" in
        1) ARG_VERSION="v1.9.0" ;;
        2) ARG_VERSION="v2.2.1" ;;
        3) ARG_VERSION="v3.0.0" ;;
        *) echo "use_profile: bad major $1" >&2; return 1 ;;
    esac
    TARGET_VERSION=""
    ARG_ALLOW_BREAKING=""
}

reset_config() {
    rm -f "$URL_FILE" "$HOST_FILE" "$NAME_FILE" "$PORTAL_LOG" "$SANDBOX/last-url"
    rm -f "$CERT_MODE_FILE"
    ARG_HOST=""
    ARG_NAME=""
    ARG_SOCKS=""
}

# Drop ANSI colour escapes so share output can be matched literally.
plain() { sed -e 's/\x1b\[[0-9;]*m//g'; }

# --- builder wrappers: the real functions take 18/14 positional args --------
# nw3_portal <key> <port> <tls> <morph> [tcp_port] [udp_port] <out_mode>
nw3_portal() {
    build_portal_url "$1" "$2" "$3" mix "" "" "" "" "" "" "" "" "" "" "$4" "${5:-}" "${6:-}" "$7"
}
# nw3_vector <key> <host> <port> <carrier> <socks> <morph> [sni] [pin]
nw3_vector() {
    build_vector_url "$1" "$2" "$3" "$4" "$4" "$5" "" "" "${7:-}" "${8:-}" "$6" "" "" "$4"
}
# nw3_vector_shim <key> <host> <port> <up> <down> <socks>  (no net= -> v2 shim)
nw3_vector_shim() {
    build_vector_url "$1" "$2" "$3" "$4" "$5" "$6" "" "" "" "" "" "" "" ""
}
# nw2_portal <key> <port> <tls> <socks> <next> <up> <down> <morph> [tcp] [udp]
nw2_portal() {
    build_portal_url "$1" "$2" "$3" mix "" "" "" "$4" "$5" "$6" "$7" "" "" "" "$8" "${9:-}" "${10:-}" ""
}
# nw2_vector <key> <host> <port> <up> <down> <socks> [morph] [tcp] [udp]
nw2_vector() {
    build_vector_url "$1" "$2" "$3" "$4" "$5" "$6" "" "" "" "" "$7" "${8:-}" "${9:-}" ""
}

# ==================== profile core ====================
section "profile core"

use_profile 3
assert_eq "proto_profile nw3" "nw3" "$(proto_profile)"
assert_eq "config_major from ARG_VERSION" "3" "$(config_major)"
ARG_VERSION=""
TARGET_VERSION=""
get_installed_version() { echo ""; }
assert_eq "default config_major is 3" "3" "$(config_major)"
get_installed_version() { :; }
assert_eq "is_nw3_profile" "yes" "$(is_nw3_profile && echo yes || echo no)"
assert_eq "is_nw2_profile under nw3" "no" "$(is_nw2_profile && echo yes || echo no)"
assert_eq "is_v2_profile under nw3" "yes" "$(is_v2_profile && echo yes || echo no)"

use_profile 2
assert_eq "proto_profile nw2" "nw2" "$(proto_profile)"
assert_eq "is_nw2_profile" "yes" "$(is_nw2_profile && echo yes || echo no)"
assert_eq "is_nw3_profile under nw2" "no" "$(is_nw3_profile && echo yes || echo no)"
assert_eq "config_major honors TARGET_VERSION" "2" "$(ARG_VERSION=""; TARGET_VERSION="v2.2.1"; config_major)"

use_profile 1
assert_eq "proto_profile nw1" "nw1" "$(proto_profile)"
assert_eq "is_v2_profile under nw1" "no" "$(is_v2_profile && echo yes || echo no)"

use_profile 3
assert_eq "valid_key nw3 32hex" "ok" "$(valid_key_for_profile "$(printf 'b%.0s' {1..32})" portal && echo ok || echo no)"
assert_eq "valid_key nw3 31hex rejected" "no" "$(valid_key_for_profile "$(printf 'b%.0s' {1..31})" portal && echo yes || echo no)"
assert_eq "valid_key nw3 33hex rejected" "no" "$(valid_key_for_profile "$(printf 'b%.0s' {1..33})" portal && echo yes || echo no)"
assert_eq "valid_key nw3 uppercase rejected" "no" "$(valid_key_for_profile "$(printf 'B%.0s' {1..32})" portal && echo yes || echo no)"
assert_eq "valid_key nw3 egress 32hex" "ok" "$(valid_key_for_profile "$(printf 'c%.0s' {1..32})" egress && echo ok || echo no)"
assert_eq "valid_key nw3 vector 32hex" "ok" "$(valid_key_for_profile "$(printf 'd%.0s' {1..32})" vector && echo ok || echo no)"
assert_match "generate_random_key nw3 is 32hex" '^[0-9a-f]{32}$' "$(generate_random_key)"

use_profile 2
assert_eq "valid_key nw2 portal 64hex" "ok" "$(valid_key_for_profile "$(printf 'e%.0s' {1..64})" portal && echo ok || echo no)"
assert_eq "valid_key nw2 portal 31hex rejected" "no" "$(valid_key_for_profile "$(printf 'e%.0s' {1..31})" portal && echo yes || echo no)"
assert_eq "valid_key nw2 vector free text" "ok" "$(valid_key_for_profile "any-text-key" vector && echo ok || echo no)"
assert_match "generate_random_key nw2 is 32hex" '^[0-9a-f]{32}$' "$(generate_random_key)"

use_profile 1
assert_eq "valid_key nw1 any non-empty" "ok" "$(valid_key_for_profile "whatever" portal && echo ok || echo no)"

# ==================== URL builders: nw3 ====================
section "URL builders nw3"

use_profile 3
reset_config
KEY32="0123456789abcdef0123456789abcdef"

assert_eq "portal nw3 compact wildcard" \
    "portal://${KEY32}@*:2077?tls=1&out=direct&morph=1" \
    "$(nw3_portal "$KEY32" 2077 1 1 "" "" direct)"

assert_eq "portal nw3 morph default 1" \
    "portal://${KEY32}@*:2077?tls=1&out=direct&morph=1" \
    "$(nw3_portal "$KEY32" 2077 1 "" "" "" direct)"

assert_eq "portal nw3 morph=0 explicit" \
    "portal://${KEY32}@*:2077?tls=1&out=direct&morph=0" \
    "$(nw3_portal "$KEY32" 2077 1 0 "" "" direct)"

assert_eq "portal nw3 out=socks via --socks" \
    "portal://${KEY32}@*:2077?tls=1&out=10.0.0.9:1080&morph=1" \
    "$(build_portal_url "$KEY32" 2077 1 mix "" "" "" "10.0.0.9:1080" "" "" "" "" "" "" 1 "" "" "")"

assert_eq "portal nw3 out=socks with credentials" \
    "portal://${KEY32}@*:2077?tls=1&out=user:p%40ss@10.0.0.9:1080&morph=1" \
    "$(build_portal_url "$KEY32" 2077 1 mix "" "" "" "user:p@ss@10.0.0.9:1080" "" "" "" "" "" "" 1 "" "" "")"

assert_eq "portal nw3 out=egress" \
    "portal://${KEY32}@*:2077?tls=1&out=egress&morph=1" \
    "$(nw3_portal "$KEY32" "" 1 1 2077 2077 egress)"

assert_eq "portal nw3 out=egress udp-only carrier" \
    "portal://${KEY32}@*/udp:2077?tls=1&out=egress&morph=1" \
    "$(build_portal_url "$KEY32" 2077 1 udp "" "" "" "" "" "" "" "" "" "" 1 "" "" egress)"

assert_eq "portal nw3 out=egress via --out with split ports" \
    "portal://${KEY32}@*/tcp:2077/udp:8443?tls=1&out=egress&morph=1" \
    "$(nw3_portal "$KEY32" "" 1 1 2077 8443 egress)"

assert_rc "portal nw3 next= rejected" 1 \
    "$(build_portal_url "$KEY32" 2077 1 mix "" "" "" "" "${KEY32}@1.2.3.4:2077" "" "" "" "" "" 1 "" "" "" >/dev/null 2>&1; echo $?)"

assert_rc "portal nw3 tls=3 rejected" 1 \
    "$(build_portal_url "$KEY32" 2077 3 mix "" "" "" "" "" "" "" "" "" "" 1 "" "" "" >/dev/null 2>&1; echo $?)"

assert_rc "portal nw3 out=egress without udp rejected" 1 \
    "$(nw3_portal "$KEY32" 2077 1 1 egress >/dev/null 2>&1; echo $?)"

assert_rc "portal nw3 short key rejected" 1 \
    "$(nw3_portal "0123456789abcdef" 2077 1 1 direct >/dev/null 2>&1; echo $?)"

assert_eq "portal nw3 tls=2 custom cert" \
    "portal://${KEY32}@*:2077?tls=2&crt=/etc/c.pem&key=/etc/k.pem&out=direct&morph=1" \
    "$(build_portal_url "$KEY32" 2077 2 mix "" "/etc/c.pem" "/etc/k.pem" "" "" "" "" "" "" "" 1 "" "" "")"

assert_eq "vector nw3 tcp carrier with in=" \
    "vector://${KEY32}@10.0.0.5/tcp:2077?in=127.0.0.1:1080&morph=1" \
    "$(nw3_vector "$KEY32" "10.0.0.5" 2077 tcp "127.0.0.1:1080" 1)"

assert_eq "vector nw3 udp carrier with in=" \
    "vector://${KEY32}@10.0.0.5/udp:8443?in=127.0.0.1:1080&morph=0" \
    "$(nw3_vector "$KEY32" "10.0.0.5" 8443 udp "127.0.0.1:1080" 0)"

assert_eq "vector nw3 sni and pin preserved" \
    "vector://${KEY32}@10.0.0.5/tcp:2077?in=127.0.0.1:1080&sni=v.example&pin=$(printf 'f%.0s' {1..64})&morph=1" \
    "$(nw3_vector "$KEY32" "10.0.0.5" 2077 tcp "127.0.0.1:1080" 1 "v.example" "$(printf 'f%.0s' {1..64})")"

assert_eq "vector nw3 folds up/down mix onto tcp" \
    "vector://${KEY32}@10.0.0.5/tcp:2077?in=127.0.0.1:1080&morph=1" \
    "$(nw3_vector_shim "$KEY32" "10.0.0.5" 2077 mix mix "127.0.0.1:1080" 1)"

assert_rc "vector nw3 requires in=" 1 \
    "$(nw3_vector "$KEY32" "10.0.0.5" 2077 tcp "" 1 >/dev/null 2>&1; echo $?)"

assert_rc "vector nw3 rejects star host" 1 \
    "$(nw3_vector "$KEY32" "*" 2077 tcp "127.0.0.1:1080" 1 >/dev/null 2>&1; echo $?)"

assert_rc "vector nw3 short key rejected" 1 \
    "$(nw3_vector "shortkey" "10.0.0.5" 2077 tcp "127.0.0.1:1080" 1 >/dev/null 2>&1; echo $?)"

assert_eq "egress nw3" \
    "egress://${KEY32}@10.0.0.5/udp:8443?morph=1" \
    "$(build_egress_url "$KEY32" "10.0.0.5" 8443)"

assert_eq "egress nw3 morph default 1" \
    "egress://${KEY32}@10.0.0.5/udp:8443?morph=1" \
    "$(build_egress_url "$KEY32" "10.0.0.5" 8443 "" "" "")"

assert_eq "egress nw3 with sni and pin" \
    "egress://${KEY32}@10.0.0.5/udp:8443?morph=0&sni=portal.example&pin=$(printf 'f%.0s' {1..64})" \
    "$(build_egress_url "$KEY32" "10.0.0.5" 8443 "portal.example" "$(printf 'f%.0s' {1..64})" 0)"

assert_rc "egress nw3 rejects star host" 1 \
    "$(build_egress_url "$KEY32" "*" 8443 >/dev/null 2>&1; echo $?)"

assert_rc "egress nw3 short key rejected" 1 \
    "$(build_egress_url "tooshort" "10.0.0.5" 8443 >/dev/null 2>&1; echo $?)"

assert_eq "detect_url_role egress" "egress" "$(detect_url_role "egress://k@h/udp:1")"
assert_eq "detect_url_role portal" "portal" "$(detect_url_role "portal://k@h")"
assert_eq "detect_url_role vector" "vector" "$(detect_url_role "vector://k@h")"
assert_eq "detect_url_role nowhere" "vector" "$(detect_url_role "nowhere://k@h")"

assert_eq "build_endpoint_hostpart nw3 portal wildcard" "*:2077" \
    "$(build_endpoint_hostpart portal "*" 2077 2077)"
assert_eq "build_endpoint_hostpart nw3 portal split" "*/tcp:2077/udp:8443" \
    "$(build_endpoint_hostpart portal "*" 2077 8443)"
assert_eq "build_endpoint_hostpart nw3 vector tcp" "10.0.0.5/tcp:2077" \
    "$(build_endpoint_hostpart vector "10.0.0.5" 2077 "")"
assert_eq "build_endpoint_hostpart nw3 egress udp" "10.0.0.5/udp:8443" \
    "$(build_endpoint_hostpart egress "10.0.0.5" "" 8443)"

# ==================== URL builders: nw2 / nw1 regression ====================
section "URL builders nw2 and nw1"

use_profile 2
reset_config
KEY64="0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

assert_eq "portal nw2 keeps up/down/socks" \
    "portal://${KEY64}@:2077?tls=1&socks=10.0.0.9:1080" \
    "$(nw2_portal "$KEY64" 2077 1 "10.0.0.9:1080" "" tcp tcp "" 2077 2077)"

assert_eq "portal nw2 next= preserved" \
    "portal://${KEY64}@:2077?tls=1&next=${KEY64}@1.2.3.4:2077&up=tcp&down=tcp" \
    "$(nw2_portal "$KEY64" 2077 1 "" "${KEY64}@1.2.3.4:2077" tcp tcp "" 2077 2077)"

assert_eq "vector nw2 keeps up/down/socks" \
    "vector://${KEY64}@10.0.0.5:2077?up=tcp&down=udp&socks=127.0.0.1:1080" \
    "$(nw2_vector "$KEY64" "10.0.0.5" "" tcp udp "127.0.0.1:1080" "" 2077 2077)"

assert_eq "build_endpoint_hostpart nw2 portal compact wildcard" ":2077" \
    "$(build_endpoint_hostpart portal "*" 2077 2077)"

use_profile 1
reset_config
assert_eq "portal nw1 keeps net=/alpn" \
    "portal://k1@:2077?tls=1&net=mix" \
    "$(build_portal_url "k1" 2077 1 mix "" "" "" "" "" "" "" "" "" "" "" "" "" "")"
assert_eq "vector nw1 keeps up/down/socks" \
    "vector://k1@10.0.0.5:2077?up=tcp&down=tcp&socks=127.0.0.1:1080&mux=1" \
    "$(build_vector_url "k1" "10.0.0.5" 2077 tcp tcp "127.0.0.1:1080")"

# ==================== migration nw2 -> nw3 ====================
section "migration nw2 to nw3"

use_profile 3
reset_config
write_url "portal://${KEY32}@*:2077/tcp:2077/udp:2077?tls=1&up=tcp&down=tcp&socks=10.0.0.9%3A1080&morph=1"
migrate_stored_url >/dev/null 2>&1
assert_eq "portal nw2->nw3 socks->out, up/down dropped" \
    "portal://${KEY32}@*:2077?tls=1&out=10.0.0.9%3A1080&morph=1" "$(read_url)"

reset_config
write_url "portal://${KEY32}@*:2077/tcp:2077/udp:2077?tls=1&up=tcp&down=tcp"
migrate_stored_url >/dev/null 2>&1
assert_eq "portal nw2->nw3 no socks -> out=direct, morph defaults 0" \
    "portal://${KEY32}@*:2077?tls=1&out=direct&morph=0" "$(read_url)"

reset_config
write_url "portal://${KEY32}@*:2077/tcp:2077/udp:2077?tls=1&socks=10.0.0.9%3A1080&rate=100&etar=50"
migrate_stored_url >/dev/null 2>&1
assert_eq "portal nw2->nw3 keeps rate/etar leftovers" \
    "portal://${KEY32}@*:2077?tls=1&out=10.0.0.9%3A1080&morph=0&rate=100&etar=50" "$(read_url)"

reset_config
write_url "portal://${KEY32}@*:2077/tcp:2077/udp:2077?tls=1&up=tcp&down=tcp&socks=10.0.0.9%3A1080&morph=1"
migrate_stored_url >/dev/null 2>&1
first="$(read_url)"
migrate_stored_url >/dev/null 2>&1
assert_eq "portal nw2->nw3 idempotent" "$first" "$(read_url)"

reset_config
write_url "portal://legacykey@*:2077/tcp:2077/udp:2077?tls=1&up=tcp&down=tcp"
migrate_stored_url >/dev/null 2>&1
assert_match "portal nw2->nw3 regenerates non-hex key" \
    '^portal://a{32}@\*:2077\?tls=1&out=direct&morph=0$' "$(read_url)"

reset_config
write_url "vector://${KEY32}@10.0.0.5/tcp:2077/udp:2077?up=tcp&down=tcp&socks=127.0.0.1%3A1080&morph=1&sni=v.example"
migrate_stored_url >/dev/null 2>&1
assert_eq "vector nw2->nw3 single tcp carrier, socks->in, sni kept once" \
    "vector://${KEY32}@10.0.0.5/tcp:2077?in=127.0.0.1%3A1080&sni=v.example&morph=1" "$(read_url)"

reset_config
write_url "vector://${KEY32}@10.0.0.5/tcp:2077/udp:2077?up=udp&down=udp&socks=127.0.0.1%3A1080"
migrate_stored_url >/dev/null 2>&1
assert_eq "vector nw2->nw3 single udp carrier" \
    "vector://${KEY32}@10.0.0.5/udp:2077?in=127.0.0.1%3A1080&morph=0" "$(read_url)"

reset_config
write_url "vector://${KEY32}@10.0.0.5/tcp:2077/udp:8443?up=tcp&down=udp&socks=127.0.0.1%3A1080"
migrate_stored_url >/dev/null 2>&1
assert_eq "vector nw2->nw3 mismatched carriers fold to tcp" \
    "vector://${KEY32}@10.0.0.5/tcp:2077?in=127.0.0.1%3A1080&morph=0" "$(read_url)"

reset_config
write_url "vector://peerkey@10.0.0.5:2077?up=tcp&down=tcp&socks=127.0.0.1%3A1080"
migrate_stored_url >/dev/null 2>&1
assert_eq "vector nw2->nw3 compact endpoint" \
    "vector://peerkey@10.0.0.5/tcp:2077?in=127.0.0.1%3A1080&morph=0" "$(read_url)"

reset_config
write_url "vector://${KEY32}@10.0.0.5/tcp:2077?in=127.0.0.1%3A1080&morph=1"
migrate_stored_url >/dev/null 2>&1
assert_eq "vector nw3 untouched (already in=)" \
    "vector://${KEY32}@10.0.0.5/tcp:2077?in=127.0.0.1%3A1080&morph=1" "$(read_url)"

reset_config
write_url "portal://${KEY32}@:2077?tls=1&net=mix&alpn=h2%2Chttp%2F1.1"
migrate_stored_url >/dev/null 2>&1
assert_eq "portal 1.x->nw3 chains v2 then nw3" \
    "portal://${KEY32}@*:2077?tls=1&out=direct&morph=0" "$(read_url)"

reset_config
write_url "egress://${KEY32}@10.0.0.5/udp:8443?morph=1"
migrate_stored_url >/dev/null 2>&1
assert_rc "egress url survives nw3 migration" 0 "$?"
assert_eq "egress url unchanged" "egress://${KEY32}@10.0.0.5/udp:8443?morph=1" "$(read_url)"

# next= cannot be migrated: fail-stop, URL untouched.
reset_config
write_url "portal://${KEY32}@*:2077/tcp:2077/udp:2077?tls=1&up=tcp&down=tcp&next=${KEY64}%401.2.3.4%3A2077"
migrate_stored_url >/dev/null 2>&1
assert_rc "portal next= blocks nw3 migration" 1 "$?"
assert_eq "portal next= leaves url untouched" \
    "portal://${KEY32}@*:2077/tcp:2077/udp:2077?tls=1&up=tcp&down=tcp&next=${KEY64}%401.2.3.4%3A2077" "$(read_url)"

# ==================== migration nw3 -> nw2 ====================
section "migration nw3 to nw2"

use_profile 2
reset_config
write_url "portal://${KEY32}@*:2077?tls=1&out=direct&morph=1"
migrate_url_to_nw2 >/dev/null 2>&1
assert_eq "portal nw3->nw2 direct drops out=" \
    "portal://${KEY32}@*:2077?tls=1&morph=1" "$(read_url)"

reset_config
write_url "portal://${KEY32}@*:2077?tls=1&out=10.0.0.9%3A1080&morph=1"
migrate_url_to_nw2 >/dev/null 2>&1
assert_eq "portal nw3->nw2 out=->socks=" \
    "portal://${KEY32}@*:2077?tls=1&socks=10.0.0.9%3A1080&morph=1" "$(read_url)"

reset_config
write_url "vector://${KEY32}@10.0.0.5/tcp:2077?in=127.0.0.1%3A1080&morph=1"
migrate_url_to_nw2 >/dev/null 2>&1
assert_eq "vector nw3->nw2 in=->socks=, single carrier expands" \
    "vector://${KEY32}@10.0.0.5/tcp:2077?up=tcp&down=tcp&socks=127.0.0.1%3A1080&morph=1" "$(read_url)"

reset_config
write_url "vector://${KEY32}@10.0.0.5/udp:8443?in=127.0.0.1%3A1080"
migrate_url_to_nw2 >/dev/null 2>&1
assert_eq "vector nw3->nw2 udp carrier, morph=0 dropped" \
    "vector://${KEY32}@10.0.0.5/udp:8443?up=udp&down=udp&socks=127.0.0.1%3A1080" "$(read_url)"

reset_config
write_url "egress://${KEY32}@10.0.0.5/udp:8443?morph=1"
migrate_url_to_nw2 >/dev/null 2>&1
assert_rc "egress blocks nw3->nw2 migration" 1 "$?"
assert_eq "egress url untouched by blocked migration" \
    "egress://${KEY32}@10.0.0.5/udp:8443?morph=1" "$(read_url)"

reset_config
write_url "portal://${KEY32}@*:2077?tls=1&out=egress&morph=1"
migrate_url_to_nw2 >/dev/null 2>&1
assert_rc "out=egress blocks nw3->nw2 migration" 1 "$?"

reset_config
write_url "portal://${KEY32}@*:2077?tls=1&out=direct&morph=1"
migrate_url_to_nw2 >/dev/null 2>&1
first="$(read_url)"
migrate_url_to_nw2 >/dev/null 2>&1
assert_eq "portal nw3->nw2 idempotent" "$first" "$(read_url)"

reset_config
write_url "vector://${KEY32}@10.0.0.5/tcp:2077?in=127.0.0.1%3A1080&morph=1"
migrate_url_to_nw2 >/dev/null 2>&1
first="$(read_url)"
migrate_url_to_nw2 >/dev/null 2>&1
assert_eq "vector nw3->nw2 idempotent" "$first" "$(read_url)"

# ==================== preflight ====================
section "preflight_profile_switch"

use_profile 3
reset_config
write_url "portal://${KEY32}@*:2077/tcp:2077/udp:2077?tls=1&up=tcp&down=tcp&next=${KEY64}%401.2.3.4%3A2077"
preflight_profile_switch 2 3 >/dev/null 2>&1
assert_rc "preflight blocks nw2->nw3 with next=" 1 "$?"

reset_config
write_url "portal://${KEY32}@*:2077/tcp:2077/udp:2077?tls=1&up=tcp&down=tcp&socks=10.0.0.9%3A1080"
preflight_profile_switch 2 3 >/dev/null 2>&1
assert_rc "preflight allows nw2->nw3 with socks=" 0 "$?"

reset_config
write_url "egress://${KEY32}@10.0.0.5/udp:8443?morph=1"
preflight_profile_switch 3 2 >/dev/null 2>&1
assert_rc "preflight blocks nw3->nw2 egress" 1 "$?"

reset_config
write_url "portal://${KEY32}@*:2077?tls=1&out=egress&morph=1"
preflight_profile_switch 3 2 >/dev/null 2>&1
assert_rc "preflight blocks nw3->nw2 out=egress" 1 "$?"

reset_config
write_url "portal://${KEY32}@*:2077?tls=1&out=direct&morph=1"
preflight_profile_switch 3 2 >/dev/null 2>&1
assert_rc "preflight allows nw3->nw2 direct" 0 "$?"

assert_rc "preflight same major is a no-op" 0 "$(preflight_profile_switch 2 2 >/dev/null 2>&1; echo $?)"

reset_config
preflight_profile_switch 2 3 >/dev/null 2>&1
assert_rc "preflight without url.conf passes" 0 "$?"

# ==================== upgrade target resolution ====================
section "resolve_upgrade_target"

use_profile 3
assert_eq "upgrade target: explicit ARG_VERSION wins" "v3.1.0" "$(ARG_VERSION="v3.1.0"; resolve_upgrade_target)"
assert_eq "upgrade target: allow-breaking jumps to latest" "" "$(ARG_VERSION=""; TARGET_VERSION=""; ARG_ALLOW_BREAKING="1"; resolve_upgrade_target)"

get_installed_version() { echo "2.2.1"; }
assert_eq "upgrade target: installed nw2 stays on v2 line" "v2.2.1" \
    "$(ARG_VERSION=""; TARGET_VERSION=""; ARG_ALLOW_BREAKING=""; resolve_upgrade_target)"
get_installed_version() { echo "3.0.0"; }
assert_eq "upgrade target: installed nw3 goes latest" "" \
    "$(ARG_VERSION=""; TARGET_VERSION=""; ARG_ALLOW_BREAKING=""; resolve_upgrade_target)"
get_installed_version() { echo ""; }
assert_eq "upgrade target: fresh install goes latest" "" \
    "$(ARG_VERSION=""; TARGET_VERSION=""; ARG_ALLOW_BREAKING=""; resolve_upgrade_target)"
get_installed_version() { :; }

# ==================== fingerprint probe ====================
section "build_fingerprint_probe_url"

use_profile 3
reset_config
build_fingerprint_probe_url "$KEY32" "node.example" 2077 mix "" "" "" "" >/dev/null 2>&1
assert_eq "fingerprint probe nw3 uses net=tcp" \
    "nowhere://${KEY32}@node.example:2077?net=tcp" "$FINGERPRINT_PROBE_URL"

build_fingerprint_probe_url "$KEY32" "node.example" 2077 mix "" "" "" 1 >/dev/null 2>&1
assert_eq "fingerprint probe nw3 appends morph=1" \
    "nowhere://${KEY32}@node.example:2077?net=tcp&morph=1" "$FINGERPRINT_PROBE_URL"

build_fingerprint_probe_url "$KEY32" "node.example" 2077 mix "" "" "v.example" "" >/dev/null 2>&1
assert_eq "fingerprint probe nw3 appends sni" \
    "nowhere://${KEY32}@node.example:2077?net=tcp&sni=v.example" "$FINGERPRINT_PROBE_URL"

build_fingerprint_probe_url "$KEY32" "*" 2077 mix "" "" "" "" >/dev/null 2>&1
assert_rc "fingerprint probe rejects wildcard host" 1 "$?"

build_fingerprint_probe_url "$KEY32" "node.example" "" udp "" "" "" "" >/dev/null 2>&1
assert_rc "fingerprint probe rejects udp-only" 1 "$?"

use_profile 2
reset_config
build_fingerprint_probe_url "$KEY64" "node.example" 2077 mix "" "" "" "" >/dev/null 2>&1
assert_eq "fingerprint probe nw2 uses carrier path" \
    "nowhere://${KEY64}@node.example/tcp:2077" "$FINGERPRINT_PROBE_URL"

# get_portal_fingerprint reads the service log when systemd is absent.
use_profile 3
reset_config
printf 'nowhere-v3.0.0 linux/x86_64\ntls certificate fingerprint: %s\n' \
    "$(printf 'f%.0s' {1..64})" > "$PORTAL_LOG"
assert_match "get_portal_fingerprint parses nw3 log line" \
    '^f{64}$' "$(get_portal_fingerprint "nowhere://${KEY32}@127.0.0.1:2077?net=tcp")"

reset_config
assert_eq "get_portal_fingerprint empty without service" "" \
    "$(get_portal_fingerprint "nowhere://${KEY32}@127.0.0.1:2077?net=tcp")"

# ==================== share URIs ====================
section "share URIs"

use_profile 3
reset_config
printf '203.0.113.7\n' > "$HOST_FILE"
printf 'Nowhere-US-203\n' > "$NAME_FILE"
write_url "portal://${KEY32}@*:2077/tcp:2077/udp:2077?tls=1&morph=1"
out="$(show_share_uri 2>&1 | plain)"
assert_match "share nw3 tcp link" \
    "nowhere://${KEY32}@203\.0\.113\.7:2077\?net=tcp&morph=1#Nowhere-US-203" "$out"
assert_match "share nw3 udp link" \
    "nowhere://${KEY32}@203\.0\.113\.7:2077\?net=udp&morph=1#Nowhere-US-203" "$out"
assert_eq "share nw3 emits one link per carrier" "2" \
    "$(printf '%s\n' "$out" | grep -cE '^nowhere://[0-9a-f]{32}@')"

reset_config
printf '203.0.113.7\n' > "$HOST_FILE"
printf '' > "$NAME_FILE"
write_url "portal://${KEY32}@*:2077/tcp:2077?tls=1&morph=0"
out="$(show_share_uri 2>&1 | plain)"
assert_match "share nw3 tcp-only portal" \
    "nowhere://${KEY32}@203\.0\.113\.7:2077\?net=tcp&morph=0" "$out"
assert_eq "share nw3 tcp-only has no udp link" "0" \
    "$(printf '%s\n' "$out" | grep -cE '^nowhere://[0-9a-f]{32}@.*net=udp')"

reset_config
printf '203.0.113.7\n' > "$HOST_FILE"
printf '' > "$NAME_FILE"
write_url "portal://${KEY32}@*:2077/tcp:2077/udp:2077?tls=2&morph=1"
out="$(show_share_uri 2>&1 | plain)"
assert_match "share nw3 tls=2 embeds sni from share host" \
    "nowhere://${KEY32}@203\.0\.113\.7:2077\?net=tcp&morph=1&sni=203\.0\.113\.7" "$out"
assert_eq "share nw3 tls=2 omits pin" "0" \
    "$(printf '%s\n' "$out" | grep -c 'pin=')"

reset_config
printf '203.0.113.7\n' > "$HOST_FILE"
write_url "vector://${KEY32}@10.0.0.5/tcp:2077?in=127.0.0.1%3A1080&morph=1"
out="$(show_share_uri 2>&1 | plain)"
assert_match "share vector prints run url" "vector://${KEY32}@10\.0\.0\.5/tcp:2077\?in=127\.0\.0\.1%3A1080&morph=1" "$out"
assert_eq "share vector has no client link" "0" \
    "$(printf '%s\n' "$out" | grep -cE '^nowhere://[0-9a-f]{32}@')"

reset_config
printf '203.0.113.7\n' > "$HOST_FILE"
write_url "egress://${KEY32}@10.0.0.5/udp:8443?morph=1"
out="$(show_share_uri 2>&1 | plain)"
assert_match "share egress prints run url" "egress://${KEY32}@10\.0\.0\.5/udp:8443\?morph=1" "$out"
assert_match "share egress notes no inbound" "no inbound" "$out"

# nw2 share URI keeps the classic single-link form (regression).
use_profile 2
reset_config
printf '203.0.113.7\n' > "$HOST_FILE"
printf '' > "$NAME_FILE"
write_url "portal://${KEY64}@*:2077/tcp:2077/udp:2077?tls=1&morph=1"
out="$(show_share_uri 2>&1 | plain)"
assert_match "share nw2 keeps single nowhere:// link with up/down" \
    "nowhere://${KEY64}@203\.0\.113\.7:2077\?up=udp&down=udp&morph=1" "$out"
assert_eq "share nw2 emits exactly one client link" "1" \
    "$(printf '%s\n' "$out" | grep -cE '^nowhere://[0-9a-f]{64}@')"

# ==================== launcher guard ====================
section "launcher guard"

# Materialize a launcher in the sandbox and rewrite the hardcoded system paths
# so it can be executed without root/systemd. $1 = fake binary major version.
make_sandbox_launcher() {
    local major="$1"
    write_launcher >/dev/null 2>&1
    sed -i \
        -e "s#/etc/nowhere/url.conf#${SANDBOX}/etc/nowhere/url.conf#g" \
        -e "s#/usr/local/bin/nowhere#${SANDBOX}/bin/nowhere#g" \
        "$LAUNCHER"
    cat > "$SANDBOX/bin/nowhere" <<EOF
#!/usr/bin/env bash
if [[ "\$1" == "--version" ]]; then
    echo "nowhere-v${major}.0.0 linux/x86_64"
    exit 0
fi
printf '%s\n' "\$1" > "$SANDBOX/last-url"
exit 0
EOF
    chmod +x "$SANDBOX/bin/nowhere"
}

use_profile 3
reset_config
make_sandbox_launcher 3
write_url "portal://${KEY32}@*:2077?tls=1&out=direct&morph=1"
out="$("$LAUNCHER" 2>&1)"; rc=$?
assert_rc "launcher nw3 binary + clean nw3 url" 0 "$rc"
assert_eq "launcher passes nw3 url through" "portal://${KEY32}@*:2077?tls=1&out=direct&morph=1" "$(cat "$SANDBOX/last-url")"

reset_config
make_sandbox_launcher 3
write_url "portal://${KEY32}@*:2077/tcp:2077/udp:2077?tls=1&up=tcp&down=tcp&socks=10.0.0.9%3A1080"
out="$("$LAUNCHER" 2>&1)"; rc=$?
assert_rc "launcher nw3 binary + nw2 url blocked" 1 "$rc"
assert_match "launcher guard explains nw2 params" "silently ignores" "$out"

reset_config
make_sandbox_launcher 3
write_url "vector://${KEY32}@10.0.0.5/tcp:2077?in=127.0.0.1%3A1080&morph=1"
out="$("$LAUNCHER" 2>&1)"; rc=$?
assert_rc "launcher nw3 binary + clean nw3 vector" 0 "$rc"
assert_eq "launcher passes nw3 vector url through" \
    "vector://${KEY32}@10.0.0.5/tcp:2077?in=127.0.0.1%3A1080&morph=1" "$(cat "$SANDBOX/last-url")"

reset_config
make_sandbox_launcher 2
write_url "portal://${KEY64}@*:2077/tcp:2077/udp:2077?tls=1&up=tcp&down=tcp&socks=10.0.0.9%3A1080"
out="$("$LAUNCHER" 2>&1)"; rc=$?
assert_rc "launcher nw2 binary + nw2 url" 0 "$rc"
assert_eq "launcher passes nw2 url through" \
    "portal://${KEY64}@*:2077/tcp:2077/udp:2077?tls=1&up=tcp&down=tcp&socks=10.0.0.9%3A1080" "$(cat "$SANDBOX/last-url")"

reset_config
make_sandbox_launcher 3
write_url "nowhere://${KEY32}@10.0.0.5:2077"
out="$("$LAUNCHER" 2>&1)"; rc=$?
assert_rc "launcher nw3 converts nowhere:// url" 0 "$rc"
assert_eq "launcher nw3 appends in= to converted url" \
    "vector://${KEY32}@10.0.0.5:2077?in=127.0.0.1:1080" "$(cat "$SANDBOX/last-url")"
assert_eq "launcher nw3 persists converted url" \
    "vector://${KEY32}@10.0.0.5:2077?in=127.0.0.1:1080" "$(read_url)"

reset_config
make_sandbox_launcher 2
write_url "nowhere://${KEY64}@10.0.0.5:2077"
out="$("$LAUNCHER" 2>&1)"; rc=$?
assert_rc "launcher nw2 converts nowhere:// url" 0 "$rc"
assert_eq "launcher nw2 appends socks= to converted url" \
    "vector://${KEY64}@10.0.0.5:2077?socks=127.0.0.1:1080" "$(cat "$SANDBOX/last-url")"

reset_config
make_sandbox_launcher 3
rm -f "$URL_FILE"
out="$("$LAUNCHER" 2>&1)"; rc=$?
assert_rc "launcher fails on missing url.conf" 1 "$rc"

# ==================== script version ====================
section "script version"

assert_match "SCRIPT_VERSION is semver" '^[0-9]+\.[0-9]+\.[0-9]+$' "$SCRIPT_VERSION"
file_ver="$(read_script_version_file "$SCRIPT_UNDER_TEST" || true)"
assert_eq "SCRIPT_VERSION line matches the constant" "$SCRIPT_VERSION" "$file_ver"
version_ge "1.2.0" "1.0.0"
assert_rc "newer script version compares greater" 0 "$?"
version_ge "1.0.0" "1.2.0"
assert_rc "older script version compares lower" 1 "$?"

# ==================== i18n key parity ====================
section "i18n key parity"

KEYS_EN="$(set_language en; printf '%s\n' "${!MSG[@]}" | sort)"
KEYS_ZH="$(set_language zh; printf '%s\n' "${!MSG[@]}" | sort)"
KEYS_RU="$(set_language ru; printf '%s\n' "${!MSG[@]}" | sort)"
assert_eq "i18n key sets identical across en/zh/ru" "identical" \
    "$(if [[ "$KEYS_EN" == "$KEYS_ZH" && "$KEYS_ZH" == "$KEYS_RU" ]]; then echo identical; else echo differs; fi)"

# Every key the nw3 work relies on must resolve to a real message, not the key.
use_profile 3
MISSING=""
for k in warn_nw3_protocol err_next_removed err_invalid_out err_egress_needs_udp \
         err_egress_requires_nw3 err_preflight_next err_preflight_egress \
         err_migrate_requires_flag prompt_migrate_confirm info_migrate_flag_accepted \
         warn_url_backed_up warn_protocol_switch warn_migrated_nw3 warn_migrated_nw2 \
         warn_vector_carrier_fallback warn_vector_key_peer label_out label_in \
         info_launching_status info_configure_egress info_egress_no_inbound \
         prompt_outbound_mode_nw3 prompt_carrier_single label_share_link_tcp \
         label_share_link_udp help_opt_out help_opt_allow_breaking mf_out \
         mf_out_socks mf_in mf_carrier err_out_socks_required; do
    val="$(t "$k")"
    [[ "$val" == "$k" ]] && MISSING="${MISSING}${k} "
done
assert_eq "all nw3 i18n keys resolve" "" "$MISSING"

assert_eq "t() substitutes placeholders" "Invalid port: abc" "$(t err_invalid_port "abc")"

# A key that is defined but never echoed shows up as a silently missing option,
# which is how --acme-renew-days first shipped. Check the help text itself.
HELP_OUT="$(SCRIPT_LANG=en; set_language en; show_help 2>&1)"
for opt in --cert-mode --self-sign-days --cert-san --acme-domain --acme-email \
           --acme-challenge --acme-dns --acme-auto-renew --acme-renew-days \
           --renew-cert; do
    assert_match "help lists ${opt}" "$opt" "$HELP_OUT"
done

# ==================== certificate modes ====================
section "certificate modes"

use_profile 3
reset_config
clear_pin

# A real openssl self-signed certificate, generated once for the whole section:
# the pin must match what the binary computes (SHA-256 over the leaf DER), and
# the key must be mode 600.
CERT_SANDBOX="$SANDBOX/certs"
mkdir -p "$CERT_SANDBOX"
TEST_CRT="$CERT_SANDBOX/cert.pem"
TEST_KEY="$CERT_SANDBOX/key.pem"
TEST_PIN="$(openssl_self_sign "$TEST_CRT" "$TEST_KEY" 398 "DNS:relay.example,IP:203.0.113.7" "relay.example")"

# normalize_cert_mode accepts the interactive numbers, the words and empty.
assert_eq "normalize_cert_mode empty defaults to program" "program" "$(normalize_cert_mode "")"
assert_eq "normalize_cert_mode 1" "program" "$(normalize_cert_mode 1)"
assert_eq "normalize_cert_mode 2" "openssl" "$(normalize_cert_mode 2)"
assert_eq "normalize_cert_mode 3" "custom" "$(normalize_cert_mode 3)"
assert_eq "normalize_cert_mode word program" "program" "$(normalize_cert_mode program)"
assert_eq "normalize_cert_mode word openssl" "openssl" "$(normalize_cert_mode openssl)"
assert_eq "normalize_cert_mode word custom" "custom" "$(normalize_cert_mode custom)"
assert_eq "normalize_cert_mode 4" "acme" "$(normalize_cert_mode 4)"
assert_eq "normalize_cert_mode word acme" "acme" "$(normalize_cert_mode acme)"
normalize_cert_mode "bogus" >/dev/null 2>&1
assert_rc "normalize_cert_mode rejects garbage" 1 "$?"
normalize_cert_mode "5" >/dev/null 2>&1
assert_rc "normalize_cert_mode rejects 5" 1 "$?"

assert_eq "cert_mode_tls program" "1" "$(cert_mode_tls program)"
assert_eq "cert_mode_tls openssl" "2" "$(cert_mode_tls openssl)"
assert_eq "cert_mode_tls custom" "2" "$(cert_mode_tls custom)"
assert_eq "cert_mode_tls acme" "2" "$(cert_mode_tls acme)"

# detect_cert_mode recovers the source from the stored URL plus pin.conf.
clear_pin
assert_eq "detect_cert_mode tls=1" "program" "$(detect_cert_mode "portal://${KEY32}@*:2077?tls=1&morph=1")"
assert_eq "detect_cert_mode tls=2 without pin" "custom" \
    "$(detect_cert_mode "portal://${KEY32}@*:2077?tls=2&crt=/etc/nowhere/cert.pem&key=/etc/nowhere/key.pem&morph=1")"
save_pin "$(printf 'a%.0s' {1..64})"
assert_eq "detect_cert_mode tls=2 with pin" "openssl" \
    "$(detect_cert_mode "portal://${KEY32}@*:2077?tls=2&crt=${TEST_CRT}&key=${TEST_KEY}&morph=1")"
assert_eq "load_pin round-trips" "$(printf 'a%.0s' {1..64})" "$(load_pin)"
clear_pin
assert_eq "clear_pin empties load_pin" "" "$(load_pin)"

# save_pin with an empty value removes the file rather than writing a blank one.
save_pin ""
assert_eq "save_pin empty removes the file" "absent" \
    "$(if [[ -f "$PIN_FILE" ]]; then echo present; else echo absent; fi)"
save_pin "deadbeef"
assert_eq "save_pin writes the file" "present" \
    "$(if [[ -f "$PIN_FILE" ]]; then echo present; else echo absent; fi)"
clear_pin

# normalize_cert_san prefixes bare entries and rejects junk.
assert_eq "normalize_cert_san adds IP:/DNS: prefixes" "DNS:a.example,IP:203.0.113.7" \
    "$(normalize_cert_san "a.example,203.0.113.7")"
assert_eq "normalize_cert_san keeps explicit prefixes" "DNS:a.example,IP:10.0.0.1" \
    "$(normalize_cert_san "DNS:a.example,IP:10.0.0.1")"
assert_eq "normalize_cert_san trims whitespace" "DNS:a.example" "$(normalize_cert_san " a.example ")"
normalize_cert_san "" >/dev/null 2>&1
assert_rc "normalize_cert_san rejects empty" 1 "$?"
normalize_cert_san "a b" >/dev/null 2>&1
assert_rc "normalize_cert_san rejects spaces inside a name" 1 "$?"
normalize_cert_san "IP:not-an-ip" >/dev/null 2>&1
assert_rc "normalize_cert_san rejects IP: with a non-address" 1 "$?"

assert_eq "default_cert_san includes loopback and the public IP" \
    "DNS:relay.example,IP:203.0.113.7,DNS:localhost,IP:127.0.0.1" \
    "$(default_cert_san "relay.example")"
assert_eq "default_cert_san dedupes the share host against the public IP" \
    "IP:203.0.113.7,DNS:localhost,IP:127.0.0.1" \
    "$(default_cert_san "203.0.113.7")"

# A real openssl self-signed certificate: the pin must match what the binary
# computes (SHA-256 over the leaf DER), and the key must be mode 600.
assert_match "openssl_self_sign returns a 64 hex pin" '^[0-9a-f]{64}$' "$TEST_PIN"
assert_eq "openssl_self_sign pin matches openssl x509 -outform DER | sha256sum" \
    "$(openssl x509 -in "$TEST_CRT" -outform DER | sha256sum | cut -d' ' -f1)" "$TEST_PIN"
assert_eq "cert_pin_from_file agrees with openssl_self_sign" "$TEST_PIN" "$(cert_pin_from_file "$TEST_CRT")"
assert_eq "self-signed key file is mode 600" "600" "$(stat -c '%a' "$TEST_KEY")"
assert_eq "self-signed cert file is mode 644" "644" "$(stat -c '%a' "$TEST_CRT")"
assert_match "self-signed cert carries the requested SAN" 'DNS:relay\.example, IP Address:203\.0\.113\.7' \
    "$(openssl x509 -in "$TEST_CRT" -noout -ext subjectAltName 2>/dev/null | tail -n +2)"
assert_match "self-signed cert is a P-256 EC key" 'ASN1 OID: prime256v1' \
    "$(openssl pkey -in "$TEST_KEY" -noout -text 2>/dev/null)"
assert_eq "cert_not_after reports a date" "yes" \
    "$(if [[ "$(cert_not_after "$TEST_CRT")" =~ ^[A-Z][a-z]{2}\ +[0-9] ]]; then echo yes; else echo no; fi)"
cert_pin_from_file "$CERT_SANDBOX/absent.pem" >/dev/null 2>&1
assert_rc "cert_pin_from_file fails on a missing file" 1 "$?"
openssl_self_sign "$TEST_CRT" "$TEST_KEY" 0 "DNS:a.example" "a.example" >/dev/null 2>&1
assert_rc "openssl_self_sign rejects 0 days" 1 "$?"
openssl_self_sign "$TEST_CRT" "$TEST_KEY" 99999 "DNS:a.example" "a.example" >/dev/null 2>&1
assert_rc "openssl_self_sign rejects >36500 days" 1 "$?"

# Share URIs: openssl self-signed (tls=2 + pin.conf) carries pin= and no sni=;
# a custom certificate keeps sni= and no pin=.
use_profile 3
reset_config
printf '203.0.113.7\n' > "$HOST_FILE"
printf '' > "$NAME_FILE"
save_pin "$TEST_PIN"
write_url "portal://${KEY32}@*:2077/tcp:2077/udp:2077?tls=2&crt=${TEST_CRT}&key=${TEST_KEY}&morph=1"
out="$(show_share_uri 2>&1 | plain)"
assert_match "share nw3 openssl self-signed embeds pin" \
    "nowhere://${KEY32}@203\.0\.113\.7:2077\?net=tcp&morph=1&pin=${TEST_PIN}" "$out"
assert_match "share nw3 openssl self-signed udp link embeds pin" \
    "nowhere://${KEY32}@203\.0\.113\.7:2077\?net=udp&morph=1&pin=${TEST_PIN}" "$out"
assert_eq "share nw3 openssl self-signed omits sni" "0" \
    "$(printf '%s\n' "$out" | grep -c 'sni=')"
assert_match "share nw3 openssl self-signed prints the pin" "Cert pin:   ${TEST_PIN}" "$out"

reset_config
printf '203.0.113.7\n' > "$HOST_FILE"
printf '' > "$NAME_FILE"
clear_pin
write_url "portal://${KEY32}@*:2077/tcp:2077/udp:2077?tls=2&crt=${TEST_CRT}&key=${TEST_KEY}&morph=1"
out="$(show_share_uri 2>&1 | plain)"
assert_match "share nw3 custom cert still embeds sni" \
    "nowhere://${KEY32}@203\.0\.113\.7:2077\?net=tcp&morph=1&sni=203\.0\.113\.7" "$out"
assert_eq "share nw3 custom cert omits pin" "0" \
    "$(printf '%s\n' "$out" | grep -c 'pin=')"

# nw2 keeps the classic single-link form and must honour the same split.
use_profile 2
reset_config
printf '203.0.113.7\n' > "$HOST_FILE"
printf '' > "$NAME_FILE"
save_pin "$TEST_PIN"
write_url "portal://${KEY64}@*:2077/tcp:2077/udp:2077?tls=2&crt=${TEST_CRT}&key=${TEST_KEY}&morph=1"
out="$(show_share_uri 2>&1 | plain)"
assert_match "share nw2 openssl self-signed embeds pin" \
    "nowhere://${KEY64}@203\.0\.113\.7:2077\?up=udp&down=udp&morph=1&pin=${TEST_PIN}" "$out"
assert_eq "share nw2 openssl self-signed omits sni" "0" \
    "$(printf '%s\n' "$out" | grep -c 'sni=')"

reset_config
printf '203.0.113.7\n' > "$HOST_FILE"
printf '' > "$NAME_FILE"
clear_pin
write_url "portal://${KEY64}@*:2077/tcp:2077/udp:2077?tls=2&crt=${TEST_CRT}&key=${TEST_KEY}&morph=1"
out="$(show_share_uri 2>&1 | plain)"
assert_match "share nw2 custom cert still embeds sni" \
    "nowhere://${KEY64}@203\.0\.113\.7:2077\?up=udp&down=udp&morph=1&sni=203\.0\.113\.7" "$out"
assert_eq "share nw2 custom cert omits pin" "0" \
    "$(printf '%s\n' "$out" | grep -c 'pin=')"

# build_portal_url never leaks pin= into the server-side URL for tls=2.
# build_portal_url takes 18 positional args; call it directly (the nw3_portal
# wrapper hardcodes empty crt/keyfile).
use_profile 3
reset_config
clear_pin
save_pin "$TEST_PIN"
assert_eq "build_portal_url tls=2 emits crt/key only" \
    "portal://${KEY32}@*:2077?tls=2&crt=${TEST_CRT}&key=${TEST_KEY}&out=direct&morph=1" \
    "$(build_portal_url "$KEY32" 2077 2 mix "" "$TEST_CRT" "$TEST_KEY" "" "" "" "" "" "" "" 1 2077 2077 direct)"
assert_eq "build_portal_url tls=2 never emits pin=" "0" \
    "$(build_portal_url "$KEY32" 2077 2 mix "" "$TEST_CRT" "$TEST_KEY" "" "" "" "" "" "" "" 1 2077 2077 direct | grep -c 'pin=')"

# resolve_cert_mode: program clears the pin, custom clears it too.
use_profile 3
reset_config
clear_pin
save_pin "$TEST_PIN"
resolve_cert_mode "program" "" true
assert_eq "resolve_cert_mode program sets tls=1" "1" "$CERT_TLS"
assert_eq "resolve_cert_mode program clears the pin" "" "$(load_pin)"

save_pin "$TEST_PIN"
resolve_cert_mode "custom" "relay.example" true
assert_eq "resolve_cert_mode custom sets tls=2" "2" "$CERT_TLS"
assert_eq "resolve_cert_mode custom clears the pin" "" "$(load_pin)"
assert_eq "resolve_cert_mode custom defaults the paths" "$DEFAULT_CERT" "$CERT_CRT"

# An unknown mode is rejected rather than silently falling back.
resolve_cert_mode "bogus" "" true >/dev/null 2>&1
assert_rc "resolve_cert_mode rejects an unknown mode" 1 "$?"

# Status output reports the certificate source and expiry for a file-backed cert.
use_profile 3
reset_config
printf '203.0.113.7\n' > "$HOST_FILE"
save_pin "$TEST_PIN"
write_url "portal://${KEY32}@*:2077/tcp:2077?tls=2&crt=${TEST_CRT}&key=${TEST_KEY}&morph=1"
out="$(show_status 2>&1 | plain)"
assert_match "status shows the openssl certificate source" "openssl" "$out"
assert_match "status shows the pin prefix" "pin ${TEST_PIN:0:8}" "$out"
assert_match "status shows the certificate expiry" "Cert until:" "$out"
assert_eq "status does not warn for a 398-day certificate" "0" \
    "$(printf '%s\n' "$out" | grep -c 'expire')"

# The modify-configuration editor re-asks the certificate source and can
# re-issue the openssl certificate on demand (mf_edit_field assigns in the
# caller's scope, so drive it from a wrapper function).
mf_cert_case() {
    local cert_mode="$1" tls="$2" crt="$DEFAULT_CERT" keyfile="$DEFAULT_KEYFILE" host="relay.example"
    shift 2
    mf_edit_field "portal" "cert_mode" "prompt_cert_mode" < <(printf '%s' "$1") >/dev/null 2>&1
    MF_CERT_MODE="$cert_mode"; MF_TLS="$tls"; MF_CRT="$crt"
}
use_profile 3
reset_config
clear_pin
mf_cert_case program 1 $'2\n\n\n'
assert_eq "mf_edit_field switches to openssl" "openssl" "$MF_CERT_MODE"
assert_eq "mf_edit_field openssl sets tls=2" "2" "$MF_TLS"
assert_eq "mf_edit_field openssl points crt at the default" "$DEFAULT_CERT" "$MF_CRT"
assert_eq "mf_edit_field openssl stores the pin" "$(cert_pin_from_file "$DEFAULT_CERT")" "$(load_pin)"

mf_cert_case openssl 2 $'1\n'
assert_eq "mf_edit_field back to program" "program" "$MF_CERT_MODE"
assert_eq "mf_edit_field program sets tls=1" "1" "$MF_TLS"
assert_eq "mf_edit_field program clears the pin" "" "$(load_pin)"

mf_cert_case program 1 $'3\n\n\n'
assert_eq "mf_edit_field switches to custom" "custom" "$MF_CERT_MODE"
assert_eq "mf_edit_field custom sets tls=2" "2" "$MF_TLS"
assert_eq "mf_edit_field custom clears the pin" "" "$(load_pin)"

# Editing the PEM paths by hand drops the pin (clients fall back to sni=).
save_pin "$TEST_PIN"
cert_mode="custom"; tls="2"; crt="$DEFAULT_CERT"; keyfile="$DEFAULT_KEYFILE"; host="relay.example"
mf_edit_field "portal" "crt" "prompt_cert" < <(printf '%s\n' "/etc/ssl/mine.pem") >/dev/null 2>&1
assert_eq "mf_edit_field crt accepts a new path" "/etc/ssl/mine.pem" "$crt"
assert_eq "mf_edit_field crt drops the pin" "" "$(load_pin)"
clear_pin

# ==================== acme.sh certificate mode ====================
section "acme.sh certificate mode"

# Sandbox every acme path before touching anything: the real ~/.acme.sh must
# never be read or written, and the cron entries must land in a scratch file.
ACME_BIN="$SANDBOX/bin/acme.sh"
ACME_DIR="$SANDBOX/acme"
ACME_CRT="$ACME_DIR/fullchain.pem"
ACME_KEY="$ACME_DIR/private.key"
ACME_RELOAD_HOOK="$CONFIG_DIR/acme-reload.sh"
ACME_RENEW_HOOK="$CONFIG_DIR/acme-renew.sh"
ACME_RENEW_LOG="$CONFIG_DIR/acme-renew.log"
ACME_CRON_D_FILE="$SANDBOX/cron.d/nowhere-acme"
ACME_CRON_SCHEDULE="17 3 * * *"

# A stub acme.sh: records its arguments and fakes the issued files.
mkdir -p "$SANDBOX/bin" "$ACME_DIR"
cat > "$ACME_BIN" <<'STUB'
#!/bin/sh
echo "$@" >> "$ACME_STUB_LOG"
case "$1" in
    --issue)
        mkdir -p "${ACME_DIR}/relay.example.com_ecc"
        echo "cert" > "${ACME_DIR}/relay.example.com_ecc/fullchain.cer"
        echo "key"  > "${ACME_DIR}/relay.example.com_ecc/relay.example.com.key"
        ;;
esac
exit 0
STUB
chmod 755 "$ACME_BIN"
ACME_STUB_LOG="$SANDBOX/acme-stub.log"
export ACME_STUB_LOG ACME_DIR

# A stub crontab(1) that stores the crontab in a file instead of the daemon.
# POSIX sh only: the stub is run by /bin/sh, not bash.
cat > "$SANDBOX/bin/crontab" <<'STUB'
#!/bin/sh
case "$1" in
    -l) [ -f "$CRONTAB_FILE" ] && cat "$CRONTAB_FILE"; exit 0 ;;
    -)  cat > "$CRONTAB_FILE"; exit 0 ;;
esac
exit 0
STUB
chmod 755 "$SANDBOX/bin/crontab"
CRONTAB_FILE="$SANDBOX/root-crontab"
export CRONTAB_FILE
PATH="$SANDBOX/bin:$PATH"

use_profile 3
reset_config
clear_pin
clear_cert_mode

# --- mode plumbing -------------------------------------------------------
assert_eq "CERT_MODES includes acme" "yes" \
    "$(case " $CERT_MODES " in *" acme "*) echo yes ;; *) echo no ;; esac)"
assert_eq "detect_cert_mode prefers the sidecar" "acme" \
    "$(save_cert_mode acme relay.example.com yes; detect_cert_mode "portal://${KEY32}@*:2077?tls=2&crt=/x&key=/y&morph=1")"
assert_eq "detect_cert_mode honours a custom sidecar" "custom" \
    "$(save_cert_mode custom "" ""; detect_cert_mode "portal://${KEY32}@*:2077?tls=2&crt=/x&key=/y&morph=1")"
clear_cert_mode
# A stale pin.conf must not outrank the sidecar: tls=2 + pin normally means
# openssl, but certmode.conf is the authority once it exists.
save_pin "$(printf 'a%.0s' {1..64})"
save_cert_mode acme relay.example.com yes
assert_eq "detect_cert_mode prefers the acme sidecar over a pin" "acme" \
    "$(detect_cert_mode "portal://${KEY32}@*:2077?tls=2&crt=/x&key=/y&morph=1")"
clear_cert_mode
assert_eq "detect_cert_mode falls back to pin without a sidecar" "openssl" \
    "$(save_pin "$(printf 'a%.0s' {1..64})"; detect_cert_mode "portal://${KEY32}@*:2077?tls=2&crt=/x&key=/y&morph=1")"
clear_pin

# --- sidecar round-trip --------------------------------------------------
save_cert_mode acme relay.example.com yes 30
assert_eq "certmode.conf records mode" "acme" "$(load_cert_mode_field mode)"
assert_eq "certmode.conf records domain" "relay.example.com" "$(load_cert_mode_field domain)"
assert_eq "certmode.conf records autorenew" "yes" "$(load_cert_mode_field autorenew)"
assert_eq "certmode.conf records renewdays" "30" "$(load_cert_mode_field renewdays)"
save_cert_mode acme "" no
assert_eq "certmode.conf omits an empty domain" "" "$(load_cert_mode_field domain)"
assert_eq "certmode.conf records autorenew no" "no" "$(load_cert_mode_field autorenew)"
assert_eq "certmode.conf omits renewdays when unset" "" "$(load_cert_mode_field renewdays)"
clear_cert_mode
assert_eq "load_cert_mode_field on a missing file is empty" "" "$(load_cert_mode_field mode)"
assert_eq "clear_cert_mode removes the file" "absent" \
    "$(if [[ -f "$CERT_MODE_FILE" ]]; then echo present; else echo absent; fi)"
assert_eq "load_cert_mode_field after clear is empty" "" "$(load_cert_mode_field mode)"

# --- domain validation ---------------------------------------------------
acme_valid_domain "relay.example.com" && r=0 || r=$?
assert_rc "acme_valid_domain accepts a normal hostname" 0 "$r"
acme_valid_domain "a.b.c.example.org" && r=0 || r=$?
assert_rc "acme_valid_domain accepts a deep hostname" 0 "$r"
acme_valid_domain "relay.example.com." && r=0 || r=$?
assert_rc "acme_valid_domain rejects a trailing dot" 1 "$r"
acme_valid_domain "relay.example.com " && r=0 || r=$?
assert_rc "acme_valid_domain rejects a trailing space" 1 "$r"
acme_valid_domain "*.example.com" && r=0 || r=$?
assert_rc "acme_valid_domain rejects a wildcard" 1 "$r"
acme_valid_domain "example" && r=0 || r=$?
assert_rc "acme_valid_domain rejects a bare label" 1 "$r"
acme_valid_domain "-relay.example.com" && r=0 || r=$?
assert_rc "acme_valid_domain rejects a leading hyphen" 1 "$r"
acme_valid_domain "relay-.example.com" && r=0 || r=$?
assert_rc "acme_valid_domain rejects a trailing hyphen" 1 "$r"
acme_valid_domain "203.0.113.7" && r=0 || r=$?
assert_rc "acme_valid_domain rejects an IP literal" 1 "$r"
acme_valid_domain "::1" && r=0 || r=$?
assert_rc "acme_valid_domain rejects an IPv6 literal" 1 "$r"
acme_valid_domain "Relay.Example" && r=0 || r=$?
assert_rc "acme_valid_domain rejects uppercase" 1 "$r"
acme_valid_domain "a..b" && r=0 || r=$?
assert_rc "acme_valid_domain rejects an empty label" 1 "$r"
acme_valid_domain "a-b.c.example" && r=0 || r=$?
assert_rc "acme_valid_domain accepts inner hyphens" 0 "$r"
acme_valid_domain "acme-sh.example" && r=0 || r=$?
assert_rc "acme_valid_domain accepts a hyphenated label" 0 "$r"
acme_valid_domain "relay_example.com" && r=0 || r=$?
assert_rc "acme_valid_domain rejects an underscore" 1 "$r"
acme_valid_domain "" && r=0 || r=$?
assert_rc "acme_valid_domain rejects empty" 1 "$r"

# --- standalone preflight -------------------------------------------------
# The http challenge runs in acme.sh's own standalone mode, which binds port 80
# itself: nothing else may hold it, and socat or python3 must be present.
assert_eq "ACME_HTTP_PORT is 80" "80" "$ACME_HTTP_PORT"

# port_in_use reads ss; a stub makes the busy case deterministic. The real
# `ss -H -tuln` layout puts the local address in field 5.
busy_ss() {
    cat > "$SANDBOX/bin/ss" <<'STUB'
#!/bin/sh
echo "tcp LISTEN 0 128 0.0.0.0:80 0.0.0.0:*"
STUB
    chmod 755 "$SANDBOX/bin/ss"
}
busy_ss
port_in_use 80 && r=0 || r=$?
assert_rc "port_in_use sees a bound port" 0 "$r"
rm -f "$SANDBOX/bin/ss"

mkdir -p "$SANDBOX/bin"
if ! command -v socat >/dev/null 2>&1; then
    printf '#!/bin/sh\nexit 0\n' > "$SANDBOX/bin/socat"
    chmod 755 "$SANDBOX/bin/socat"
fi
ensure_standalone_tool && r=0 || r=$?
assert_rc "ensure_standalone_tool accepts socat" 0 "$r"

# With neither socat nor python3 and no known package manager, it fails rather
# than pretending the challenge will work.
emptybin="$SANDBOX/emptybin"; mkdir -p "$emptybin"
(
    PATH="$emptybin"
    PKG_MANAGER=""
    ensure_standalone_tool >/dev/null 2>&1
)
assert_rc "ensure_standalone_tool fails without socat, python3 or a package manager" 1 "$?"

# resolve_cert_mode refuses to issue when the port is taken, and points at the
# dns escape hatch. The check runs before ensure_acme, so the real acme.sh
# installer is never reached.
rm -rf "$ACME_DIR"; rm -f "$CRONTAB_FILE"; clear_cert_mode; clear_pin
ARG_ACME_DOMAIN="relay.example.com"; ARG_ACME_EMAIL=""
ARG_ACME_CHALLENGE="http"; ARG_ACME_DNS=""; ARG_ACME_AUTO_RENEW="yes"
: > "$ACME_STUB_LOG"
busy_ss
out="$(resolve_cert_mode "acme" "relay.example.com" true 2>&1)"
rc=$?
rm -f "$SANDBOX/bin/ss"
assert_rc "resolve_cert_mode acme aborts when port 80 is busy" 1 "$rc"
assert_match "the busy-port error names the port" "Port 80 is in use" "$out"
assert_match "the busy-port error suggests dns" "acme-challenge dns" "$out"
assert_eq "a busy port never reaches acme.sh" "0" "$(grep -c ' --issue' "$ACME_STUB_LOG")"
assert_eq "a busy port records no sidecar" "absent" \
    "$(if [[ -f "$CERT_MODE_FILE" ]]; then echo present; else echo absent; fi)"

# dns skips the port check entirely.
: > "$ACME_STUB_LOG"
rm -rf "$ACME_DIR"; rm -f "$CRONTAB_FILE"; clear_cert_mode; clear_pin
ARG_ACME_CHALLENGE="dns"; ARG_ACME_DNS="dns_cf"
resolve_cert_mode "acme" "relay.example.com" true >/dev/null 2>&1
assert_eq "dns challenge issues despite a busy port 80" "1" \
    "$(grep -c ' --dns dns_cf' "$ACME_STUB_LOG")"
assert_eq "dns challenge records the sidecar" "acme" "$(load_cert_mode_field mode)"
ARG_ACME_CHALLENGE="http"; ARG_ACME_DNS=""

# --- acme_paths ----------------------------------------------------------
# acme_paths assigns ACME_CRT/ACME_KEY in the caller's scope, so it must not be
# called inside a command substitution (that would drop them in a subshell).
acme_paths relay.example.com >/dev/null
assert_eq "acme_paths echoes crt then key" \
    "${ACME_DIR}/relay.example.com_ecc/fullchain.cer
${ACME_DIR}/relay.example.com_ecc/relay.example.com.key" "$(acme_paths relay.example.com)"
assert_eq "acme_paths exports ACME_CRT" \
    "${ACME_DIR}/relay.example.com_ecc/fullchain.cer" "$ACME_CRT"
assert_eq "acme_paths exports ACME_KEY" \
    "${ACME_DIR}/relay.example.com_ecc/relay.example.com.key" "$ACME_KEY"

# --- hooks ---------------------------------------------------------------
write_acme_reload_hook
assert_eq "acme-reload.sh is executable" "755" "$(stat -c '%a' "$ACME_RELOAD_HOOK")"
assert_match "acme-reload.sh restarts the service" "restart ${SERVICE_NAME}" "$(cat "$ACME_RELOAD_HOOK")"
assert_eq "acme-reload.sh exits 0 so a reload failure never fails the issue" "1" \
    "$(grep -c '^exit 0$' "$ACME_RELOAD_HOOK")"

write_acme_renew_hook relay.example.com 30
assert_eq "acme-renew.sh is executable" "755" "$(stat -c '%a' "$ACME_RENEW_HOOK")"
assert_match "acme-renew.sh renews only our domain" '--renew -d "\$DOMAIN" --ecc --home' "$(cat "$ACME_RENEW_HOOK")"
assert_match "acme-renew.sh logs to the renew log" "$ACME_RENEW_LOG" "$(cat "$ACME_RENEW_HOOK")"
assert_match "acme-renew.sh gates on the renewal window" 'checkend "\$\(\(RENEW_DAYS \* 86400\)\)"' "$(cat "$ACME_RENEW_HOOK")"
assert_eq "acme-renew.sh bakes in the renewal window" "1" "$(grep -c '^RENEW_DAYS="30"$' "$ACME_RENEW_HOOK")"
assert_eq "acme-renew.sh bakes in the domain" "1" "$(grep -c '^DOMAIN="relay\.example\.com"$' "$ACME_RENEW_HOOK")"
assert_eq "acme-renew.sh pins cron's PATH" "1" \
    "$(grep -c '^PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin$' "$ACME_RENEW_HOOK")"
assert_eq "acme-renew.sh exits 0 so cron never sees a failure" "1" \
    "$(grep -c '^exit 0$' "$ACME_RENEW_HOOK")"
# A custom window must reach the hook, or --acme-renew-days would be a no-op.
write_acme_renew_hook relay.example.com 14
assert_eq "acme-renew.sh honours a custom renewal window" "1" "$(grep -c '^RENEW_DAYS="14"$' "$ACME_RENEW_HOOK")"
# The gate is what makes a daily job quiet: a certificate far from expiry must
# not reach acme.sh at all.
FAKE_CRT="$SANDBOX/far.crt"
openssl req -x509 -newkey rsa:2048 -keyout "$SANDBOX/far.key" -out "$FAKE_CRT" \
    -days 400 -nodes -subj "/CN=far.example.com" >/dev/null 2>&1
acme_renew_due "$FAKE_CRT" 30 && r=0 || r=$?
assert_rc "acme_renew_due is false well outside the window" 1 "$r"
acme_renew_due "$FAKE_CRT" 500 && r=0 || r=$?
assert_rc "acme_renew_due is true inside the window" 0 "$r"
acme_renew_due "$SANDBOX/nonexistent.crt" 30 && r=0 || r=$?
assert_rc "acme_renew_due is true when no certificate exists" 0 "$r"

# --- cron install / remove ----------------------------------------------
rm -f "$CRONTAB_FILE" "$ACME_CRON_D_FILE"
install_acme_auto_renew
assert_eq "crontab gets a marked entry" "1" "$(grep -c "$ACME_CRON_MARK" "$CRONTAB_FILE")"
assert_eq "crontab entry runs the renew hook" "1" "$(grep -c "$ACME_RENEW_HOOK" "$CRONTAB_FILE")"
assert_eq "crontab entry uses the odd-minute schedule" "1" \
    "$(grep -cF "${ACME_CRON_MARK} ${ACME_CRON_SCHEDULE} ${ACME_RENEW_HOOK}" "$CRONTAB_FILE")"
assert_eq "install leaves no leading blank line" "1" "$(head -n 1 "$CRONTAB_FILE" | grep -c "$ACME_CRON_MARK")"
acme_auto_renew_active && r=0 || r=$?
assert_rc "acme_auto_renew_active sees the entry" 0 "$r"
install_acme_auto_renew
assert_eq "a second install does not duplicate the entry" "1" "$(grep -c "$ACME_CRON_MARK" "$CRONTAB_FILE")"
# A pre-existing crontab must survive.
printf '0 5 * * * /usr/local/bin/backup\n' > "$CRONTAB_FILE"
install_acme_auto_renew
assert_eq "install_acme_auto_renew keeps the operator's own jobs" "1" \
    "$(grep -c '/usr/local/bin/backup' "$CRONTAB_FILE")"
remove_acme_auto_renew
assert_eq "remove_acme_auto_renew drops the mark" "0" "$(grep -c "$ACME_CRON_MARK" "$CRONTAB_FILE")"
assert_eq "remove_acme_auto_renew drops the hook path" "0" "$(grep -c "$ACME_RENEW_HOOK" "$CRONTAB_FILE")"
assert_eq "remove_acme_auto_renew keeps the operator's own jobs" "1" \
    "$(grep -c '/usr/local/bin/backup' "$CRONTAB_FILE")"
acme_auto_renew_active && r=0 || r=$?
assert_rc "acme_auto_renew_active is false after removal" 1 "$r"
rm -f "$CRONTAB_FILE"

# cron.d fallback: install_acme_auto_renew prefers the crontab branch whenever
# crontab exists, so assert the cron.d file is only used (and cleared) when
# crontab is absent. Shadow crontab with a non-executable file so the branch is
# genuinely unreachable, then confirm the fallback file is not written.
mkdir -p "$SANDBOX/bin-noexec"
printf '#!/bin/sh\nexit 127\n' > "$SANDBOX/bin-noexec/crontab"
chmod 644 "$SANDBOX/bin-noexec/crontab"
install_acme_auto_renew
assert_eq "crontab branch is still preferred" "1" "$(grep -c "$ACME_RENEW_HOOK" "$CRONTAB_FILE")"
assert_eq "the cron.d file is not written when crontab exists" "absent" \
    "$(if [[ -f "$ACME_CRON_D_FILE" ]]; then echo present; else echo absent; fi)"
remove_acme_auto_renew
assert_eq "remove_acme_auto_renew clears the cron.d file too" "absent" \
    "$(if [[ -f "$ACME_CRON_D_FILE" ]]; then echo present; else echo absent; fi)"
rm -f "$CRONTAB_FILE"
cron_daemon_available && r=0 || r=$?
assert_rc "cron_daemon_available is true with the crontab stub" 0 "$r"
# The same probe with no crontab(1) on PATH and no /etc/cron.d: only reachable
# by clearing PATH, which is why this one runs in a subshell.
cron_daemon_available_nopath() {
    local saved="$PATH"
    PATH="/nonexistent"
    cron_daemon_available
    local rc=$?
    PATH="$saved"
    return $rc
}
[[ -d /etc/cron.d ]] && r=0 || r=$?
if [[ "$r" == "0" ]]; then
    cron_daemon_available_nopath && r2=0 || r2=$?
    assert_rc "cron_daemon_available falls back to /etc/cron.d" 0 "$r2"
else
    cron_daemon_available_nopath && r2=0 || r2=$?
    assert_rc "cron_daemon_available is false without cron or cron.d" 1 "$r2"
fi

# A cron entry count helper: grep -c already prints 0 on no match and exits 1,
# so `|| echo 0` would double the output.
cron_hits() {
    if [[ -f "$CRONTAB_FILE" ]]; then
        grep -c "$1" "$CRONTAB_FILE" 2>/dev/null || true
    else
        echo 0
    fi
}

# --- issue / renew -------------------------------------------------------
rm -rf "$ACME_DIR"
: > "$ACME_STUB_LOG"
acme_issue_cert relay.example.com me@example.com http ""
assert_eq "acme_issue_cert succeeds with the stub" "0" "$?"
assert_eq "acme_issue_cert passes --issue" "1" "$(grep -c '^--issue' "$ACME_STUB_LOG")"
assert_eq "acme_issue_cert passes -d" "1" "$(grep -c ' -d relay\.example\.com' "$ACME_STUB_LOG")"
assert_eq "acme_issue_cert uses ec-256" "1" "$(grep -c ' --keylength ec-256' "$ACME_STUB_LOG")"
assert_eq "acme_issue_cert uses the letsencrypt server" "1" \
    "$(grep -c ' --server letsencrypt' "$ACME_STUB_LOG")"
assert_eq "acme_issue_cert passes the reload hook" "1" \
    "$(grep -c " --reloadcmd ${ACME_RELOAD_HOOK}" "$ACME_STUB_LOG")"
assert_eq "acme_issue_cert passes the account email" "1" \
    "$(grep -c ' --accountemail me@example\.com' "$ACME_STUB_LOG")"
assert_eq "acme_issue_cert http challenge uses --standalone" "1" \
    "$(grep -c ' --standalone' "$ACME_STUB_LOG")"
assert_eq "acme_issue_cert http challenge omits --dns" "0" "$(grep -c ' --dns ' "$ACME_STUB_LOG")"

: > "$ACME_STUB_LOG"
acme_issue_cert relay.example.com "" dns dns_cf
assert_eq "acme_issue_cert dns challenge passes the plugin" "1" \
    "$(grep -c ' --dns dns_cf' "$ACME_STUB_LOG")"
assert_eq "acme_issue_cert dns challenge omits --standalone" "0" \
    "$(grep -c ' --standalone' "$ACME_STUB_LOG")"
assert_eq "acme_issue_cert omits the email flag when empty" "0" \
    "$(grep -c ' --accountemail' "$ACME_STUB_LOG")"
acme_issue_cert relay.example.com "" dns "" && r=0 || r=$?
assert_rc "acme_issue_cert rejects dns without a plugin" 1 "$r"

: > "$ACME_STUB_LOG"
acme_renew_cert relay.example.com
assert_eq "acme_renew_cert succeeds" "0" "$?"
assert_eq "acme_renew_cert passes --renew -d --ecc" "1" \
    "$(grep -c '^--renew -d relay\.example\.com --ecc$' "$ACME_STUB_LOG")"

# A failing stub propagates.
printf '#!/bin/sh\nexit 1\n' > "$ACME_BIN"
chmod 755 "$ACME_BIN"
acme_issue_cert relay.example.com "" http "" && r=0 || r=$?
assert_rc "acme_issue_cert reports a stub failure" 1 "$r"
acme_renew_cert relay.example.com && r=0 || r=$?
assert_rc "acme_renew_cert reports a stub failure" 1 "$r"

# --- resolve_cert_mode acme branch (skip_prompts=true) --------------------
cat > "$ACME_BIN" <<'STUB'
#!/bin/sh
echo "$@" >> "$ACME_STUB_LOG"
case "$1" in
    --issue)
        mkdir -p "${ACME_DIR}/relay.example.com_ecc"
        echo "cert" > "${ACME_DIR}/relay.example.com_ecc/fullchain.cer"
        echo "key"  > "${ACME_DIR}/relay.example.com_ecc/relay.example.com.key"
        ;;
esac
exit 0
STUB
chmod 755 "$ACME_BIN"

rm -rf "$ACME_DIR"; rm -f "$CRONTAB_FILE"
clear_cert_mode; clear_pin
ARG_ACME_DOMAIN="relay.example.com"
ARG_ACME_EMAIL="me@example.com"
ARG_ACME_CHALLENGE="http"
ARG_ACME_DNS=""
ARG_ACME_AUTO_RENEW="yes"
resolve_cert_mode "acme" "relay.example.com" true >/dev/null 2>&1
assert_eq "resolve_cert_mode acme sets tls=2" "2" "$CERT_TLS"
assert_eq "resolve_cert_mode acme clears the pin" "" "$(load_pin)"
assert_eq "resolve_cert_mode acme points crt at the issued chain" \
    "${ACME_DIR}/relay.example.com_ecc/fullchain.cer" "$CERT_CRT"
assert_eq "resolve_cert_mode acme points keyfile at the issued key" \
    "${ACME_DIR}/relay.example.com_ecc/relay.example.com.key" "$CERT_KEYFILE"
assert_eq "resolve_cert_mode acme writes the sidecar mode" "acme" "$(load_cert_mode_field mode)"
assert_eq "resolve_cert_mode acme writes the sidecar domain" "relay.example.com" "$(load_cert_mode_field domain)"
assert_eq "resolve_cert_mode acme writes the sidecar autorenew" "yes" "$(load_cert_mode_field autorenew)"
assert_eq "resolve_cert_mode acme writes the sidecar renewdays" "30" "$(load_cert_mode_field renewdays)"
assert_eq "resolve_cert_mode acme installs the reload hook" "755" "$(stat -c '%a' "$ACME_RELOAD_HOOK")"
assert_eq "resolve_cert_mode acme installs the renew hook" "755" "$(stat -c '%a' "$ACME_RENEW_HOOK")"
assert_eq "resolve_cert_mode acme installs the cron entry" "1" "$(grep -c "$ACME_RENEW_HOOK" "$CRONTAB_FILE")"
assert_eq "resolve_cert_mode acme bakes the window into the renew hook" "1" \
    "$(grep -c '^RENEW_DAYS="30"$' "$ACME_RENEW_HOOK")"

# Re-running with the certificate already present renews instead of issuing.
: > "$ACME_STUB_LOG"
resolve_cert_mode "acme" "relay.example.com" true >/dev/null 2>&1
assert_eq "resolve_cert_mode acme re-runs renew, not issue" "1" "$(grep -c '^--renew' "$ACME_STUB_LOG")"
assert_eq "resolve_cert_mode acme re-run issues nothing" "0" "$(grep -c '^--issue' "$ACME_STUB_LOG")"

# A real certificate far from expiry must be left alone: this is the whole point
# of the renewal window, and re-issuing here would waste a duplicate allowance.
mk_real_acme_cert() {
    local days="$1" dir="${ACME_DIR}/relay.example.com_ecc"
    mkdir -p "$dir"
    openssl req -x509 -newkey rsa:2048 -keyout "$dir/relay.example.com.key" \
        -out "$dir/fullchain.cer" -days "$days" -nodes \
        -subj "/CN=relay.example.com" >/dev/null 2>&1
}
mk_real_acme_cert 400
: > "$ACME_STUB_LOG"
resolve_cert_mode "acme" "relay.example.com" true >/dev/null 2>&1
assert_eq "a certificate outside the window is not renewed" "0" "$(grep -c '^--renew' "$ACME_STUB_LOG")"
assert_eq "a certificate outside the window is not re-issued" "0" "$(grep -c '^--issue' "$ACME_STUB_LOG")"
assert_eq "a certificate outside the window still records the sidecar" "acme" "$(load_cert_mode_field mode)"

# The same certificate inside a short window is renewed.
mk_real_acme_cert 20
: > "$ACME_STUB_LOG"
resolve_cert_mode "acme" "relay.example.com" true >/dev/null 2>&1
assert_eq "a certificate inside the window is renewed" "1" "$(grep -c '^--renew' "$ACME_STUB_LOG")"
assert_eq "a certificate inside the window is not re-issued" "0" "$(grep -c '^--issue' "$ACME_STUB_LOG")"

# --acme-renew-days reaches the sidecar and the generated hook.
ARG_ACME_RENEW_DAYS="45"
: > "$ACME_STUB_LOG"
resolve_cert_mode "acme" "relay.example.com" true >/dev/null 2>&1
assert_eq "resolve_cert_mode acme honours --acme-renew-days in the sidecar" "45" \
    "$(load_cert_mode_field renewdays)"
assert_eq "resolve_cert_mode acme honours --acme-renew-days in the renew hook" "1" \
    "$(grep -c '^RENEW_DAYS="45"$' "$ACME_RENEW_HOOK")"
ARG_ACME_RENEW_DAYS=""

# A previously chosen window survives a re-configure that does not restate it.
mk_real_acme_cert 400
: > "$ACME_STUB_LOG"
resolve_cert_mode "acme" "relay.example.com" true >/dev/null 2>&1
assert_eq "a re-configure keeps the stored renewal window" "45" "$(load_cert_mode_field renewdays)"
assert_eq "a re-configure does not renew outside the window" "0" "$(grep -c '^--renew' "$ACME_STUB_LOG")"

# An out-of-range window is rejected before acme.sh runs.
rm -rf "$ACME_DIR"; clear_cert_mode
ARG_ACME_RENEW_DAYS="120"
resolve_cert_mode "acme" "relay.example.com" true >/dev/null 2>&1
assert_rc "resolve_cert_mode acme rejects a window over 89 days" 1 "$?"
ARG_ACME_RENEW_DAYS="0"
resolve_cert_mode "acme" "relay.example.com" true >/dev/null 2>&1
assert_rc "resolve_cert_mode acme rejects a zero-day window" 1 "$?"
ARG_ACME_RENEW_DAYS=""

# --acme-auto-renew no removes the cron entry and records no.
ARG_ACME_AUTO_RENEW="no"
resolve_cert_mode "acme" "relay.example.com" true >/dev/null 2>&1
assert_eq "autorenew=no records no" "no" "$(load_cert_mode_field autorenew)"
assert_eq "autorenew=no removes the cron entry" "0" "$(cron_hits "$ACME_RENEW_HOOK")"
acme_auto_renew_active && r=0 || r=$?
assert_rc "autorenew=no leaves auto-renew inactive" 1 "$r"
ARG_ACME_AUTO_RENEW="yes"

# A failed issue is fatal and leaves no sidecar behind.
printf '#!/bin/sh\nexit 1\n' > "$ACME_BIN"; chmod 755 "$ACME_BIN"
rm -rf "$ACME_DIR"; clear_cert_mode
resolve_cert_mode "acme" "relay.example.com" true >/dev/null 2>&1
assert_rc "resolve_cert_mode acme fails when the issue fails" 1 "$?"
assert_eq "a failed issue writes no sidecar" "absent" \
    "$(if [[ -f "$CERT_MODE_FILE" ]]; then echo present; else echo absent; fi)"

# A bad domain is rejected before acme.sh is ever invoked.
cat > "$ACME_BIN" <<'STUB'
#!/bin/sh
echo "$@" >> "$ACME_STUB_LOG"
exit 0
STUB
chmod 755 "$ACME_BIN"
: > "$ACME_STUB_LOG"
ARG_ACME_DOMAIN="not a domain"
resolve_cert_mode "acme" "relay.example" true >/dev/null 2>&1
assert_rc "resolve_cert_mode acme rejects a bad domain" 1 "$?"
assert_eq "a rejected domain never reaches acme.sh" "0" "$(wc -c < "$ACME_STUB_LOG")"

# dns without a plugin is rejected too.
ARG_ACME_DOMAIN="relay.example.com"
ARG_ACME_CHALLENGE="dns"
ARG_ACME_DNS=""
resolve_cert_mode "acme" "relay.example.com" true >/dev/null 2>&1
assert_rc "resolve_cert_mode acme rejects dns without a plugin" 1 "$?"
ARG_ACME_CHALLENGE="http"

# An unparsable autorenew value is rejected.
ARG_ACME_AUTO_RENEW="maybe"
resolve_cert_mode "acme" "relay.example.com" true >/dev/null 2>&1
assert_rc "resolve_cert_mode acme rejects a bad autorenew value" 1 "$?"
ARG_ACME_AUTO_RENEW="yes"

# --- interactive prompts -------------------------------------------------
# Feed the acme answers through stdin; the prompts are read in this order:
# domain, email, challenge, auto-renew, renew-days (and the DNS plugin right
# after the challenge when dns is chosen).
cat > "$ACME_BIN" <<'STUB'
#!/bin/sh
echo "$@" >> "$ACME_STUB_LOG"
case "$1" in
    --issue)
        mkdir -p "${ACME_DIR}/relay.example.com_ecc"
        echo "cert" > "${ACME_DIR}/relay.example.com_ecc/fullchain.cer"
        echo "key"  > "${ACME_DIR}/relay.example.com_ecc/relay.example.com.key"
        ;;
esac
exit 0
STUB
chmod 755 "$ACME_BIN"
rm -rf "$ACME_DIR"; rm -f "$CRONTAB_FILE"; clear_cert_mode; clear_pin
ARG_ACME_DOMAIN=""; ARG_ACME_EMAIL=""; ARG_ACME_CHALLENGE="http"; ARG_ACME_DNS=""
ARG_ACME_AUTO_RENEW="yes"
: > "$ACME_STUB_LOG"
resolve_cert_mode "acme" "relay.example.com" false \
    < <(printf 'relay.example.com\nme@example.com\nhttp\nyes\n14\n') >/dev/null 2>&1
assert_eq "prompted domain is used" "relay.example.com" "$(load_cert_mode_field domain)"
assert_eq "prompted email reaches acme.sh" "1" \
    "$(grep -c ' --accountemail me@example\.com' "$ACME_STUB_LOG")"
assert_eq "prompted challenge http uses standalone" "1" "$(grep -c ' --standalone' "$ACME_STUB_LOG")"
assert_eq "prompted autorenew yes installs cron" "1" "$(grep -c "$ACME_RENEW_HOOK" "$CRONTAB_FILE")"
assert_eq "prompted renew days reach the sidecar" "14" "$(load_cert_mode_field renewdays)"
assert_eq "prompted renew days reach the renew hook" "1" \
    "$(grep -c '^RENEW_DAYS="14"$' "$ACME_RENEW_HOOK")"

# dns as the prompted challenge asks for the plugin afterwards.
: > "$ACME_STUB_LOG"
rm -rf "$ACME_DIR"; rm -f "$CRONTAB_FILE"; clear_cert_mode
resolve_cert_mode "acme" "relay.example.com" false \
    < <(printf 'relay.example.com\n\ndns\ndns_cf\nno\n21\n') >/dev/null 2>&1
assert_eq "prompted dns plugin reaches acme.sh" "1" "$(grep -c ' --dns dns_cf' "$ACME_STUB_LOG")"
assert_eq "prompted dns omits standalone" "0" "$(grep -c ' --standalone' "$ACME_STUB_LOG")"
assert_eq "prompted autorenew no records no" "no" "$(load_cert_mode_field autorenew)"
assert_eq "prompted renew days after dns reach the sidecar" "21" "$(load_cert_mode_field renewdays)"

# Empty answers fall back to the ARG_* defaults.
: > "$ACME_STUB_LOG"
rm -rf "$ACME_DIR"; rm -f "$CRONTAB_FILE"; clear_cert_mode
ARG_ACME_DOMAIN="relay.example.com"; ARG_ACME_EMAIL="me@example.com"
ARG_ACME_CHALLENGE="http"; ARG_ACME_AUTO_RENEW="yes"
resolve_cert_mode "acme" "relay.example.com" false \
    < <(printf '\n\n\n\n\n') >/dev/null 2>&1
assert_eq "empty answers keep the CLI domain" "relay.example.com" "$(load_cert_mode_field domain)"
assert_eq "empty answers keep the CLI email" "1" \
    "$(grep -c ' --accountemail me@example\.com' "$ACME_STUB_LOG")"
assert_eq "empty answers keep the CLI autorenew" "yes" "$(load_cert_mode_field autorenew)"
assert_eq "empty answers keep the default renewal window" "30" "$(load_cert_mode_field renewdays)"

# --- share URI: acme behaves exactly like custom (sni=, no pin=) ---------
use_profile 3
reset_config
printf 'relay.example.com\n' > "$HOST_FILE"
printf '' > "$NAME_FILE"
clear_pin
save_cert_mode acme relay.example.com yes 30
acme_paths relay.example.com >/dev/null
write_url "portal://${KEY32}@*:2077/tcp:2077/udp:2077?tls=2&crt=${ACME_CRT}&key=${ACME_KEY}&morph=1"
out="$(show_share_uri 2>&1 | plain)"
assert_match "share nw3 acme embeds sni" \
    "nowhere://${KEY32}@relay\.example\.com:2077\?net=tcp&morph=1&sni=relay\.example\.com" "$out"
assert_eq "share nw3 acme omits pin" "0" "$(printf '%s\n' "$out" | grep -c 'pin=')"

use_profile 2
reset_config
printf 'relay.example.com\n' > "$HOST_FILE"
printf '' > "$NAME_FILE"
clear_pin
save_cert_mode acme relay.example.com yes 30
acme_paths relay.example.com >/dev/null
write_url "portal://${KEY64}@*:2077/tcp:2077/udp:2077?tls=2&crt=${ACME_CRT}&key=${ACME_KEY}&morph=1"
out="$(show_share_uri 2>&1 | plain)"
assert_match "share nw2 acme embeds sni" \
    "nowhere://${KEY64}@relay\.example\.com:2077\?up=udp&down=udp&morph=1&sni=relay\.example\.com" "$out"
assert_eq "share nw2 acme omits pin" "0" "$(printf '%s\n' "$out" | grep -c 'pin=')"

# --- status output -------------------------------------------------------
use_profile 3
reset_config
printf 'relay.example.com\n' > "$HOST_FILE"
save_cert_mode acme relay.example.com yes 30
acme_paths relay.example.com >/dev/null
write_url "portal://${KEY32}@*:2077/tcp:2077/udp:2077?tls=2&crt=${ACME_CRT}&key=${ACME_KEY}&morph=1"
out="$(show_status 2>&1 | plain | grep -v 'Migrated')"
assert_match "status shows the acme certificate source" "acme" "$out"
assert_match "status shows the ACME domain" "ACME domain: relay.example.com" "$out"
assert_match "status shows the renewal schedule" "ACME renew: *on \(17 3 \* \* \*, renews inside the last 30 days of validity\)" "$out"
assert_eq "status omits a pin for acme" "0" "$(printf '%s\n' "$out" | grep -c 'pin ')"

save_cert_mode acme relay.example.com no
out="$(show_status 2>&1 | plain | grep -v 'Migrated')"
assert_match "status shows renewal off" "off - renew with --renew-cert" "$out"

# --- mf_display_value ---------------------------------------------------
use_profile 3
reset_config
cert_mode="acme"
assert_eq "mf_display_value cert_mode acme shows tls=2" "acme (tls=2)" \
    "$(mf_display_value cert_mode 2>/dev/null)"


# The modify-configuration editor can switch to acme too: it drives
# resolve_cert_mode with the interactive prompts, so the sandbox above is
# what keeps the real ~/.acme.sh and the cron daemon out of the way.
mf_acme_case() {
    local cert_mode="$1" tls="$2" crt="$DEFAULT_CERT" keyfile="$DEFAULT_KEYFILE" host="relay.example.com"
    shift 2
    mf_edit_field "portal" "cert_mode" "prompt_cert_mode" < <(printf '%s' "$1") >/dev/null 2>&1
    MF_CERT_MODE="$cert_mode"; MF_TLS="$tls"; MF_CRT="$crt"
}
use_profile 3
reset_config
clear_pin
clear_cert_mode
rm -rf "$ACME_DIR"; rm -f "$CRONTAB_FILE"
ARG_ACME_DOMAIN=""; ARG_ACME_EMAIL=""; ARG_ACME_CHALLENGE="http"
ARG_ACME_DNS=""; ARG_ACME_AUTO_RENEW="yes"
mf_acme_case acme 2 $'4\nrelay.example.com\nme@example.com\nhttp\nno\n'
assert_eq "mf_edit_field switches to acme" "acme" "$MF_CERT_MODE"
assert_eq "mf_edit_field acme sets tls=2" "2" "$MF_TLS"
assert_eq "mf_edit_field acme points crt at the acme chain" "$ACME_DIR/relay.example.com_ecc/fullchain.cer" "$MF_CRT"
assert_eq "mf_edit_field acme records the sidecar mode" "acme" "$(load_cert_mode_field mode)"
assert_eq "mf_edit_field acme records the sidecar domain" "relay.example.com" "$(load_cert_mode_field domain)"
assert_eq "mf_edit_field acme honours autorenew no" "no" "$(load_cert_mode_field autorenew)"
assert_eq "mf_edit_field acme clears the pin" "" "$(load_pin)"
assert_eq "mf_edit_field acme with autorenew no installs no cron" "0" \
    "$(cron_hits "$ACME_CRON_MARK")"

# --- systemd unit path ---------------------------------------------------
# A sourced install flow must be able to redirect the unit file, otherwise a
# test would write the host's real /etc/systemd/system/nowhere.service.
SYSTEMD_UNIT_FILE="$SANDBOX/nowhere.service"
install_systemd_service
assert_eq "install_systemd_service honours SYSTEMD_UNIT_FILE" "yes" \
    "$([[ -f "$SANDBOX/nowhere.service" ]] && echo yes || echo no)"
assert_eq "the sandboxed unit points at the launcher" "1" \
    "$(grep -c "^ExecStart=${LAUNCHER}$" "$SANDBOX/nowhere.service")"
assert_eq "the sandboxed unit carries the service name" "1" \
    "$(grep -c "^SyslogIdentifier=${SERVICE_NAME}$" "$SANDBOX/nowhere.service")"
assert_eq "the real unit file is untouched" "no" \
    "$([[ -f "/etc/systemd/system/${SERVICE_NAME}.service" ]] && echo yes || echo no)"
SYSTEMD_UNIT_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

# ==================== summary ====================
printf '\n----------------------------------------\n'
printf 'passed: %d   failed: %d\n' "$PASS" "$FAIL"
if [[ "$FAIL" -gt 0 ]]; then
    printf 'failing tests:\n'
    printf '  - %s\n' "${FAILED_NAMES[@]}"
    exit 1
fi
printf 'ALL TESTS PASSED\n'
exit 0
