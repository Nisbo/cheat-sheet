# Failover for PI-Hole

## Installation
Install `keepalived` on both server
```
sudo apt update
sudo apt install keepalived -y
```

## Configuration

### create / edit the configuration

```
sudo nano /etc/keepalived/keepalived.conf
```
download or paste the content

for the `MASTER`from here:

`wget https://raw.githubusercontent.com/Nisbo/cheat-sheet/refs/heads/main/pihole/MASTER/etc/keepalived/keepalived.conf`

https://raw.githubusercontent.com/Nisbo/cheat-sheet/refs/heads/main/pihole/MASTER/etc/keepalived/keepalived.conf

for the `BACKUP` from here:

`wget https://raw.githubusercontent.com/Nisbo/cheat-sheet/refs/heads/main/pihole/BACKUP/etc/keepalived/keepalived.conf`

https://raw.githubusercontent.com/Nisbo/cheat-sheet/refs/heads/main/pihole/BACKUP/etc/keepalived/keepalived.conf

On both server
- replace the VIP (Virtual IP) `192.168.178.9` with an IP from your subnet.
- replace the netwotk interface `eth0` with your interface.

> [!IMPORTANT]
> make sure that this IP is **not** in your DHCP range to avoid that your DHCP server assign this IP to an other device.

---
### start the services on both server

```
sudo systemctl enable keepalived
sudo systemctl restart keepalived
```

---
### check if the service is running on both server

```sudo systemctl status keepalived```

you should see something like this

```
pi@pihole:~ $ sudo systemctl status keepalived
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
Dec 09 05:27:35 pihole systemd[1]: keepalived.service: Got notification message from PID 1208181, but reception only permitted for main PID 1208180
Dec 09 05:27:35 pihole Keepalived[1208180]: Startup complete
Dec 09 05:27:35 pihole Keepalived_vrrp[1208181]: (VI_1) Entering BACKUP STATE (init)
Dec 09 05:27:35 pihole systemd[1]: Started keepalived.service - Keepalive Daemon (LVS and VRRP).
Dec 09 05:27:36 pihole Keepalived_vrrp[1208181]: (VI_1) received lower priority (100) advert from 192.168.178.13 - discarding
Dec 09 05:27:37 pihole Keepalived_vrrp[1208181]: (VI_1) received lower priority (100) advert from 192.168.178.13 - discarding
Dec 09 05:27:38 pihole Keepalived_vrrp[1208181]: (VI_1) received lower priority (100) advert from 192.168.178.13 - discarding
Dec 09 05:27:39 pihole Keepalived_vrrp[1208181]: (VI_1) received lower priority (100) advert from 192.168.178.13 - discarding
Dec 09 05:27:39 pihole Keepalived_vrrp[1208181]: (VI_1) Entering MASTER STATE
pi@pihole:~ $
```




---
### Check if the VIP is assigned to the MASTER Pi-Hole

On your MASTER Pi-Hole run this command:

```ip addr show eth0 | grep 192.168.178.9```

If your MASTER Pi-Hole is currently the MASTER, you should see something like this:

```inet 192.168.178.9/32 scope global eth0```

If there is no output, keepalived is not running or your MASTER Pi-Hole is in BACKUP mode.

---
### Check if the VIP changes to the BACKUP Pi-Hole

On your MASTER Pi-Hole run this command:

```sudo systemctl stop keepalived```

to stop keepalived and simulate an outage

On your BACKUP Pi-Hole run this command:

```ip addr show eth0 | grep 192.168.178.9```

If your BACKUP Pi-Hole is now the MASTER, you should see something like this:

```inet 192.168.178.9/32 scope global eth0```

If there is no output, keepalived is not running or your BACKUP Pi-Hole is still in BACKUP mode.

On your MASTER Pi-Hole run this command:

```sudo systemctl start keepalived```

to make the MASTER Pi-Hole again to the MASTER

---
### Configure your router
Configure your router to use the VIP `192.168.178.9` instead of the Pi-Hole IP

---
### Clear your DNS cache from your device
Disconnect from the network (turn off/on WLAN, pull/insert the network cable, reboot) or wait some time till your lease is expired.





