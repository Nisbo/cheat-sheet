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

https://raw.githubusercontent.com/Nisbo/cheat-sheet/refs/heads/main/pihole/MASTER/etc/keepalived/keepalived.conf
```bash
sudo mkdir -p /etc/keepalived
cd /etc/keepalived
sudo nano /etc/keepalived/keepalived.conf

# or use wget instead of using nano and pasting the code
wget https://raw.githubusercontent.com/Nisbo/cheat-sheet/refs/heads/main/pihole/MASTER/etc/keepalived/keepalived.conf
```


## For/On the **BACKUP**:

wget https://raw.githubusercontent.com/Nisbo/cheat-sheet/refs/heads/main/pihole/BACKUP/etc/keepalived/keepalived.conf
```bash
sudo mkdir -p /etc/keepalived
cd /etc/keepalived
sudo nano /etc/keepalived/keepalived.conf

# or use wget instead of using nano and pasting the code
wget https://raw.githubusercontent.com/Nisbo/cheat-sheet/refs/heads/main/pihole/BACKUP/etc/keepalived/keepalived.conf
```


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

On the `Master` Pi-hole, run: (replace `192.168.178.9` with your `VIP`)

```bash
ip addr show eth0 | grep 192.168.178.9
```

If the Pi-hole is Master, you should see something like:

```
inet 192.168.178.9/32 scope global eth0
```

---

## Test failover

- Stop Keepalived on the `Master`:

```bash
sudo systemctl stop keepalived
```

- Check on the `Backup` Pi-hole if VIP is taken over: (replace `192.168.178.9` with your `VIP`)

```bash
ip addr show eth0 | grep 192.168.178.9
```

If the VIP is now on the Backup, it has entered MASTER state.

- Start Keepalived on the `Master` again:

```bash
sudo systemctl start keepalived
```

---

## Router configuration

Set your router’s DNS server to the virtual IP: `192.168.178.9` (replace `192.168.178.9` with your `VIP`).

---



> [!NOTE]
> ### Clear DNS cache on your devices
> After changes, you may need to clear the DNS cache or reconnect your network (toggle Wi-Fi, restart network, reboot device).

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

https://raw.githubusercontent.com/Nisbo/cheat-sheet/refs/heads/main/pihole/keepalived_api.py


or use wget to download the file
```
cd /usr/local/bin
wget https://raw.githubusercontent.com/Nisbo/cheat-sheet/refs/heads/main/pihole/keepalived_api.py
```


### config file

```
sudo nano /usr/local/bin/keepalived_api.conf
```

paste this content and addapt to your needs


```
[keepalived_api]
# Port for the Flask server to listen on
port = 5000

# Comma-separated list of allowed client IP addresses
allowed_ips = 192.168.178.87,192.168.178.72

[mqtt]
# Enable MQTT support (true/false)
enabled = true

# MQTT device name used in topics and Home Assistant
name = MASTER Pi-Hole

# MQTT broker IP address
ip = 192.168.178.27

# MQTT broker port (default 1883)
port = 1883

# MQTT username (optional)
username =

# MQTT password (optional)
password =

# Interval (in seconds) for periodic MQTT status updates
update_interval = 30

```


### MQTT Paho client installation (for Home Assistant MQTT discovery)

> [!CAUTION]
> Make sure that nobody has access to your MQTT server because with MQTT access you can stop the keepalive service and if you stop it on both servers DNS is down because nobody is listening to your VIP

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

### API Commands

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

## Usage inside Home Assistant

MQTT auto discovery will create automatically a new sensor for both Pi-Holes

<img width="1000" height="880" alt="grafik" src="https://github.com/user-attachments/assets/4fe832dd-6f56-4ad7-b3d0-eed00663d9f9" />

So you can Start, Stop and Restart from Home Assistant. Additionally the FTL status wil lbe monitored (appart from the other stats)
In the past (some FTL versions ago) there was an issue with FTL and your Pi Hole was not working anymore. In this case keepalived will not work because both Pi Holes were "available". This script checks the FTL status and is also checking DNS response time and DNS status.

In my case I am using this 2 automations to detect if FTL is working and if not working I turn off keepalived for the master server. And turn is on abain if FTL is available.

