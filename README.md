# PS5OpenWrt: PlayStation 5 Jailbreak Protection & Isolation for OpenWrt

[![OpenWrt Version](https://img.shields.io/badge/OpenWrt-21.02%20--%2025.12+-blue.svg)](https://openwrt.org)
[![Firewall](https://img.shields.io/badge/Firewall-fw4%20(nftables)-green.svg)](https://openwrt.org/docs/guide-user/firewall/firewall_configuration)
[![PS5 Firmware](https://img.shields.io/badge/PS5%20Exploits-Y2JB%20%7C%20WebKit%20Autoloader-purple.svg)](https://github.com/drakmor/nanoDNS)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

A battle-tested, automated OpenWrt configuration framework designed for **PlayStation 5 jailbroken and exploit consoles** (firmwares 3.xx, 4.xx, 5.xx, 7.xx, etc.).

> [!WARNING]
> ### ⚠️ Always Back Up Your OpenWrt Configuration First!
> Before applying any firewall or network changes, create a complete backup archive of your router:
> - **Via LuCI Web UI:** Go to **System** $\rightarrow$ **Backup / Flash Firmware** $\rightarrow$ Click **Generate archive**.
> - **Via SSH:** Run `sysupgrade -b /tmp/openwrt-pre-ps5-backup.tar.gz` and download it with `scp root@<ROUTER_IP>:/tmp/openwrt-pre-ps5-backup.tar.gz .`
> *(Note: The included setup script and AI agent protocol automatically create a pre-configuration backup before touching any settings!)*

---

## 📋 Prerequisites

Before setting up `PS5OpenWrt`, ensure you have:
1. **OpenWrt Router:** Running OpenWrt 21.02, 22.03, 23.05, 24.xx, or 25.xx (OpenWrt with modern `fw4` / nftables is strongly recommended).
2. **AdGuard Home (Recommended):** Installed on your router (listening on port 53 or integrated with dnsmasq). AdGuard Home is required for client-specific (`$client=...`) filtering so YouTube and PlayStation updates are blocked *only* on the PS5 while other household devices remain unblocked. (If using native dnsmasq, domain rules apply globally).
3. **Root Access:** SSH access (`root@<ROUTER_IP>`) to your OpenWrt router.
4. **Console Connection:** PS5 connected to the router via Ethernet cable (recommended) or Wi-Fi.

---

## 💡 Key Benefits: No Manual DNS & No Payload Autostart Needed

* **No Manual DNS Setup on the PS5:**
  You can leave your PS5 Network Settings on **Automatic** (DHCP)! The router's firewall rules automatically intercept any rogue UDP/TCP port 53 DNS queries and force them into AdGuard Home. If someone on your network tries to set DNS to `8.8.8.8` or `1.1.1.1` on the console, it is still transparently intercepted. Outbound DNS-over-TLS (port 853) is also rejected.
* **No nanoDNS Payload or Autostart Needed:**
  Because the router intercepts and blocks updates/telemetry network-wide at the gateway, **you never need to load or autostart the nanoDNS payload on the PS5**. 
* **User's Guide Always Ready:**
  The User's Guide exploit entrypoint (`feature.api.playstation.com`) and STUN servers are permanently whitelisted, allowing you to launch exploits anytime from **Settings $\rightarrow$ User's Guide**.

---

## 📖 Background & The KASLR Interface Bug

Many PS5 exploit autoloaders (such as **Y2JB Autoloader** and **WebKit Autoloader v0.6.1**) use the `relapse.js` payload. In `relapse.js`, the function `firstInterfaceAddress()` invokes the FreeBSD/OrbisOS kernel syscall `SYS_NETGETIFLIST` (`sceNetGetIfList`) to defeat Kernel Address Space Layout Randomization (KASLR).

This function inspects the 4-byte **IPv4 address** at offset 40 (`0x28`) of each interface record. If all interfaces return `0.0.0.0`, the exploit throws:
```text
relapse FAILED kaslr: no interface has an address
```

### Why Naive Router Setups Cause This Error
- **The MediaTek DSA Switch Driver Bug:** Attaching low-level `nftables` `netdev` ingress/egress hooks (`table netdev filter_lan4`) directly to physical DSA switch slave ports (`lan1`–`lan4`) on Linux 6.x causes the switch port's receive queue to wedge (`rx_packets` freezes) when the PS5 reboots and cycles physical link state. The console is unable to complete DHCP and boots with `0.0.0.0`.
- **The IPv6 SLAAC Bypass:** When dual-stack is enabled on `br-lan`, the PS5 generates random IPv6 SLAAC privacy addresses (`2406:...`). It will send `AAAA` DNS queries over IPv6 directly, bypassing any client-specific IPv4 filters.

### The PS5OpenWrt Solution
`PS5OpenWrt` solves both issues cleanly using standard **OpenWrt `fw4` (nftables)** layer-3 rules and client-scoped DNS filtering:
- Runs at layer 3 *after* the bridge driver, completely preventing DSA switch driver freezes.
- Immediately rejects IPv6 input and forward traffic from the PS5's MAC addresses, forcing the PS5 into instant (< 1 ms) IPv4 fallback.

---

## 🏗️ Architecture Modes

| Feature | Mode A: Bridged LAN (Recommended) | Mode B: Dedicated Port & Subnet |
| :--- | :--- | :--- |
| **Subnet** | Same home subnet (e.g. `192.168.1.100`) | Isolated subnet (e.g. `192.168.4.1/24`) |
| **Physical Port** | Any port (`lan1`–`lan4`) or Wi-Fi | Dedicated physical port (e.g. `lan4`) |
| **PC/Phone Payloads** | Direct LAN communication (no routing setup) | Allowed via LAN firewall zone sharing |
| **IPv6 Handling** | L3 MAC rejection (`fw4`) | Port natively detached with `ipv6 '0'` |
| **Best For** | Users wanting plug-and-play flexibility | Users wanting physical port isolation |

---

## 🚀 Quick Start

### Option 1: AI Coding Agent (Automated Setup & Verification)
If you are using an AI Coding Assistant (Antigravity, Claude, ChatGPT, Cursor, Aider):
Simply give your agent the repository URL and say:

**To Setup:**
```text
"Please connect to my OpenWrt router and configure it for my PS5 using the instructions in https://github.com/naveen-ramalingam/PS5OpenWrt/blob/main/AGENT.md"
```

**To Verify:**
```text
"Please run the verification checks from https://github.com/naveen-ramalingam/PS5OpenWrt to confirm my PS5 static lease, firewall rules, and YouTube/nanoDNS blocking are working."
```
The agent will inspect your router, create a safety backup, prompt you for your setup preferences, apply the configuration, and run the verification diagnostics automatically!

---

### Option 2: Interactive Setup Script (On OpenWrt)
SSH into your OpenWrt router and run:

```sh
# Download setup script
curl -sSL -o /tmp/setup-ps5-openwrt.sh https://raw.githubusercontent.com/naveen-ramalingam/PS5OpenWrt/main/scripts/setup-ps5-openwrt.sh

# Run interactive wizard
sh /tmp/setup-ps5-openwrt.sh
```

The script will:
1. Detect your LAN switch ports.
2. Prompt you to select **Mode A** or **Mode B**.
3. Prompt for your PS5's Ethernet and optional Wi-Fi MAC addresses.
4. Set up a unified static DHCP reservation.
5. Configure `fw4` port 53 DNAT, port 853 DoT rejection, and IPv6 isolation.
6. Configure AdGuard Home client-scoped rules (or provide dnsmasq settings).

---

### Option 3: Unattended / Scripted Execution
For scripted deployments:

```sh
sh /tmp/setup-ps5-openwrt.sh \
  --mode a \
  --ip 192.168.1.100 \
  --eth-mac c0:15:1b:xx:xx:xx \
  --wifi-mac 90:47:48:xx:xx:xx \
  --unattended
```

---

## 🛡️ Blocklist Overview

### 1. nanoDNS PlayStation Rules
Prevents system software updates and telemetry while whitelisting exploit access:

* **Whitelisted Exceptions (REQUIRED for User's Guide Exploit):**
  - `feature.api.playstation.com`
  - `stun.playstation.net`
  - `*.stun.playstation.net`
  - `ena.net.playstation.net`
  - `post.net.playstation.net`
  - `gst.prod.dl.playstation.net`

* **Blocked Overrides (Blocks Updates & PSN):**
  - `playstation.com`
  - `playstation.net`
  - `psndl.net`
  - `playstation.com.*`
  - `playstation.net.*`

### 2. Scoped YouTube Rules
Blocks YouTube only for the PS5 static IP:
```text
||youtube.*^$client=192.168.1.100
||googlevideo.com^$client=192.168.1.100
||youtu.be^$client=192.168.1.100
||ytimg.com^$client=192.168.1.100
```

---

## 🔍 Verification

Run the verification tool on your router to test connectivity, DHCP, firewall status, and DNS blocking:

```sh
curl -sSL -o /tmp/verify-ps5-openwrt.sh https://raw.githubusercontent.com/naveen-ramalingam/PS5OpenWrt/main/scripts/verify-ps5-openwrt.sh
sh /tmp/verify-ps5-openwrt.sh 192.168.1.100
```

Sample output:
```text
======================================================================
           PS5OpenWrt Configuration Verification Tool                 
======================================================================
[*] Target PS5 IP: 192.168.1.100

[*] Step 1: Checking PS5 network reachability (ping)...
    [✓] PS5 is ONLINE and responding at 192.168.1.100.

[*] Step 2: Checking DHCP static lease in /var/etc/dnsmasq.conf*...
    [✓] dhcp-host=c0:15:1b:00:11:22,90:47:48:33:44:55,192.168.1.100,PS5

[*] Step 3: Checking OpenWrt firewall4 (nftables) rules...
    [✓] Port 53 DNS redirection (DNAT) rule is ACTIVE.
    [✓] Port 853 DoT rejection rule is ACTIVE.
    [✓] PS5 IPv6 Input rejection rule is ACTIVE.

[*] Step 4: Testing DNS filtering resolution for PS5 (192.168.1.100)...
    [✓] youtube.com               -> 0.0.0.0 (Blocked)
    [✓] playstation.com           -> 0.0.0.0 (Blocked)
    [✓] feature.api.playstation.com -> Resolved (Allowed for User's Guide)
```

---

## 📂 Repository Structure

```text
PS5OpenWrt/
├── README.md                          # Comprehensive documentation
├── AGENT.md                           # AI Agent Guidance & Execution Protocol
├── LICENSE                            # MIT License
├── blocklists/
│   ├── nanodns-playstation-adguard.txt# nanoDNS block/whitelist rules
│   ├── youtube-adguard.txt            # Scoped YouTube blocking rules
│   └── ps5-dnsmasq.conf               # Native dnsmasq configuration snippet
├── configs/
│   ├── uci-dhcp-template.conf         # Unified static DHCP lease template
│   ├── uci-firewall-mode-a.conf       # Mode A (Bridged L3 MAC filter) UCI snippet
│   ├── uci-firewall-mode-b.conf       # Mode B (Dedicated switch port) UCI snippet
│   └── adguardhome-rules.yaml         # Sample AdGuard Home YAML snippet
└── scripts/
    ├── setup-ps5-openwrt.sh           # Interactive & automated setup wizard
    └── verify-ps5-openwrt.sh          # Diagnostics & verification script
```

---

## ⚠️ Disclaimer

This project is for educational, home network administration, and research purposes. Use responsibly. Always verify your own MAC addresses and router interface names before applying settings.

---

## 📄 License

This project is licensed under the [MIT License](LICENSE).
EOF
