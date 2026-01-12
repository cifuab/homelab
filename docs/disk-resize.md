### Proxmox Increase RAM and Disk

---
A) Increase RAM (Proxmox GUI)

- Shutdown the jumpbox VM (recommended).

- VM → Hardware → Memory → set new RAM (and optionally “Ballooning Device” if you use it).

- Start VM.

- Verify in Linux:
```shell
free -h
```
B) Increase Disk size
1) Grow the virtual disk in Proxmox

   - Proxmox GUI:

     - VM → Hardware → select the disk (e.g., scsi0 / virtio0) → Resize disk → add e.g. +20G.

     - Or CLI on Proxmox:
```shell
qm resize <VMID> scsi0 +20G
# (replace scsi0 with your actual disk name)
```
2) Expand inside Ubuntu (jumpbox)

   - First, see what you have:
```shell
lsblk
df -hT
```
- Now choose the correct path:

- If jumpbox uses LVM (common on Ubuntu server)
```shell
sudo pvresize /dev/sda3          # example PV partition (check lsblk!)
sudo lvextend -l +100%FREE /dev/mapper/ubuntu--vg-ubuntu--lv
sudo resize2fs /dev/mapper/ubuntu--vg-ubuntu--lv   # for ext4
# or: sudo xfs_growfs /           # if XFS
```
- If jumpbox uses a normal partition (no LVM)

- Install helper (once):
```shell
sudo apt-get update && sudo apt-get install -y cloud-guest-utils
```
- then:
```shell
sudo growpart /dev/sda 1         # example: disk /dev/sda, partition 1
sudo resize2fs /dev/sda1         # ext4
# or: sudo xfs_growfs /          # xfs
```
- verify:
```shell
lsblk
df -hT
```
- Quick note about safety

  - RAM: safe.

  - Disk: safe if you expand (not shrink). Still, best practice is to have a snapshot/backup before resizing.

- If you paste the output of:
```shell
lsblk
df -hT
```