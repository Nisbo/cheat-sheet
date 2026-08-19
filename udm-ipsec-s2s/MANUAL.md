# IPsec S2S Manager --- Manual

This manual describes **IPsec S2S Manager 1.0.0**.

All IP addresses, hostnames and network names in the examples are
fictional documentation data. Replace them with your own values.

------------------------------------------------------------------------

# 1. Concept

IPsec S2S Manager creates **route-based IKEv2/IPsec tunnels** on Debian
13.

The encrypted IPsec connection transports traffic for a Linux **VTI
interface**. The VTI receives an address from a dedicated `/30` transfer
network.

Example:

``` text
Server A                                             Server B
198.51.100.10                                        203.0.113.50
     │                                                     │
     └────────────── IKEv2 / IPsec / ESP ─────────────────┘
                           │
                 10.200.210.0/30
                           │
             .1 ◄──────────┴──────────► .2
          ipsec0                         ipsec0
```

The `/30` is not a LAN. It is the point-to-point transfer network
between the two tunnel interfaces.

Remote LAN/VLAN routes are then sent through the VTI.

------------------------------------------------------------------------

# 2. State and system files

Manager state:

``` text
/root/s2s-manager/
```

The state contains tunnel definitions, remote routes, PSKs, backups and
exports.

Installed tunnels additionally create manager-owned system files similar
to:

``` text
/etc/swanctl/conf.d/s2s-manager-office-unifi.conf
/usr/local/sbin/s2s-manager-vti-office-unifi.sh
/etc/systemd/system/s2s-manager-vti-office-unifi.service
```

The manager distinguishes between:

-   **DEFINED** --- saved in the manager but not installed on Debian.
-   **MANAGED** --- installed and owned by the manager.
-   **IMPORTED** --- discovered existing configuration, initially
    read-only.
-   **PARTIAL / BROKEN** --- expected manager-owned installation
    artifacts are incomplete.

Connection state is checked separately from management state.

------------------------------------------------------------------------

# 3. Pre-flight setup

On first use, the manager checks Debian and the required IPsec/VTI
environment.

If prerequisites are missing, the setup menu is shown:

``` text
──────────────────────────────────────────────────────────────
  SETUP REQUIRED
──────────────────────────────────────────────────────────────

  [1] Install / repair prerequisites
  [2] Run pre-flight check again
  [3] Discover / import existing tunnels
  [E] Exit
```

Choose **\[1\]** on a normal new installation.

UFW is optional. The manager can add the shared IPsec rules for:

``` text
UDP 500   IKE
UDP 4500  IPsec NAT-T
```

If you use a provider firewall, cloud firewall or upstream firewall, it
must also allow the required traffic.

------------------------------------------------------------------------

# 4. Main menu

``` text
  TUNNEL CONFIGURATION                         TUNNEL OPERATIONS
  ─────────────────────────────────────────    ────────────────────────────────────────
  [1] Show tunnel configuration                [7] Install tunnel on Debian
  [2] Add S2S tunnel                           [8] Re-apply tunnel configuration
  [3] Add remote network to tunnel             [9] Reconnect tunnel
  [4] Remove remote network from tunnel        [10] Tunnel diagnostics
  [5] Show UniFi configuration
  [6] Rename tunnel display name

  REMOVE / DELETE                              IMPORT / TAKE OVER
  ─────────────────────────────────────────    ────────────────────────────────────────
  [11] Uninstall tunnel from Debian            [13] Discover / import existing tunnels
  [12] Delete tunnel completely                [14] Take over imported tunnel
                                                [15] Show Take Over backups

  EXPORT / TRANSFER                            SYSTEM
  ─────────────────────────────────────────    ────────────────────────────────────────
  [16] Tunnel backup / restore                 [20] Show system status
  [17] Create Debian peer bundle
  [18] Transfer Debian peer bundle via SCP
  [19] Import Debian peer bundle
```

------------------------------------------------------------------------

# 5. Menu reference

## \[1\] Show tunnel configuration

Displays the complete saved definition and current connection state.

It is read-only.

Typical output:

