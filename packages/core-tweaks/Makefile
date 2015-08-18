APPLAUNCHERDIR = nixysa/examples/applauncher
APPLAUNCHER = $(APPLAUNCHERDIR)/libapplauncher.so

all: $(APPLAUNCHER)

$(APPLAUNCHER):
	scons -C $(APPLAUNCHERDIR)

install:
	mkdir -p $(DESTDIR)/usr/share/core-tweaks
	install -m 644 mozilla.tar.bz2 $(DESTDIR)/usr/share/core-tweaks/mozilla.tar.bz2
	install -m 755 $(APPLAUNCHER)  $(DESTDIR)/usr/share/core-tweaks/
	install -m 644 $(APPLAUNCHERDIR)/index.html  $(DESTDIR)/usr/share/core-tweaks/

clean:
	find nixysa/ -name "*.so" -delete
	find nixysa/ -name "*.os" -delete
	find nixysa/ -name "*.out" -delete
	rm -rf $(APPLAUNCHERDIR)/glue $(APPLAUNCHERDIR)/.sconsign.dblite

distclean: clean

package:
	dpkg-buildpackage -rfakeroot -b -tc || true
