NAME = DrakX
LOCALEDIR = ${prefix}/share/locale
METATASK = share/meta-task/compssUsers.pl
PMSFILES = *.pm $(METATASK) ../../advertising/*.pl
PMSFILES_HERE = $(wildcard $(PMSFILES:%=../../%))

MAIN_PO_FILES = ../../../share/po/libDrakX.pot

POFILES = $(wildcard *.po)
MOFILES = $(POFILES:%.po=%.mo)
LANGS = $(POFILES:%.po=%)

default: $(MOFILES)

%.mo: %.po
	msgfmt -o $@ $<

update_n_merge: $(NAME).pot merge

merge: $(NAME).pot
	for n in $(POFILES); do \
	  echo "Merging $$n"; \
	  msgmerge $$n $(NAME).pot > "$$n"t ; \
	  mv -f "$$n"t $$n ; \
	done

../../$(METATASK):
	mkdir -p ../../share/meta-task
	svn cat svn://svn.mageia.org/svn/packages/cauldron/meta-task/current/SOURCES/compssUsers.pl > $@

$(NAME).pot: $(PMSFILES_HERE) ../../$(METATASK)
	cd ../.. ; perl_checker -q --generate-pot share/po/.$@ $(PMSFILES)
	xgettext $(MAIN_PO_FILES:%=-x %) -o $@ .$@
	rm -f .$@

install: $(MOFILES)
	for l in $(LANGS); do \
		install -d $(LOCALEDIR)/$$l/LC_MESSAGES; \
		install -m 644 $$l.mo $(LOCALEDIR)/$$l/LC_MESSAGES/$(NAME).mo; \
	done

clean:
	@rm -rf *.mo $(POFILES:%=%t) ../../$(METATASK)
	@rmdir ../../share/meta-task
