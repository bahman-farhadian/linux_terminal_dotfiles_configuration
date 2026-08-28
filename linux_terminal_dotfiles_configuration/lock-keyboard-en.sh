#!/bin/sh
# Keep the unlock prompt on a US keyboard.
#
# Locking the screen while the German or Persian layout is active leaves the
# password prompt on that layout, which can make the password impossible to
# type. Run from cron every 10 minutes: while the session is locked this puts
# the layout back to English. While it is unlocked it does nothing, so it never
# interferes with typing in another language.

# cron has no session bus of its own. gsettings and gdbus both need one.
DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"
export DBUS_SESSION_BUS_ADDRESS

EN_SOURCES="[('xkb', 'us'), ('xkb', 'ir')]"

# Is the screen locked? No session, no answer, nothing to do.
locked=$(gdbus call --session --dest org.gnome.ScreenSaver \
    --object-path /org/gnome/ScreenSaver \
    --method org.gnome.ScreenSaver.GetActive 2>/dev/null)

case "$locked" in
    *true*) ;;
    *) exit 0 ;;
esac

# Already English: leave it alone rather than rewriting the same value.
[ "$(gsettings get org.gnome.desktop.input-sources sources 2>/dev/null)" = "$EN_SOURCES" ] && exit 0

gsettings set org.gnome.desktop.input-sources sources "$EN_SOURCES"
