# Debian 13 ↔ UniFi UDM IPsec Site-to-Site VPN

This guide describes how to configure an **IKEv2 IPsec Site-to-Site VPN** between a Debian 13 server with a public IP address and a UniFi Dream Machine (UDM).

The setup uses:

- Debian 13
- strongSwan 6.x
- `swanctl`
- IKEv2
- Pre-Shared Key (PSK)
- Route-based IPsec using a VTI interface
- UniFi Site-to-Site IPsec VPN
- Support for a dynamic public IP address on the UniFi side
- Persistent routing after reboot
- Optional routing for UniFi LANs and UniFi Teleport

---

# 1. Choose the IP addresses

Before starting, choose a dedicated subnet for the Site-to-Site tunnel.

This guide uses the following example addresses:

| Purpose | Example |
|---|---|
| Debian public IP | `<DEBIAN_PUBLIC_IP>` |
| Debian VTI address | `10.200.201.1/30` |
| UniFi VTI address | `10.200.201.2` |
| VTI network | `10.200.201.0/30` |
| UniFi LAN | `192.168.178.0/23` |
| UniFi Teleport network | `192.168.4.0/24` |
| VTI key / mark | `42` |

## Important

Replace `<DEBIAN_PUBLIC_IP>` everywhere in this guide with the public IPv4 address of your Debian server.

The addresses `10.200.201.0/30`, `10.200.201.1` and `10.200.201.2` are only examples.

You may use another unused private subnet instead.

For a `/30` network:

```text
10.200.201.0/30

10.200.201.0 = network address
10.200.201.1 = Debian
10.200.201.2 = UniFi UDM
10.200.201.3 = broadcast address
```

If you already use `10.200.201.0/30`, choose another unused subnet.

For example, a second Site-to-Site tunnel could use:

```text
10.200.202.0/30

Debian: 10.200.202.1
UDM:    10.200.202.2
```

Every Site-to-Site tunnel must use its own non-overlapping VTI subnet.

The VTI subnet must also not overlap with any LAN, VLAN, VPN or other routed network on either side.

---

# 2. Install strongSwan on Debian

Run the following commands as `root` on the Debian server:

```bash
apt update

apt install -y \
    strongswan \
    charon-systemd \
    strongswan-swanctl \
    libstrongswan-standard-plugins \
    libstrongswan-extra-plugins
```

The additional plugin packages provide the cryptographic plugins required by strongSwan.

---

# 3. Disable the TPM plugin

If TPM support is not required, disable the TPM plugin.

Create the configuration:

```bash
cat > /etc/strongswan.d/charon/tpm.conf <<'EOF'
tpm {
    load = no
}
EOF
```

Restart strongSwan:

```bash
systemctl restart strongswan
```

Check for plugin errors:

```bash
journalctl -u strongswan --since "1 minute ago" --no-pager | grep -i "failed to load" || echo "No plugin errors"
```

Expected result:

```text
No plugin errors
```

---

# 4. Configure the Debian firewall

## Replace before running

Replace:

```text
<DEBIAN_PUBLIC_IP>
```

with the public IPv4 address of your Debian server.

If UFW is used:

```bash
ufw allow 500/udp comment 'IPsec IKE'
ufw allow 4500/udp comment 'IPsec NAT-T'
ufw allow to <DEBIAN_PUBLIC_IP> proto esp comment 'IPsec ESP'
```

Check the firewall:

```bash
ufw status
```

The firewall should allow:

```text
UDP 500
UDP 4500
ESP
```

If you are using another firewall, create equivalent rules there.

---

# 5. Generate a Pre-Shared Key

Generate a random PSK:

```bash
openssl rand -base64 32
```

Example:

```text
YOUR_RANDOM_PSK_HERE
```

Save this key securely.

The same PSK must be configured on both Debian and the UniFi UDM.

---

# 6. Create the strongSwan configuration

Create the configuration directory:

```bash
mkdir -p /etc/swanctl/conf.d
chmod 700 /etc/swanctl
```

## Replace before running

Replace:

```text
<DEBIAN_PUBLIC_IP>
```

with the public IPv4 address of your Debian server.

Replace:

```text
YOUR_RANDOM_PSK_HERE
```

with the PSK generated in the previous step.

If you selected a different VTI subnet, no change is required in this particular configuration because the traffic selectors use `0.0.0.0/0`.

Create the configuration:

```bash
cat > /etc/swanctl/conf.d/debian-unifi.conf <<'EOF'
connections {
    unifi-s2s {
        version = 2

        local_addrs = <DEBIAN_PUBLIC_IP>
        remote_addrs = %any

        proposals = aes256-sha256-modp2048

        local {
            auth = psk
            id = <DEBIAN_PUBLIC_IP>
        }

        remote {
            auth = psk
            id = unifi-s2s
        }

        children {
            unifi-s2s {
                local_ts = 0.0.0.0/0
                remote_ts = 0.0.0.0/0

                esp_proposals = aes256-sha256-modp2048

                mark_in = 42
                mark_out = 42

                start_action = none
                dpd_action = restart
            }
        }
    }
}

secrets {
    ike-unifi {
        id-1 = <DEBIAN_PUBLIC_IP>
        id-2 = unifi-s2s
        secret = "YOUR_RANDOM_PSK_HERE"
    }
}
EOF
```

The following setting allows the UniFi side to use a dynamic public WAN address:

```text
remote_addrs = %any
```

The UniFi UDM authenticates itself using the configured IKE identity:

```text
unifi-s2s
```

---

# 7. Load the strongSwan configuration

Restart strongSwan:

```bash
systemctl restart strongswan
```

Load the configuration:

```bash
swanctl --load-all
```

Check the loaded connection:

```bash
swanctl --list-conns
```

It should contain:

```text
unifi-s2s: IKEv2
```

and show:

```text
local:  <DEBIAN_PUBLIC_IP>
remote: %any
```

---

# 8. Create the Debian VTI interface

## Replace before running

Replace:

```text
<DEBIAN_PUBLIC_IP>
```

with the public IPv4 address of your Debian server.

The example uses:

```text
VTI network: 10.200.201.0/30
Debian:      10.200.201.1
UDM:         10.200.201.2
```

If you selected another VTI subnet in Step 1, replace all occurrences of:

```text
10.200.201.0/30
10.200.201.1/30
```

with your selected network and Debian VTI address.

Also replace the example UniFi networks:

```text
192.168.178.0/23
192.168.4.0/24
```

with the actual networks that should be reachable through the Site-to-Site tunnel.

If you do not use UniFi Teleport, remove:

```text
ip route replace 192.168.4.0/24 dev ipsec0 table 220
```

Create the VTI script:

```bash
cat > /usr/local/sbin/ipsec-vti-up.sh <<'EOF'
#!/bin/bash
set -e

ip link show ipsec0 >/dev/null 2>&1 || \
ip tunnel add ipsec0 \
    local <DEBIAN_PUBLIC_IP> \
    remote 0.0.0.0 \
    mode vti \
    key 42

ip link set ipsec0 up

ip addr show dev ipsec0 | grep -q '10.200.201.1/30' || \
ip addr add 10.200.201.1/30 dev ipsec0

ip route replace 10.200.201.0/30 dev ipsec0 table 220
ip route replace 192.168.178.0/23 dev ipsec0 table 220
ip route replace 192.168.4.0/24 dev ipsec0 table 220

sysctl -w net.ipv4.conf.ipsec0.disable_policy=1 >/dev/null
sysctl -w net.ipv4.conf.ipsec0.rp_filter=0 >/dev/null
EOF

chmod +x /usr/local/sbin/ipsec-vti-up.sh
```

The routes determine which remote networks Debian sends through the Site-to-Site tunnel.

