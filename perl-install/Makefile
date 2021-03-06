include ../Makefile.config
include Makefile.config

PACKAGE = drakxtools
PKGVERSION = $(VERSION)

POFILES   = $(shell ls share/po/*.po)
MOFILES   = $(POFILES:%.po=%.mo)
OTHERS     = $(OTHERDIRS) $(OTHERFILES)
OTHERDIRS  = tools/serial_probe
OTHERFILES = tools/rpcinfo-flushed.c

.PHONY: all $(DIRS) install clean

all: TAGS $(DIRS)

xs: $(DIRS)

TAGS: $(ALLPMS)
	-etags $^ /usr/lib/perl5/*/*/MDK/Common/*.pm

clean:
	for i in $(DIRS) share/po install/help/po install/share/po; do $(MAKE) -C $$i clean; done;:
	rm -rf auto drakxtools*.tar* *.bak
	find . -name "*~" -o -name ".#*" -o -name "TAGS" -o -name "*.old" | xargs rm -f
	rm -rf $(PACKAGE)-$(PKGVERSION)*

check_pms_encoding:
	@for i in $(ALLPMS); do charset=ascii; grep -q 'use utf8' $$i && charset=utf8; iconv -f $$charset -t $$charset $$i >/dev/null || { echo "bad $$charset character in $$i"; exit 1; }; done

check_full: check_pms_encoding
	perl -I. -Mlang -e 'lang::check'

check2:
	perl -I. -Mkeyboard -e 'keyboard::check'

$(DIRS):
	install -d auto
	$(MAKE) -C $@

test_pms:
	perl_checker install/install2.pm install/steps_gtk.pm install/steps_stdio.pm partition_table/*.pm standalone/{harddrake2,diskdrake,draksec}

test_pms_all:
	perl_checker -v --generate-package-dependencies-graph .deps $(ALLPMS)

%.mo: %.po
	msgfmt -o $@ $<

install_pms stage2 full_stage2:
	make -C install $@

mo_files : $(MOFILES)

# rules to build tarball
dist: tar

tar: clean
	rm -rf $(PACKAGE)*.tar* $(PACKAGE)-$(PKGVERSION)
	mkdir -p $(PACKAGE)-$(PKGVERSION)/tools
	(cd ..; git archive HEAD "perl-install/" $(OTHERS) kernel/list_modules.pm Makefile.config) | tar xC $(PACKAGE)-$(PKGVERSION)
	rm -rf $(PACKAGE)-$(PKGVERSION)/perl-install/{install,unused,list_modules.pm}
	cp -f ../kernel/list_modules.pm $(PACKAGE)-$(PKGVERSION)/perl-install
	cd $(PACKAGE)-$(PKGVERSION)/perl-install ; mv -f Makefile.drakxtools Makefile
	@make nuke_perl
	tar cfa $(PACKAGE)-$(PKGVERSION).tar.xz $(PACKAGE)-$(PKGVERSION)
	rm -rf $(PACKAGE)-$(PKGVERSION)
	$(info $(PACKAGE)-$(PKGVERSION).tar.xz is ready)

tag:
	git tag $(VERSION)

# rules to build a distributable rpm

nuke_perl:
	find $(PACKAGE)-$(PKGVERSION)/perl-install -name '*.pm' | xargs ../tools/simplify-drakx-modules
	find $(PACKAGE)-$(PKGVERSION)/perl-install/standalone -type f | xargs ../tools/simplify-drakx-modules

# [pixel] for my grep looking for any .pm files
pixel_standalone_links:
	rm -rf .standalone_apps.swa
	mkdir .standalone_apps.swa
	for i in $(STANDALONEPMS_); do ln -sf ../standalone/$$i .standalone_apps.swa/$$i.pm; done

check_perl_checker:
	rm -f share/po/libDrakX.pot install/share/po/DrakX.pot
	@make -C share/po libDrakX.pot
	@make -C install/share/po DrakX.pot

list_firmwares.pm:
	../tools/find-drivers-needing-nonfree-firmware

.PHONY: list_firmwares.pm
