# IPsec S2S Manager

Interactive Bash manager for **route-based IKEv2/IPsec Site-to-Site
tunnels on Debian 13** using **strongSwan/swanctl** and Linux **VTI
interfaces**.

It is designed for two common scenarios:

-   **UniFi Gateway ↔ Debian**
-   **Debian / strongSwan ↔ Debian / strongSwan**

The manager guides you through tunnel creation, validates conflicts,
creates the strongSwan/VTI/systemd configuration, stores tunnel
definitions and PSKs, and provides diagnostics, backup/restore and
migration/take-over tools.

> The terminal examples in this README and the manual use fictional
> documentation addresses and networks. The real program uses colors;
> the simulated terminal screenshots below are intentionally plain text
> so they render reliably on GitHub.

## What it does

The manager maintains the Debian side of route-based IPsec tunnels. Each
managed tunnel receives its own VTI interface and a private `/30`
transfer network.

For example:

``` text
                    IKEv2 / IPsec
        ┌──────────────────────────────────┐
        │                                  │
  UniFi Gateway                       Debian Server
  203.0.113.20                       198.51.100.10
        │                                  │
  VTI 10.200.202.2/30  ◄────────►  VTI 10.200.202.1/30
        │                                  │
  192.168.10.0/24                    Debian services
  192.168.20.0/24
```

For Debian-to-Debian connections, the manager can create a **mirrored
peer bundle** containing the matching endpoint/VTI settings and PSK,
transfer it directly to the second server over SCP, and import it there.

## Features

-   Interactive terminal UI with overview of configured tunnels
-   Route-based **IKEv2/IPsec**
-   **strongSwan / swanctl**
-   Linux **VTI** interfaces
-   Separate `/30` transfer network per tunnel
-   Routing via **table 220**
-   UniFi Gateway peers
-   Debian / strongSwan peers
-   Static IPv4 peer endpoints
-   Hostname / Dynamic DNS endpoints
-   Dynamic/unknown UniFi endpoint mode
-   Automatic VTI interface and mark/key allocation
-   Network overlap and route-conflict validation
-   VTI endpoint conflict detection
-   Authentication-ID conflict detection
-   Remote-network management
-   Generated UniFi configuration reference
-   Install, uninstall and re-apply without deleting the saved
    definition
-   Controlled tunnel reconnect
-   Tunnel diagnostics and VTI ping test
-   IKE/CHILD SA status and traffic counters
-   strongSwan log display
-   Tunnel backup and restore
-   Debian peer bundles including the shared PSK
-   Direct server-to-server peer-bundle transfer via **SCP**
-   Discovery/import of existing strongSwan/VTI tunnels
-   Controlled take-over of imported tunnels with backups
-   Optional UFW integration for UDP 500/4500
-   Sensitive PSKs stored separately with restrictive permissions
-   External backup and peer-bundle files are parsed as data rather than
    executed as shell code

## Requirements

-   Debian **13**
-   root privileges
-   Internet/package access for initial prerequisite installation
-   A public IPv4 address or suitable routed/NAT environment
-   UDP **500** and **4500** allowed between the IPsec peers
-   For Debian-to-Debian bundle transfer: SSH access between the servers

The manager performs a pre-flight check and can install/repair its
required Debian packages.

## Installation

Save the stable script as `s2s-manager.sh`, then:

``` bash
chmod +x s2s-manager.sh
sudo ./s2s-manager.sh
```

When already logged in as root:

``` bash
./s2s-manager.sh
```

Manager state is stored in:

``` text
/root/s2s-manager/
```

Managed system files use names such as:

``` text
/etc/swanctl/conf.d/s2s-manager-<tunnel>.conf
/usr/local/sbin/s2s-manager-vti-<tunnel>.sh
/etc/systemd/system/s2s-manager-vti-<tunnel>.service
```

## Main screen

A typical main screen looks like this:

``` text
╔══════════════════════════════════════════════════════════════╗
║                      IPsec S2S Manager                       ║
║                       Version 1.0.0                          ║
╚══════════════════════════════════════════════════════════════╝

State directory: /root/s2s-manager


──────────────────────────────────────────────────────────────
  CONFIGURED TUNNELS
──────────────────────────────────────────────────────────────

#     Name                    Interface   Tunnel Network        Management   Connection
────  ──────────────────────  ──────────  ────────────────────  ──────────   ──────────
1     Office-UniFi            ipsec0      10.200.202.0/30       MANAGED      CONNECTED
2     VPS-East - VPS-West     ipsec1      10.200.210.0/30       MANAGED      CONNECTED

──────────────────────────────────────────────────────────────────────────────────────

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

  [E] Exit
```

