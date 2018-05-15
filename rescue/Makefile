include ../Makefile.config

VERSION=1.57
PRODUCT=drakx-installer-rescue

RESCUE = rescue.sqfs

all: $(RESCUE)

install: $(RESCUE)
	cp -f $< $(STAGE2_DEST)

$(RESCUE): $(wildcard tree/**/*) $(wildcard bin/*) $(wildcard sbin/*) make_rescue_img list.xml aliases
	DISTRIB_DESCR=$(DISTRIB_DESCR) ./make_rescue_img

dist: tar

tar:
	rm -rf $(PRODUCT)*.tar* $(PRODUCT)-$(VERSION)
	@cd ..; git archive --prefix=$(PRODUCT)-$(VERSION)/ HEAD rescue tools/install-xml-file-list Makefile.config | xz >$(PRODUCT)-$(VERSION).tar.xz;
	$(info $(PRODUCT)-$(VERSION).tar.xz is ready)

clean: 
	rm -f $(RESCUE) kernel_read_part
