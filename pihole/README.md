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
#!/usr/bin/env python3

from flask import Flask, request, jsonify, abort
import subprocess
import configparser
import threading
import time
import paho.mqtt.client as mqtt
import json
import re

app = Flask(__name__)

# Config laden
config = configparser.ConfigParser()
config.read('/usr/local/bin/keepalived_api.conf')

# keepalived_api Section
PORT = int(config['keepalived_api'].get('port', '5000'))
INTERFACE = config['keepalived_api'].get('interface', 'eth0')
VIRTUAL_IP = config['keepalived_api'].get('vip', '192.168.178.9')

allowed_ips_str = config['keepalived_api'].get('allowed_ips', '')
ALLOWED_IPS = [ip.strip() for ip in allowed_ips_str.split(',') if ip.strip()]

# MQTT Section
mqtt_enabled = config['mqtt'].getboolean('enabled', fallback=False)
mqtt_name = config['mqtt'].get('name', 'Pi-Hole')
mqtt_ip = config['mqtt'].get('ip', '127.0.0.1')
mqtt_port = int(config['mqtt'].get('port', 1883))
mqtt_username = config['mqtt'].get('username', '')
mqtt_password = config['mqtt'].get('password', '')
update_interval = int(config['mqtt'].get('update_interval', 30))

mqtt_client = None

def is_allowed_ip():
    return request.remote_addr in ALLOWED_IPS

@app.before_request
def limit_remote_addr():
    if not is_allowed_ip():
        abort(403)

def get_keepalived_status():
    try:
        result = subprocess.run(
            ['systemctl', 'is-active', 'keepalived'],
            capture_output=True, text=True, check=True
        )
        status = result.stdout.strip()
        stdout = result.stdout.strip()
        stderr = result.stderr.strip()
    except subprocess.CalledProcessError as e:
        if e.returncode == 3:
            status = "inactive"
            stdout = ""
            stderr = ""
        else:
            raise e
    return status, stdout, stderr

def get_vip_assigned():
    try:
        result = subprocess.run(
            ['ip', 'addr', 'show', INTERFACE],
            capture_output=True, text=True, check=True
        )
        vip_assigned = VIRTUAL_IP in result.stdout
        return vip_assigned
    except subprocess.CalledProcessError as e:
        raise e

def determine_mode(vip_assigned):
    return "MASTER" if vip_assigned else "BACKUP"

def compose_response(action, keepalived_status, vip_assigned, stdout, stderr):
    keepalived_mode = determine_mode(vip_assigned)
    return jsonify({
        "action": action,
        "keepalived_status": keepalived_status,
        "keepalived_mode": keepalived_mode,
        "configured_vip": VIRTUAL_IP,
        "vip_assigned": vip_assigned,
        "stdout": stdout,
        "stderr": stderr
    })

@app.route('/keepalived/status', methods=['GET'])
def status():
    try:
        keepalived_status, stdout, stderr = get_keepalived_status()
        vip_assigned = get_vip_assigned()
    except subprocess.CalledProcessError as e:
        return jsonify({"error": str(e)}), 500

    return compose_response("status", keepalived_status, vip_assigned, stdout, stderr)

@app.route('/keepalived/<action>', methods=['GET', 'POST'])
def control(action):
    if action not in ['start', 'stop', 'restart']:
        return jsonify({"error": "Invalid action"}), 400
    try:
        result = subprocess.run(
            ['systemctl', action, 'keepalived'],
            capture_output=True, text=True, check=True
        )
        keepalived_status, stdout_status, stderr_status = get_keepalived_status()
        vip_assigned = get_vip_assigned()
        return compose_response(action, keepalived_status, vip_assigned, result.stdout.strip(), result.stderr.strip())
    except subprocess.CalledProcessError as e:
        return jsonify({"error": str(e)}), 500


# MQTT Integration
def mqtt_connect():
    global mqtt_client
    mqtt_client = mqtt.Client()
    if mqtt_username and mqtt_password:
        mqtt_client.username_pw_set(mqtt_username, mqtt_password)
    mqtt_client.connect(mqtt_ip, mqtt_port, 60)
    mqtt_client.loop_start()

def sanitize_topic_name(name):
    # Ersetzt alles außer a-z, A-Z, 0-9 durch _
    return re.sub(r'[^a-zA-Z0-9]', '_', name)

