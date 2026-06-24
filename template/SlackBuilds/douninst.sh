PKGNAME="%PKFNAME%"

if [ -x /usr/bin/install-info -a -r usr/info/dir ]; then
  for logfile in var/lib/pkgtools/packages/${PKGNAME}-*; do
    [ -r "$logfile" ] || continue
    basename_log=$(basename "$logfile")
    pkg_name="${basename_log%%-*}"
    [ "$pkg_name" = "$PKGNAME" ] || continue

    grep "^usr/info/.*\.info\.gz$" "$logfile" | while read -r infofile; do
      /usr/bin/install-info --delete --info-dir=usr/info "$infofile" 2> /dev/null
    done
  done
fi