``` text
──────────────────────────────────────────────────────────────
  Tunnel configuration: Office-UniFi
──────────────────────────────────────────────────────────────

Display name:                Office-UniFi
Internal name:               office-unifi
Peer type:                   UniFi Gateway
Management:                  MANAGED
Connection:                  CONNECTED
Local Debian public IP:      198.51.100.10
Authentication ID:           office-unifi
Peer mode:                   Static IPv4
Peer address:                203.0.113.20
VTI interface:               ipsec0
VTI key / mark:              42
Tunnel network:              10.200.202.0/30
Local Debian VTI IP:         10.200.202.1
UniFi VTI IP:                10.200.202.2

Remote networks:
  • 192.168.10.0/24
  • 192.168.20.0/24
```

## \[2\] Add S2S tunnel

Starts the eight-step creation wizard.

The wizard does not immediately alter the system. At the end you first
save the definition and are then asked whether it should be installed.

The eight steps are:

1.  Tunnel Display Name
2.  Peer Type
3.  Peer Endpoint
4.  Debian Public IP
5.  Site-to-Site Tunnel Network
6.  Peer Authentication ID
7.  Remote Networks
8.  Pre-Shared Key

A display name is intended for humans. The manager derives a technical
internal name for files and services.

## \[3\] Add remote network to tunnel

Adds another network reachable through the remote side of an existing
tunnel.

Examples:

``` text
192.168.30.0/24
10.50.0.0/16
```

The manager checks overlap with:

-   transfer networks;
-   other configured remote networks;
-   live Debian routes such as LAN, VPN or WireGuard routes.

For an installed tunnel, re-apply the configuration afterwards when
prompted/required so the route is present in the active manager
configuration.

## \[4\] Remove remote network from tunnel

Removes a remote route from the saved tunnel definition.

It does **not** delete the tunnel.

## \[5\] Show UniFi configuration

Only applies to a tunnel whose peer type is **UniFi Gateway**.

It prints the values to enter in UniFi, including:

``` text
VPN Type:                       IPsec
VPN Method:                     Route Based
Tunnel IP:                      Enabled
IPv4 Address:                   10.200.202.2
Netmask:                        30
Key Exchange Version:           IKEv2

IKE:
Encryption: AES-256
Hash:       SHA256
DH Group:   14
Lifetime:   28800

ESP:
Encryption: AES-256
Hash:       SHA256
DH Group:   14
Lifetime:   3600

Perfect Forward Secrecy:        Enabled
Local Authentication ID:       office-unifi
Remote Authentication ID:      198.51.100.10
```

The PSK is hidden by default and can be shown after an explicit
confirmation.

## \[6\] Rename tunnel display name

Changes only the human-readable display name.

It does **not** rename:

-   the internal tunnel name;
-   strongSwan connection files;
-   VTI scripts;
-   systemd services;
-   manager filenames.

This makes renaming safe for an installed tunnel.

## \[7\] Install tunnel on Debian

Takes an existing **DEFINED** tunnel and creates its manager-owned
Debian configuration.

This includes:

-   strongSwan connection;
-   VTI startup script;
-   systemd VTI service;
-   table 220 routes;
-   shared UFW IPsec rules when applicable.

The saved PSK is reused.

## \[8\] Re-apply tunnel configuration

Regenerates manager-owned configuration from the saved definition.

Use it after changing saved settings or when manager-owned files need to
be repaired.

Re-apply is **not the same as reconnect**.

An already established IKE/CHILD SA may remain active until its next
rekey. If a changed IPsec setting must take effect immediately, use
**\[9\] Reconnect tunnel** afterwards.

## \[9\] Reconnect tunnel

Terminates the current IKE/CHILD SAs and establishes a fresh IPsec
connection.

It does not regenerate the PSK or rewrite the tunnel definition.

Traffic is briefly interrupted.

For Debian-to-Debian peers, the manager can actively initiate the
connection. A UniFi peer may instead reconnect from the UniFi side
depending on the configured endpoint mode.

## \[10\] Tunnel diagnostics

Read-only diagnostics for one tunnel.

Example:

