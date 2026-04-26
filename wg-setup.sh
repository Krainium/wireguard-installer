#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
#  🔷🌐  wg-setup  —  WireGuard VPN Server Installer
#  Fast · Modern · Encrypted · QR Code · Peer Management · Multi-distro
# https://github.com/Krainium/wireguard-installer
# Copyright (c) 2026 Krainium. Released under the MIT License.
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

# ─── Colours ──────────────────────────────────────────────────────────────────
R="\033[0m"
BOLD="\033[1m"
DIM="\033[2m"
RED="\033[31m"
GRN="\033[32m"
YLW="\033[33m"
BLU="\033[34m"
MAG="\033[35m"
CYN="\033[36m"
WHT="\033[97m"
PUR="\033[38;5;135m"
ORG="\033[38;5;208m"

# ─── Logging helpers ──────────────────────────────────────────────────────────
info()       { echo -e "${BLU}${BOLD}  ℹ  ${R}${WHT}$*${R}"; }
ok()         { echo -e "${GRN}${BOLD}  ✔  ${R}${GRN}$*${R}"; }
warn()       { echo -e "${YLW}${BOLD}  ⚠  ${R}${YLW}$*${R}"; }
err()        { echo -e "${RED}${BOLD}  ✖  ${R}${RED}$*${R}"; exit 1; }
step()       { echo -e "\n${CYN}${BOLD}  ▶  $*${R}"; }
divider()    { echo -e "${DIM}  ──────────────────────────────────────────────────${R}"; }
installing() { echo -e "${MAG}${BOLD}  ⬇  ${R}${MAG}Installing $*...${R}"; }
prompt()     { echo -en "${CYN}${BOLD}  ➤  ${R}${WHT}$*${R}"; }

# ─── Root check ───────────────────────────────────────────────────────────────
[[ "$EUID" -ne 0 ]] && { echo -e "\n  Run as root:  sudo bash $0\n"; exit 1; }

# ─── OS + package manager ─────────────────────────────────────────────────────
OS="unknown"; PM_UPDATE=""; PM_INSTALL=""

detect_os() {
    [[ -f /etc/os-release ]] && { source /etc/os-release; OS="${ID:-unknown}"; }
    if   command -v apt-get &>/dev/null; then
        PM_UPDATE="apt-get update -qq"
        PM_INSTALL="DEBIAN_FRONTEND=noninteractive apt-get install -y -qq"
    elif command -v dnf &>/dev/null; then
        PM_UPDATE="dnf check-update -q || true"
        PM_INSTALL="dnf install -y -q"
    elif command -v yum &>/dev/null; then
        PM_UPDATE="yum check-update -q || true"
        PM_INSTALL="yum install -y -q"
    elif command -v pacman &>/dev/null; then
        PM_UPDATE="pacman -Sy --noconfirm --quiet"
        PM_INSTALL="pacman -S --noconfirm --quiet"
    fi
}

pkg_install() {
    [[ -z "$PM_INSTALL" ]] && { warn "No package manager — install $* manually"; return 1; }
    eval "$PM_UPDATE" &>/dev/null || true
    eval "$PM_INSTALL $*"
}

# ─── State ────────────────────────────────────────────────────────────────────
STATE_DIR="/etc/wg-setup"
STATE_FILE="${STATE_DIR}/state.conf"
WG_CONF="/etc/wireguard/wg0.conf"
PEER_DIR="/root/wg-setup/peers"

SERVER_PUB_IP=""; WG_PORT="51820"
SERVER_PRIV_KEY=""; SERVER_PUB_KEY=""
WG_NIC=""
DNS1="1.1.1.1"; DNS2="1.0.0.1"
WG_SUBNET="10.10.0"   # peers get 10.10.0.x/24 — server is .1
INSTALLED=0

save_state() {
    mkdir -p "$STATE_DIR"; chmod 700 "$STATE_DIR"
    cat > "$STATE_FILE" <<EOF
SERVER_PUB_IP="${SERVER_PUB_IP:-}"
WG_PORT="${WG_PORT:-51820}"
SERVER_PRIV_KEY="${SERVER_PRIV_KEY:-}"
SERVER_PUB_KEY="${SERVER_PUB_KEY:-}"
WG_NIC="${WG_NIC:-}"
DNS1="${DNS1:-1.1.1.1}"
DNS2="${DNS2:-1.0.0.1}"
WG_SUBNET="${WG_SUBNET:-10.10.0}"
INSTALLED="${INSTALLED:-0}"
EOF
    chmod 600 "$STATE_FILE"
}

