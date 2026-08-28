#!/bin/sh
# Put the keyboard back to English the moment the screen locks.
#
# Locking while the German or Persian layout is active leaves the unlock prompt
# on that layout, which can make the password impossible to type. Whatever is
# active at the time, locking returns to English.
#
# This watches for the lock signal rather than polling: a poll only notices the
# lock on its next tick, which is far too late to be useful. It runs for the
# life of the session under systemd --user.

DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"
export DBUS_SESSION_BUS_ADDRESS

EN_SOURCES="[('xkb', 'us'), ('xkb', 'ir')]"

set_english() {
    [ "$(gsettings get org.gnome.desktop.input-sources sources 2>/dev/null)" = "$EN_SOURCES" ] && return
    gsettings set org.gnome.desktop.input-sources sources "$EN_SOURCES"
}

# If the screen is already locked when this starts, act immediately.
case "$(gdbus call --session --dest org.gnome.ScreenSaver \
        --object-path /org/gnome/ScreenSaver \
        --method org.gnome.ScreenSaver.GetActive 2>/dev/null)" in
    *true*) set_english ;;
esac

# ActiveChanged carries true when the screen locks and false when it unlocks.
gdbus monitor --session --dest org.gnome.ScreenSaver 2>/dev/null |
while IFS= read -r line; do
    case "$line" in
        *ActiveChanged*true*) set_english ;;
    esac
done
