Frigate auf einem Pi5 installieren

zuerst Docker

🧱 1. System vorbereiten
```
sudo apt update && sudo apt upgrade -y
sudo reboot
```
🐳 2. Docker installieren (offizielles Script)

Das ist die zuverlässigste Methode auf Raspberry Pi OS:

```
curl -fsSL https://get.docker.com | sudo sh
```


👤 3. Benutzerrechte setzen (wichtig!)

Damit du Docker ohne sudo nutzen kannst:

```
sudo usermod -aG docker pi
```

👉 danach abmelden & neu einloggen (oder reboot)


🧩 4. Docker Compose Plugin installieren

Auf aktuellen Raspberry Pi OS Versionen:

```
sudo apt install -y docker-compose-plugin
```


Test:

```
docker compose version
```


🔧 5. Grundcheck

Nach Login prüfen:

```
docker run hello-world
```

Wenn das läuft → Docker ist sauber installiert.

📦 7. Verzeichnisstruktur vorbereiten (wie geplant)

```
sudo mkdir -p /data/docker/frigate/config
sudo mkdir -p /data/docker/frigate/media
sudo mkdir -p /data/docker/frigate/db
sudo chown -R pi:pi /data/docker
```

```
cd /data/docker/frigate
nano docker-compose.yml
```

Einfügen

```
services:
  frigate:
    container_name: frigate
    image: ghcr.io/blakeblackshear/frigate:stable
    restart: unless-stopped
    privileged: true

    shm_size: "512mb"

    devices:
      - /dev/bus/usb:/dev/bus/usb

    volumes:
      - /etc/localtime:/etc/localtime:ro
      - /data/docker/frigate/config:/config
      - /data/docker/frigate/media:/media/frigate
      - /data/docker/frigate/db:/db
      - type: tmpfs
        target: /tmp/cache
        tmpfs:
          size: 1000000000

    ports:
      - "8971:8971"
      - "8554:8554"
```

Config

```
auth:
  enabled: false

detectors:
  coral:
    type: edgetpu
    device: usb

mqtt:
  host: 192.168.178.27
  port: 1884

ui:
  # Optional: Set a timezone to use in the UI (default: use browser local time)
  # timezone: America/Denver
  # Optional: Set the time format used.
  # Options are browser, 12hour, or 24hour (default: shown below)
  time_format: 24hour

cameras:
  strasse:
    ffmpeg:
      inputs:
        - path: rtsps://192.168.178.1:7441/L91wDlwRXyKP2VLm?enableSrtp
          roles:
            - detect
    objects:
      track:
        - car
        - bus
    snapshots:
      enabled: true
      timestamp: true
      bounding_box: true
      retain:
        default: 1        # Anzahl Tage
        objects:
          bus: 30

  arbeitszimmer-regal:
    ffmpeg:
      inputs:
        - path: rtsps://192.168.178.1:7441/XwfeZL2iCgGixkQ0?enableSrtp
          roles:
            - detect
    objects:
      track:
        - cat
        - person
    snapshots:
      enabled: true
      timestamp: true
      bounding_box: true
      retain:
        default: 2        # Anzahl Tage
        objects:
          cat: 30


  flur:
    ffmpeg:
      inputs:
        - path: rtsps://192.168.178.1:7441/LiklcH7yJHnbdUZy?enableSrtp
          roles:
            - detect
    objects:
      track:
        - cat
        - person
    snapshots:
      enabled: true
      timestamp: true
      bounding_box: true
      retain:
        default: 2        # Anzahl Tage
        objects:
          cat: 30


logger:
  default: info
detect:
  enabled: true
version: 0.16-0

```


