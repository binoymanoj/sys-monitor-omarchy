# System Monitor Plugin for Omarchy

A high-performance, native system monitoring plugin and status bar widget for the [Omarchy](https://github.com/omarchy) desktop shell (powered by [Quickshell](https://quickshell.org/)).

Shows live CPU utilization, RAM usage, and Network speed directly on your topbar, complete with a rich popup window providing real-time hardware diagnostics and visual configuration toggles.

![Preview](preview.png)

---

## ✨ Features

- **Topbar System Status**:
  - **CPU Utilization**: ` <usage>%` (e.g., ` 18%`).
  - **RAM Memory Usage**: ` <usage>%` (e.g., ` 35%`).
  - **Internal Storage Usage**: `󰋊 <usage>%` (e.g., `󰋊 34%`).
  - **External Storage (When Attached)**: `󱛟 <usage>%` (dynamically appears when USB/external drives are plugged in).
  - **Network Download Speed**: `↓ <speed>` (e.g., `↓ 1.2 MB/s`).
  - **Network Upload Speed**: `↑ <speed>` (optional, e.g., `↑ 45 KB/s`).
  - **Dynamic Theme Palette**: Inherits active Omarchy theme foreground, accent, and font colors.
  - **High Load Alert**: Changes metric color to `urgent` (#ef4444) when CPU ≥ 85%, RAM ≥ 90%, or Storage ≥ 90%.
  - **Orientation-Aware**: Responsive layout for horizontal and vertical status bars.
- **Interactive Configuration & Diagnostic Popup**:
  - **System Overview**: Displays CPU model name, system uptime, and a one-click button to open `btop`.
  - **Detailed CPU Card**: Animated progress bar, 1m/5m/15m load averages, and live per-core mini load bars.
  - **Detailed RAM Card**: Animated memory progress bar, used / total GB, free/available GB, and swap usage.
  - **Detailed Internal Storage Card**: Root filesystem usage progress bar, used/total/available GB, mount point, filesystem format, disk model, and secondary partitions.
  - **Dynamic External Storage Card**: Automatically detects attached external drives, USB thumb drives, and external SSDs/HDDs; shows capacity, used/free space, mount status, and one-click "Open" in file manager button.
  - **Detailed Network Card**: Active interface detection, live download & upload speed cards.
    - **Icon-Only Mode**: Option to display just 1 clean icon on the bar instead of stats; clicking the icon opens the full stats and diagnostics popup. Even if you disable all individual stats, this icon stays present so the widget is never an empty hole!
    - **Show Main Icon**: Toggle whether the main system monitor icon appears on the bar.
    - **Customizable Topbar Icon**: Pick between CPU (``), Gauge (`󰻠`), Heartbeat (``), Chip (`󰍛`), Storage (`󰋊`), Dashboard (`󰾆`), or any custom Nerd Font glyph.
    - Toggle CPU display on the bar on/off.
    - Toggle RAM display on the bar on/off.
    - Toggle Internal Storage display on the bar on/off.
    - Toggle External Storage display on the bar on/off.
    - Toggle Download speed on the bar on/off.
    - Toggle Upload speed on the bar on/off.
    - Toggle Metric icons on the bar on/off.
    - Adjustable refresh interval buttons (1s, 2s, 3s, 5s).
- **High Efficiency & Native Linux Performance**:
  - Reads CPU, memory, and network directly from Linux `/proc/stat`, `/proc/meminfo`, `/proc/net/dev`, `/proc/loadavg`, and `/proc/uptime` via Quickshell's native C++ `FileView`.
  - Uses asynchronous, non-blocking hardware queries (`lsblk -b -J`) for instant, low-overhead disk and hotplug detection.
  - No `sudo` or `pkexec` required.
- **Persistent Preferences**:
  - Saves your preferences to `~/.local/state/omarchy/settings/sys-monitor.json` and syncs with Omarchy's `shell.json`.

---

## 📦 Requirements & Dependencies

- **Desktop Shell**: [Omarchy Quattro](https://omarchy.org/) with Quickshell.
- **System**: Linux with `/proc` filesystem.
- **Optional**: `btop` (launched via the popup's "btop" button if installed).

---

## 🚀 Installation

Install directly using the Omarchy plugin CLI:

```bash
omarchy plugin add https://github.com/binoymanoj/sys-monitor-omarchy.git --enable --yes
```

To update to the latest version:

```bash
omarchy plugin update sys-monitor --yes
```

---

## 🗑️ Removal

To disable and remove the plugin from Omarchy:

```bash
omarchy plugin remove sys-monitor --yes
```

---

## ⌨️ Controls & Keybindings

| Action | Control | Description |
|---|---|---|
| **Toggle Popup Window** | Left-Click on bar widget | Opens or closes the detailed diagnostic and settings popup |
| **Launch Task Manager** | Right-Click on bar widget | Spawns `btop` in your configured terminal |
| **Force Immediate Refresh** | Middle-Click on bar widget | Forces an instant reload of all system stats |
| **Close Popup** | <kbd>Esc</kbd> or click outside | Closes the popup window |

### Custom Keyboard Shortcut

To bind a keyboard shortcut in Hyprland to summon or toggle the System Monitor popup:

```hyprlang
# In ~/.config/hypr/hyprland.conf:
bind = SUPER, M, exec, omarchy-shell shell toggle sys-monitor '{}'
```

---

## ⚙️ Bar Position & Layout

You can rearrange the bar widget position using the standard `omarchy bar` command:

```bash
# Move to the center section:
omarchy bar move sys-monitor --section center

# Move next to another widget:
omarchy bar move sys-monitor --section right --after omarchy.tray
```

---

## 📁 Repository Structure

```
.
├── BarWidget.qml        # Main Quickshell bar widget, topbar layout, and popup window
├── SysMonitorModel.js   # Pure JS parsing engine for /proc statistics and speed formatting
├── manifest.json        # Omarchy shell plugin manifest
├── LICENSE              # MIT License
├── preview.png          # High-resolution screenshot preview
└── README.md            # Documentation
```

---

## 📄 License

This project is licensed under the [MIT License](LICENSE).
