use Config;

print '
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include <ctype.h>
#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>
#include <syslog.h>
#include <fcntl.h>
#include <resolv.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <sys/ioctl.h>
#include <sys/time.h>
#include <sys/resource.h>
#include <sys/stat.h>
#include <sys/utsname.h>
#include <sys/mount.h>
#undef __USE_MISC
#include <linux/if.h>
#include <linux/wireless.h>
#include <linux/keyboard.h>
#include <linux/kd.h>
#include <linux/hdreg.h>
#include <linux/vt.h>
#include <linux/fd.h>
#include <linux/cdrom.h>
#include <linux/loop.h>
#include <linux/blkpg.h>
#include <linux/iso_fs.h>
#include <net/if.h>
#include <net/route.h>
#include <netinet/in.h>
#include <linux/sockios.h>
#include <linux/ethtool.h>
#include <linux/input.h>
#include <execinfo.h>

// for UPS on USB:
# define HID_MAX_USAGES 1024
#include <linux/hiddev.h>

#include <libldetect.h>

#include <string.h>

#define SECTORSIZE 512

#include <parted/parted.h>
';

$Config{archname} =~ /i.86/ and print '
char *pcmcia_probe(void);
';

print '

/* log_message and log_perror are used in stage1 pcmcia probe */
void log_message(const char * s, ...) {
   va_list args;
   va_list args_copy;
   FILE * logtty = fopen("/dev/tty3", "w");
   if (!logtty)
      return;
   fprintf(logtty, "* ");
   va_start(args, s);
   vfprintf(logtty, s, args);
   fprintf(logtty, "\n");
   fclose(logtty);
   va_end(args);

   logtty = fopen("/tmp/ddebug.log", "a");
   if (!logtty)
      return;
   fprintf(logtty, "* ");
   va_copy(args_copy, args);
   va_start(args_copy, s);
   vfprintf(logtty, s, args_copy);
   fprintf(logtty, "\n");
   fclose(logtty);
   va_end(args_copy);
}
void log_perror(const char *msg) {
   log_message("%s: %s", msg, strerror(errno));
}

HV* common_pciusb_hash_init(struct pciusb_entry *e) {
   HV *rh = (HV *)sv_2mortal((SV *)newHV()); 
   hv_store(rh, "vendor",         6, newSViv(e->vendor),     0);
   hv_store(rh, "subvendor",      9, newSViv(e->subvendor),  0);
   hv_store(rh, "id",             2, newSViv(e->device),     0);
   hv_store(rh, "subid",          5, newSViv(e->subdevice),  0);
   hv_store(rh, "driver",         6, newSVpv(e->module ? e->module : "unknown", 0), 0);
   hv_store(rh, "description",   11, newSVpv(e->text, 0),    0); 
   hv_store(rh, "pci_bus",        7, newSViv(e->pci_bus),    0);
   hv_store(rh, "pci_device",    10, newSViv(e->pci_device), 0);
   return rh;
}

';

print '