## Quick start: UniFi Gateway ↔ Debian

Assume this fictional example:

  Item                      Example
  ------------------------- -------------------
  Debian public IPv4        `198.51.100.10`
  UniFi public IPv4         `203.0.113.20`
  Tunnel transfer network   `10.200.202.0/30`
  Debian VTI                `10.200.202.1`
  UniFi VTI                 `10.200.202.2`
  UniFi LAN                 `192.168.10.0/24`
  Authentication ID         `office-unifi`

1.  Select **\[2\] Add S2S tunnel**.
2.  Enter a display name such as `Office-UniFi`.
3.  Choose **UniFi Gateway**.
4.  Choose Dynamic, Static IPv4 or Hostname/DDNS for the UniFi endpoint.
5.  Confirm the Debian public IPv4.
6.  Choose a free `/30` transfer network.
7.  Set a unique UniFi Authentication ID.
8.  Enter the UniFi-side LAN/VLAN networks Debian should reach.
9.  Generate or enter a PSK.
10. Save and install the Debian tunnel.
11. Use **\[5\] Show UniFi configuration** and enter those values in the
    UniFi Site-to-Site VPN configuration.
12. Use **\[10\] Tunnel diagnostics** to verify IKE, CHILD_SA and VTI
    connectivity.

The generated UniFi reference includes the route-based tunnel IP, IKEv2
proposals, Authentication IDs and PSK.

## Quick start: Debian ↔ Debian

Assume:

  Item               Server A          Server B
  ------------------ ----------------- -------------------
  Public IPv4        `198.51.100.10`   `203.0.113.50`
  VTI IP             `10.200.210.1`    `10.200.210.2`
  Transfer network   \-                `10.200.210.0/30`

On **Server A**:

1.  Select **\[2\] Add S2S tunnel**.
2.  Choose **Debian / strongSwan**.
3.  Enter Server B's public IPv4 or hostname.
4.  Confirm Server A's public IPv4.
5.  Select a free `/30`.
6.  Add any networks behind Server B that Server A must reach.
7.  Generate a PSK and save/install the tunnel.
8.  Select **\[17\] Create Debian peer bundle**.
9.  Select **\[18\] Transfer Debian peer bundle via SCP** to send it
    directly to Server B.

On **Server B**:

10. Start IPsec S2S Manager.
11. Select **\[19\] Import Debian peer bundle**.
12. Review the local conflict validation and preview.
13. Import and install the mirrored tunnel.
14. If necessary, use **\[9\] Reconnect tunnel**.
15. Verify with **\[10\] Tunnel diagnostics** and ping the remote VTI
    address.

No laptop or intermediate copy is required when SCP transfer is used.

## Safety model

The manager deliberately separates a **saved tunnel definition** from an
**installed tunnel**.

That means you can:

-   define a tunnel without activating it;
-   uninstall system configuration while keeping its definition and PSK;
-   re-install it later;
-   back up a definition before deleting it;
-   preview and validate imports before manager files or PSKs are
    written.

A **Delete tunnel completely** operation is different from **Uninstall
tunnel from Debian**. Delete removes the manager definition and stored
PSK; uninstall keeps them.

## Documentation

For a detailed explanation of every menu item and complete walkthroughs,
see:

**[MANUAL.md](MANUAL.md)**

## Important notes

-   Every tunnel needs its own non-overlapping `/30` transfer network.
-   Do not reuse remote LAN/VLAN networks where routing would become
    ambiguous.
-   A classic VTI has one concrete remote endpoint. A DDNS hostname
    resolving to multiple IPv4 addresses is therefore rejected.
-   Dynamic/unknown UniFi mode uses a wildcard VTI endpoint; only one
    wildcard VTI can use the same Debian public IPv4.
-   Opening UDP 500/4500 in UFW does not automatically configure a
    provider/cloud firewall.
-   Peer bundles and backups can contain PSKs and must be treated as
    sensitive files.

## License

Add the license you want to use for the project here before publishing
the repository.