load_state() { [[ -f "$STATE_FILE" ]] && source "$STATE_FILE" || true; }

# ─── Helpers ──────────────────────────────────────────────────────────────────
is_installed() { [[ -f "$WG_CONF" ]] && command -v wg &>/dev/null; }

get_public_ip() {
    curl -4 -fsSL --max-time 5 https://ifconfig.me 2>/dev/null \
        || curl -4 -fsSL --max-time 5 https://api.ipify.org 2>/dev/null \
        || curl -4 -fsSL --max-time 5 https://icanhazip.com 2>/dev/null \
        || echo ""
}

count_peers() { grep -c "^\[Peer\]" "$WG_CONF" 2>/dev/null || echo 0; }

# Next available /32 IP in the WG subnet (starts at .2, server is .1)
next_peer_ip() {
    local used last
    used=$(grep -oP "${WG_SUBNET//./\\.}\\.\\K[0-9]+" "$WG_CONF" 2>/dev/null | sort -n)
    last=$(echo "$used" | tail -1)
    echo "${WG_SUBNET}.$((${last:-1} + 1))"
}

# ─── Banner ───────────────────────────────────────────────────────────────────
banner() {
    clear 2>/dev/null || true
    echo -e "${PUR}${BOLD}"
    echo "  ╔══════════════════════════════════════════════════════════╗"
    echo "  ║  🔷🌐  wg-setup   WireGuard VPN Server Installer       ║"
    echo "  ║  ⚡ Fast  🔐 Modern  📱 QR Code  👥 Peer Management     ║"
    echo "  ╚══════════════════════════════════════════════════════════╝"
    echo -e "${R}"
    if is_installed; then
        load_state
        echo -e "  ${DIM}Server : ${WHT}${BOLD}${SERVER_PUB_IP}:${WG_PORT}/udp${R}"
        echo -e "  ${DIM}Peers  : ${WHT}$(count_peers)${R}"
        echo ""
    fi
}

# ─── DNS selector ─────────────────────────────────────────────────────────────
select_dns() {
    echo -e "\n${CYN}${BOLD}  Select DNS for peers:${R}"
    echo -e "  ${WHT}1${R}  Cloudflare     (1.1.1.1 / 1.0.0.1)"
    echo -e "  ${WHT}2${R}  Google         (8.8.8.8 / 8.8.4.4)"
    echo -e "  ${WHT}3${R}  OpenDNS        (208.67.222.222 / 208.67.220.220)"
    echo -e "  ${WHT}4${R}  Quad9          (9.9.9.9 / 149.112.112.112)"
    echo -e "  ${WHT}5${R}  AdGuard        (94.140.14.14 / 94.140.15.15)"
    echo -e "  ${WHT}6${R}  Current system (/etc/resolv.conf)"
    echo ""
    prompt "Choice [1]: "; read -r _d; _d="${_d:-1}"
    case "$_d" in
        1) DNS1="1.1.1.1";        DNS2="1.0.0.1" ;;
        2) DNS1="8.8.8.8";        DNS2="8.8.4.4" ;;
        3) DNS1="208.67.222.222"; DNS2="208.67.220.220" ;;
        4) DNS1="9.9.9.9";        DNS2="149.112.112.112" ;;
        5) DNS1="94.140.14.14";   DNS2="94.140.15.15" ;;
        6) DNS1=$(grep -m1 '^nameserver' /etc/resolv.conf 2>/dev/null | awk '{print $2}')
           DNS2=$(grep '^nameserver' /etc/resolv.conf 2>/dev/null | awk 'NR==2{print $2}')
           DNS1="${DNS1:-1.1.1.1}"; DNS2="${DNS2:-1.0.0.1}" ;;
        *) DNS1="1.1.1.1"; DNS2="1.0.0.1" ;;
    esac
}

