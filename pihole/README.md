# Failover for PI-Hole

## Installation
Install `keepalived` on both server
```
sudo apt update
sudo apt install keepalived -y
```

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

replace the VIP (Virtual IP) `192.168.178.9` with an IP from your subnet.

> [!IMPORTANT]
> make sure that this IP is **not** in your DHCP range to avoid that your DHCP server assign this IP to an other device.

### start the services on both server

```
sudo systemctl enable keepalived
sudo systemctl restart keepalived
```

### Check if the VIP is assigned to the MASTER Pi-Hole

```ip addr show eth0 | grep 192.168.178.9```

If your MASTER Pi-Hole is currently the MASTER, you should see something like this:

```inet 192.168.178.9/32 scope global eth0```

If there is no output, keepalived is not running or your MASTR Pi-Hle is in BACKUP moode.



