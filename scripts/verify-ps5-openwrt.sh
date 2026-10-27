#!/bin/sh
# ==============================================================================
# PS5OpenWrt Automated Verification Script
# Tests DHCP, Firewall rules, DNS interception, and domain block status.
# ==============================================================================

set -e

PS5_IP="${1:-192.168.1.100}"

echo "======================================================================"
echo "           PS5OpenWrt Configuration Verification Tool                 "
echo "======================================================================"
echo "[*] Target PS5 IP: $PS5_IP"
echo ""

# 1. Check Ping
echo "[*] Step 1: Checking PS5 network reachability (ping)..."
if ping -c 1 -W 2 "$PS5_IP" >/dev/null 2>&1; then
  echo "    [✓] PS5 is ONLINE and responding at $PS5_IP."
else
  echo "    [!] Notice: PS5 did not reply to ping (it may be in rest mode or off)."
fi

# 2. Check Static Lease in dnsmasq
echo ""
echo "[*] Step 2: Checking DHCP static lease in /var/etc/dnsmasq.conf*..."
if grep -r "$PS5_IP" /var/etc/dnsmasq.conf* >/dev/null 2>&1; then
  grep -r "$PS5_IP" /var/etc/dnsmasq.conf* | head -n 1 | sed 's/^/    [✓] /'
else
  echo "    [!] Warning: Static lease for $PS5_IP not found in running dnsmasq config."
fi

# 3. Check Firewall Rules
echo ""
echo "[*] Step 3: Checking OpenWrt firewall4 (nftables) rules..."
if nft list chain inet fw4 dstnat_lan 2>/dev/null | grep -qi "Redirect-PS5-DNS"; then
  echo "    [✓] Port 53 DNS redirection (DNAT) rule is ACTIVE."
else
  echo "    [!] Warning: Redirect-PS5-DNS rule not active in dstnat_lan."
fi

if nft list chain inet fw4 forward_lan 2>/dev/null | grep -qi "Block-PS5-DoT"; then
  echo "    [✓] Port 853 DoT rejection rule is ACTIVE."
else
  echo "    [!] Warning: Block-PS5-DoT rule not active in forward_lan."
fi

if nft list chain inet fw4 input_lan 2>/dev/null | grep -qi "Block-PS5-IPv6-Input"; then
  echo "    [✓] PS5 IPv6 Input rejection rule is ACTIVE."
else
  echo "    [-] Notice: Block-PS5-IPv6-Input rule not found (normal if running Mode B)."
fi

# 4. Check AdGuard Home Filtering if present
echo ""
echo "[*] Step 4: Testing DNS filtering resolution for PS5 ($PS5_IP)..."
if command -v curl >/dev/null 2>&1 && netstat -tlpn 2>/dev/null | grep -qE "AdGuardHome.*(8080|3000)"; then
  AGH_PORT=$(netstat -tlpn 2>/dev/null | grep AdGuardHome | grep -oE ":(8080|3000)" | head -n 1 | tr -d ':')
  echo "    [*] AdGuard Home detected on port $AGH_PORT. Testing simulated queries..."

  for domain in youtube.com playstation.com feature.api.playstation.com stun.playstation.net; do
    printf "    - %-32s: " "$domain"
    # Query via local resolver
    ans=$(nslookup "$domain" 127.0.0.1 2>/dev/null | grep "Address" | tail -n 1 || true)
    echo "$ans"
  done
else
  echo "    [!] Note: AdGuard Home web API not directly testable or curl not installed."
fi

echo ""
echo "======================================================================"
echo "[✓] Verification script completed."
echo "======================================================================"
EOF
