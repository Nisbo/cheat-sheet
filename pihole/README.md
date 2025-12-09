# Failover for Pi-hole with Keepalived

## Installation

Install `keepalived` on both servers:

```bash
sudo apt update
sudo apt install keepalived -y
```

---

## Configuration

### Create or edit the configuration file

```bash
sudo nano /etc/keepalived/keepalived.conf
```

Download the appropriate configuration or paste the content:

- For the **MASTER**:

```bash
wget https://raw.githubusercontent.com/Nisbo/cheat-sheet/refs/heads/main/pihole/MASTER/etc/keepalived/keepalived.conf
```
https://raw.githubusercontent.com/Nisbo/cheat-sheet/refs/heads/main/pihole/MASTER/etc/keepalived/keepalived.conf

- For the **BACKUP**:

```bash
wget https://raw.githubusercontent.com/Nisbo/cheat-sheet/refs/heads/main/pihole/BACKUP/etc/keepalived/keepalived.conf
```
wget https://raw.githubusercontent.com/Nisbo/cheat-sheet/refs/heads/main/pihole/BACKUP/etc/keepalived/keepalived.conf

---

### Adjust the configuration

- Replace the virtual IP (`192.168.178.9`) in both files with an IP from your subnet that is **not** in your DHCP range!  
- Replace `eth0` with the interface your Pi-hole uses (e.g. `eth1` or `ens18`).

> **Important:**  
> The virtual IP must not be assigned by your DHCP server to avoid IP conflicts.

---

## Start the services

On both servers:

```bash
sudo systemctl enable keepalived
sudo systemctl restart keepalived
```

---

## Check status

```bash
sudo systemctl status keepalived
```

You should see output similar to this:

```
● keepalived.service - Keepalive Daemon (LVS and VRRP)
     Loaded: loaded (/lib/systemd/system/keepalived.service; enabled; preset: enabled)
     Active: active (running) since Tue 2025-12-09 05:27:35 CET; 1h 53min ago
       Docs: man:keepalived(8)
             man:keepalived.conf(5)
             man:genhash(1)
             https://keepalived.org
   Main PID: 1208180 (keepalived)
      Tasks: 2 (limit: 760)
        CPU: 1.383s
     CGroup: /system.slice/keepalived.service
             ├─1208180 /usr/sbin/keepalived --dont-fork
             └─1208181 /usr/sbin/keepalived --dont-fork

Dec 09 05:27:35 pihole Keepalived[1208180]: Starting VRRP child process, pid=1208181
Dec 09 05:27:35 pihole Keepalived_vrrp[1208181]: (VI_1) Entering BACKUP STATE (init)
Dec 09 05:27:39 pihole Keepalived_vrrp[1208181]: (VI_1) Entering MASTER STATE
```

---

## Check if VIP is assigned to the Master Pi-hole

On the Master Pi-hole, run:

```bash
ip addr show eth0 | grep 192.168.178.9
```

If the Pi-hole is Master, you should see something like:

```
inet 192.168.178.9/32 scope global eth0
```

---

## Test failover

- Stop Keepalived on the Master:

```bash
sudo systemctl stop keepalived
```

- Check on the Backup Pi-hole if VIP is taken over:

```bash
ip addr show eth0 | grep 192.168.178.9
```

If the VIP is now on the Backup, it has entered MASTER state.

- Start Keepalived on the Master again:

```bash
sudo systemctl start keepalived
```

---

## Router configuration

Set your router’s DNS server to the virtual IP (`192.168.178.9`), not the static IPs of the individual Pi-holes.

---

## Clear DNS cache on your devices

After changes, you may need to clear the DNS cache or reconnect your network (toggle Wi-Fi, restart network, reboot device).

---





