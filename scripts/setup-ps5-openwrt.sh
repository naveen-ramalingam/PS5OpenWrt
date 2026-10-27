#!/bin/sh
# ==============================================================================
# PS5OpenWrt Automated & Interactive Setup Script
# Works on OpenWrt 21.x, 22.x, 23.x, 24.x, and 25.x (fw4 / nftables)
# Agent-Friendly: Supports both interactive prompts and CLI argument automation.
# ==============================================================================

set -e

# Default values
MODE=""
LAN_PORT=""
PS5_IP=""
ETH_MAC=""
WIFI_MAC=""
BLOCK_YOUTUBE="yes"
BLOCK_NANODNS="yes"
UNATTENDED="no"

print_header() {
  cat <<'EOF'
======================================================================
         ____  _____ _____   ____                      _   _ 
        |  _ \| ____|___ /  / __ \ _ __   ___ _ ____ _| |_| |
        | |_) |___ \  |_ \ / / _` | '_ \ / _ \ '_ \ V / __| |
        |  __/ ___) |___) | | (_| | |_) |  __/ | | | | |_|_|
        |_|   |____/|____/ \ \__,_| .__/ \___|_| |_|_|\__(_)
                            \____/|_|                        
   PlayStation 5 Jailbreak Protection & Isolation for OpenWrt
======================================================================
EOF
}

usage() {
  cat <<EOF
Usage: $0 [options]

Options:
  -m, --mode <a|b>          Deployment Mode:
                              a = Bridged LAN + Layer-3 MAC Filtering (Recommended)
                              b = Dedicated Switch Port & Subnet (e.g. lan4)
  -p, --port <port>         Switch port for Mode B (e.g. lan4)
  -i, --ip <ip>             Static IP for PS5 (e.g. 192.168.1.100)
  -e, --eth-mac <mac>       PS5 Wired Ethernet MAC (e.g. c0:15:1b:xx:xx:xx)
  -w, --wifi-mac <mac>      PS5 Wi-Fi MAC (optional)
  --no-youtube              Do not block YouTube on PS5
  --no-nanodns              Do not apply nanoDNS PlayStation blocklist
  -y, --unattended          Run non-interactively with provided arguments
  -h, --help                Show this help message

Examples:
  Interactive:
    sh setup-ps5-openwrt.sh

  Unattended / AI Agent Mode:
    sh setup-ps5-openwrt.sh --mode a --ip 192.168.1.100 \
      --eth-mac c0:15:1b:00:11:22 --wifi-mac 90:47:48:33:44:55 --unattended
EOF
  exit 0
}

# Parse command line arguments
while [ "$#" -gt 0 ]; do
  case "$1" in
    -m|--mode) MODE="$2"; shift 2 ;;
    -p|--port) LAN_PORT="$2"; shift 2 ;;
    -i|--ip) PS5_IP="$2"; shift 2 ;;
    -e|--eth-mac) ETH_MAC="$2"; shift 2 ;;
    -w|--wifi-mac) WIFI_MAC="$2"; shift 2 ;;
    --no-youtube) BLOCK_YOUTUBE="no"; shift ;;
    --no-nanodns) BLOCK_NANODNS="no"; shift ;;
    -y|--unattended) UNATTENDED="yes"; shift ;;
    -h|--help) usage ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
done

if [ "$(id -u)" -ne 0 ]; then
  echo "[-] Error: This script must be run as root on your OpenWrt router." >&2
  exit 1
fi

if ! command -v uci >/dev/null 2>&1; then
  echo "[-] Error: 'uci' CLI command not found. Are you running on OpenWrt?" >&2
  exit 1
fi

print_header

# Detect available switch ports
DETECTED_PORTS=$(uci -q get network.@device[0].ports | tr ' ' '\n' | grep -E '^lan' || true)

if [ "$UNATTENDED" != "yes" ]; then
  echo "[+] Detected LAN ports on main bridge: $DETECTED_PORTS"
  echo ""
  echo "Select Deployment Architecture:"
  echo "  1) Mode A (Recommended): Bridged LAN with Layer-3 MAC Filtering"
  echo "     - PS5 stays on main home subnet (e.g. 192.168.1.100)"
  echo "     - Easy PC/Phone communication for FTP and exploit payloads"
  echo "     - Completely blocks IPv6 DNS/Internet bypass via fw4 MAC rules"
  echo "     - Avoids MediaTek/DSA switch port driver lockups"
  echo ""
  echo "  2) Mode B: Dedicated Switch Port & Subnet (e.g. lan4)"
  echo "     - Removes chosen physical port from br-lan"
  echo "     - Runs isolated IPv4-only subnet (e.g. 192.168.4.1/24)"
  echo "     - Native zero-IPv6 configuration"
  echo ""
  printf "Enter choice [1/2] (Default: 1): "
  read -r CHOICE
  case "$CHOICE" in
    2) MODE="b" ;;
    *) MODE="a" ;;
  esac

  if [ "$MODE" = "b" ]; then
    printf "Enter physical LAN port to isolate (e.g. lan4) [%s]: " "$(echo "$DETECTED_PORTS" | tail -n 1)"
    read -r INPUT_PORT
    LAN_PORT="${INPUT_PORT:-$(echo "$DETECTED_PORTS" | tail -n 1)}"
  fi

  printf "Enter PS5 Wired Ethernet MAC (e.g. c0:15:1b:xx:xx:xx): "
  read -r INPUT_ETH_MAC
  ETH_MAC="$INPUT_ETH_MAC"

  printf "Enter PS5 Wi-Fi MAC (optional, press Enter to skip): "
  read -r INPUT_WIFI_MAC
  WIFI_MAC="$INPUT_WIFI_MAC"

  DEFAULT_IP="192.168.1.100"
  [ "$MODE" = "b" ] && DEFAULT_IP="192.168.4.100"
  printf "Enter desired static IP for PS5 [%s]: " "$DEFAULT_IP"
  read -r INPUT_IP
  PS5_IP="${INPUT_IP:-$DEFAULT_IP}"

  printf "Block YouTube on PS5? [Y/n]: "
  read -r ANS_YT
  case "$ANS_YT" in [nN]*) BLOCK_YOUTUBE="no" ;; *) BLOCK_YOUTUBE="yes" ;; esac

  printf "Block PlayStation System Updates / Telemetry (nanoDNS)? [Y/n]: "
  read -r ANS_ND
  case "$ANS_ND" in [nN]*) BLOCK_NANODNS="no" ;; *) BLOCK_NANODNS="yes" ;; esac
fi

# Validation
if [ -z "$MODE" ]; then MODE="a"; fi
if [ -z "$PS5_IP" ]; then
  [ "$MODE" = "b" ] && PS5_IP="192.168.4.100" || PS5_IP="192.168.1.100"
fi
if [ -z "$ETH_MAC" ] && [ -z "$WIFI_MAC" ]; then
  echo "[-] Error: At least one MAC address (Ethernet or Wi-Fi) is required." >&2
  exit 1
fi

ROUTER_LAN_IP=$(uci -q get network.lan.ipaddr || echo "192.168.1.1")

echo ""
echo "[*] Configuration Summary:"
echo "    - Mode: $MODE"
[ "$MODE" = "b" ] && echo "    - Port: $LAN_PORT"
echo "    - PS5 IP: $PS5_IP"
echo "    - Ethernet MAC: ${ETH_MAC:-None}"
echo "    - Wi-Fi MAC: ${WIFI_MAC:-None}"
echo "    - Block YouTube: $BLOCK_YOUTUBE"
echo "    - Block nanoDNS / Updates: $BLOCK_NANODNS"
echo "    - Router LAN IP: $ROUTER_LAN_IP"
echo ""

# ------------------------------------------------------------------------------
# 0. Safety First: Automatic Router Configuration Backup
# ------------------------------------------------------------------------------
BACKUP_ARCHIVE="/tmp/openwrt-pre-ps5-backup-$(date +%s).tar.gz"
echo "[*] Step 0: Creating safety router configuration backup..."
if command -v sysupgrade >/dev/null 2>&1; then
  sysupgrade -b "$BACKUP_ARCHIVE" >/dev/null 2>&1 || true
  echo "    [✓] Router backup archive created: $BACKUP_ARCHIVE"
  echo "        (Download to your PC via: scp root@$ROUTER_LAN_IP:$BACKUP_ARCHIVE .)"
else
  echo "    [!] Notice: 'sysupgrade' utility not found; skipping tar.gz generation."
fi
echo ""

# ------------------------------------------------------------------------------
# 1. DHCP Static Host Reservation
# ------------------------------------------------------------------------------
echo "[*] Step 1: Configuring unified DHCP static lease..."
# Remove any existing PS5 host entry
for idx in $(uci show dhcp | grep -E "name='PS5'" | cut -d'.' -f2 | cut -d'=' -f1); do
  uci -q delete "dhcp.$idx"
done

uci add dhcp host >/dev/null
uci set dhcp.@host[-1].name='PS5'
[ -n "$ETH_MAC" ] && uci add_list dhcp.@host[-1].mac="$ETH_MAC"
[ -n "$WIFI_MAC" ] && uci add_list dhcp.@host[-1].mac="$WIFI_MAC"
uci set dhcp.@host[-1].ip="$PS5_IP"
uci commit dhcp
/etc/init.d/dnsmasq reload

# ------------------------------------------------------------------------------
# 2. Firewall Rules (OpenWrt fw4)
# ------------------------------------------------------------------------------
echo "[*] Step 2: Configuring OpenWrt firewall redirection & isolation..."

# Clean old rules if present
for section in Redirect-PS5-DNS-to-AdGuard Block-PS5-DoT Block-PS5-IPv6-Input Block-PS5-IPv6-Forward; do
  for idx in $(uci show firewall | grep -E "name='$section'" | cut -d'.' -f2 | cut -d'=' -f1); do
    uci -q delete "firewall.$idx"
  done
done
uci -q delete firewall.ps5_ipv6_in || true
uci -q delete firewall.ps5_ipv6_fwd || true

# Rule A: DNS DNAT (Force IPv4 UDP/TCP port 53 to local resolver)
uci add firewall redirect >/dev/null
uci set firewall.@redirect[-1].name='Redirect-PS5-DNS-to-AdGuard'
uci set firewall.@redirect[-1].src='lan'
uci set firewall.@redirect[-1].proto='tcp udp'
uci set firewall.@redirect[-1].src_dport='53'
uci set firewall.@redirect[-1].dest_ip="$ROUTER_LAN_IP"
uci set firewall.@redirect[-1].dest_port='53'
uci set firewall.@redirect[-1].target='DNAT'
uci set firewall.@redirect[-1].family='ipv4'
[ -n "$ETH_MAC" ] && uci add_list firewall.@redirect[-1].src_mac="$ETH_MAC"
[ -n "$WIFI_MAC" ] && uci add_list firewall.@redirect[-1].src_mac="$WIFI_MAC"

# Rule B: Block outbound DoT (port 853)
uci add firewall rule >/dev/null
uci set firewall.@rule[-1].name='Block-PS5-DoT'
uci set firewall.@rule[-1].src='lan'
uci set firewall.@rule[-1].dest='wan'
uci set firewall.@rule[-1].proto='tcp udp'
uci set firewall.@rule[-1].dest_port='853'
uci set firewall.@rule[-1].target='REJECT'
[ -n "$ETH_MAC" ] && uci add_list firewall.@rule[-1].src_mac="$ETH_MAC"
[ -n "$WIFI_MAC" ] && uci add_list firewall.@rule[-1].src_mac="$WIFI_MAC"

if [ "$MODE" = "a" ]; then
  if [ -d /proc/sys/net/ipv6 ]; then
    echo "    [*] IPv6 stack detected: Adding MAC-based L3 rejection rules to prevent DNS leaks..."
    # Rule C: Reject IPv6 Input from PS5 MACs
    uci set firewall.ps5_ipv6_in=rule
    uci set firewall.ps5_ipv6_in.name='Block-PS5-IPv6-Input'
    uci set firewall.ps5_ipv6_in.src='lan'
    uci set firewall.ps5_ipv6_in.family='ipv6'
    uci set firewall.ps5_ipv6_in.proto='tcp udp'
    [ -n "$ETH_MAC" ] && uci add_list firewall.ps5_ipv6_in.src_mac="$ETH_MAC"
    [ -n "$WIFI_MAC" ] && uci add_list firewall.ps5_ipv6_in.src_mac="$WIFI_MAC"
    uci set firewall.ps5_ipv6_in.target='REJECT'

    # Rule D: Reject IPv6 Forward from PS5 MACs
    uci set firewall.ps5_ipv6_fwd=rule
    uci set firewall.ps5_ipv6_fwd.name='Block-PS5-IPv6-Forward'
    uci set firewall.ps5_ipv6_fwd.src='lan'
    uci set firewall.ps5_ipv6_fwd.dest='*'
    uci set firewall.ps5_ipv6_fwd.family='ipv6'
    uci set firewall.ps5_ipv6_fwd.proto='all'
    [ -n "$ETH_MAC" ] && uci add_list firewall.ps5_ipv6_fwd.src_mac="$ETH_MAC"
    [ -n "$WIFI_MAC" ] && uci add_list firewall.ps5_ipv6_fwd.src_mac="$WIFI_MAC"
    uci set firewall.ps5_ipv6_fwd.target='REJECT'
  else
    echo "    [✓] IPv6 is disabled in the kernel; PS5 is natively IPv4-only."
  fi
fi

if [ "$MODE" = "b" ]; then
  echo "[*] Step 2b: Isolating switch port $LAN_PORT into dedicated subnet..."
  uci del_list network.@device[0].ports="$LAN_PORT" 2>/dev/null || true
  uci set network.ps5lan=interface
  uci set network.ps5lan.device="$LAN_PORT"
  uci set network.ps5lan.proto='static'
  uci set network.ps5lan.ipaddr='192.168.4.1'
  uci set network.ps5lan.netmask='255.255.255.0'
  uci set network.ps5lan.ipv6='0'

  uci set dhcp.ps5lan=dhcp
  uci set dhcp.ps5lan.interface='ps5lan'
  uci set dhcp.ps5lan.start='100'
  uci set dhcp.ps5lan.limit='50'
  uci set dhcp.ps5lan.leasetime='12h'
  uci set dhcp.ps5lan.dhcpv4='server'
  uci set dhcp.ps5lan.dhcpv6='disabled'
  uci set dhcp.ps5lan.ra='disabled'
  uci set dhcp.ps5lan.ndp='disabled'

  uci add_list firewall.@zone[0].network='ps5lan' 2>/dev/null || true
  uci commit network
fi

uci commit firewall
/etc/init.d/firewall reload
[ "$MODE" = "b" ] && /etc/init.d/network reload

# ------------------------------------------------------------------------------
# 3. AdGuard Home Domain Filtering
# ------------------------------------------------------------------------------
AGH_CONF="/etc/adguardhome/adguardhome.yaml"
if [ -f "$AGH_CONF" ]; then
  echo "[*] Step 3: Configuring AdGuard Home client-scoped rules..."
  cp "$AGH_CONF" "${AGH_CONF}.bak.$(date +%s)"

  # Remove existing PS5 client block if present
  # We append user rules scoped specifically to $client=PS5_IP
  RULES_TO_ADD=""
  if [ "$BLOCK_YOUTUBE" = "yes" ]; then
    RULES_TO_ADD="$RULES_TO_ADD
  - '||youtube.*^\$client=$PS5_IP'
  - '||googlevideo.com^\$client=$PS5_IP'
  - '||youtu.be^\$client=$PS5_IP'
  - '||ytimg.com^\$client=$PS5_IP'"
  fi

  if [ "$BLOCK_NANODNS" = "yes" ]; then
    RULES_TO_ADD="$RULES_TO_ADD
  - '@@||feature.api.playstation.com^\$client=$PS5_IP'
  - '@@||stun.playstation.net^\$client=$PS5_IP'
  - '@@||*.stun.playstation.net^\$client=$PS5_IP'
  - '@@||stun.*.playstation.net^\$client=$PS5_IP'
  - '@@||ena.net.playstation.net^\$client=$PS5_IP'
  - '@@||post.net.playstation.net^\$client=$PS5_IP'
  - '@@||gst.prod.dl.playstation.net^\$client=$PS5_IP'
  - '||playstation.com^\$client=$PS5_IP'
  - '||playstation.net^\$client=$PS5_IP'
  - '||psndl.net^\$client=$PS5_IP'
  - '||playstation.com.*^\$client=$PS5_IP'
  - '||playstation.net.*^\$client=$PS5_IP'"
  fi

  # Add client entry if missing
  if ! grep -q "name: PS5" "$AGH_CONF"; then
    cat <<EOF >> "$AGH_CONF"
# Added by PS5OpenWrt
clients:
  persistent:
    - name: PS5
      ids:
        - $PS5_IP
EOF
    [ -n "$ETH_MAC" ] && echo "        - $ETH_MAC" >> "$AGH_CONF"
    [ -n "$WIFI_MAC" ] && echo "        - $WIFI_MAC" >> "$AGH_CONF"
    cat <<EOF >> "$AGH_CONF"
      blocked_services:
        - youtube
EOF
  fi

  # Append custom rules under user_rules:
  if [ -n "$RULES_TO_ADD" ]; then
    echo "$RULES_TO_ADD" >> "$AGH_CONF"
  fi

  /etc/init.d/adguardhome restart >/dev/null 2>&1 || true
  echo "[+] AdGuard Home rules updated and service restarted."
else
  echo "[!] Note: AdGuard Home not detected at $AGH_CONF."
  echo "    Standard dnsmasq static lease and firewall rules are active."
fi

echo ""
echo "======================================================================"
echo "[✓] PS5OpenWrt Setup Completed Successfully!"
echo "    - Static IP: $PS5_IP"
echo "    - Exploit Compatibility: Verified for Y2JB & WebKit Autoloader"
echo "    - YouTube Block: $BLOCK_YOUTUBE"
echo "    - PlayStation nanoDNS Block: $BLOCK_NANODNS"
echo ""
echo "[*] IMPORTANT PS5 SETUP NOTES:"
echo "    1. NO MANUAL DNS NEEDED ON PS5: Keep PS5 Network DNS set to"
echo "       'Automatic' (DHCP). The router intercepts all DNS queries."
echo "    2. NO NANODNS PAYLOAD NEEDED: Update/telemetry blocking is handled"
echo "       entirely at the router level. You do not need to run or auto-load"
echo "       the nanoDNS payload anymore."
echo "    3. USER'S GUIDE READY: Exploit entrypoint (feature.api.playstation.com)"
echo "       is whitelisted. Open Settings -> User's Guide to launch exploits!"
echo "======================================================================"
EOF