For example:

```text
10.200.201.0/30    VTI network
192.168.178.0/23   UniFi LAN
192.168.4.0/24     UniFi Teleport
```

Add additional UniFi LAN/VLAN networks as required:

```bash
ip route replace <REMOTE_NETWORK> dev ipsec0 table 220
```

For example:

```bash
ip route replace 192.168.50.0/24 dev ipsec0 table 220
```

---

# 9. Create the VTI systemd service

Create:

```bash
cat > /etc/systemd/system/ipsec-vti.service <<'EOF'
[Unit]
Description=IPsec VTI Interface
After=network-online.target strongswan.service
Wants=network-online.target
Requires=strongswan.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/ipsec-vti-up.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
```

Enable and start the service:

```bash
systemctl daemon-reload
systemctl enable --now ipsec-vti.service
```

Check:

```bash
systemctl status ipsec-vti.service
```

---

# 10. Verify the VTI on Debian

Check the interface:

```bash
ip -br addr show ipsec0
```

With the example addresses, the result should contain:

```text
10.200.201.1/30
```

Check routing table 220:

```bash
ip route show table 220
```

With the example networks, it should contain:

```text
10.200.201.0/30 dev ipsec0
192.168.178.0/23 dev ipsec0
192.168.4.0/24 dev ipsec0
```

---

# 11. Configure the UniFi UDM

Open:

```text
UniFi Network
→ Settings
→ VPN
→ Site-to-Site VPN
```

Create a new IPsec Site-to-Site VPN.

## Replace before configuring

Replace:

```text
<DEBIAN_PUBLIC_IP>
```

with the public IPv4 address of your Debian server.

If you selected another VTI subnet, replace:

```text
10.200.201.1
10.200.201.2
```

with your selected Debian and UniFi VTI addresses.

Use the same PSK generated in Step 5.

---

# 12. UniFi basic settings

Configure the VPN as an IPsec Site-to-Site connection.

Use:

```text
Remote Gateway:
<DEBIAN_PUBLIC_IP>

Pre-Shared Key:
YOUR_RANDOM_PSK_HERE

IKE Version:
IKEv2
```

The public WAN IP of the UDM may be dynamic.

The Debian configuration accepts the UDM from any source address using:

```text
remote_addrs = %any
```

---

# 13. UniFi IKE identities

Configure the UniFi/local IKE identity as:

```text
unifi-s2s
```

This must match the Debian configuration:

```text
remote {
    auth = psk
    id = unifi-s2s
}
```

Configure the remote IKE identity as:

```text
<DEBIAN_PUBLIC_IP>
```

This must match:

```text
local {
    auth = psk
    id = <DEBIAN_PUBLIC_IP>
}
```

---

# 14. UniFi Phase 1 / IKE settings

Configure:

```text
IKE Version:       IKEv2
Encryption:        AES-256
Hash / Integrity:  SHA-256
DH Group:          14
```

DH Group 14 corresponds to MODP 2048.

This matches:

```text
aes256-sha256-modp2048
```

on Debian.

---

# 15. UniFi Phase 2 / ESP settings

Configure:

```text
Encryption:        AES-256
Hash / Integrity:  SHA-256
PFS / DH Group:    14
```

This matches the Debian ESP proposal:

```text
aes256-sha256-modp2048
```

---

# 16. Configure the route-based tunnel on UniFi

## Replace before configuring

The example uses:

```text
Debian VTI: 10.200.201.1
UniFi VTI:  10.200.201.2
```

If you selected another VTI subnet, use those addresses instead.

Configure the Site-to-Site VPN as a route-based/VTI connection.

Use:

```text
Remote Tunnel IP:
10.200.201.1

Local Tunnel IP:
10.200.201.2
```

The resulting tunnel network in this example is:

```text
10.200.201.0/30
```

Do not reuse these VTI addresses for another Site-to-Site connection.

