Entfernt das nervige "no valid" Popup 

```
wget -O proxmox-nag-remove.sh https://raw.githubusercontent.com/Nisbo/cheat-sheet/main/proxmox-popup/proxmox-nag-remove.sh
chmod +x proxmox-nag-remove.sh
./proxmox-nag-remove.sh
```

oder 

```
bash <(wget -qO- https://raw.githubusercontent.com/Nisbo/cheat-sheet/main/proxmox-popup/proxmox-nag-remove.sh)
```


Output:

```
== Proxmox No-Subscription Popup Patch ==

[INFO] Checking file...

[FOUND] Matches:

614:                        res.data.status.toLowerCase() !== 'active'
21106:                    res.data.status.toLowerCase() !== 'active'

Apply patch? [y/N]: y

Create backup? [Y/n]: y
[OK] Backup created:
     /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js.bak.20260524-171423

[INFO] Applying patch...

[INFO] Verifying...
[SUCCESS] Patch applied.

[INFO] Clearing cache...
Restart pveproxy now? [Y/n]: y
[OK] pveproxy restarted.

Done.
root@proxmox3:~#
```
