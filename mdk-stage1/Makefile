 #******************************************************************************
 #
 #    mdk-stage1 - the program that will load second-stage install
 #
 # Pixel (pixel) (mostly done by Guillaume Cottenceau)
 #
 # Copyright 2000-2004 Mandriva
 #
 # This software may be freely redistributed under the terms of the GNU
 # public license.
 #
 # You should have received a copy of the GNU General Public License
 # along with this program; if not, write to the Free Software
 # Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

VERSION=2.27
PRODUCT=drakx-installer-binaries

 #
 # Portions from Erik Troan (ewt@redhat.com) Copyright 1996 Red Hat Software 
 #


top_dir = .

include $(top_dir)/Makefile.common
include $(top_dir)/../Makefile.config
ARCHDIR=$(ARCH)
ifeq (i386, $(ARCH))
ARCHDIR=i586
endif

DEFS = -DDISTRIB_NAME=\"$(DISTRIB_NAME)\" -DDISTRIB_VERSION=\"$(DISTRIB_VERSION)\" -DDISTRIB_TYPE=\"$(DISTRIB_TYPE)\" -DDISTRIB_DESCR=\"$(DISTRIB_DESCR)\" $(ADDITIONAL_DEFS) -D_FILE_OFFSET_BITS=64 -DARCH=\"$(ARCHDIR)\" -DCONFIG_USE_ZLIB

COMPILE = $(CC) $(DEFS) $(CFLAGS)

INITSRC = init.c

STAGE1_DEFS=-DDISABLE_KA

INITOBJS = $(INITSRC:.c=.o)


 #- frontends
NEWT_FRONTEND_SRC = newt-frontend.c
NEWT_FRONTEND_LIBS = -lnewt -lslang

STDIO_FRONTEND_SRC = stdio-frontend.c
STDIO_FRONTEND_LIBS =

FRONTEND_OBJS = $($(F)_FRONTEND_SRC:.c=.o)

FRONTEND_LINK = $(FRONTEND_OBJS) $($(F)_FRONTEND_LIBS)

STAGE1_OWN_LIBS = -lz -lldetect -lkmod -lpci -llzma -lsysfs


 #- stage1 itself
STAGE1SRC = stage1.c log.c utils.c params.c tools.c modules.c probing.c mount.c automatic.c frontend-common.c lomount.c thirdparty.c zlibsupport.c
CDROMSRC = cdrom.c
DISKSRC = disk.c directory.c partition.c
NETWORKSRC = network.c nfsmount.c dhcp.c url.c dns.c adsl.c directory.c wireless.c
#KASRC = ka.c

# use sort to remove duplicates
STAGE1_ALLSRC = $(sort $(STAGE1SRC) $(CDROMSRC) $(DISKSRC) $(NETWORKSRC) $(KASRC))
ALLSRC = $(INITSRC) $(STAGE1_ALLSRC)



CDROM_DEFS = -DSPAWN_SHELL -DDISABLE_DISK -DDISABLE_NETWORK


STAGE1OBJS-NETWORK = $(subst .c,-NETWORK.o,$(STAGE1SRC) $(NETWORKSRC))

NETWORK_DEFS = -DSPAWN_SHELL -DDISABLE_CDROM -DDISABLE_DISK -DDISABLE_KA


STAGE1OBJS-NETWORK-STANDALONE = $(subst .c,-NETWORK-STANDALONE.o,$(STAGE1SRC) $(NETWORKSRC))

NETWORK_STANDALONE_DEFS = -DDISABLE_CDROM -DDISABLE_DISK -DENABLE_NETWORK_STANDALONE -DDISABLE_KA


STAGE1OBJS-FULL = $(STAGE1_ALLSRC:.c=-FULL.o)

BINS = init stage1 dhcp-client rescue-gui probe-modules

OTHERS = pci-ids.h usb-ids.h
ifneq (,$(filter $(ARCH),i386 x86_64))
OTHERS += pcmcia-ids.h pcmcia
PCMCIA_LIB = pcmcia/libpcmcia.a
PCMCIA_DEFS = -DENABLE_PCMCIA
endif

