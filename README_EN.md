<div align="center">

[**中文**](README.md) | [**English**](README_EN.md)

</div>

# 🚀 Xray Auto Installer

**Fully Automated, Modular Xray Deployment Script**

[![Top Language](https://img.shields.io/github/languages/top/ISFZY/Xray-Auto?style=flat-square&color=5D6D7E)](https://github.com/ISFZY/Xray-Auto/search?l=Shell)
[![Xray Core](https://img.shields.io/badge/Core-Xray-blue?style=flat-square)](https://github.com/XTLS/Xray-core)
[![License](https://img.shields.io/badge/License-MIT-orange?style=flat-square)](LICENSE)
[![GitHub release (latest by date including pre-releases)](https://img.shields.io/github/v/release/ISFZY/Xray-Auto?include_prereleases&style=flat-square&color=blue&refresh=1)](https://github.com/ISFZY/Xray-Auto/releases)

This project is a highly modular Shell script designed for the rapid deployment of proxy services based on the **Xray** core on Linux servers. It supports the latest **Vision** and **XHTTP** protocols and integrates SNI masking technology powered by Reality.

<div align="center">

[**中文**](README.md) | [**English**](README_EN.md)

</div>

---

## ✨ Features

* **📦 Modular Design**: The code is logically organized into three main modules: Core, Lib, and Tools.
* **🔒 Latest Protocols**: Supports Vision and XHTTP protocols with integrated Reality masking.
* **🛡️ Security Hardening**: Automatically configures Fail2ban and the Firewall.
* **🛠️ Rich Toolbox**: Built-in tools for WARP, BBR, port management, SNI optimization, and more.


## 📋 Requirements

* **OS**: Debian 10+, Ubuntu 20.04+ (Debian 11/12 recommended)
* **Architecture**: amd64, arm64
* **Permissions**: `root` access required
* **Ports**: Uses high random ports by default (for Vision and XHTTP).
* **Client**: Ensure your client supports these protocols (e.g., Shadowrocket, v2rayN, etc.)


## 📥 Quick Start

### 🚀 Recommended: One-Click Installation (Bootstrap)

Run the following command as the `root` user. The bootstrap script will automatically install Git, clone the repository, and start the installer.

```bash
bash <(curl -sL https://raw.githubusercontent.com/ISFZY/test/main/bootstrap.sh)

```

### 🛠️ Alternative: Manual Installation
If you cannot connect to GitHub Raw, you can try cloning manually:

```bash
# 1. Install Git
apt update && apt install -y git

# 2. Clone the repository
git clone https://github.com/ISFZY/test.git xray-install

# 3. Run the script
cd xray-install
chmod +x install.sh
./install.sh

```


## 🗑️ Uninstall

If you want to completely remove Xray and its related configurations, run the following (or type remove in the server terminal):

```bash
bash <(curl -sL https://raw.githubusercontent.com/ISFZY/test/main/tools/remove.sh)

```


## 🎮 Usage Guide

After installation, the management tools are registered to the system path. You can enter the following commands directly in the terminal:

| Command | Function | Description |
| :--- | :--- | :--- |
| `info` | **Admin Dashboard** | View node links, QR codes, service status, and the shortcut menu. |
| `user` | **User Management** | Query, add, or delete users. |
| `ports` | **Port Management** | Modify SSH, Vision, or XHTTP ports and automatically update firewall rules. |
| `net` | **Network Policy** | Switch IPv4/IPv6 priority or force single-stack mode. |
| `xw` | **WARP Manager** | Install Cloudflare WARP for Netflix/ChatGPT routing. |
| `bbr` | **Kernel Optimization** | Enable/Disable BBR acceleration, adjust queue algorithms (FQ/FQ_CODEL). |
| `sni` | **SNI Management** | Automatically test and select optimal SNI domains, or specify manually. |
| `bt` | **Audit Management** | One-click toggle for blocking BitTorrent downloads and private IP access. |
| `swap` | **Memory Management** | Add/Remove Swap partitions and adjust Swappiness. |
| `f2b` | **Fail2ban** | View banned IPs, unban IPs, and adjust banning policies. |
| `backup` | **Backup & Restore** | Query, backup, and restore configurations. |
| `sniff` | **Traffic Sniffing** | Enable/Disable traffic sniffing and logging. |
| `zone` | **Timezone Manager** | Configure timezone and system time. |
| `update` | **Updata** | Updata Xray core and Geodata。 |
| `remove` | **Uninstall** | Remove Xray and all installed components. |


### 📝 Client Configuration Reference

| Parameter | Value (Example) | Description |
| :--- | :--- | :--- |
| **Address** | `1.2.3.4` or `[2001::1]` | Server IP |
| **Port** | `443` | Port set during installation |
| **UUID** | `de305d54-...` | Type `info` to retrieve |
| **Flow** | `xtls-rprx-vision` | **Required for Vision nodes only** |
| **Network**| `tcp` or `xhttp` | Select TCP for Vision, xhttp for XHTTP |
| **SNI** | `www.microsoft.com` | Type `info` to retrieve |
| **Fingerprint**| `chrome` | Recommended fingerprint |
| **Public Key** | `B9s...` | Type `info` to retrieve |
| **ShortId** | `a1b2...` | Type `info` to retrieve |
| **Path** | `/8d39f310` | **Required for XHTTP nodes only** |


## 📂 Project Structure

This project uses a modular architecture with the following directory structure:

```text
.
├── bootstrap.sh       # One-click bootstrap script (Download, verify, start)
├── install.sh         # Main installation entry (Orchestration, lock mechanism)
├── lib/
│   └── utils.sh       # Common function library (UI, Logs, Colors, Task executor)
├── core/              # Core installation process
│   ├── 1_env.sh       # Environment check and initialization
│   ├── 2_install.sh   # Dependency and Xray core installation
│   ├── 3_system.sh    # System configuration (Firewall, Kernel)
│   └── 4_config.sh    # Configuration generation and service startup
└── tools/             # Standalone tools (Deployed to /usr/local/bin after install)
    ├── info.sh
    ├── ports.sh
    ├── net.sh
    ├── ...
```


## ⚠️ Disclaimer
1. **Research & Learning Only**: This project is intended solely for **network technology research, learning, and system testing**. Do not use this script for any purpose that violates national laws or regulations.
2. **Legal Compliance**: When using this script, you must comply with the laws and regulations of your country/region and the location of the server. Use for spreading illegal content involving politics, religion, pornography, or fraud is strictly prohibited. The user assumes all legal consequences arising from non-compliant use; the author assumes no joint liability.
3. **No Warranty**: This software is provided "as is" without any express or implied warranty. The author is not responsible for any direct or indirect losses (including but not limited to data loss, system crashes, IP bans, or server suspension by providers) caused by the use of this script.
4. **Third-Party Components**: This script integrates third-party open-source programs (such as Xray-core), whose copyright and liability belong to their original authors. The author of this script makes no guarantees regarding the security or stability of third-party programs.
5. **License**: This project follows the **GNU General Public License v3.0**. Please refer to the `LICENSE` file in the repository for detailed terms.

**Made with ❤️ by ISFZY**
