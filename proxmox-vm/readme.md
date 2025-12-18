Deutsches Layout installieren

```
sudo apt update
sudo apt install console-setup
```

VM Speicherplatz vergrößern wenn neuer Platz zugewiesen wurde und ggf vorher Platz freimachen falls die Partition voll ist.

```
# Platz prüfen
df -h

# Reserved Blocks reduzieren (auf 1% reservieren)
sudo tune2fs -m 1 /dev/sda3

# Platz durch Logs und Cache freimachen
sudo journalctl --vacuum-size=100M
sudo rm -rf /var/cache/apt/archives/*
sudo truncate -s 0 /var/log/syslog /var/log/kern.log /var/log/auth.log
sudo find /var/lib/docker/containers/ -name "*.log" -exec truncate -s 0 {} \;

# cloud-guest-utils installieren (für growpart)
sudo apt update
sudo apt install cloud-guest-utils

# Partition mit growpart vergrößern (z.B. Partition 3)
sudo growpart /dev/sda 3

# Dateisystem vergrößern (ext4)
sudo resize2fs /dev/sda3

# Falls nötig Reparieren abgebrochener dpkg Vorgänge
sudo dpkg --configure -a
```
