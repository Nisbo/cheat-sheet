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

def parse_keepalived_config(conf_path="/etc/keepalived/keepalived.conf"):
    data = {
        "state": None,
        "interface": None,
        "vrid": None,
        "priority": None,
        "vips": []
    }

    try:
        with open(conf_path, "r") as f:
            lines = f.readlines()

        inside_instance = False
        inside_vip_block = False
        block_level = 0  # block count { }

        for line in lines:
            stripped = line.strip()

            # begin vrrp_instance
            if stripped.startswith("vrrp_instance"):
                inside_instance = True
                block_level = 0
                block_level += stripped.count("{") - stripped.count("}")
                continue

            if inside_instance:
                # count all { and }
                block_level += stripped.count("{") - stripped.count("}")

                if block_level <= 0:
                    inside_instance = False
                    inside_vip_block = False
                    continue

                if stripped.startswith("virtual_ipaddress"):
                    inside_vip_block = True
                    continue

                if inside_vip_block:
                    if stripped.startswith("}"):
                        inside_vip_block = False
                        continue
                    if stripped and not stripped.startswith("#"):
                        data["vips"].append(stripped)
                    continue

                if stripped.lower().startswith("state "):
                    data["state"] = stripped.split()[1].upper()
                    continue

                if stripped.lower().startswith("interface "):
                    data["interface"] = stripped.split()[1]
                    continue

                if stripped.lower().startswith("virtual_router_id"):
                    data["vrid"] = stripped.split()[1]
                    continue

                if stripped.lower().startswith("priority"):
                    data["priority"] = stripped.split()[1]
                    continue

    except Exception as e:
        return {"error": str(e)}

    return data


# Config
config = configparser.ConfigParser()
config.read('/usr/local/bin/keepalived_api.conf')
config_data = parse_keepalived_config() # data from keepalived.conf
#print(config_data)

if "error" in config_data:
    print(f"Fehler beim Parsen: {config_data['error']}")
    import sys
    sys.exit(1)

CONFIGURED_MODE  = config_data.get("state", "UNKNOWN")

# keepalived_api Section
PORT            = int(config['keepalived_api'].get('port', '5000'))
INTERFACE       = config_data.get("interface", "eth0")          #config['keepalived_api'].get('interface', 'eth0')
VIRTUAL_IP      = config_data.get("vips", ["0.0.0.0"])[0]       #config['keepalived_api'].get('vip', '192.168.178.9')
allowed_ips_str = config['keepalived_api'].get('allowed_ips', '')
ALLOWED_IPS     = [ip.strip() for ip in allowed_ips_str.split(',') if ip.strip()]

# MQTT Section
mqtt_enabled    = config['mqtt'].getboolean('enabled', fallback=False)
mqtt_name       = config['mqtt'].get('name', 'Pi-Hole')
mqtt_ip         = config['mqtt'].get('ip', '127.0.0.1')
mqtt_port       = int(config['mqtt'].get('port', 1883))
mqtt_username   = config['mqtt'].get('username', '')
mqtt_password   = config['mqtt'].get('password', '')
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

# MQTT
def mqtt_connect():
    global mqtt_client
    mqtt_client = mqtt.Client()
    if mqtt_username and mqtt_password:
        mqtt_client.username_pw_set(mqtt_username, mqtt_password)
    mqtt_client.connect(mqtt_ip, mqtt_port, 60)
    mqtt_client.loop_start()

def sanitize_topic_name(name):
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
    attribute_names = [
        "keepalived_mode",
        "keepalived_configured_mode",
        "configured_vip",
        "vip_assigned",
        "stdout",
        "stderr",
        "ftl_service_status",
        "dns_query_ok",
        "dns_response_time_ms",
        "dns_response"
    ]

    for attr in attribute_names:
        is_numeric = attr == "dns_response_time_ms"

        attr_sensor_payload = {
            "name": f"{attr.replace('_', ' ').title()}",
            "unique_id": f"{unique_id}_keepalived_{attr}",
            "state_topic": state_topic,
            "value_template": f"{{{{ value_json.{attr} }}}}",
            "device": device_info,
            "icon": "mdi:information-outline",
        }

        use_binary_sensor = "sensor"
        is_dnsquery = attr == "dns_query_ok"
        # binary sensor for dns_query_ok
        if is_dnsquery:
            attr_sensor_payload = {
                "name": f"{attr.replace('_', ' ').title()}",
                "unique_id": f"{unique_id}_keepalived_{attr}",
                "state_topic": state_topic,
                "value_template": f"{{{{ value_json.{attr} }}}}",
                "device": device_info,
                "icon": "mdi:dns",
                "device_class" : "connectivity",
                "payload_on" : True,
                "payload_off" : False,
            }

            use_binary_sensor = "binary_sensor"

        # numeric sensor
        if is_numeric:
            attr_sensor_payload["state_class"] = "measurement"
            attr_sensor_payload["device_class"] = "duration"
            attr_sensor_payload["unit_of_measurement"] = "ms"

        # unwanted by default
        if attr in ["stdout", "stderr", "dns_response"]:
            attr_sensor_payload["enabled_by_default"] = False

        mqtt_client.publish(
            f"homeassistant/{use_binary_sensor}/{unique_id}_keepalived_{attr}/config",
            json.dumps(attr_sensor_payload),
            retain=True
        )

