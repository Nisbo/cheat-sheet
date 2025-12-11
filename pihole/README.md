# Failover for Pi-hole with Keepalived

## Installation

Install `keepalived` on both servers:

```bash
sudo apt update
sudo apt install keepalived -y
```

---

## Configuration

### Create and adjust the configuration file

> [!TIP]
> nano commands:
> - `CTRL + V` → paste the content
> - `CTRL + O` → save the file (then press `ENTER` to confirm)
> - `CTRL + X` → exit nano


Download the appropriate configuration or paste the content:
- Replace the virtual IP (`192.168.178.9`) in both files with an IP from your subnet that is **not** in your DHCP range!  
- Replace `eth0` with the interface your Pi-hole uses (e.g. `eth1` or `ens18`).

> [!IMPORTANT] 
> The virtual IP must not be assigned by your DHCP server to avoid IP conflicts.


### For/On the **MASTER**:

```bash
sudo mkdir -p /etc/keepalived
cd /etc/keepalived
sudo nano /etc/keepalived/keepalived.conf

# or use wget instead of using nano and pasting the code
wget https://raw.githubusercontent.com/Nisbo/cheat-sheet/refs/heads/main/pihole/MASTER/etc/keepalived/keepalived.conf
```
https://raw.githubusercontent.com/Nisbo/cheat-sheet/refs/heads/main/pihole/MASTER/etc/keepalived/keepalived.conf

## For/On the **BACKUP**:

```bash
sudo mkdir -p /etc/keepalived
cd /etc/keepalived
sudo nano /etc/keepalived/keepalived.conf

# or use wget instead of using nano and pasting the code
wget https://raw.githubusercontent.com/Nisbo/cheat-sheet/refs/heads/main/pihole/BACKUP/etc/keepalived/keepalived.conf
```
wget https://raw.githubusercontent.com/Nisbo/cheat-sheet/refs/heads/main/pihole/BACKUP/etc/keepalived/keepalived.conf

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

On the Master Pi-hole, run: (replace `192.168.178.9` with your `VIP`)

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

- Check on the Backup Pi-hole if VIP is taken over: (replace `192.168.178.9` with your `VIP`)

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

Set your router’s DNS server to the virtual IP: `192.168.178.9` (replace `192.168.178.9` with your `VIP`).

---

## Clear DNS cache on your devices

After changes, you may need to clear the DNS cache or reconnect your network (toggle Wi-Fi, restart network, reboot device).

---

---

---

# Monitoring / Changing via API

Install Flask
```
sudo apt update
sudo apt install python3 python3-flask -y
```

### Create the API script

```
sudo nano /usr/local/bin/keepalived_api.py
```

and use this content

```
wget https://raw.githubusercontent.com/Nisbo/cheat-sheet/refs/heads/main/pihole/keepalived_api.py
```

https://raw.githubusercontent.com/Nisbo/cheat-sheet/refs/heads/main/pihole/keepalived_api.py


### config file

```
sudo nano /usr/local/bin/keepalived_api.conf
```

paste this content and addapt to your needs

- `port`: Port for Flask-Server
- `allowed_ips`: allowed Client-IP-Addresses, comma-separated


```
[keepalived_api]
port = 5000
allowed_ips = 192.168.178.87,192.168.178.72

[mqtt]
enabled = true
name = MASTER Pi-Hole
ip = 192.168.178.27
port = 1883
username =
password =
update_interval = 30
```

### MQTT Paho client installation (for Home Assistant MQTT discovery)

```
sudo apt update
sudo apt install -y mosquitto mosquitto-clients python3-paho-mqtt
sudo systemctl enable mosquitto
sudo systemctl start mosquitto
```


### Systemd service

```
sudo nano /etc/systemd/system/keepalived_api.service
```

```
[Unit]
Description=Keepalived Control API
After=network.target

[Service]
User=root
ExecStart=/usr/bin/python3 /usr/local/bin/keepalived_api.py
Restart=always

[Install]
WantedBy=multi-user.target
```

### Start and check

```
sudo systemctl daemon-reload
sudo systemctl enable keepalived_api.service
sudo systemctl start keepalived_api.service
```

```
sudo systemctl status keepalived_api.service
```

### API

Status:

```
curl http://<your-ip>:5000/keepalived/status
```

Start:

```
curl http://<your-pi-ip>:5000/keepalived/start
```

Restart:

```
curl http://<your-pi-ip>:5000/keepalived/restart
```

Stop:

```
curl http://<your-pi-ip>:5000/keepalived/stop
```

