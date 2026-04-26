# 🔷🌐 wg-setup

A single Bash script that installs a full WireGuard server on any Ubuntu or Debian VPS. It generates the server keys, writes the interface config, enables IP forwarding, sets up NAT, starts the service. When it finishes it generates the first peer config file, prints a QR code you can scan directly from the terminal.

```bash
git clone https://github.com/krainium/wireguard-installer
cd wireguard-installer
sudo bash wg-setup.sh
```

---

## 🎯 What it does

The script detects your OS, installs WireGuard, generates server keys, assigns the VPN subnet `10.10.0.0/24`, writes `wg0.conf` with PostUp and PostDown NAT rules, enables IP forwarding, opens the UDP port in the firewall, starts `wg-quick@wg0`. It then creates the first peer config and shows its QR code on screen.

No manual key generation. No editing config files by hand.

---

## ⚙️ Setup walkthrough

Run the script as root. It asks three questions then does the rest on its own.

**Public IP** — it detects this automatically. Press Enter to confirm or type a different address if you are behind NAT.

**Port** — defaults to `51820`. WireGuard is UDP only. Change the port to anything you prefer.

**DNS** — pick what your VPN peers will use for name resolution.
```
1  Cloudflare     1.1.1.1 / 1.0.0.1
2  Google         8.8.8.8 / 8.8.4.4
3  OpenDNS        208.67.222.222 / 208.67.220.220
4  Quad9          9.9.9.9 / 149.112.112.112
5  AdGuard        94.140.14.14 / 94.140.15.15
6  System         reads from /etc/resolv.conf
```

After you answer those, the script runs without any more input. At the end it prompts for a peer name, generates the peer config, prints a QR code in the terminal.

---

## 📋 Management menu

Run the script again any time to open the menu.

```
  1  👤  Add Peer          generates keys, config file, QR code
  2  🗑   Remove Peer       removes from wg0.conf, deletes the config file
  3  📋  List Peers         shows live wg show output + saved config paths
  4  📱  Show QR Code       prints the QR code for any peer on screen
  5  📊  Status             service status + interface stats
  6  🔄  Restart WireGuard  restarts wg-quick@wg0
  7  🗑   Uninstall          removes everything — asks you to type YES first
  0  ❌  Exit
```

---

## 📁 Where things live

| Path | What is it |
|------|------------|
| `/root/wg-setup/peers/` | All generated peer `.conf` files |
| `/etc/wireguard/wg0.conf` | Server interface config |
| `/etc/wg-setup/state.conf` | Saved setup values |

---

## 📱 Connecting a device

**Mobile — scan the QR code**
Open the WireGuard app on your phone, tap the `+` button, choose `Scan from QR code`. Point the camera at the QR code printed in the terminal. Done.

**Desktop — import the config file**
Copy the peer `.conf` file from `/root/wg-setup/peers/` to your computer. In the WireGuard desktop app, click `Import tunnel(s) from file` and select it.

**Linux client**
```bash
sudo apt install wireguard
sudo cp peername.conf /etc/wireguard/wg0.conf
sudo wg-quick up wg0
```

---

## 📱 Compatible clients

| Client | Platform |
|--------|----------|
| WireGuard | Android · iOS · Windows · macOS · Linux |

The WireGuard app is the only client you need. It is the official client on every platform.

---

## 🔒 Security details

Every peer gets its own private key, public key, a unique preshared key for an extra layer of post-quantum resistance. Each peer is assigned its own IP from the `10.10.0.0/24` subnet. The server only forwards traffic from known peers — anyone without a valid key pair simply gets no response.

---

## 🛠 Troubleshooting

**Peer connects but no internet**
```bash
ip link show wg0                     # interface should be UP
wg show wg0                          # check latest handshake time
cat /proc/sys/net/ipv4/ip_forward    # should print 1
iptables -t nat -L POSTROUTING -n    # should show MASQUERADE rule
```

**Handshake never happens**
The UDP port is probably blocked by the VPS firewall or host provider. Check the firewall:
```bash
ufw status
iptables -L INPUT -n | grep <your-port>
```
If the port is not listed as allowed, open it manually or reinstall the script with a different port.

**No QR code after adding a peer**
Install `qrencode` on the server:
```bash
apt-get install qrencode
```
Then open the menu, pick option `4` and select the peer. The QR code will display.

**Peer was added but stops connecting after server restart**
The peer block in `wg0.conf` may be incomplete. Remove the peer from the menu and add it again. New peers are always written to `wg0.conf` so they survive restarts.