Each additional Site-to-Site VPN requires its own non-overlapping VTI subnet.

For example:

```text
First S2S:
10.200.201.0/30
Debian: 10.200.201.1
UDM:    10.200.201.2

Second S2S:
10.200.202.0/30
Debian: 10.200.202.1
UDM:    10.200.202.2
```

---

# 17. Configure UniFi routing

Add the networks that should use the Site-to-Site VPN on the UniFi side.

The exact UniFi UI depends on the UniFi Network version.

The destination for the Debian side in this example is:

```text
10.200.201.1
```

Traffic to this address must be routed through the Site-to-Site VPN.

If additional networks exist behind the Debian server, add routes for those networks as required.

---

# 18. Verify the IPsec tunnel

On Debian:

```bash
swanctl --list-sas
```

A working tunnel should contain:

```text
ESTABLISHED
```

and the CHILD_SA should contain:

```text
INSTALLED
TUNNEL
```

Example:

```text
unifi-s2s: #1, ESTABLISHED, IKEv2
  local  '<DEBIAN_PUBLIC_IP>' @ <DEBIAN_PUBLIC_IP>[4500]
  remote 'unifi-s2s' @ <UDM_PUBLIC_IP>[4500]

  AES_CBC-256/HMAC_SHA2_256_128/PRF_HMAC_SHA2_256/MODP_2048

  unifi-s2s: #1, INSTALLED, TUNNEL
    local  0.0.0.0/0
    remote 0.0.0.0/0
```

---

# 19. Test the VTI connection

## Replace before running

If you selected another VTI subnet, replace:

```text
10.200.201.2
```

with the VTI address of your UDM.

From Debian:

```bash
ping -c 4 10.200.201.2
```

Check the route:

```bash
ip route get 10.200.201.2
```

With the example configuration, it should use:

```text
dev ipsec0
```

and the source should be:

```text
10.200.201.1
```

---

# 20. Verify the return routes

Debian must have a route through `ipsec0` for every remote network that needs to communicate through the Site-to-Site tunnel.

Check:

```bash
ip route show table 220
```

Example:

```text
10.200.201.0/30 dev ipsec0
192.168.178.0/23 dev ipsec0
192.168.4.0/24 dev ipsec0
```

To add another remote network:

```bash
ip route replace <REMOTE_NETWORK> dev ipsec0 table 220
```

Also add the same route to:

```text
/usr/local/sbin/ipsec-vti-up.sh
```

so it survives a reboot.

---

# 21. UniFi Teleport

If UniFi Teleport clients should reach the Debian server, determine the Teleport network used by the UDM.

In this example it is:

```text
192.168.4.0/24
```

## Replace before running

Replace:

```text
192.168.4.0/24
```

with your actual UniFi Teleport network.

Add the return route on Debian:

```bash
ip route replace 192.168.4.0/24 dev ipsec0 table 220
```

Also add it permanently to:

```text
/usr/local/sbin/ipsec-vti-up.sh
```

A Teleport client should then be able to reach the Debian VTI address:

```text
10.200.201.1
```

or the corresponding Debian VTI address if another subnet was selected.

---

# 22. Troubleshooting with tcpdump

Install tcpdump if required:

```bash
apt install -y tcpdump
```

On Debian:

```bash
tcpdump -ni any host <CLIENT_IP>
```

For example:

```bash
tcpdump -ni any host 192.168.4.1
```

Incoming traffic through the tunnel should appear on:

```text
ipsec0
```

If the response leaves through the normal Internet interface instead of `ipsec0`, check routing table 220:

```bash
ip route show table 220
```

Add the missing remote network:

```bash
ip route replace <REMOTE_NETWORK> dev ipsec0 table 220
```

On the UDM, traffic can be inspected with:

```bash
tcpdump -ni any host <DEBIAN_VTI_IP>
```

For the example configuration:

```bash
tcpdump -ni any host 10.200.201.1
```

