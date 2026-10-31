# AGENT.md — AI Agent Guidance & Execution Protocol

> **Target Audience:** Autonomous AI coding agents (Antigravity, Claude Engineer, ChatGPT, Aider, Cursor, Copilot) assisting a user with configuring an OpenWrt router for PlayStation 5 jailbreak protection and isolation.

---

## 1. Mission Overview

Your goal is to safely configure an OpenWrt router to:
1. **Prevent accidental PS5 firmware updates** by implementing the [nanoDNS](https://github.com/drakmor/nanoDNS) rule set while keeping the **User's Guide** exploit entrypoint (`feature.api.playstation.com`) and STUN operational.
2. **Block YouTube specifically on the PS5** without affecting any other household devices (TVs, laptops, phones).
3. **Preserve exploit compatibility** for PS5 WebKit and Kernel exploits (**Y2JB Autoloader**, **WebKit Autoloader**, **relapse.js**), avoiding the critical `kaslr: no interface has an address` failure.

---

## 2. User Invocation Prompts

Users typically invoke you with one of two instructions:
- **Setup Prompt:**
  > *"Please connect to my OpenWrt router and configure it for my PS5 using the instructions in https://github.com/naveen-ramalingam/PS5OpenWrt/blob/main/AGENT.md"*
- **Verification Prompt:**
  > *"Please run the verification checks from https://github.com/naveen-ramalingam/PS5OpenWrt to confirm my PS5 static lease, firewall rules, and YouTube/nanoDNS blocking are working."*

---

## 3. Prerequisites Checklist

Before proceeding with any router configuration, verify that the following are present:
1. **OpenWrt Router:** Running OpenWrt 21.02, 22.03, 23.05, 24.xx, or 25.xx (OpenWrt with `fw4` / nftables is strongly recommended).
2. **AdGuard Home (Recommended):** Running on the router (e.g. listening on port 53 or integrated with dnsmasq). AdGuard Home is required for client-specific (`$client=...`) filtering so only the PS5 is blocked while household devices are untouched. (If using native dnsmasq, domain blocks apply router-wide).
3. **Root Access:** SSH access (`root@<ROUTER_IP>`) with password or public key authentication.
4. **PS5 Hardware Connection:** Connected to the router via Ethernet cable (recommended) or Wi-Fi.

---

## 4. Mandatory Safety Rule: Create Router Backup First!

> [!CAUTION]
> **AI AGENT MANDATE:** You MUST take a full configuration backup of the user's OpenWrt router BEFORE executing any configuration commands or running scripts.

Execute via SSH:
```sh
BACKUP="/tmp/openwrt-pre-ps5-backup-$(date +%s).tar.gz"
sysupgrade -b "$BACKUP"
echo "Backup created at: $BACKUP"
```
Inform the user of the saved backup path and provide them the `scp` command to download it to their local machine:
`scp root@<ROUTER_IP>:/tmp/openwrt-pre-ps5-backup-*.tar.gz .`

---

## 5. Interactive Discovery Workflow (Phase 1)

When the user asks you to configure their router for PS5, **do not immediately run destructive commands**. Follow this phased interview:

### Step 1: Detect Router Topology & Ports
Run via SSH on the user's OpenWrt router:
```sh
ubus call network.device status
uci show network.@device[0]
uci show firewall.@defaults[0]
```
- Check the physical DSA ports (e.g., `lan1`, `lan2`, `lan3`, `lan4`).
- Check firewall version: `fw4` (nftables, OpenWrt 22+) vs `fw3` (iptables).
- Check DNS setup: Is **AdGuard Home** running on port 53/8080/3000, or is it standalone **dnsmasq**?

### Step 2: Present Options to the User
Ask the user two simple questions:
1. **Deployment Architecture:**
   - **Mode A (Recommended - Bridged LAN):** Keeps PS5 on your main home subnet (e.g., `192.168.1.100`). Easy PC/phone FTP payload delivery. Restricts IPv6 via layer-3 firewall (`fw4`) rules matching the PS5 MAC address.
   - **Mode B (Dedicated Switch Port & Subnet):** Completely detaches a physical port (e.g., `lan4`) from `br-lan` and creates a dedicated IPv4-only subnet (`192.168.4.1/24`). Zero IPv6 traffic physically touches the port.
2. **PS5 Hardware Identifiers:**
   - Ask for the PS5 **Wired Ethernet MAC** (and optional **Wi-Fi MAC**).
   - Ask for their preferred static IP (default: `192.168.1.100` for Mode A, `192.168.4.100` for Mode B).

---

## 6. Critical Technical Pitfalls (Must Read!)

### ⚠️ Never attach `table netdev` hooks to DSA switch ports!
- **The Bug:** Attaching an `nftables` `netdev` ingress/egress hook (e.g. `hook ingress device "lan4"`) directly to MediaTek MT7530/MT7531 or Broadcom DSA switch slave ports on Linux 6.x causes the switch port's RX queue to permanently freeze when the PS5 reboots and cycles physical link state (`rx_packets` freezes).
- **The Symptom:** The PS5 cannot complete DHCP on boot, assigns itself `0.0.0.0`, and the `relapse.js` exploit throws:
  `relapse FAILED kaslr: no interface has an address`
- **The Solution:** 
  - In **Mode A**, always use standard `table inet fw4` layer-3 rules matching `ether saddr { <PS5_MACS> }`. These run at L3 *after* the bridge driver and never touch the low-level switch driver.
  - In **Mode B**, remove the port from `br-lan` and make it a native layer-3 interface with `option ipv6 '0'` and `option ra 'disabled'`.

### ⚠️ IPv6 Privacy Address Leak
- If the home LAN has IPv6 enabled, the PS5 generates temporary **SLAAC privacy addresses** (`2406:...`) and queries DNS over IPv6 (`AAAA`).
- If AdGuard Home user rules are scoped to `$client=192.168.1.100`, IPv6 queries will bypass the filter because the source IP is an IPv6 address!
- **Fix:** In `fw4`, add rule `Block-PS5-IPv6-Input` (rejecting IPv6 TCP/UDP port 53/547) and `Block-PS5-IPv6-Forward` (rejecting outbound IPv6 to WAN). This forces the PS5 to use IPv4 (`192.168.1.100`) in `< 1 ms` with zero timeouts.

---

## 7. Automated Execution (Phase 2)

You can execute the included script directly on the router:
```sh
# Copy script to router /tmp
scp scripts/setup-ps5-openwrt.sh root@<ROUTER_IP>:/tmp/

# Run unattended (automatically takes a pre-change backup!)
ssh root@<ROUTER_IP> 'sh /tmp/setup-ps5-openwrt.sh --mode a \
  --ip 192.168.1.100 \
  --eth-mac c0:15:1b:00:11:22 \
  --wifi-mac 90:47:48:33:44:55 \
  --unattended'
```

Or apply the equivalent UCI commands idempotently:
1. `uci add dhcp host` with both MACs bound to `192.168.1.100`.
2. Firewall DNAT: Port 53 redirected to router IP for PS5 MACs.
3. Firewall Reject: Port 853 (DoT) rejected for PS5 MACs.
4. Firewall Reject: IPv6 input and forward rejected for PS5 MACs.
5. AdGuard Home: Persistent client `PS5` with `blocked_services: [youtube]` and `user_rules` for nanoDNS overrides.

---

## 8. Verification Protocol (Phase 3)

After configuration, verify:
1. **Connectivity:** `ping -c 2 192.168.1.100` (must be `< 1 ms`).
2. **DNS Blocking:** Test AdGuard Home API:
   ```sh
   curl -u "admin:<PASSWORD>" "http://127.0.0.1:8080/control/filtering/check_host?name=playstation.com&client=192.168.1.100"
   # Must return reason: FilteredBlackList
   
   curl -u "admin:<PASSWORD>" "http://127.0.0.1:8080/control/filtering/check_host?name=feature.api.playstation.com&client=192.168.1.100"
   # Must return reason: NotFilteredWhiteList
   
   curl -u "admin:<PASSWORD>" "http://127.0.0.1:8080/control/filtering/check_host?name=youtube.com&client=192.168.1.100"
   # Must return reason: FilteredBlackList
   ```
3. **Exploit Launch:** Instruct the user to open User's Guide or WebKit Autoloader on the PS5. The exploit will obtain KASLR and execute without interface errors.

---

## 9. Final Advice to Give the User

Inform the user:
1. **No Manual DNS Configuration Needed on the PS5:**
   - Network settings on the PS5 should be left on **Automatic** (DHCP).
   - The router automatically captures all DNS requests and forces them into AdGuard Home.
2. **No nanoDNS Payload or Autostart Needed:**
   - Because the router enforces nanoDNS rules 24/7 at the gateway level, they **do not need to load or autostart the nanoDNS payload** on the console.
3. **User's Guide Ready:**
   - Exploit hosting entrypoints (`feature.api.playstation.com`) are permanently whitelisted, allowing instant access via Settings -> User's Guide.
