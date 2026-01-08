# HyprWhspr & Parakeet Cheat Sheet

## 🎮 VRAM Management (Gaming vs Work)

The Parakeet model takes up ~1-2GB of VRAM. You can unload it when you need max GPU performance for gaming or rendering.

**Unload Model (Free VRAM):**

```bash
systemctl --user stop parakeet-tdt-0.6b-v3.service
```

**Load Model (Ready to Dictate):**
_Note: Wait approx 5 seconds after running this before speaking._

```bash
systemctl --user start parakeet-tdt-0.6b-v3.service
```

---

## ⚙️ Configuration

**Edit Config:**

```bash
micro ~/.config/hyprwhspr/config.json
```

**Apply Changes:**
_You must run this every time you edit the config file._

```bash
systemctl --user restart hyprwhspr
```

---

## 🔍 Troubleshooting & Logs

**Watch Real-time Logs (Main App):**
_Use this to see if it hears you (Beep/Boop) or if the backend connection fails._

```bash
journalctl --user -u hyprwhspr -f
```

**Watch Real-time Logs (Backend Server):**
_Use this if the server isn't starting or if the model crashes._

```bash
journalctl --user -u parakeet-tdt-0.6b-v3.service -f
```

**Fix "Clipboard Injection Failed" / "Exit Status 1":**
_Run this if text appears in logs but not on screen (Wayland issue)._

```bash
dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP
systemctl --user restart hyprwhspr
```

---

## 🛠️ Emergency Repairs

**Fix Python Dependency Hell (Numpy/Numba Crash):**
_If the backend fails after a system update, run these inside the venv:_

```bash
~/.local/share/hyprwhspr/parakeet-venv/bin/pip install --upgrade "ml_dtypes>=0.5.0"
~/.local/share/hyprwhspr/parakeet-venv/bin/pip install "numpy<2.4"
systemctl --user restart parakeet-tdt-0.6b-v3.service
```

**Fix Ydotool (Permission Denied):**
_If the logs say `dependency failed` or `ydotool exit code 2`._

```bash
systemctl --user reset-failed
systemctl --user start ydotool
systemctl --user restart hyprwhspr
```