USB_DEFS_GEN = -DENABLE_USB
USB_DEFS = -DENABLE_USB -DDISABLE_PCIADAPTERS

all: $(OTHERS) $(BINS)

pci-ids.h: /usr/share/ldetect-lst/pcitable.gz update-pci-ids.pl
	perl update-pci-ids.pl > $@ || { rm -f $@; exit 1; }

usb-ids.h: /usr/share/ldetect-lst/usbtable.gz update-usb-ids.pl
	perl update-usb-ids.pl > $@ || rm -f $@

pcmcia-ids.h: update-pcmcia-ids.pl
	perl update-pcmcia-ids.pl > $@ || { rm -f $@; exit 1; }

pcmcia/libpcmcia.a:
	make -j -C pcmcia

probing.c: pci-ids.h

init: $(INITOBJS)
	$(CC) $(LDFLAGS) -o $@ $^
	$(STRIPCMD) $@

stage1: $(STAGE1OBJS-FULL) $(STAGE1_OWN_LIBS) $(FRONTEND_LINK) $(PCMCIA_LIB)
	$(CC) $(LDFLAGS) -o $@ $^
	$(STRIPCMD) $@

dhcp-client: $(STAGE1OBJS-NETWORK-STANDALONE) $(STAGE1_OWN_LIBS) $(FRONTEND_LINK)
	$(CC) $(LDFLAGS) -o $@ $^
	$(STRIPCMD) $@


$(INITOBJS): %.o: %.c
	$(COMPILE) -c $<

$(STAGE1OBJS-NETWORK): %-NETWORK.o: %.c
	$(COMPILE) $(INCLUDES) $(NETWORK_DEFS) $(PCMCIA_DEFS) $(USB_DEFS_GEN) -DENABLE_ADDITIONAL_MODULES -c $< -o $@

$(STAGE1OBJS-NETWORK-STANDALONE): %-NETWORK-STANDALONE.o: %.c
	$(COMPILE) $(INCLUDES) $(NETWORK_STANDALONE_DEFS) $(USB_DEFS_GEN) -c $< -o $@

$(STAGE1OBJS-FULL): %-FULL.o: %.c
	$(COMPILE) $(INCLUDES) -DSPAWN_SHELL $(USB_DEFS_GEN) $(PCMCIA_DEFS) $(STAGE1_DEFS) -c $< -o $@

.c.o:
	$(COMPILE) $(INCLUDES) -c $<


clean: localclean
	@for n in $(DIRS); do \
		(cd $$n; make clean) \
	done

localclean:
	rm -f *.o .depend *.rdz *.img pci-ids.h pcmcia-ids.h usb-ids.h $(BINS)


rescue-gui: rescue-gui.o frontend-common.o params.o utils.o log.o automatic.o $(FRONTEND_LINK)
	$(CC) $(LDFLAGS) -o $@ $^
	$(STRIPCMD) $@

probe-modules: probe-modules.o probing-FULL.o modules-FULL.o params-FULL.o utils-FULL.o log-FULL.o automatic-FULL.o frontend-common-FULL.o stdio-frontend.o zlibsupport-FULL.o $(STAGE1_OWN_LIBS) $(PCMCIA_LIB)
	$(CC) $(LDFLAGS) -o $@ $^
	$(STRIPCMD) $@

dist: tar
tar:
	rm -rf $(PRODUCT)*.tar* $(PRODUCT)-$(VERSION)
	@cd ..; git archive --prefix=$(PRODUCT)-$(VERSION)/ HEAD mdk-stage1 kernel Makefile.config | xz >mdk-stage1/$(PRODUCT)-$(VERSION).tar.xz;
	$(info $(PRODUCT)-$(VERSION).tar.xz is ready)

.depend:
	$(CPP) $(CFLAGS) -M $(ALLSRC) > .depend

ifeq (.depend,$(wildcard .depend))
include .depend
endif


*-NETWORK.o: %-NETWORK.o: %.o

*-FULL.o: %-FULL.o: %.o