``` text
──────────────────────────────────────────────────────────────
  SERVICE / INTERFACE
──────────────────────────────────────────────────────────────

[✓] strongSwan: active
[✓] s2s-manager-vti-office-unifi.service: active
[✓] ipsec0: present
Current VTI address:         10.200.202.1/30

──────────────────────────────────────────────────────────────
  ROUTING
──────────────────────────────────────────────────────────────

Table:                       220
[✓] 10.200.202.0/30 -> ipsec0
[✓] 192.168.10.0/24 -> ipsec0

──────────────────────────────────────────────────────────────
  IPSEC STATUS
──────────────────────────────────────────────────────────────

[✓] IKE: ESTABLISHED
[✓] CHILD_SA: INSTALLED
[✓] Transport: ESP-in-UDP / NAT-T
Traffic IN:                  12.4 KiB
Traffic OUT:                 8.1 KiB
```

Optional tests include:

1.  Ping the remote VTI address
2.  Analyze continuous connection uptime
3.  Show recent strongSwan logs

## \[11\] Uninstall tunnel from Debian

Removes the installed manager-owned system configuration while keeping:

-   tunnel definition;
-   remote networks;
-   PSK.

Use this when you want to deactivate/remove the Debian installation but
may install the same tunnel again later.

## \[12\] Delete tunnel completely

Permanently deletes the manager tunnel.

If installed, its manager-owned Debian configuration is removed as part
of the operation.

The definition and PSK are then deleted.

Create a backup first if you may need the tunnel later.

## \[13\] Discover / import existing tunnels

Scans the Debian system for existing strongSwan/VTI tunnels that are not
yet managed.

A discovered tunnel can be imported as a read-only manager entry.

Importing is deliberately separate from taking ownership: the existing
configuration is not immediately rewritten.

## \[14\] Take over imported tunnel

Converts a previously imported tunnel into a manager-owned tunnel.

Before changing source files, the manager creates a timestamped
take-over backup and validates the proposed managed configuration.

After successful take-over, normal manager functions can be used.

## \[15\] Show Take Over backups

Displays backups created before take-over operations.

This view is read-only.

## \[16\] Tunnel backup / restore

Contains two functions:

``` text
[1] Create tunnel backup
[2] Restore tunnel backup
```

A backup is a portable archive of one manager tunnel and can include:

-   tunnel definition;
-   remote networks;
-   PSK.

Restored tunnels always return as **DEFINED**. Restore does not
automatically install strongSwan/VTI/systemd configuration.

If the internal name or display name already exists, restore stops. It
does not overwrite the existing tunnel and does not automatically append
`-2`.

## \[17\] Create Debian peer bundle

Only for **Debian / strongSwan** peer tunnels.

Creates the mirrored definition needed by the second Debian server.

The bundle contains the same PSK and is therefore sensitive.

Example flow:

``` text
Server A tunnel:
  Local public:   198.51.100.10
  Remote public:  203.0.113.50
  Local VTI:      10.200.210.1
  Remote VTI:     10.200.210.2

Generated peer bundle for Server B:
  Local public:   203.0.113.50
  Remote public:  198.51.100.10
  Local VTI:      10.200.210.2
  Remote VTI:     10.200.210.1
```

## \[18\] Transfer Debian peer bundle via SCP

Transfers an already-created peer bundle directly from the current
Debian server to the remote Debian server.

Example destination:

``` text
root@203.0.113.50:/root/s2s-manager-import/
```

The remote import directory is created automatically if necessary.

With password-based SSH you normally enter the password once while
preparing/checking the remote directory and again for the SCP transfer.
With suitable SSH key authentication, no interactive password may be
required.

The local computer is not used as an intermediate hop.

## \[19\] Import Debian peer bundle

On the second Debian server, finds bundles in:

``` text
/root/s2s-manager-import/
```

or allows another path.

Before writing manager files or the included PSK, the manager performs
local conflict validation for items such as:

-   transfer network;
-   endpoint pair;
-   VTI interface allocation;
-   VTI key/mark allocation.

It then shows a preview and asks for confirmation.

## \[20\] Show system status

Shows the manager's view of the local prerequisites and IPsec/VTI
environment.