def publish_discovery():
    unique_id = sanitize_topic_name(mqtt_name).lower()
    base_command_topic = f"homeassistant/button/{unique_id}/set_keepalived"
    state_topic = f"homeassistant/sensor/{unique_id}_keepalived_status/state"
    sensor_config_topic = f"homeassistant/sensor/{unique_id}_keepalived_status/config"

    device_info = {
        "identifiers": [unique_id],
        "name": mqtt_name,
        "manufacturer": "Custom",
        "model": "Keepalived API",
        "sw_version": "1.0"
    }

    # Buttons discovery (start, stop, restart)
    actions = ['start', 'stop', 'restart']
    for action in actions:
        topic = f"homeassistant/button/{unique_id}_keepalived_{action}/config"
        payload = {
            "name": f"{mqtt_name} Keepalived {action.capitalize()}",
            "unique_id": f"{unique_id}_keepalived_{action}",
            "command_topic": f"{base_command_topic}/{action}",
            "device": device_info
        }
        mqtt_client.publish(topic, json.dumps(payload), retain=True)

    # Mainsensor (keepalived_status) including attributes
    sensor_payload = {
        "name": f"{mqtt_name} Keepalived Status",
        "unique_id": f"{unique_id}_keepalived_status",
        "state_topic": state_topic,
        "json_attributes_topic": state_topic,
        "value_template": "{{ value_json.keepalived_status }}",
        "icon": "mdi:router-network",
        "device": device_info
    }
    mqtt_client.publish(sensor_config_topic, json.dumps(sensor_payload), retain=True)

    # Single sensors for each attribute
    attribute_names = ["keepalived_mode", "configured_vip", "vip_assigned", "stdout", "stderr"]
    for attr in attribute_names:
        attr_sensor_payload = {
            "name": f"{attr.replace('_', ' ').title()}",
            "unique_id": f"{unique_id}_keepalived_{attr}",
            "state_topic": state_topic,
            "value_template": f"{{{{ value_json.{attr} }}}}",
            "device": device_info,
            "icon": "mdi:information-outline",
        }
        # dont enable stdout and stderr by default "enabled_by_default": false
        if attr in ["stdout", "stderr"]:
            attr_sensor_payload["enabled_by_default"] = False

        mqtt_client.publish(
            f"homeassistant/sensor/{unique_id}_keepalived_{attr}/config",
            json.dumps(attr_sensor_payload),
            retain=True
        )

def publish_status_periodic():
    while True:
        try:
            keepalived_status, stdout, stderr = get_keepalived_status()
            vip_assigned = get_vip_assigned()
            keepalived_mode = determine_mode(vip_assigned)

            base_topic = f"homeassistant/sensor/{sanitize_topic_name(mqtt_name).lower()}_keepalived_status"
            payload = {
                "action": "status",
                "keepalived_status": keepalived_status,
                "keepalived_mode": keepalived_mode,
                "configured_vip": VIRTUAL_IP,
                "vip_assigned": vip_assigned,
                "stdout": stdout,
                "stderr": stderr
            }
            mqtt_client.publish(base_topic + "/state", json.dumps(payload), retain=True)
        except Exception as e:
            print(f"MQTT publish error: {e}")
        time.sleep(update_interval)

def on_mqtt_message(client, userdata, msg):
    topic = msg.topic
    unique_id = sanitize_topic_name(mqtt_name).lower()
    base_command_topic = f"homeassistant/button/{unique_id}/set_keepalived/"
    state_topic = f"homeassistant/sensor/{unique_id}_keepalived_status/state"

    if topic.startswith(base_command_topic):
        action = topic[len(base_command_topic):]
        print(f"Received MQTT command: {action}")
        try:
            result = subprocess.run(
                ['systemctl', action, 'keepalived'],
                capture_output=True, text=True, check=True
            )
            keepalived_status, stdout_status, stderr_status = get_keepalived_status()
            vip_assigned = get_vip_assigned()
            keepalived_mode = determine_mode(vip_assigned)
            response_payload = {
                "action": action,
                "keepalived_status": keepalived_status,
                "keepalived_mode": keepalived_mode,
                "configured_vip": VIRTUAL_IP,
                "vip_assigned": vip_assigned,
                "stdout": result.stdout.strip(),
                "stderr": result.stderr.strip()
            }
            mqtt_client.publish(state_topic, json.dumps(response_payload), retain=True)
        except subprocess.CalledProcessError as e:
            mqtt_client.publish(state_topic, json.dumps({"error": str(e)}), retain=True)

if __name__ == '__main__':
    if mqtt_enabled:
        mqtt_connect()
        publish_discovery()
        mqtt_client.subscribe(f"homeassistant/button/{sanitize_topic_name(mqtt_name).lower()}/set_keepalived/#")
        mqtt_client.on_message = on_mqtt_message
        thread = threading.Thread(target=publish_status_periodic, daemon=True)
        thread.start()

    app.run(host='0.0.0.0', port=PORT)


```

### config file

```
sudo nano /usr/local/bin/keepalived_api.conf
```

paste this content and addapt to your needs

- `port`: Port for Flask-Server
- `interface`: Network-Interface, z.B. eth0 oder eth0@if9
- `vip`: The virtuell IP from Keepalived
- `allowed_ips`: allowed Client-IP-Addresses, comma-separated


```
[keepalived_api]
port = 5000
interface = eth0
vip = 192.168.178.9
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