# ─── Install WireGuard ────────────────────────────────────────────────────────
install_wireguard() {
    detect_os
    step "Install WireGuard Server"
    divider

    # Public IP
    info "Detecting public IP..."
    SERVER_PUB_IP=$(get_public_ip)
    if [[ -z "$SERVER_PUB_IP" ]]; then
        prompt "Public IP / hostname: "; read -r SERVER_PUB_IP
    else
        prompt "Public IP [${SERVER_PUB_IP}]: "; read -r _inp
        [[ -n "$_inp" ]] && SERVER_PUB_IP="$_inp"
    fi
    ok "Server: ${SERVER_PUB_IP}"

    # Port
    prompt "WireGuard UDP port [51820]: "; read -r _port
    WG_PORT="${_port:-51820}"
    [[ ! "$WG_PORT" =~ ^[0-9]+$ ]] && WG_PORT="51820"
    ok "Port: ${WG_PORT}/udp"

    # DNS
    select_dns
    ok "DNS: ${DNS1} / ${DNS2}"

    divider
    info "Starting installation..."

    # Packages
    installing "WireGuard"
    if command -v apt-get &>/dev/null; then
        eval "$PM_UPDATE" &>/dev/null
        eval "$PM_INSTALL wireguard-tools qrencode curl" &>/dev/null
        # Kernel module — needed on older kernels
        if ! modinfo wireguard &>/dev/null 2>&1; then
            eval "$PM_INSTALL "linux-headers-$(uname -r)" wireguard" &>/dev/null || true
        fi
    elif command -v dnf &>/dev/null; then
        dnf install -y epel-release &>/dev/null || true
        eval "$PM_INSTALL wireguard-tools qrencode curl" &>/dev/null
    elif command -v yum &>/dev/null; then
        yum install -y epel-release elrepo-release &>/dev/null || true
        eval "$PM_INSTALL wireguard-tools qrencode curl" &>/dev/null
    elif command -v pacman &>/dev/null; then
        eval "$PM_INSTALL wireguard-tools qrencode curl" &>/dev/null
    fi
    ok "WireGuard installed"

    # Server keys
    step "Generate server keys"
    mkdir -p /etc/wireguard; chmod 700 /etc/wireguard
    SERVER_PRIV_KEY=$(wg genkey)
    SERVER_PUB_KEY=$(echo "$SERVER_PRIV_KEY" | wg pubkey)
    ok "Server key pair generated"

    # Default NIC (for NAT PostUp/PostDown)
    WG_NIC=$(ip route show default 2>/dev/null | head -1 | awk '{print $5}')
    [[ -z "${WG_NIC:-}" ]] && WG_NIC=$(ip link show | awk -F': ' '/^[0-9]+: [^lo]/{print $2; exit}')
    ok "Outbound interface: ${WG_NIC}"

    # Write server config
    step "Write server config"
    cat > "$WG_CONF" <<WGCFG
[Interface]
Address    = ${WG_SUBNET}.1/24
ListenPort = ${WG_PORT}
PrivateKey = ${SERVER_PRIV_KEY}

# NAT — route peer traffic through ${WG_NIC}
PostUp   = iptables -A FORWARD -i %i -j ACCEPT; iptables -A FORWARD -o %i -j ACCEPT; iptables -t nat -A POSTROUTING -o ${WG_NIC} -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -D FORWARD -o %i -j ACCEPT; iptables -t nat -D POSTROUTING -o ${WG_NIC} -j MASQUERADE
WGCFG
    chmod 600 "$WG_CONF"
    ok "Server config → ${WG_CONF}"

    # IP forwarding
    step "Enable IP forwarding"
    {
        echo "net.ipv4.ip_forward = 1"
        echo "net.ipv6.conf.all.forwarding = 1"
    } > /etc/sysctl.d/99-wireguard.conf
    sysctl -p /etc/sysctl.d/99-wireguard.conf &>/dev/null || true
    ok "IP forwarding enabled"

    # Firewall
    step "Open port ${WG_PORT}/udp"
    if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "Status: active"; then
        ufw allow "${WG_PORT}/udp" &>/dev/null || true
        ok "UFW: ${WG_PORT}/udp allowed"
    elif command -v firewall-cmd &>/dev/null && firewall-cmd --state &>/dev/null 2>&1; then
        firewall-cmd --permanent --add-port="${WG_PORT}/udp" &>/dev/null || true
        firewall-cmd --reload &>/dev/null || true
        ok "firewalld: ${WG_PORT}/udp allowed"
    else
        iptables -A INPUT -p udp --dport "${WG_PORT}" -j ACCEPT 2>/dev/null || true
        ok "iptables: ${WG_PORT}/udp allowed"
    fi

    # Start WireGuard
    step "Start WireGuard"
    systemctl enable  wg-quick@wg0 &>/dev/null || true
    systemctl start   wg-quick@wg0 2>/dev/null || wg-quick up wg0 2>/dev/null || true
    sleep 1
    if systemctl is-active wg-quick@wg0 &>/dev/null || ip link show wg0 &>/dev/null 2>&1; then
        ok "WireGuard running  (wg0 up)"
    else
        warn "WireGuard may not have started — check: journalctl -u wg-quick@wg0 -n 20"
    fi

    INSTALLED=1
    save_state

    # First peer
    echo ""
    divider
    prompt "Name for the first peer [peer1]: "; read -r _pname
    _pname="${_pname:-peer1}"; _pname="${_pname// /_}"
    _add_peer "$_pname"
    divider
    ok "WireGuard server is ready!"
    echo -e "  ${DIM}Peer config → ${ORG}${PEER_DIR}/${_pname}.conf${R}"
    echo ""
}

