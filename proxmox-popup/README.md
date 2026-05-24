Remove the "no valid" Popup 


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

If already patched with this script, you can revert it

```
== Proxmox No-Subscription Popup Patch ==

[INFO] Checking file...

[INFO] Already patched.

614:                        42 === 0
21106:                    42 === 0

Revert patch? [y/N]: y

[INFO] Reverting patch...
Create backup before reverting? [Y/n]: y
[OK] Backup created:
     /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js.revertbak.20260524-171629
[SUCCESS] Revert successful.

[INFO] Clearing cache...
Restart pveproxy now? [Y/n]: y
[OK] pveproxy restarted.
root@proxmox3:~#
```