```
alias: MASTER Pi-Hole - DNS OK
description: ""
triggers:
  - type: connected
    device_id: 2b271f1c2b60a905147d1cf896af682d
    entity_id: 97857fa13261e92d25f66ec20ed62d83
    domain: binary_sensor
    trigger: device
conditions: []
actions:
  - device_id: 2b271f1c2b60a905147d1cf896af682d
    domain: button
    entity_id: 2844c459a899b0bf539eddbb0519bfdb
    type: press
mode: single
```

```
alias: MASTER Pi-Hole - DNS not OK
description: ""
triggers:
  - type: not_connected
    device_id: 2b271f1c2b60a905147d1cf896af682d
    entity_id: 97857fa13261e92d25f66ec20ed62d83
    domain: binary_sensor
    trigger: device
conditions: []
actions:
  - device_id: 2b271f1c2b60a905147d1cf896af682d
    domain: button
    entity_id: 45eee4ffce5a7400023ecfa4693ef49f
    type: press
mode: single
```

Unfortunately Home Assistant is converting the human readable names to the cryptic IDs.  
So maybe this screenshot is more helpfull.

<img width="606" height="624" alt="grafik" src="https://github.com/user-attachments/assets/c5751c59-827c-4253-b906-5f9fec355eb9" />

If you want to play around with this you can stopp FTL to simulate an outage
```
sudo systemctl stop pihole-FTL.service
```

To start it again

```
sudo systemctl start pihole-FTL.service
```

Normal Conditions

<img width="1047" height="866" alt="grafik" src="https://github.com/user-attachments/assets/4e44f9c2-c92c-4b5a-a91d-674ffa3a80ee" />


BackUp took over

<img width="1048" height="859" alt="grafik" src="https://github.com/user-attachments/assets/ef0bd92c-4290-4920-9ae8-10a4bc359cfc" />

## If you have `card_mod` installed you can do something like this

### Normal Conditions

<img width="1061" height="940" alt="grafik" src="https://github.com/user-attachments/assets/5c92e790-0794-45d4-8ac3-2a13245336e0" />

### BackUp took over (if you disable keepalive)

<img width="1056" height="933" alt="grafik" src="https://github.com/user-attachments/assets/e2b6e19a-a6a8-4d10-9391-121c0885ff0f" />

### BackUp took over (if FTL is not alive)

<img width="1057" height="938" alt="grafik" src="https://github.com/user-attachments/assets/dd34a30a-de8a-4c73-bd0e-caae38d12ea4" />

My Code for the MASTER 

```
type: vertical-stack
cards:
  - type: entity
    entity: sensor.master_pi_hole_master_pi_hole_keepalived_status
    name: Keepalived Status
    card_mod:
      style: |
        :host {
          --state-color:
            {% if states('sensor.master_pi_hole_master_pi_hole_keepalived_status') == 'active' %}
              green
            {% else %}
              red
            {% endif %};
        }
        .value {
          color: var(--state-color);
          font-weight: bold;
        }
  - type: entity
    entity: sensor.master_pi_hole_master_pi_hole_keepalived_keepalived_mode
    name: Keepalived Mode
    card_mod:
      style: |
        :host {
          --state-color:
            {% if states('sensor.master_pi_hole_master_pi_hole_keepalived_keepalived_mode') == 'MASTER' %}
              green
            {% else %}
              red
            {% endif %};
        }
        .value {
          color: var(--state-color);
          font-weight: bold;
        }
  - type: entity
    entity: sensor.master_pi_hole_keepalived_configured_mode
    name: Keepalived Mode (configured)
  - type: entity
    entity: sensor.master_pi_hole_ftl_service_status
    name: FTL Status
    card_mod:
      style: |
        :host {
          --state-color:
            {% if states('sensor.master_pi_hole_ftl_service_status') == 'active' %}
              green
            {% else %}
              red
            {% endif %};
        }
        .value {
          color: var(--state-color);
          font-weight: bold;
        }
  - type: entity
    entity: binary_sensor.master_pi_hole_dns_query_ok
    name: DNS Queries OK
    card_mod:
      style: |
        :host {
          --state-color:
            {% if states('binary_sensor.master_pi_hole_dns_query_ok') == 'on' %}
              green
            {% else %}
              red
            {% endif %};
        }
        .value {
          color: var(--state-color);
          font-weight: bold;
        }
  - type: entity
    entity: sensor.master_pi_hole_dns_response_time_ms
    name: DNS Response Time (-1 = no response)
  - type: entity
    entity: sensor.master_pi_hole_master_pi_hole_keepalived_vip_assigned
    name: VIP assigned to MASTER
    card_mod:
      style: |
        :host {
          --state-color:
            {% if states('sensor.master_pi_hole_master_pi_hole_keepalived_vip_assigned') == 'True' %}
              green
            {% else %}
              red
            {% endif %};
        }
        .value {
          color: var(--state-color);
          font-weight: bold;
        }
  - type: entity
    entity: sensor.master_pi_hole_master_pi_hole_keepalived_configured_vip
    name: Configured VIP
  - type: horizontal-stack
    cards:
      - type: tile
        entity: button.master_pi_hole_master_pi_hole_keepalived_start
        name: Start
        icon: mdi:play
        color: green
        hide_state: true
        vertical: false
        features_position: bottom
      - type: tile
        entity: button.master_pi_hole_master_pi_hole_keepalived_restart
        name: Restart
        icon: mdi:refresh
        color: accent
        hide_state: true
        vertical: false
        features_position: bottom
      - type: tile
        entity: button.master_pi_hole_master_pi_hole_keepalived_stop
        name: Stop
        icon: mdi:stop
        color: red
        hide_state: true
        vertical: false
        features_position: bottom

```