Use it when checking the host itself rather than one particular tunnel.

------------------------------------------------------------------------

# 6. Complete walkthrough --- UniFi Gateway ↔ Debian

## 6.1 Example topology

``` text
                           Internet

        UniFi Gateway                       Debian VPS
        203.0.113.20                      198.51.100.10
              │                                  │
              └──────── IKEv2/IPsec ─────────────┘
                         Route Based

              VTI .2                         VTI .1
         10.200.202.2/30                10.200.202.1/30
              │
        ┌─────┴─────────────┐
        │                   │
192.168.10.0/24      192.168.20.0/24
Office LAN            Server VLAN
```

We want Debian to reach both UniFi-side networks.

## 6.2 Start tunnel creation

Choose:

``` text
Selection: 2
```

### Step 1 --- Display name

``` text
──────────────────────────────────────────────────────────────
  STEP 1/8  Tunnel Display Name
──────────────────────────────────────────────────────────────

Tunnel display name [home]: Office-UniFi

Display name:                Office-UniFi
Internal name:               office-unifi
```

### Step 2 --- Peer type

``` text
──────────────────────────────────────────────────────────────
  STEP 2/8  Peer Type
──────────────────────────────────────────────────────────────

  [1] UniFi Gateway
  [2] Debian / strongSwan

Selection [1]: 1
```

### Step 3 --- Peer endpoint

For a fixed UniFi WAN address:

``` text
──────────────────────────────────────────────────────────────
  STEP 3/8  Peer Endpoint
──────────────────────────────────────────────────────────────

  [1] Dynamic / unknown
  [2] Static IPv4 address
  [3] Hostname / Dynamic DNS

Selection [1]: 2

UniFi public IPv4: 203.0.113.20
```

Use **Dynamic / unknown** when the UniFi WAN address is not known to
Debian and UniFi will initiate. Use **Hostname / Dynamic DNS** when a
hostname resolves to one IPv4 address.

### Step 4 --- Debian public IP

``` text
──────────────────────────────────────────────────────────────
  STEP 4/8  Debian Public IP
──────────────────────────────────────────────────────────────

Debian public IP [198.51.100.10]:
```

Press Enter if detection is correct.

### Step 5 --- transfer network

``` text
──────────────────────────────────────────────────────────────
  STEP 5/8  Site-to-Site Tunnel Network
──────────────────────────────────────────────────────────────

Tunnel network [10.200.202.0]: 10.200.202.0/30

[✓] Tunnel network available: 10.200.202.0/30

Network:       10.200.202.0/30
Debian IP:     10.200.202.1
UniFi IP:      10.200.202.2
Broadcast:     10.200.202.3

Use these addresses? [Y/n]: y
```

### Step 6 --- Authentication ID

``` text
──────────────────────────────────────────────────────────────
  STEP 6/8  Peer Authentication ID
──────────────────────────────────────────────────────────────

UniFi authentication ID [unifi-office-unifi]: office-unifi
```

This is an IKE identity, not a DNS name.

### Step 7 --- UniFi-side networks

``` text
──────────────────────────────────────────────────────────────
  STEP 7/8  Remote Networks
──────────────────────────────────────────────────────────────

Remote network #1: 192.168.10.0/24
[✓] Network available: 192.168.10.0/24

Remote network #2: 192.168.20.0/24
[✓] Network available: 192.168.20.0/24

Remote network #3:
[✓] Remote network entry finished (2 network(s)).
```

### Step 8 --- PSK

``` text
──────────────────────────────────────────────────────────────
  STEP 8/8  Pre-Shared Key
──────────────────────────────────────────────────────────────

  [1] Generate a secure random PSK
  [2] Enter my own PSK

Selection [1]: 1
[✓] Secure random PSK generated.
```

Save and install the definition.

## 6.3 Configure UniFi

Back in the main menu choose **\[5\] Show UniFi configuration**.

For the simulated tunnel, the important values are:

``` text
VPN Type:                       IPsec
Remote IP / Hostname:           198.51.100.10
VPN Method:                     Route Based
Tunnel IP:                      Enabled
IPv4 Address:                   10.200.202.2
Netmask:                        30
Remote Subnets:                 None

Mode:                           Manual
Key Exchange Version:           IKEv2

IKE  AES-256 / SHA256 / DH14 / 28800
ESP  AES-256 / SHA256 / DH14 / 3600
PFS: Enabled

Local Authentication ID:        office-unifi
Remote Authentication ID:       198.51.100.10
```

Select **Show Pre-Shared Key** and copy the same PSK into UniFi.

The exact placement/naming of fields in the UniFi Network UI can change
between UniFi versions; use the values printed by the manager as the
authoritative tunnel settings.

## 6.4 Verify

Choose **\[10\] Tunnel diagnostics**.

A healthy tunnel should show:

``` text
[✓] strongSwan: active
[✓] VTI service: active
[✓] ipsec0: present
[✓] transfer-network route present
[✓] IKE: ESTABLISHED
[✓] CHILD_SA: INSTALLED
```

Then run the optional VTI ping.

------------------------------------------------------------------------

# 7. Complete walkthrough --- Debian ↔ Debian

## 7.1 Example topology

``` text
       Debian A                                      Debian B
    198.51.100.10                                 203.0.113.50
          │                                              │
          └──────────── IKEv2 / IPsec ───────────────────┘

       ipsec0 .1                                      ipsec0 .2
      10.200.210.1  ◄──── 10.200.210.0/30 ────►  10.200.210.2
```

Optional routed networks:

``` text
Behind Debian A: 10.10.0.0/24
Behind Debian B: 10.50.0.0/24
```

## 7.2 Create the tunnel on Debian A

Choose **\[2\] Add S2S tunnel**.

### Display name

``` text
Tunnel display name [home]: VPS-A - VPS-B
```

### Peer type

``` text
[1] UniFi Gateway
[2] Debian / strongSwan

Selection [1]: 2
```

### Remote Debian endpoint

``` text
[1] Static IPv4 address
[2] Hostname / Dynamic DNS

Selection [1]: 1

Remote Debian public IPv4: 203.0.113.50
```

### Local public IP

``` text
Debian public IP [198.51.100.10]:
```

### Transfer network

``` text
Tunnel network [10.200.210.0]: 10.200.210.0/30

Network:       10.200.210.0/30
Debian IP:     10.200.210.1
Peer IP:       10.200.210.2
Broadcast:     10.200.210.3
```

### Authentication ID

For Debian peers the manager derives the remote peer Authentication ID
from its public IPv4:

``` text
Authentication ID:           203.0.113.50
[✓] Debian peer Authentication ID set automatically
```

### Remote networks

If Debian A must reach `10.50.0.0/24` behind Debian B:

``` text
Remote network #1: 10.50.0.0/24
Remote network #2:
```

If there are no routed networks behind B, simply press Enter.

### PSK

Generate a secure random PSK. The same PSK will later be included in the
peer bundle.

Save and install the tunnel on Debian A.

At this point the local installation can be valid while the connection
is still disconnected because Debian B has not yet been configured.

## 7.3 Create the peer bundle

On Debian A choose **\[17\] Create Debian peer bundle**.

Example:

``` text
──────────────────────────────────────────────────────────────
  CREATE DEBIAN PEER BUNDLE
──────────────────────────────────────────────────────────────

  [1] VPS-A - VPS-B

Selection: 1

Peer display name [VPS-A - VPS-B - Peer]: VPS-B - VPS-A

[✓] Debian peer bundle created.
```

The bundle contains the PSK. Treat it like a secret.

## 7.4 Transfer directly with SCP

Choose **\[18\] Transfer Debian peer bundle via SCP**.

``` text
Remote SSH server (hostname or IPv4) [203.0.113.50]:
SSH user [root]:
SSH port [22]:
Remote import directory [/root/s2s-manager-import]:
```

Destination:

``` text
root@203.0.113.50:/root/s2s-manager-import/
```

The directory is created automatically when missing.

With password authentication you may be prompted twice: once while
preparing/checking the directory and once by SCP.

## 7.5 Import on Debian B

Run the manager on Debian B and choose **\[19\] Import Debian peer
bundle**.