# ─── Generate peer config ─────────────────────────────────────────────────────
_add_peer() {
    local name="$1"
    load_state
    mkdir -p "$PEER_DIR"; chmod 700 "$PEER_DIR"

    # Keys
    local priv pub psk
    priv=$(wg genkey)
    pub=$(echo "$priv" | wg pubkey)
    psk=$(wg genpsk)

    # Assign next IP
    local peer_ip; peer_ip=$(next_peer_ip)

    # Add peer to running WireGuard instance (live — no restart needed)
    if ip link show wg0 &>/dev/null 2>&1; then
        wg set wg0 peer "$pub" \
            preshared-key <(echo "$psk") \
            allowed-ips "${peer_ip}/32" 2>/dev/null || true
    fi

    # Persist peer block to wg0.conf for restarts
    cat >> "$WG_CONF" <<PEERSECTION

# Peer: ${name}
[Peer]
PublicKey    = ${pub}
PresharedKey = ${psk}
AllowedIPs   = ${peer_ip}/32
PEERSECTION

    # Write peer .conf file
    cat > "${PEER_DIR}/${name}.conf" <<PEERCFG
[Interface]
Address    = ${peer_ip}/24
DNS        = ${DNS1}, ${DNS2}
PrivateKey = ${priv}

[Peer]
PublicKey           = ${SERVER_PUB_KEY}
PresharedKey        = ${psk}
Endpoint            = ${SERVER_PUB_IP}:${WG_PORT}
AllowedIPs          = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
PEERCFG
    chmod 600 "${PEER_DIR}/${name}.conf"

    ok "Peer '${name}' added  —  IP: ${peer_ip}/24"
    echo -e "  ${DIM}Config → ${ORG}${PEER_DIR}/${name}.conf${R}"
    echo ""

    # QR code
    if command -v qrencode &>/dev/null; then
        echo -e "${CYN}${BOLD}  QR Code — scan in the WireGuard app:${R}"
        qrencode -t ansiutf8 < "${PEER_DIR}/${name}.conf"
        echo ""
    else
        warn "qrencode not installed — install it to display QR codes: apt-get install qrencode"
    fi
}

# ─── Add peer (interactive) ───────────────────────────────────────────────────
add_peer() {
    load_state
    step "Add WireGuard Peer"
    prompt "Peer name: "; read -r _name
    [[ -z "${_name// }" ]] && { warn "Name cannot be empty."; return; }
    _name="${_name// /_}"
    if [[ -f "${PEER_DIR}/${_name}.conf" ]]; then
        warn "Peer '${_name}' already exists."
        return
    fi
    _add_peer "$_name"
}

