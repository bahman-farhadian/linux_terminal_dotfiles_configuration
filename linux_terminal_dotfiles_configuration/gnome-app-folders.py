#!/usr/bin/env python3
"""Sort the GNOME application grid (Super+A) into alphabetical folders.

Reads every visible .desktop entry the desktop knows about, buckets them by the
first letter of their displayed name, and writes the result to
org.gnome.desktop.app-folders.

Idempotent: it clears the folders it manages and rebuilds them from the current
set of applications, so running it again after installing something puts the
new entry in the right folder and leaves everything else where it belongs.

  gnome-app-folders.py --list        show what would happen, change nothing
  gnome-app-folders.py --status      read back what is currently set
  gnome-app-folders.py               apply it
  gnome-app-folders.py --clear-dock  apply it and also empty the pinned dock

The dock is never touched unless --clear-dock is given.
"""
import configparser
import os
import re
import subprocess
import sys

SCHEMA = "org.gnome.desktop.app-folders"
FOLDER_SCHEMA = "org.gnome.desktop.app-folders.folder"
FOLDER_PATH = "/org/gnome/desktop/app-folders/folders"
SHELL_SCHEMA = "org.gnome.shell"


def application_dirs():
    home = os.environ.get("XDG_DATA_HOME", os.path.expanduser("~/.local/share"))
    dirs = [home]
    dirs += os.environ.get("XDG_DATA_DIRS", "/usr/local/share:/usr/share").split(":")
    dirs += ["/var/lib/flatpak/exports/share", os.path.join(home, "flatpak/exports/share")]
    out = []
    for d in dirs:
        p = os.path.join(d, "applications")
        if os.path.isdir(p) and p not in out:
            out.append(p)
    return out


def visible_applications():
    """desktop id -> display name, honouring XDG precedence (first wins)."""
    found = {}
    for directory in application_dirs():
        for entry in sorted(os.listdir(directory)):
            if not entry.endswith(".desktop") or entry in found:
                continue
            parser = configparser.RawConfigParser(strict=False, interpolation=None)
            parser.optionxform = str
            try:
                parser.read(os.path.join(directory, entry), encoding="utf-8")
                section = parser["Desktop Entry"]
            except Exception:
                continue
            if section.get("Type", "Application") != "Application":
                continue
            if section.get("NoDisplay", "false").lower() == "true":
                continue
            if section.get("Hidden", "false").lower() == "true":
                continue
            found[entry] = section.get("Name", entry[:-8])
    return found


def bucket(name):
    first = name.strip()[:1].upper()
    if first.isalpha() and first.isascii():
        return first
    if first.isdigit():
        return "0-9"
    return "Other"


def gsettings(*args):
    result = subprocess.run(["gsettings", *args], capture_output=True, text=True)
    if result.returncode != 0:
        print(f"  ! gsettings {' '.join(args)}\n    {result.stderr.strip()}", file=sys.stderr)
    return result


def gsettings_get(*args):
    return subprocess.run(["gsettings", "get", *args],
                          capture_output=True, text=True).stdout.strip()


def current_folders():
    """Folder ids currently registered. Handles the '@as []' empty form."""
    return re.findall(r"'([^']*)'", gsettings_get(SCHEMA, "folder-children"))


def show_status():
    folders = current_folders()
    if not folders:
        print("no folders are configured")
        return
    total = 0
    for folder in folders:
        apps = re.findall(r"'([^']*)'",
                          gsettings_get(f"{FOLDER_SCHEMA}:{FOLDER_PATH}/{folder}/", "apps"))
        total += len(apps)
        print(f"  {folder:<6} {len(apps):>3} apps")
    print(f"\n{len(folders)} folders, {total} applications")
    print(f"app-picker-layout: {gsettings_get(SHELL_SCHEMA, 'app-picker-layout')[:60]}")
    pinned = re.findall(r"'([^']*)'", gsettings_get(SHELL_SCHEMA, "favorite-apps"))
    print(f"pinned to the dock: {len(pinned)}")
    for app in pinned:
        print(f"  {app}")


def gvariant(items):
    return "[" + ", ".join("'" + i.replace("'", r"\'") + "'" for i in items) + "]"


def main():
    if "--status" in sys.argv:
        show_status()
        return

    preview = "--list" in sys.argv
    clear_dock = "--clear-dock" in sys.argv
    apps = visible_applications()
    if not apps:
        sys.exit("no .desktop entries found — is this a desktop session?")

    folders = {}
    for desktop_id, name in apps.items():
        folders.setdefault(bucket(name), []).append((name, desktop_id))
    for entries in folders.values():
        entries.sort(key=lambda pair: pair[0].lower())
    order = sorted(folders, key=lambda k: (k in ("0-9", "Other"), k))

    if preview:
        for key in order:
            print(f"\n[{key}]")
            for name, desktop_id in folders[key]:
                print(f"  {name}  ({desktop_id})")
        print(f"\n{len(apps)} applications in {len(order)} folders")
        if clear_dock:
            pinned = re.findall(r"'([^']*)'", gsettings_get(SHELL_SCHEMA, "favorite-apps"))
            print(f"would also unpin {len(pinned)} application(s) from the dock")
        else:
            print("the dock would be left alone (pass --clear-dock to empty it)")
        return

    existing = current_folders()
    print(f"clearing {len(existing)} existing folder(s): {' '.join(existing) or 'none'}")
    for old in existing:
        gsettings("reset-recursively", f"{FOLDER_SCHEMA}:{FOLDER_PATH}/{old}/")
    gsettings("reset", SCHEMA, "folder-children")

    for key in order:
        path = f"{FOLDER_SCHEMA}:{FOLDER_PATH}/{key}/"
        gsettings("set", path, "name", key)
        gsettings("set", path, "apps", gvariant([d for _, d in folders[key]]))
        print(f"  {key:<6} {len(folders[key]):>3} apps")
    gsettings("set", SCHEMA, "folder-children", gvariant(order))

    # GNOME Shell stores its own arrangement of the grid. While that exists it
    # overrides the folder layout, so the folders appear to have no effect even
    # after a log out. Clearing it makes the shell rebuild from app-folders.
    print("resetting org.gnome.shell app-picker-layout")
    gsettings("reset", "org.gnome.shell", "app-picker-layout")

    # The dock is a separate setting and is deliberately left alone unless asked.
    if clear_dock:
        pinned = re.findall(r"'([^']*)'", gsettings_get(SHELL_SCHEMA, "favorite-apps"))
        print(f"unpinning {len(pinned)} application(s) from the dock")
        gsettings("set", SHELL_SCHEMA, "favorite-apps", "[]")

    print(f"\n{len(apps)} applications sorted into {len(order)} folders: {' '.join(order)}")
    print("log out and back in for GNOME Shell to rebuild the grid")


if __name__ == "__main__":
    main()