int length_of_space_padded(char *str, int len) {
  while (len >= 0 && str[len-1] == \' \')
    --len;
  return len;
}

PedPartitionFlag string_to_pedpartflag(char*type) {
   PedPartitionFlag flag = 0;
   if (!strcmp(type, "ESP")) {
      flag = PED_PARTITION_ESP;
   } else if (!strcmp(type, "BIOS_GRUB")) {
      flag = PED_PARTITION_BIOS_GRUB;
   } else if (!strcmp(type, "LVM")) {
      flag = PED_PARTITION_LVM;
   } else if (!strcmp(type, "RAID")) {
      flag = PED_PARTITION_RAID;
   } else {
      printf("set_partition_flag: unknown type: %s\n", type);
   }
   return flag;
}

int is_recovery_partition(PedPartition*part) {
  /* FIXME: not sure everything is covered ... */
  return ped_partition_get_flag(part, PED_PARTITION_HPSERVICE) // HP-UX service partition
      || ped_partition_get_flag(part, PED_PARTITION_MSFT_RESERVED) // Microsoft Reserved Partition -> LDM metadata, ...
      || ped_partition_get_flag(part, PED_PARTITION_DIAG) // ==> PARTITION_MSFT_RECOVERY (Windows Recovery Environment)
      || ped_partition_get_flag(part, PED_PARTITION_APPLE_TV_RECOVERY)
      || ped_partition_get_flag(part, PED_PARTITION_HIDDEN);
}

MODULE = c::stuff		PACKAGE = c::stuff

';

$Config{archname} =~ /i.86/ and print '
char *
pcmcia_probe()
';

print '
int
del_partition(hd, part_number)
  int hd
  int part_number
  CODE:
  {
    struct blkpg_partition p = { 0, 0, part_number, "", "" };
    struct blkpg_ioctl_arg s = { BLKPG_DEL_PARTITION, 0, sizeof(struct blkpg_partition), (void *) &p };
    RETVAL = ioctl(hd, BLKPG, &s) == 0;
  }
  OUTPUT:
  RETVAL

int
add_partition(hd, part_number, start_sector, size_sector)
  int hd
  int part_number
  unsigned long start_sector
  unsigned long size_sector
  CODE:
  {
    long long start = (long long) start_sector * 512;
    long long size = (long long) size_sector * 512;
    struct blkpg_partition p = { start, size, part_number, "", "" };
    struct blkpg_ioctl_arg s = { BLKPG_ADD_PARTITION, 0, sizeof(struct blkpg_partition), (void *) &p };
    RETVAL = ioctl(hd, BLKPG, &s) == 0;
  }
  OUTPUT:
  RETVAL

int
is_secure_file(filename)
  char * filename
  CODE:
  {
    int fd;
    unlink(filename); /* in case it exists and we manage to remove it */
    RETVAL = (fd = open(filename, O_RDWR | O_CREAT | O_EXCL, 0600)) != -1;
    if (RETVAL) close(fd);
  }
  OUTPUT:
  RETVAL

void
init_setlocale()
   CODE:
   setlocale(LC_ALL, "");
   setlocale(LC_NUMERIC, "C"); /* otherwise eval "1.5" returns 1 in fr_FR for example */

char *
setlocale(category, locale = NULL)
    int     category
    char *      locale

int
lseek_sector(fd, sector, offset)
  int fd
  unsigned long sector
  long offset
  CODE:
  RETVAL = lseek64(fd, (off64_t) sector * SECTORSIZE + offset, SEEK_SET) >= 0;
  OUTPUT:
  RETVAL

int
isBurner(fd)
  int fd
  CODE:
  RETVAL = ioctl(fd, CDROM_GET_CAPABILITY) & CDC_CD_RW;
  OUTPUT:
  RETVAL

int
isDvdDrive(fd)
  int fd
  CODE:
  RETVAL = ioctl(fd, CDROM_GET_CAPABILITY) & CDC_DVD;
  OUTPUT:
  RETVAL

char *
floppy_info(name)
  char * name
  CODE:
  int fd = open(name, O_RDONLY | O_NONBLOCK);
  RETVAL = NULL;
  if (fd != -1) {
     char drivtyp[17];
     if (ioctl(fd, FDGETDRVTYP, (void *)drivtyp) == 0) {
       struct floppy_drive_struct ds;
       if (ioctl(fd, FDPOLLDRVSTAT, &ds) == 0 && ds.track >= 0)
         RETVAL = drivtyp;
     }
     close(fd);
  }
  OUTPUT:
  RETVAL

NV
total_sectors(fd)
  int fd
  CODE:
  {
    unsigned long long ll;
    unsigned long l;
    RETVAL = ioctl(fd, BLKGETSIZE64, &ll) == 0 ? ll / 512 : 
             ioctl(fd, BLKGETSIZE, &l) == 0 ? l : 0;
  }
  OUTPUT:
  RETVAL

void
openlog(ident)
  char *ident
  CODE:
  openlog(ident, 0, 0);

void
closelog()

void
syslog(priority, mesg)
  int priority
  char *mesg
  CODE:
  syslog(priority, "%s", mesg);

void
setsid()

void
_exit(status)
  int status

void
usleep(microseconds)
  unsigned long microseconds


char*
get_pci_description(int vendor_id,int device_id)

void
hid_probe()
  PPCODE:
    struct hid_entries entries = hid_probe();
    int i;

    EXTEND(SP, entries.nb);
    for (i = 0; i < entries.nb; i++) {
      struct hid_entry *e = &entries.entries[i];
      HV *rh = (HV *)sv_2mortal((SV *)newHV());
      hv_store(rh, "description", 11, newSVpv(e->text, 0),   0);
      hv_store(rh, "driver",       6, newSVpv(e->module, 0), 0);
      PUSHs(newRV((SV *)rh));
    }
    hid_entries_free(&entries);

void
pci_probe()
  PPCODE:
    struct pciusb_entries entries = pci_probe();
    int i;

    EXTEND(SP, entries.nb);
    for (i = 0; i < entries.nb; i++) {
      struct pciusb_entry *e = &entries.entries[i];
      HV * rh = common_pciusb_hash_init(e);
      hv_store(rh, "pci_domain",    10, newSViv(e->pci_domain),      0);
      hv_store(rh, "pci_function",  12, newSViv(e->pci_function),    0);
      hv_store(rh, "pci_revision",  12, newSViv(e->pci_revision),    0);
      hv_store(rh, "is_pciexpress", 13, newSViv(e->is_pciexpress),   0);
      hv_store(rh, "nice_media_type", 15, newSVpv(e->class, 0),      0);
      hv_store(rh, "media_type",    10, newSVpv(pci_class2text(e->class_id), 0), 0); 
      PUSHs(newRV((SV *)rh));
    }
    pciusb_free(&entries);

void
usb_probe()
  PPCODE:
    struct pciusb_entries entries = usb_probe();
    char buf[2048];
    int i;

    EXTEND(SP, entries.nb);
    for (i = 0; i < entries.nb; i++) {
      struct pciusb_entry *e = &entries.entries[i];
      struct usb_class_text class_text = usb_class2text(e->class_id);
      snprintf(buf, sizeof(buf), "%s|%s|%s", class_text.usb_class_text, class_text.usb_sub_text, class_text.usb_prot_text);
      HV * rh = common_pciusb_hash_init(e);
      hv_store(rh, "usb_port",       8, newSViv(e->usb_port),   0);
      hv_store(rh, "media_type",    10, newSVpv(buf, 0),        0);
      PUSHs(newRV((SV *)rh));
    }
    pciusb_free(&entries);

void
dmi_probe()
  PPCODE:
    //dmidecode_file = "/usr/share/ldetect-lst/dmidecode.Laptop.Dell-Latitude-C810";
    //dmidecode_file = "../../soft/ldetect-lst/test/dmidecode.Laptop.Sony-Vaio-GRX316MP";

    struct dmi_entries entries = dmi_probe();
    int i;

    EXTEND(SP, entries.nb);
    for (i = 0; i < entries.nb; i++) {
      HV * rh = (HV *)sv_2mortal((SV *)newHV()); 
      hv_store(rh, "driver",       6, newSVpv(entries.entries[i].module, 0),     0); 
      hv_store(rh, "description", 11, newSVpv(entries.entries[i].constraints, 0),  0); 
      PUSHs(newRV((SV *)rh));
    }
    dmi_entries_free(entries);


unsigned int
getpagesize()


char*
get_usb_ups_name(int fd)
  CODE:
        /* from nut/drivers/hidups.c::upsdrv_initups() : */
        char name[256];
        ioctl(fd, HIDIOCGNAME(sizeof(name)), name);
        RETVAL=name;
        ioctl(fd, HIDIOCINITREPORT, 0);
  OUTPUT:
  RETVAL


int
res_init()

int
isNetDeviceWirelessAware(device)
  char * device
  CODE:
    struct iwreq ifr;

    int s = socket(AF_INET, SOCK_DGRAM, 0);

    memset(&ifr, 0, sizeof(ifr));
    strncpy(ifr.ifr_name, device, IFNAMSIZ);
    RETVAL = ioctl(s, SIOCGIWNAME, &ifr) != -1;
    close(s);
  OUTPUT:
  RETVAL


void
get_netdevices()
  PPCODE:
     struct ifconf ifc;
     struct ifreq *ifr;
     int i;
     int numreqs = 10;

     int s = socket(AF_INET, SOCK_DGRAM, 0);

     ifc.ifc_buf = NULL;
     for (;;) {
          ifc.ifc_len = sizeof(struct ifreq) * numreqs;
          ifc.ifc_buf = realloc(ifc.ifc_buf, ifc.ifc_len);

          if (ioctl(s, SIOCGIFCONF, &ifc) < 0) {
               perror("SIOCGIFCONF");
               close(s);
               return;
          }
          if (ifc.ifc_len == sizeof(struct ifreq) * numreqs) {
               /* assume it overflowed and try again */
               numreqs += 10;                                                                         
               continue;                                                                              
          }
          break;
     }
     if (ifc.ifc_len) {
          ifr = ifc.ifc_req;
          EXTEND(sp, ifc.ifc_len);
          for (i=0; i < ifc.ifc_len; i+= sizeof(struct ifreq)) {
               PUSHs(sv_2mortal(newSVpv(ifr->ifr_name, 0)));
               ifr++;
          }
     }

     close(s);


char*
getNetDriver(char* device)
  ALIAS:
    getHwIDs = 1
  CODE:
    struct ifreq ifr;
    struct ethtool_drvinfo drvinfo;
    int s = socket(AF_INET, SOCK_DGRAM, 0);

    memset(&ifr, 0, sizeof(ifr));
    strncpy(ifr.ifr_name, device, IFNAMSIZ);

    drvinfo.cmd = ETHTOOL_GDRVINFO;
    ifr.ifr_data = (caddr_t) &drvinfo;

    if (ioctl(s, SIOCETHTOOL, &ifr) != -1) {
        switch (ix) {
            case 0:
                RETVAL = strdup(drvinfo.driver);
                break;
            case 1:
                RETVAL = strdup(drvinfo.bus_info);
                break;
        }
    } else { perror("SIOCETHTOOL"); RETVAL = strdup(""); }
    close(s);
  OUTPUT:
  RETVAL


int
addDefaultRoute(gateway)
  char *gateway
  CODE:
    struct rtentry route;
    struct sockaddr_in addr;
    int s = socket(AF_INET, SOCK_DGRAM, 0);
    if (s == -1) { RETVAL = 0; return; }

    memset(&route, 0, sizeof(route));

    addr.sin_family = AF_INET;
    addr.sin_port = 0;
    inet_aton(gateway, &addr.sin_addr);
    memcpy(&route.rt_gateway, &addr, sizeof(addr));

    addr.sin_addr.s_addr = INADDR_ANY;
    memcpy(&route.rt_dst, &addr, sizeof(addr));
    memcpy(&route.rt_genmask, &addr, sizeof(addr));

    route.rt_flags = RTF_UP | RTF_GATEWAY;
    route.rt_metric = 0;

    RETVAL = !ioctl(s, SIOCADDRT, &route);
  OUTPUT:
  RETVAL


char*
get_hw_address(const char* ifname)
  CODE:
    int s;
    struct ifreq ifr;
    unsigned char *a;
    char *res;
    s = socket(AF_INET, SOCK_DGRAM, IPPROTO_IP);
    if (s < 0) {
        perror("socket");
        RETVAL = NULL;
        return;
    }
    strncpy((char*) &ifr.ifr_name, ifname, IFNAMSIZ);
    if (ioctl(s, SIOCGIFHWADDR, &ifr) < 0) {
        perror("ioctl(SIOCGIFHWADDR)");
        RETVAL = NULL;
        return;
    }
    a = (unsigned char*)ifr.ifr_hwaddr.sa_data;
    asprintf(&res, "%02x:%02x:%02x:%02x:%02x:%02x", a[0],a[1],a[2],a[3],a[4],a[5]);
    RETVAL= res;
  OUTPUT:
  RETVAL


void
strftime(fmt, sec, min, hour, mday, mon, year, wday = -1, yday = -1, isdst = -1)
    char *      fmt
    int     sec
    int     min
    int     hour
    int     mday
    int     mon
    int     year
    int     wday
    int     yday
    int     isdst
    CODE:
    {   
        char *buf = my_strftime(fmt, sec, min, hour, mday, mon, year, wday, yday, isdst);
        if (buf) {
        ST(0) = sv_2mortal(newSVpv(buf, 0));
        Safefree(buf);
        }
    }

#define BITS_PER_LONG (sizeof(long) * 8)
#define NBITS(x) ((((x)-1)/BITS_PER_LONG)+1)
#define OFF(x)  ((x)%BITS_PER_LONG)
#define BIT(x)  (1UL<<OFF(x))
#define LONG(x) ((x)/BITS_PER_LONG)
#define test_bit(bit, array)    ((array[LONG(bit)] >> OFF(bit)) & 1)

void
EVIocGBitKey (char *file)
	PPCODE:
		int fd;
		int i;
		long bitmask[NBITS(KEY_MAX)];

		fd = open (file, O_RDONLY);
		if (fd < 0) {
			warn("Cannot open %s: %s\n", file, strerror(errno));
			return;
		}

		if (ioctl (fd, EVIOCGBIT(EV_KEY, sizeof (bitmask)), bitmask) < 0) {
			perror ("ioctl EVIOCGBIT failed");
			close (fd);
			return;
		}

		close (fd);
        	for (i = NBITS(KEY_MAX) - 1; i > 0; i--)
			if (bitmask[i])
				break;

		for (; i >= 0; i--) {
			EXTEND(sp, 1);
			PUSHs(sv_2mortal(newSViv(bitmask[i])));
		}

char *
kernel_version()
  CODE:
  struct utsname u;
  if (uname(&u) == 0) RETVAL = u.release; else RETVAL = NULL;
  OUTPUT:
  RETVAL

void
set_tagged_utf8(s)
   SV *s
   CODE:
   SvUTF8_on(s);

void
get_iso_volume_ids(int fd)
  INIT:
  struct iso_primary_descriptor voldesc;
  PPCODE:
  lseek(fd, 16 * ISOFS_BLOCK_SIZE, SEEK_SET);
  if (read(fd, &voldesc, sizeof(struct iso_primary_descriptor)) == sizeof(struct iso_primary_descriptor)) {
    if (voldesc.type[0] == ISO_VD_PRIMARY && !strncmp(voldesc.id, ISO_STANDARD_ID, sizeof(voldesc.id))) {
      size_t vol_id_len = length_of_space_padded(voldesc.volume_id, sizeof(voldesc.volume_id));
      size_t app_id_len = length_of_space_padded(voldesc.application_id, sizeof(voldesc.application_id));
      XPUSHs(vol_id_len != -1 ? sv_2mortal(newSVpv(voldesc.volume_id, vol_id_len)) : newSVpvs(""));
      XPUSHs(app_id_len != -1 ? sv_2mortal(newSVpv(voldesc.application_id, app_id_len)) : newSVpvs(""));
    }
  }

';

print '

TYPEMAP: <<HERE
PedDisk*              T_PTROBJ
HERE



int
set_partition_flag(PedDisk *disk, int part_number, char * type)
  CODE:
  RETVAL = 0;
  PedPartition* part = ped_disk_get_partition(disk, part_number);
  if (!part) {
    printf("set_partition_flag: failed to find partition\n");
  } else {
    PedPartitionFlag flag = string_to_pedpartflag(type);
    if (flag) {
      RETVAL = ped_partition_set_flag(part, flag, 1);
    }
  }
  OUTPUT:
  RETVAL


const char *
get_disk_type(char * device_path)
  CODE:
  PedDevice *dev = ped_device_get(device_path);
  RETVAL = NULL;
  if(dev) {
    PedDiskType* type = ped_disk_probe(dev);
    if(type) {
      RETVAL = type->name;
    } 
  }
  OUTPUT:
  RETVAL

void
get_disk_partitions(char * device_path)
  PPCODE:
  PedDevice *dev = ped_device_get(device_path);
  if(dev) {
    PedDisk* disk = ped_disk_new(dev);
    PedPartition *part = NULL, *first_part = NULL;
    int count = 1;
    if(!disk)
      return;
    first_part = part = ped_disk_next_partition(disk, NULL);
    while(part) {
      part = ped_disk_next_partition(disk, part);
      count++;
    }
    EXTEND(SP, count);
    part = first_part;
    while(part) {
      if(part->num == -1) {
	   part = ped_disk_next_partition(disk, part);
	   continue;
      }
      char *path = ped_partition_get_path(part);
      char *flag = "";
      if (ped_partition_get_flag(part, PED_PARTITION_ESP)) {
        flag = "ESP";
      } else if (ped_partition_get_flag(part, PED_PARTITION_BIOS_GRUB)) {
        flag = "BIOS_GRUB";
      } else if (ped_partition_get_flag(part, PED_PARTITION_LVM)) {
        flag = "LVM";
      } else if (ped_partition_get_flag(part, PED_PARTITION_RAID)) {
        flag = "RAID";
      } else if (is_recovery_partition(part)) {
        flag = "RECOVERY";
      }
      HV * rh = (HV *)sv_2mortal((SV *)newHV());
      hv_store(rh, "part_number",    11, newSViv(part->num),      0);
      hv_store(rh, "real_device",    11, newSVpv(path, 0),        0);
      hv_store(rh, "start",           5, newSViv(part->geom.start), 0);
      hv_store(rh, "size",            4, newSViv(part->geom.length), 0);
      hv_store(rh, "pt_type",         7, newSViv(0xba),           0);
      hv_store(rh, "flag",            4, newSVpv(flag, 0),        0);
      free(path);
      if(part->fs_type)
        hv_store(rh, "fs_type",       7, newSVpv(part->fs_type->name, 0), 0);
      PUSHs(newRV((SV *)rh));
      part = ped_disk_next_partition(disk, part);
    }
    ped_disk_destroy(disk);
  }

PedDisk*
disk_open(char * device_path, const char * type_name = NULL)
  CODE:
  PedDevice *dev = ped_device_get(device_path);
  RETVAL = NULL;
  if(dev) {
    if(type_name) {
      PedDiskType* type = ped_disk_type_get(type_name);
      if(type) {
        RETVAL = ped_disk_new_fresh(dev, type);
      }
    } else {
      RETVAL = ped_disk_new(dev);
    }
  }
  OUTPUT:
  RETVAL

int
disk_delete_all(PedDisk* disk)
  CODE:
  RETVAL = 0;
  if (ped_disk_delete_all(disk)) {
    RETVAL = 1;
  }
  OUTPUT:
  RETVAL

int
disk_del_partition(PedDisk* disk, int part_number)
  CODE:
  RETVAL = 0;
  PedPartition* part = ped_disk_get_partition(disk, part_number);
  if(!part) {
    printf("disk_del_partition: failed to find partition\n");
  } else {
    RETVAL = ped_disk_delete_partition(disk, part);
  }
  OUTPUT:
  RETVAL

int
disk_add_partition(PedDisk* disk, double start, double length, const char * fs_type)
  CODE:
  RETVAL=0;
  PedGeometry* geom = ped_geometry_new(disk->dev, (long long)start, (long long)length);
  PedPartition* part = ped_partition_new (disk, PED_PARTITION_NORMAL, ped_file_system_type_get(fs_type), (long long)start, (long long)start+length-1);
  PedConstraint* constraint = ped_constraint_new_from_max(geom);
  if(!part) {
    printf("ped_partition_new failed\n");
  } else {
    RETVAL = ped_disk_add_partition (disk, part, constraint);
  }
  ped_geometry_destroy(geom);
  ped_constraint_destroy(constraint);
  OUTPUT:
  RETVAL

int
disk_commit(PedDisk *disk)
  CODE:
  RETVAL = 0;
  /* As done in ped_disk_commit(), open the device here, so that the underlying
     file descriptor is not closed between the call to ped_disk_commit_to_dev()
     and the call to ped_disk_commit_to_os(). This avoids unwanted udev events. */
  if (ped_device_open(disk->dev)) {
    if (ped_disk_commit_to_dev(disk)) {
      RETVAL = 1;
      if (ped_disk_commit_to_os(disk)) {
        RETVAL = 2;
      }
    }
    ped_device_close(disk->dev);
  }
  ped_disk_destroy(disk);
  OUTPUT:
  RETVAL

int
tell_kernel_to_reread_partition_table(char * device_path)
  CODE:
  PedDevice *dev = ped_device_get(device_path);
  RETVAL=0;
  if(dev) {
    PedDisk* disk = ped_disk_new(dev);
    if (disk) {
      if (ped_disk_commit_to_os (disk))
         RETVAL=1;
      ped_disk_destroy(disk);
    }
  }
  OUTPUT:
  RETVAL

#define BACKTRACE_DEPTH				20
 

char*
C_backtrace()
  CODE:
  static char buf[1024];
  int nAddresses, i;
  unsigned long idx = 0;
  void * addresses[BACKTRACE_DEPTH];
  char ** symbols = NULL;
  nAddresses = backtrace(addresses, BACKTRACE_DEPTH);
  symbols = backtrace_symbols(addresses, nAddresses);
  if (symbols == NULL) {
      idx += sprintf(buf+idx, "ERROR: Retrieving symbols failed.\n");
  } else {
      /* dump stack trace */
      for (i = 0; i < nAddresses; ++i)
          idx += sprintf(buf+idx, "%d: %s\n", i, symbols[i]);
  }
  RETVAL = strdup(buf);
  OUTPUT:
  RETVAL




';

@macros = (
  [ qw(int S_IFCHR S_IFBLK S_IFIFO S_IFMT KDSKBENT K_NOSUCHMAP NR_KEYS MAX_NR_KEYMAPS BLKRRPART TIOCSCTTY
       HDIO_GETGEO LOOP_GET_STATUS
       MS_MGC_VAL O_WRONLY O_RDWR O_CREAT O_NONBLOCK F_SETFL F_GETFL WNOHANG
       VT_ACTIVATE VT_WAITACTIVE VT_GETSTATE
       CDROMEJECT CDROMCLOSETRAY CDROM_LOCKDOOR
       LOG_WARNING LOG_INFO LOG_LOCAL1
       LC_COLLATE
       ) ],
);

$\= "\n";
print;

foreach (@macros) {
    my ($type, @l) = @$_;
    foreach (@l) {
	print<< "END"
$type
$_()
  CODE:
  RETVAL = $_;

  OUTPUT:
  RETVAL

END

    }
}
print '

PROTOTYPES: DISABLE
';