# ─── Remove peer ──────────────────────────────────────────────────────────────
remove_peer() {
    load_state
    step "Remove WireGuard Peer"

    # Extract peer names from wg0.conf comments
    local peers=()
    while IFS= read -r line; do
        peers+=("${line#*Peer: }")
    done < <(grep "^# Peer:" "$WG_CONF" 2>/dev/null)

    if [[ ${#peers[@]} -eq 0 ]]; then
        warn "No named peers found in ${WG_CONF}"; return
    fi

    echo ""
    local i=1
    for p in "${peers[@]}"; do
        echo -e "  ${WHT}${i}${R}  ${p}"; ((i++))
    done
    echo ""
    prompt "Select peer to remove (number): "; read -r _n
    [[ ! "$_n" =~ ^[0-9]+$ || "$_n" -lt 1 || "$_n" -gt "${#peers[@]}" ]] && {
        warn "Invalid selection."; return
    }
    local target="${peers[$((_n - 1))]}"
    echo -en "${YLW}${BOLD}  Remove peer '${target}'? [y/N]: ${R}"
    read -r _c; [[ "${_c,,}" != "y" ]] && { info "Cancelled."; return; }

    # Remove from running instance
    local peer_pub
    peer_pub=$(grep "^PublicKey" "${PEER_DIR}/${target}.conf" 2>/dev/null | awk '{print $3}')
    if [[ -n "${peer_pub:-}" ]]; then
        wg set wg0 peer "$peer_pub" remove 2>/dev/null || true
    fi

    # Remove peer block from wg0.conf using Python (reliable multiline deletion)
    python3 - "$WG_CONF" "$target" <<'PYPATCH'
import sys, re
conf_path, name = sys.argv[1], sys.argv[2]
with open(conf_path) as f:
    content = f.read()
pattern = rf'\n# Peer: {re.escape(name)}\n\[Peer\].*?(?=\n# Peer:|\Z)'
content = re.sub(pattern, '', content, flags=re.DOTALL)
with open(conf_path, 'w') as f:
    f.write(content)
PYPATCH

    rm -f "${PEER_DIR}/${target}.conf"
    ok "Peer '${target}' removed"
}

# ─── List peers ───────────────────────────────────────────────────────────────
list_peers() {
    load_state
    step "WireGuard Peers"
    echo ""

    # Live output from wg show
    if command -v wg &>/dev/null && ip link show wg0 &>/dev/null 2>&1; then
        echo -e "${CYN}${BOLD}  Live status  (wg show wg0):${R}"
        wg show wg0 2>/dev/null || true
        echo ""
    fi

    # Saved peer files
    local files=()
    while IFS= read -r f; do files+=("$f"); done < <(find "$PEER_DIR" -name "*.conf" 2>/dev/null | sort)

    if [[ ${#files[@]} -gt 0 ]]; then
        echo -e "${CYN}${BOLD}  Saved peer configs:${R}"
        for f in "${files[@]}"; do
            local name; name=$(basename "$f" .conf)
            local addr; addr=$(grep "^Address" "$f" 2>/dev/null | awk '{print $3}')
            local ep;   ep=$(grep "^Endpoint" "$f"  2>/dev/null | awk '{print $3}')
            echo -e "  ${GRN}●${R}  ${WHT}${name}${R}  ${DIM}${addr}  →  ${ep}  (${f})${R}"
        done
        echo ""
        ok "${#files[@]} peer config(s) found"
    else
        warn "No peer config files found in ${PEER_DIR}"
    fi
}

# ─── QR Code ──────────────────────────────────────────────────────────────────
show_qr() {
    load_state
    step "Show QR Code"

    local files=()
    while IFS= read -r f; do files+=("$f"); done < <(find "$PEER_DIR" -name "*.conf" 2>/dev/null | sort)

    if [[ ${#files[@]} -eq 0 ]]; then
        warn "No peer configs found in ${PEER_DIR}"; return
    fi

    echo ""
    local i=1
    for f in "${files[@]}"; do
        echo -e "  ${WHT}${i}${R}  $(basename "$f" .conf)"; ((i++))
    done
    echo ""
    prompt "Select peer (number): "; read -r _n
    [[ ! "$_n" =~ ^[0-9]+$ || "$_n" -lt 1 || "$_n" -gt "${#files[@]}" ]] && {
        warn "Invalid selection."; return
    }
    local target="${files[$((_n - 1))]}"
    local name; name=$(basename "$target" .conf)

    if command -v qrencode &>/dev/null; then
        echo ""
        echo -e "${CYN}${BOLD}  QR Code for '${name}':${R}"
        qrencode -t ansiutf8 < "$target"
    else
        warn "qrencode not installed. Install it: apt-get install qrencode"
        echo ""
        echo -e "${CYN}${BOLD}  Config for '${name}' (copy to device):${R}"
        cat "$target"
    fi
}

# ─── Status ───────────────────────────────────────────────────────────────────
show_status() {
    load_state
    step "WireGuard Status"
    divider
    echo -e "  ${DIM}Server   : ${WHT}${SERVER_PUB_IP}:${WG_PORT}/udp${R}"
    echo -e "  ${DIM}Subnet   : ${WHT}${WG_SUBNET}.0/24${R}"
    echo -e "  ${DIM}DNS      : ${WHT}${DNS1} / ${DNS2}${R}"
    echo -e "  ${DIM}Peers    : ${WHT}$(count_peers)${R}"
    echo -e "  ${DIM}Interface: ${WHT}${WG_NIC}${R}"
    echo ""
    systemctl status wg-quick@wg0 --no-pager -l 2>/dev/null | head -15 || true
    echo ""
    if command -v wg &>/dev/null && ip link show wg0 &>/dev/null 2>&1; then
        echo -e "${CYN}${BOLD}  Interface details:${R}"
        wg show wg0 2>/dev/null || true
    fi
}

# ─── Restart ──────────────────────────────────────────────────────────────────
restart_wireguard() {
    step "Restart WireGuard"
    if systemctl restart wg-quick@wg0 2>/dev/null; then
        ok "wg-quick@wg0 restarted"
    else
        wg-quick down wg0 2>/dev/null || true
        sleep 1
        wg-quick up wg0 2>/dev/null && ok "WireGuard restarted" \
            || warn "Failed to restart — check: journalctl -u wg-quick@wg0 -n 20"
    fi
}

# ─── Uninstall ────────────────────────────────────────────────────────────────
uninstall_wireguard() {
    step "Uninstall WireGuard"
    echo -e "${RED}${BOLD}  This removes WireGuard, all keys, and all peer configs.${R}"
    echo -en "${YLW}  Are you sure? [y/N]: ${R}"; read -r _c
    [[ "${_c,,}" != "y" ]] && { info "Cancelled."; return; }

    wg-quick down wg0 2>/dev/null || true
    systemctl stop    wg-quick@wg0 &>/dev/null || true
    systemctl disable wg-quick@wg0 &>/dev/null || true

    if   command -v apt-get &>/dev/null; then
        DEBIAN_FRONTEND=noninteractive apt-get remove -y wireguard-tools &>/dev/null || true
    elif command -v dnf &>/dev/null; then
        dnf remove -y wireguard-tools &>/dev/null || true
    elif command -v yum &>/dev/null; then
        yum remove -y wireguard-tools &>/dev/null || true
    elif command -v pacman &>/dev/null; then
        pacman -R --noconfirm wireguard-tools &>/dev/null || true
    fi

    rm -rf /etc/wireguard "$STATE_DIR" "$PEER_DIR" \
           /etc/sysctl.d/99-wireguard.conf
    systemctl daemon-reload &>/dev/null || true
    ok "WireGuard uninstalled"
    echo ""
    exit 0
}

# ─── Menu ─────────────────────────────────────────────────────────────────────
print_menu() {
    echo -e "${CYN}${BOLD}  ┌─ Peer Management ─────────────────────────────────────┐${R}"
    echo -e "  ${WHT}  1${R}  👤  Add Peer"
    echo -e "  ${WHT}  2${R}  🗑   Remove Peer"
    echo -e "  ${WHT}  3${R}  📋  List Peers"
    echo -e "  ${WHT}  4${R}  📱  Show QR Code"
    echo -e "${CYN}${BOLD}  ├─ Server ──────────────────────────────────────────────┤${R}"
    echo -e "  ${WHT}  5${R}  📊  Status"
    echo -e "  ${WHT}  6${R}  🔄  Restart WireGuard"
    echo -e "  ${WHT}  7${R}  🗑   Uninstall WireGuard"
    echo -e "${CYN}${BOLD}  └────────────────────────────────────────────────────────┘${R}"
    echo -e "  ${WHT}  0${R}  ❌  Exit"
    echo ""
    echo -en "${CYN}${BOLD}  Choice: ${R}"
}

# ─── Main ─────────────────────────────────────────────────────────────────────
main() {
    if ! is_installed; then
        banner
        echo -e "  ${YLW}WireGuard is not installed yet.${R}  Starting fresh installation...\n"
        sleep 1
        install_wireguard
        echo ""
        prompt "Press Enter to open the management menu..."; read -r
    fi

    while true; do
        banner
        print_menu
        read -r choice
        echo ""
        case "$choice" in
            1) add_peer ;;
            2) remove_peer ;;
            3) list_peers ;;
            4) show_qr ;;
            5) show_status ;;
            6) restart_wireguard ;;
            7) uninstall_wireguard ;;
            0|q|Q) echo -e "  ${DIM}Goodbye.${R}"; exit 0 ;;
            *) warn "Invalid choice — enter a number from the menu." ;;
        esac
        echo ""
        echo -en "${DIM}  Press Enter to continue...${R}"; read -r
    done
}

main "$@"