---

# 23. Check IPsec packet counters

Run:

```bash
swanctl --list-sas
```

The CHILD_SA displays incoming and outgoing packet counters.

Example:

```text
in  ... bytes, ... packets
out ... bytes, ... packets
```

When traffic is sent through the tunnel, these counters should increase.

---

# 24. Reboot test

Reboot Debian:

```bash
reboot
```

After reconnecting:

```bash
echo "===== STRONGSWAN ====="
systemctl is-active strongswan

echo
echo "===== VTI SERVICE ====="
systemctl is-active ipsec-vti

echo
echo "===== IPSEC0 ====="
ip -br addr show ipsec0

echo
echo "===== TABLE 220 ====="
ip route show table 220

echo
echo "===== IPSEC TUNNEL ====="
swanctl --list-sas
```

Expected service states:

```text
strongswan:
active

ipsec-vti:
active
```

The VTI interface should contain the configured Debian VTI address.

With the example configuration:

```text
10.200.201.1/30
```

The configured routes should also be restored automatically.

The UDM initiates the IPsec connection, so allow a short time after the Debian server has booted for the tunnel to reconnect.

---

# 25. Final configuration overview

Example topology:

```text
                     UniFi LAN
                 192.168.178.0/23
                         |
                         |
                   +-----+-----+
                   | UniFi UDM |
                   +-----+-----+
                         |
                         | IKEv2 / IPsec
                         | Route-based VTI
                         |
                  10.200.201.2
                         |
                  10.200.201.0/30
                         |
                  10.200.201.1
                   +-----+-----+
                   | Debian 13 |
                   +-----------+
                         |
                         |
                 <DEBIAN_PUBLIC_IP>


UniFi Teleport
192.168.4.0/24
       |
       v
  UniFi UDM
       |
       v
  IPsec S2S
       |
       v
 Debian VTI
10.200.201.1
```

---

# 26. Adding another Site-to-Site VPN

Never reuse the VTI subnet of an existing Site-to-Site connection.

For example, if the first tunnel uses:

```text
10.200.201.0/30
```

a second tunnel could use:

```text
10.200.202.0/30
```

Example:

```text
S2S #1

Network: 10.200.201.0/30
Debian:  10.200.201.1
Remote:  10.200.201.2


S2S #2

Network: 10.200.202.0/30
Debian:  10.200.202.1
Remote:  10.200.202.2
```

The networks must not overlap with:

- existing VTI networks
- LAN networks
- VLAN networks
- remote networks
- VPN networks
- Teleport networks
- other routed networks

A separate VTI interface, VTI key/mark and corresponding routes should be used for each additional Site-to-Site connection.

---

# 27. Useful diagnostic commands

Check strongSwan:

```bash
systemctl status strongswan
```

Check loaded connections:

```bash
swanctl --list-conns
```

Check active tunnels:

```bash
swanctl --list-sas
```

Check the VTI:

```bash
ip -br addr show ipsec0
```

Check routing table 220:

```bash
ip route show table 220
```

Check a route:

```bash
ip route get <DESTINATION_IP>
```

Check recent strongSwan logs:

```bash
journalctl -u strongswan -n 100 --no-pager
```

Check for plugin errors:

```bash
journalctl -u strongswan --since "1 minute ago" --no-pager | grep -i "failed to load" || echo "No plugin errors"
```

Monitor traffic:

```bash
tcpdump -ni any host <DESTINATION_IP>
```

---

# Result

The finished configuration provides a persistent route-based IKEv2/IPsec Site-to-Site connection between Debian 13 and a UniFi UDM.

The Debian side automatically restores after reboot:

- strongSwan
- the VTI interface
- the VTI IP address
- routing table 220 entries

Remote UniFi networks can be added by adding the corresponding route to the VTI script.

UniFi Teleport can also use the Site-to-Site connection when the Teleport subnet has a corresponding return route on the Debian server.
