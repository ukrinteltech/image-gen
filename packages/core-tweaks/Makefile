all:

install:
	mkdir -p $(DESTDIR)/usr/share/core-tweaks
	install -m 644 mozilla.tar.bz2 $(DESTDIR)/usr/share/core-tweaks/mozilla.tar.bz2

clean:

distclean:

package:
	dpkg-buildpackage -rfakeroot -b -tc || true
