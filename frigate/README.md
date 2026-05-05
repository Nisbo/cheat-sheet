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




