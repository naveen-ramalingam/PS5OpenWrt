# PS5OpenWrt: PlayStation 5 Jailbreak Protection & Isolation for OpenWrt

[![OpenWrt Version](https://img.shields.io/badge/OpenWrt-21.02%20--%2025.12+-blue.svg)](https://openwrt.org)
[![Firewall](https://img.shields.io/badge/Firewall-fw4%20(nftables)-green.svg)](https://openwrt.org/docs/guide-user/firewall/firewall_configuration)
[![PS5 Firmware](https://img.shields.io/badge/PS5%20Exploits-Y2JB%20%7C%20WebKit%20Autoloader-purple.svg)](https://github.com/drakmor/nanoDNS)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

A battle-tested, automated OpenWrt configuration framework designed for **PlayStation 5 jailbroken and exploit consoles** (firmwares 3.xx, 4.xx, 5.xx, 7.xx, etc.).

This repository provides automated scripts, UCI configuration templates, DNS blocklists, and an **AI Agent execution protocol** to:
1. **Prevent Accidental System Software Updates:** Integrated [nanoDNS](https://github.com/drakmor/nanoDNS) rule set that blocks all PlayStation update/telemetry/PSN servers while strictly whitelisting the User's Guide exploit entrypoint (`feature.api.playstation.com`) and STUN servers.
2. **Block YouTube Exclusively on PS5:** Restricts YouTube access solely for the PS5, leaving all other home devices (Smart TVs, laptops, phones) completely unblocked.
3. **Prevent Exploit Failures (`relapse FAILED kaslr: no interface has an address`):** Implements an exploit-safe layer-3 firewall architecture that avoids low-level DSA switch port lockups.
4. **Prevent IPv6 DNS/Internet Leaks:** Blocks SLAAC temporary IPv6 privacy addresses from bypassing IPv4 client-scoped filtering.

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

### Option 1: AI Coding Agent (Automated)
If you are using an AI Coding Assistant (Antigravity, Claude, ChatGPT, Cursor, Aider):
Simply point your AI agent to [AGENT.md](AGENT.md):
```text
"Please configure my OpenWrt router for my PS5 using the instructions in AGENT.md."
```
The agent will inspect your router, suggest the optimal mode, ask for your PS5 MAC address, and apply the configuration idempotently.

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