def check_ftl_status():
    try:
        result = subprocess.run(
            ['systemctl', 'is-active', 'pihole-FTL'],
            capture_output=True, text=True, check=False
        )
        return result.stdout.strip()
    except Exception as e:
        return "error"

def test_dns():
    try:
        start = time.time()
        result = subprocess.run(
            ['dig', '@127.0.0.1', 'google.com', '+time=2', '+short'],
            capture_output=True, text=True, timeout=3
        )
        duration = int((time.time() - start) * 1000)

        if result.returncode == 0:
            answer = result.stdout.strip()
            if answer:
                return True, duration, answer
            else:
                return False, -1, ""
        else:
            return False, -1, ""
    except Exception:
        return False, -1, ""

def publish_full_status():
    keepalived_status, stdout, stderr = get_keepalived_status()
    vip_assigned = get_vip_assigned()
    keepalived_mode = determine_mode(vip_assigned)

    ftl_status = check_ftl_status()
    dns_ok, dns_time, dns_answer = test_dns()

    base_topic = f"homeassistant/sensor/{sanitize_topic_name(mqtt_name).lower()}_keepalived_status"
    payload = {
        "action": "status",
        "keepalived_status": keepalived_status,
        "keepalived_configured_mode": CONFIGURED_MODE,
        "keepalived_mode": keepalived_mode,
        "configured_vip": VIRTUAL_IP,
        "vip_assigned": vip_assigned,
        "ftl_service_status": ftl_status,
        "dns_query_ok": dns_ok,
        "dns_response_time_ms": dns_time,
        "dns_response": dns_answer,
        "stdout": stdout,
        "stderr": stderr
    }
    mqtt_client.publish(base_topic + "/state", json.dumps(payload), retain=True)

def publish_status_periodic():
    while True:
        try:
            publish_full_status()
        except Exception as e:
            print(f"MQTT publish error: {e}")
        time.sleep(update_interval)

def publish_ftl_status_changes():
    last_ftl_status = None

    while True:
        try:
            current_ftl_status = check_ftl_status()
            if current_ftl_status != last_ftl_status:
                publish_full_status()  # hier kompletten Status senden
                last_ftl_status = current_ftl_status
        except Exception as e:
            print(f"FTL status publish error: {e}")
        time.sleep(2)  # alle 2 Sekunden prüfen

def on_mqtt_message(client, userdata, msg):
    topic = msg.topic
    unique_id = sanitize_topic_name(mqtt_name).lower()
    base_command_topic = f"homeassistant/button/{unique_id}/set_keepalived/"
    state_topic = f"homeassistant/sensor/{unique_id}_keepalived_status/state"

    if topic.startswith(base_command_topic):
        action = topic[len(base_command_topic):]
        #print(f"Received MQTT command: {action}")
        try:
            result = subprocess.run(
                ['systemctl', action, 'keepalived'],
                capture_output=True, text=True, check=True
            )
            keepalived_status, stdout_status, stderr_status = get_keepalived_status()
            vip_assigned = get_vip_assigned()
            keepalived_mode = determine_mode(vip_assigned)

            ftl_status = check_ftl_status()
            dns_ok, dns_time, dns_answer = test_dns()

            response_payload = {
                "action": action,
                "keepalived_status": keepalived_status,
                "keepalived_configured_mode": CONFIGURED_MODE,
                "keepalived_mode": keepalived_mode,
                "configured_vip": VIRTUAL_IP,
                "vip_assigned": vip_assigned,
                "ftl_service_status": ftl_status,
                "dns_query_ok": dns_ok,
                "dns_response_time_ms": dns_time,
                "dns_response": dns_answer,                
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

        # FTL-Statuscheck
        ftl_thread = threading.Thread(target=publish_ftl_status_changes, daemon=True)
        ftl_thread.start()

    app.run(host='0.0.0.0', port=PORT)
