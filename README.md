# whyd-scripts
“What have you done?” – A collection of Bash scripts born from repeatedly asking my BIOS/UEFI vendors why some setting changed again after a firmware update.

## The Story behind
I tinker with my PC. That includes changing BIOS settings. Even after a lot of changes over the past two decades, most vendors ignore certain settings during an update. That caused me much headache because they don't tell what settings changed. They revert to some kind of default – but not always. Applying a saved profile from a previous version can cause even more problems, so I simply check my settings and note what I need to change in the BIOS.

These scripts gather exactly that information: GPU power states, CPU power profiles, VA‑API support, RAM speed, and more – all the things that tend to get reset after a firmware update.

## Scripts Overview
- **`whyd-check`** – The main system information gatherer. Prints a report to the terminal.
- **`whyd-wrapper`** – Autostart script wrapper that runs `whyd-check`, saves the output to `~/.local/share/whyd-scripts/`, shows a notification, and opens the log in your editor.

## Requirements

### Tested Environment / Disclaimer
These scripts are primarily developed and tested on EndeavourOS (Arch-Family)
They should work on most modern Linux distributions, but this is not guaranteed.

Hardware testing is currently limited to the systems available to me. In particular:
* Intel CPUs / iGPUs cannot be tested directly
* NVIDIA GPUs cannot be tested directly

If you run the scripts on other hardware or distributions and encounter issues, feedback or pull requests are welcome.

### System Packages
Install the following dependencies using your package manager:

| Tool            | Purpose                          | Package name (examples)                |
|-----------------|----------------------------------|----------------------------------------|
| bash            | Script interpreter               | `bash` (≥4.0)                          |
| pciutils        | `lspci` for PCI device details   | `pciutils`                             |
| util-linux      | `lscpu` for CPU info             | `util-linux`                           |
| dmidecode       | RAM speed detection              | `dmidecode`                            |
| mesa-utils      | OpenGL renderer / Mesa version   | `mesa-utils`                           |
| vulkan-tools    | Vulkan info                      | `vulkan-tools`                         |
| vainfo          | VA‑API codec support             | `vainfo` + `libva-mesa-driver`         |
| powerprofilesctl| Power profile detection          | `power-profiles-daemon`                |
| libnotify-bin   | Desktop notifications (wrapper)  | `libnotify-bin`                        |
| xdg-utils       | Open log with default app        | `xdg-utils`                            |

### Kernel Module
The `amdgpu` kernel module must be loaded (for AMD GPUs). Load it manually if needed:
```bash
sudo modprobe amdgpu
```
To make it auto-load, add `amdgpu` to `/etc/modules-load.d/modules.conf`

### VA-API Groups
User must be a member of the 'render' and/or 'video' groups for VA-API device access without root
```bash
sudo usermod -aG render,video $USER
```

### Sudoers exceptions for specific commands
Passwordless sudo configured for two specific commands via `/etc/sudoers.d/`
```bash
sudo visudo -f /etc/sudoers.d/whyd-check`
```
Replace `yourusername` with your actuall username. $USER is not working there for security reasons!

`yourusername ALL=(ALL) NOPASSWD: /usr/sbin/dmidecode -t memory`

`yourusername ALL=(ALL) NOPASSWD: /usr/bin/lspci -s * -vv`

Without this, those two checks degrade gracefully with an explanation.

### Installation
* Place the wrapper in `$HOME/.config/autostart/`
* Place the checker in `$HOME/.local/bin/`

## Troubleshooting
If you encounter issues, please [open an issue](https://github.com/Naltarunir/whyd-scripts/issues) with details about your system and the problem.

## Contributing
Contributions are welcome! Feel free to open an issue or submit a pull request.
If you use AI to assist with code, please review the changes with human eyes before sending a pull request. FOSS is built on trust between humans.