VERSION = 6
PRODUCT = drakx-installer-advertising

THEME = pwp
DESTDIR = $(ROOTDEST)/install/extra/advertising

install:
	rm -rf $(DESTDIR)
	install -d $(DESTDIR)
	install -m755 `cat list-$(THEME) | sed 's/png$$/pl/'` $(DESTDIR)
	install -m644 `cat list-$(THEME)` $(DESTDIR)
	install -m644 list-$(THEME) $(DESTDIR)/list

tar:
	git archive --prefix $(PRODUCT)-$(VERSION)/ HEAD | xz -9 > $(PRODUCT)-$(VERSION).tar.xz

clean:
	find . -name "*~" -o -name ".#*" | xargs rm -f
