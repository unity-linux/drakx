include ../Makefile.config

VERSION=2.49
PRODUCT=drakx-installer-images
KERNELS=$(shell rpm -qf /lib/modules/4.*)

IMAGES_DEST = $(ROOTDEST)/install/images

all: images

boot.iso: images/boot.iso

images/boot.iso: all.kernels/.list make_boot_img
	DISTRIB_DESCR=$(DISTRIB_DESCR) DISTRIB_VERSION=$(DISTRIB_VERSION) ./make_boot_img images/boot.iso

all.img: images/all.img

images/all.img: all.kernels/.list make_boot_img
	DISTRIB_DESCR=$(DISTRIB_DESCR) DISTRIB_VERSION=$(DISTRIB_VERSION) ./make_boot_img images/all.img

images: all.kernels/.list
	DISTRIB_DESCR=$(DISTRIB_DESCR) DISTRIB_VERSION=$(DISTRIB_VERSION) ./make_boot_img
	rm -rf images/alternatives 
	if [ `ls images/*.img-* 2>/dev/null | wc -l` -gt 0 ]; then	\
	  mkdir images/alternatives; cd images/alternatives; mv ../*.img-* .; md5sum *.img-* > MD5SUM; sha512sum *.img-* > SHA512SUM; \
	fi
	cd images; md5sum *.{img,iso}* > MD5SUM; sha512sum *.{img,iso}* > SHA512SUM

all.kernels/.list: update_kernel
	./update_kernel $(KERNELS)

dist: tar
tar:
	@rm -rf $(PRODUCT)*.tar* $(PRODUCT)-$(VERSION)
	@cd ..; git archive --prefix=$(PRODUCT)-$(VERSION)/ HEAD images kernel Makefile.config | xz >images/$(PRODUCT)-$(VERSION).tar.xz;
	$(info $(PRODUCT)-$(VERSION).tar.xz is ready)

clean:
	rm -rf images isolinux all.kernels modules.description build
	find . -name "*~" -o -name ".#*" | xargs rm -f

install:
	install -d $(IMAGES_DEST)
	rm -rf $(IMAGES_DEST)/alternatives 
	cp -r images/* $(IMAGES_DEST)
    ifneq (,$(findstring $(ARCH), i386 x86_64))
	rm -rf $(ROOTDEST)/isolinux
	cp -af isolinux $(ROOTDEST)
    endif

.PHONY: boot.iso all.img install clean dist tar images
