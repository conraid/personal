config() {
    NEW="$1"
    OLD="$(dirname $NEW)/$(basename $NEW .new)"
    # If there's no config file by that name, mv it over:
    if [ ! -r $OLD ]; then
        mv $NEW $OLD
    elif [ "$(cat $OLD | md5sum)" = "$(cat $NEW | md5sum)" ]; then
        # toss the redundant copy
        rm $NEW
    fi
    # Otherwise, we leave the .new copy for the admin to consider...
}

perms() {
    # Keep same perms on file
    NEW="$1"
    OLD="$(dirname $NEW)/$(basename $NEW .new)"
    if [ -e $OLD ]; then
        cp -a $OLD $NEW.incoming
        cat $NEW >$NEW.incoming
        mv $NEW.incoming $NEW
    fi
    config $NEW
}

schema_install() {
    SCHEMA="$1"
    GCONF_CONFIG_SOURCE="xml::etc/gconf/gconf.xml.defaults" \
        chroot . gconftool-2 --makefile-install-rule \
        /etc/gconf/schemas/$SCHEMA \
        1>/dev/null
}
# Install schemas, if any
schema_install blah.schemas

# Update the desktop database:
if [ -x /usr/bin/update-desktop-database ]; then
    /usr/bin/update-desktop-database -q usr/share/applications >/dev/null 2>&1
fi

# Update the mime database:
if [ -x /usr/bin/update-mime-database ]; then
    /usr/bin/update-mime-database usr/share/mime >/dev/null 2>&1
fi

# Update icon cache if one exists
if [ -e usr/share/icons/hicolor/icon-theme.cache ]; then
    if [ -x /usr/bin/gtk-update-icon-cache ]; then
        /usr/bin/gtk-update-icon-cache -t -f -q usr/share/icons/hicolor >/dev/null 2>&1
    fi
fi

# Update schemas
if [ -e usr/share/glib-2.0/schemas ]; then
    if [ -x /usr/bin/glib-compile-schemas ]; then
        /usr/bin/glib-compile-schemas usr/share/glib-2.0/schemas >/dev/null 2>&1
    fi
fi

# Plasma applet
if [ -x /usr/bin/kbuildsycoca4 ]; then
    /usr/bin/kbuildsycoca4
fi

# Before perm, if necessary (config is not necessary)
perms etc/rc.d/rc.XXX.new
# After config. If PERMS not necessary
config etc/XXX.conf.new
for NEW in etc/XXX/*.new; do
    config $NEW
done

# Add user and group (usually uid and gid are SBo suggests)
if ! grep -q "^GROUPNAME:" etc/group; then
    if ! grep -q ":GROUPID:" etc/group; then
        chroot . groupadd -g YYY %GROUPNAME% &>/dev/null
    else
        chroot . groupadd %GROUPNAME% &>/dev/null
    fi
fi

if ! grep -q "^GROUPNAME:" etc/passwd; then
    if ! grep -q ":GROUPID:" etc/passwd; then
        chroot . useradd -u XXX -d /dev/null -s /bin/false -c "NAME" -g %GROUPNAME% %USERNAME% &>/dev/null
    else
        chroot . useradd -d /dev/null -s /bin/false -c "NAME" -g %GROUPNAME% %USERNAME% &>/dev/null
    fi
fi
