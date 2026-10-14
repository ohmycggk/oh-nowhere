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