``` text
Peer bundles found in /root/s2s-manager-import:

  [1] VPS-A-VPS-B-20260819-120000.s2s-peer

Selection: 1
```

The manager validates the local host before writing anything.

Expected preview:

``` text
──────────────────────────────────────────────────────────────
  PEER IMPORT PREVIEW
──────────────────────────────────────────────────────────────

Display name:                VPS-B - VPS-A
Local public IP:             203.0.113.50
Remote public IP:            198.51.100.10
Authentication ID:           198.51.100.10
Tunnel network:              10.200.210.0/30
Local VTI IP:                10.200.210.2
Remote VTI IP:               10.200.210.1
```

Confirm import and installation.

## 7.6 Remote networks in both directions

A peer bundle mirrors the tunnel itself. Routed networks are directional
from the point of view of each server.

If:

``` text
Debian A must reach 10.50.0.0/24 behind Debian B
Debian B must reach 10.10.0.0/24 behind Debian A
```

configure on A:

``` text
Remote network: 10.50.0.0/24
```

and on B:

``` text
Remote network: 10.10.0.0/24
```

Use **\[3\] Add remote network to tunnel** on the appropriate server and
re-apply when necessary.

## 7.7 Establish and test

If the connection has not already established, choose **\[9\] Reconnect
tunnel** on one side.

Then use **\[10\] Tunnel diagnostics**.

From Debian B, a successful transfer-network ping looks like:

``` text
Pinging remote Debian VTI address 10.200.210.1...

[✓] Ping to 10.200.210.1: SUCCESS
3 packets transmitted, 3 received, 0% packet loss
```

------------------------------------------------------------------------

# 8. Backup and restore example

Create a backup with **\[16\] → Create tunnel backup**.

The archive contains sensitive tunnel state and may contain the PSK.

To restore, use **\[16\] → Restore tunnel backup**.

A restore preview is shown before writing the definition.

If the tunnel already exists:

``` text
──────────────────────────────────────────────────────────────
  ✗ TUNNEL ALREADY EXISTS
──────────────────────────────────────────────────────────────
Internal name: office-unifi
Restore stops here without changing anything.
No automatic -2 suffix is added and the existing tunnel is not overwritten.
──────────────────────────────────────────────────────────────

[✗] Tunnel backup was NOT restored.
```

This is intentional.

------------------------------------------------------------------------

# 9. Troubleshooting

## Tunnel is DEFINED but not connected

A definition alone is not an installed tunnel. Use **\[7\] Install
tunnel on Debian**.

## VTI exists but IKE/CHILD SA is missing

Use **\[10\] Diagnostics → recent strongSwan logs**.

For Debian-to-Debian, try **\[9\] Reconnect tunnel** after both peers
are installed.

## Ping says Destination Host Unreachable

First check that IKE and CHILD_SA are established. A VTI interface can
exist even when IPsec itself is not connected.

## Tunnel shows PARTIAL / BROKEN

Diagnostics displays which manager-owned artifact is missing. Re-apply
can regenerate manager-owned configuration from the saved definition.

## DDNS hostname has multiple A records

The manager rejects it because one classic VTI needs one concrete remote
IPv4 endpoint.

## Dynamic UniFi endpoint conflicts with another tunnel

Dynamic/unknown mode uses VTI remote `0.0.0.0`. Only one wildcard VTI
can use the same Debian public endpoint. Use a static UniFi IPv4 or
single-address DDNS endpoint for additional tunnels.

## SCP transfer cannot log in

Verify SSH connectivity from the source server to the destination server
using the same host, user and port. The manager does not route the
transfer through your workstation.

------------------------------------------------------------------------

# 10. Operational recommendations

-   Keep every `/30` transfer network unique.
-   Keep Authentication IDs unique.
-   Back up important tunnel definitions before deleting them.
-   Protect `.s2s-peer` and tunnel backup files because they can contain
    PSKs.
-   Use diagnostics before changing a working configuration.
-   Prefer **Re-apply** for configuration regeneration and **Reconnect**
    for a fresh IKE/CHILD SA.
-   Do not treat an existing VTI interface by itself as proof that IPsec
    is connected.
