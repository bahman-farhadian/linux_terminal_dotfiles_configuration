#!/usr/bin/env python3
"""Sort the GNOME application grid (Super+A) into alphabetical folders.

Reads every visible .desktop entry the desktop knows about, buckets them by the
first letter of their displayed name, and writes the result to
org.gnome.desktop.app-folders.

Idempotent: it clears the folders it manages and rebuilds them from the current
set of applications, so running it again after installing something puts the
new entry in the right folder and leaves everything else where it belongs.

  gnome-app-folders.py --list    show what would happen, change nothing
  gnome-app-folders.py           apply it
"""
import configparser
import os
import subprocess
import sys

SCHEMA = "org.gnome.desktop.app-folders"
FOLDER_SCHEMA = "org.gnome.desktop.app-folders.folder"
FOLDER_PATH = "/org/gnome/desktop/app-folders/folders"


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
    subprocess.run(["gsettings", *args], check=True)


def gvariant(items):
    return "[" + ", ".join("'" + i.replace("'", r"\'") + "'" for i in items) + "]"


def main():
    preview = "--list" in sys.argv
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
        return

    existing = subprocess.run(["gsettings", "get", SCHEMA, "folder-children"],
                              capture_output=True, text=True).stdout.strip()
    for old in existing.strip("[]").replace("'", "").split(","):
        old = old.strip()
        if old:
            gsettings("reset-recursively", f"{FOLDER_SCHEMA}:{FOLDER_PATH}/{old}/")

    for key in order:
        path = f"{FOLDER_SCHEMA}:{FOLDER_PATH}/{key}/"
        gsettings("set", path, "name", key)
        gsettings("set", path, "apps", gvariant([d for _, d in folders[key]]))
    gsettings("set", SCHEMA, "folder-children", gvariant(order))
    print(f"{len(apps)} applications sorted into {len(order)} folders: {' '.join(order)}")


if __name__ == "__main__":
    main()
