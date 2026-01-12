## CIFS /mnt/data Mount (Tailscale SMB) — Recovery + Permanent Fix

This is a drop-in guide for when the SMB/CIFS mount at `/mnt/data` breaks after reboot or shows `No such device`, `Permission denied`, or systemd `automount` failures.

---

### Symptoms

- `/mnt/data` exists but is empty (not mounted)
- `cd /mnt/data` → `No such device`
- `systemctl status mnt-data.automount` shows failed / dead
- `journalctl -u mnt-data.mount` shows:
  - `error 2 ... opening credential file ...`
  - `Path /mnt/data is already a mount point, refusing start.`
  - autofs pipe hangup errors

---

### Root Causes (what happened)

1) **Duplicate `/etc/fstab` entries** for the same mount (`//100.x.x.x/data` → `/mnt/data`)
   - systemd tried the *wrong* one first (e.g. missing creds file like `/home/jumpbox/.smbcredentials`)
2) **systemd automount got stuck in a failed/unmounted state**
3) A **stale mount remained** on `/mnt/data`, so systemd refused to re-create the automount:
   - `Path /mnt/data is already a mount point, refusing start.`

---

### Permanent Fix (do once)

### 1) Ensure only ONE `/mnt/data` entry exists in `/etc/fstab`

Check:
```bash
sudo grep -n "/mnt/data" /etc/fstab
```
- Keep only ONE active line (example):
```shell
//100.85.211.128/data  /mnt/data  cifs  credentials=/root/.smbcred,vers=3.0,sec=ntlmssp,uid=1000,gid=1000,iocharset=utf8,file_mode=0664,dir_mode=0775,noperm,_netdev,nofail,x-systemd.automount,x-systemd.idle-timeout=600,x-systemd.requires=tailscaled.service,x-systemd.after=tailscaled.service  0  0
```
2) Verify credentials file exists and is protected
```shell
sudo ls -la /root/.smbcred
sudo chmod 600 /root/.smbcred
```
### Quick Recovery (mandatory)

- Use this when `/mnt/data` is “stuck” or automount won’t start.
```shell
# show current state
findmnt /mnt/data || echo "NOT MOUNTED"

# stop units (ignore errors)
sudo systemctl stop mnt-data.mount mnt-data.automount 2>/dev/null || true

# clear stale mount state
sudo umount -l /mnt/data 2>/dev/null || true

# clear failed unit state + reload
sudo systemctl reset-failed mnt-data.mount mnt-data.automount
sudo systemctl daemon-reload

# restart automount
sudo systemctl start mnt-data.automount

# trigger mount
ls -la /mnt/data

# confirm it is mounted
findmnt /mnt/data
```

Expected success output:

- `findmnt /mnt/data` shows `cifs` and source `//100.85.211.128/data`

### How to choose UID/GID

- UID/GID only affects local ownership display on the Linux client.
- Use the UID/GID of the user who should “own” files on /mnt/data (usually your login user):
```shell
id jumpbox
# or if you're logged in as that user:
id -u
id -g
```
- Example:

  - If you see `uid=1000(jumpbox) gid=1000(jumpbox)`, use `uid=1000,gid=1000` in fstab.

  - Note: UID/GID does not fix SMB login errors (`mount error(13)`); that’s credentials/permissions.
  
### Debug commands (when it fails)
```shell
# show fstab entries affecting the mount
sudo grep -n "/mnt/data" /etc/fstab

# systemd unit status
systemctl status mnt-data.automount --no-pager
systemctl status mnt-data.mount --no-pager || true

# logs (better than dmesg when dmesg is restricted)
sudo journalctl -u mnt-data.mount -n 200 --no-pager
sudo journalctl -u mnt-data.automount -n 200 --no-pager
```
- Common errors and meaning:

  - `opening credential file ... No such file` → wrong credentials path in fstab

  - `Permission denied (13)` → wrong password/user or share permissions; add `sec=ntlmssp` and verify creds

  - `Path /mnt/data is already a mount point, refusing start` → stale mount; run the Recovery block