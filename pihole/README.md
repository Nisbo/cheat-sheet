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
sudo apt install python3-flask -y
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

app = Flask(__name__)

# Konfigurationsdatei laden
config = configparser.ConfigParser()
config.read('/usr/local/bin/keepalived_api.conf')

# Werte aus der Config auslesen
PORT = int(config['keepalived_api'].get('port', '5000'))
INTERFACE = config['keepalived_api'].get('interface', 'eth0')
VIRTUAL_IP = config['keepalived_api'].get('vip', '192.168.178.9')

allowed_ips_str = config['keepalived_api'].get('allowed_ips', '')
ALLOWED_IPS = [ip.strip() for ip in allowed_ips_str.split(',') if ip.strip()]

def is_allowed_ip():
    return request.remote_addr in ALLOWED_IPS

@app.before_request
def limit_remote_addr():
    if not is_allowed_ip():
        abort(403)  # Forbidden

@app.route('/keepalived/status', methods=['GET'])
def status():
    try:
        result = subprocess.run(
            ['systemctl', 'is-active', 'keepalived'],
            capture_output=True, text=True, check=True
        )
        status_result = result.stdout.strip()
    except subprocess.CalledProcessError as e:
        if e.returncode == 3:
            status_result = "inactive"
        else:
            return jsonify({"error": str(e)}), 500

    try:
        vip_result = subprocess.run(
            ['ip', 'addr', 'show', INTERFACE],
            capture_output=True, text=True, check=True
        ).stdout

        vip_assigned = VIRTUAL_IP in vip_result

        return jsonify({
            "keepalived_status": status_result,
            "vip_assigned": vip_assigned
        })
    except subprocess.CalledProcessError as e:
        return jsonify({"error": str(e)}), 500

@app.route('/keepalived/<action>', methods=['GET', 'POST'])
def control(action):
    if action not in ['start', 'stop', 'restart']:
        return jsonify({"error": "Invalid action"}), 400
    try:
        result = subprocess.run(
            ['systemctl', action, 'keepalived'],
            capture_output=True, text=True, check=True
        )
        return jsonify({
            "action": action,
            "stdout": result.stdout.strip(),
            "stderr": result.stderr.strip()
        })
    except subprocess.CalledProcessError as e:
        return jsonify({"error": str(e)}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=PORT)

```

### config file

```
sudo nano /usr/local/bin/keepalived_api.conf
```

paste this coontent and addapt to your needs

```
[keepalived_api]
port = 5000
interface = eth0
vip = 192.168.178.9
allowed_ips = 192.168.178.87,192.168.178.72
```