May Code for the BACKUP

```
type: vertical-stack
cards:
  - type: entity
    entity: sensor.backup_pi_hole_backup_pi_hole_keepalived_status
    name: Keepalived Status
    card_mod:
      style: |
        :host {
          --state-color:
            {% if states('sensor.backup_pi_hole_backup_pi_hole_keepalived_status') == 'active' %}
              green
            {% else %}
              red
            {% endif %};
        }
        .value {
          color: var(--state-color);
          font-weight: bold;
        }
  - type: entity
    entity: sensor.backup_pi_hole_keepalived_mode
    name: Keepalived Mode
    card_mod:
      style: |
        :host {
          --state-color:
            {% if states('sensor.backup_pi_hole_keepalived_mode') == 'BACKUP' %}
              green
            {% else %}
              orange
            {% endif %};
        }
        .value {
          color: var(--state-color);
          font-weight: bold;
        }
  - type: entity
    entity: sensor.backup_pi_hole_keepalived_configured_mode
    name: Keepalived Mode (configured)
  - type: entity
    entity: sensor.backup_pi_hole_ftl_service_status
    name: FTL Status
    card_mod:
      style: |
        :host {
          --state-color:
            {% if states('sensor.backup_pi_hole_ftl_service_status') == 'active' %}
              green
            {% else %}
              red
            {% endif %};
        }
        .value {
          color: var(--state-color);
          font-weight: bold;
        }
  - type: entity
    entity: binary_sensor.backup_pi_hole_dns_query_ok
    name: DNS Queries OK
    card_mod:
      style: |
        :host {
          --state-color:
            {% if states('binary_sensor.backup_pi_hole_dns_query_ok') == 'on' %}
              green
            {% else %}
              red
            {% endif %};
        }
        .value {
          color: var(--state-color);
          font-weight: bold;
        }
  - type: entity
    entity: sensor.backup_pi_hole_dns_response_time_ms
    name: DNS Response Time (-1 = no response)
  - type: entity
    entity: sensor.backup_pi_hole_vip_assigned
    name: VIP assigned to BACKUP
    card_mod:
      style: |
        :host {
          --state-color:
            {% if states('sensor.backup_pi_hole_vip_assigned') == 'False' %}
              green
            {% else %}
              orange
            {% endif %};
        }
        .value {
          color: var(--state-color);
          font-weight: bold;
        }
  - type: entity
    entity: sensor.backup_pi_hole_configured_vip
    name: Configured VIP
  - type: horizontal-stack
    cards:
      - type: tile
        entity: button.backup_pi_hole_backup_pi_hole_keepalived_start
        name: Start
        icon: mdi:play
        color: green
        hide_state: true
        vertical: false
        features_position: bottom
      - type: tile
        entity: button.backup_pi_hole_backup_pi_hole_keepalived_restart
        name: Restart
        icon: mdi:refresh
        color: accent
        hide_state: true
        vertical: false
        features_position: bottom
      - type: tile
        entity: button.backup_pi_hole_backup_pi_hole_keepalived_stop
        name: Stop
        icon: mdi:stop
        color: red
        hide_state: true
        vertical: false
        features_position: bottom

```



