include ../../Makefile.config
include ../Makefile.config

PRODUCT=drakx-installer-stage2

ROOTDEST = /export
STAGE2_DEST = $(ROOTDEST)/install/stage2
DEST = $(STAGE2_DEST)/live

REP4PMS     = /usr/lib/libDrakX
DESTREP4PMS = $(DEST)$(REP4PMS)

all: xs

clean xs:
	make -C .. $@

dist: tar

tar:
	rm -rf $(PRODUCT)*.tar* $(PRODUCT)-$(VERSION)
	mkdir -p $(PRODUCT)-$(VERSION)/perl-install/install/share/
	(cd ../..; git archive HEAD kernel perl-install tools Makefile.config) | tar xC $(PRODUCT)-$(VERSION)
	rm -fr $(PRODUCT)-$(VERSION)/perl-install/standalone/po
	svn export svn://svn.mageia.org/svn/packages/cauldron/meta-task/current/SOURCES $(PRODUCT)-$(VERSION)/perl-install/install/share/meta-task
	tar cfa $(PRODUCT)-$(VERSION).tar.xz $(PRODUCT)-$(VERSION)
	rm -rf $(PRODUCT)-$(VERSION)
	$(info $(PRODUCT)-$(VERSION).tar.xz is ready)

tag:
	git tag $(VERSION)

install:
	$(MAKE) full_stage2
	echo $(VERSION) > $(STAGE2_DEST)/VERSION

install_pms:
	[ -d $(DEST) ] || ../../tools/mdkinst_stage2_tool --uncompress $(STAGE2_DEST)

# commands implemented in perl:
	for i in `perl -ne 's/sub (\w+?)_?(\(\))? \{.*/$$1/ and print' commands.pm` sync; do if [ ! -x $(DEST)/usr/bin/$$i ]; then ln -sf commands $(DEST)/usr/bin/$$i; fi; done

# install & clean perl modules:
	install -d $(DESTREP4PMS)
	cd .. ; for i in $(PMS); do \
		dest=$(DESTREP4PMS)/`dirname $$i`; \
		install -d $$dest; \
		perl -pe 's/#[-+].*//; $$_ = "\n" if (/^=(back|begin|head|item|over|pod)/ .. /^=cut/) || /use (diagnostics|strict|vars|warnings)/' $$i > $(DESTREP4PMS)/$$i; \
	done

	chmod a+x $(DESTREP4PMS)/install/install2
	chmod a+x $(DESTREP4PMS)/install/commands

get_needed_files: xs
# generate installer system:
	mkdir -p $(DEST)/{usr/,}{,s}bin
	for dir in /lib /lib64; do [[ -d $$dir ]] && mkdir -p $(DEST){,/usr}$$dir; done || :
	/usr/lib/dracut/modules.d/30convertfs/convertfs.sh $(DEST)
	REP4PMS=$(REP4PMS) ../../tools/install-xml-file-list share/list.xml $(DEST)
	chmod u-s -R $(DEST) # for mount/umount
	share/generate-xlocales $(DEST)

	../../tools/simplify-drakx-modules $(DEST)/usr/*/*/*/utf8_heavy.pl

	perl -I.. -Mlang -e 'symlink "UTF-8", "$(DEST)/usr/share/locale/$$_" foreach lang::list_langs()'

# various needed soft links (eg for ndiswrapper):
	perl -ane 'symlink "$$F[1]", "$(DEST)$$F[0]"' share/aliases
# default shell:
ifeq (ia64,$(ARCH))
	ln -sf bash $(DEST)/bin/sh
else
	ln -sf ash $(DEST)/bin/sh
endif

# X11 font caches:
	mkfontdir $(DEST)/usr/share/fonts
	fc-cache -f $(DEST)/usr/share/fonts

# drakx translations:
	$(MAKE) -C ../share/po install SUDO= LOCALEDIR=$(DEST)/usr/share/locale_special
	$(MAKE) -C help/po install SUDO= LOCALEDIR=$(DEST)/usr/share/locale_special
	$(MAKE) -C share/po install SUDO= LOCALEDIR=$(DEST)/usr/share/locale_special
# POFILES to disable for installation:
# be,fur: too few messages translated; 
# ta: font problem
	rm -rf $(DEST)/usr/share/locale_special/{be,fur,ta}

full_stage2:
	$(MAKE) stage2
	@if [ "$${DEBUG_INSTALL+xxx}" ]; then make dont_run_directly_stage2; else : ; fi
	$(MAKE) compress

compress:
	../../tools/mdkinst_stage2_tool --clean --compress $(STAGE2_DEST)

stage2:
	rm -rf $(DEST)
	mkdir -p $(DEST)/usr
	$(MAKE) get_needed_files 
	$(MAKE) install_pms

dont_run_directly_stage2:
	[ -d $(DEST) ] || ../../tools/mdkinst_stage2_tool --uncompress $(STAGE2_DEST)
	install -m 755 share/runinstall2.sh share/gdb-inst $(DEST)/usr/bin/
	[ -n $$DEBUG_INSTALL_LANG ] && perl -pi -e '$$_ = "loadkeys '$$DEBUG_INSTALL_LANG'\n$$_" if / sh/' $(DEST)/usr/bin/runinstall2.sh
	ln -sf runinstall2.sh $(DEST)/usr/bin/runinstall2

trace_stage2:
	[ -d $(DEST) ] || ../../tools/mdkinst_stage2_tool --uncompress $(STAGE2_DEST)
	f=`perldoc -l Devel::Trace`; install -m 644 -D $$f $(DEST)$$f
	perl -pi -e 's|(#!/usr/bin/perl).*|$$1 -d:Trace|' $(DEST)/usr/bin/runinstall2

# [pixel] after make install_pms:
# sudo sh -c 'CLEAN=1 perl ../../tools/drakx-in-chroot /export /tmp/rr --useless_thing_accepted --kickstart install/auto_inst.cfg.local.pl'
