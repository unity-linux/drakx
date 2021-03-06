/*
 * Guillaume Cottenceau (gc)
 *
 * Copyright 2000 Mandriva
 *
 * This software may be freely redistributed under the terms of the GNU
 * public license.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 *
 */

/*
 * Portions from Erik Troan (ewt@redhat.com)
 *
 * Copyright 1996 Red Hat Software 
 *
 */

#include <stdlib.h>
#include <unistd.h>
#include <stdio.h>
#include <dirent.h>
#include <string.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <sys/mount.h>
#include <linux/un.h>
#include <errno.h>
#include <signal.h>
#include <sys/resource.h>
#include <sys/wait.h>
#include <linux/unistd.h>
#include <sys/select.h>
#include <sys/ioctl.h>
#include <linux/reboot.h>

#include <sys/syscall.h>
#define syslog(...) syscall(__NR_syslog, __VA_ARGS__)

static unsigned int reboot_magic = LINUX_REBOOT_CMD_RESTART;

static inline long reboot(unsigned int command)
{
	return (long) syscall(__NR_reboot, LINUX_REBOOT_MAGIC1, LINUX_REBOOT_MAGIC2, command, 0);
}

#include "config-stage1.h"
#include <linux/cdrom.h>


#define BINARY_STAGE2 "/usr/bin/runinstall2"


char * env[] = {
	"PATH=/usr/bin:/bin:/sbin:/usr/sbin:/mnt/sbin:/mnt/usr/sbin:/mnt/bin:/mnt/usr/bin",
	"LD_LIBRARY_PATH=/lib:/usr/lib:/mnt/lib:/mnt/usr/lib"
#if defined(__x86_64__)
	":/lib64:/usr/lib64:/mnt/lib64:/mnt/usr/lib64"
#endif
	,
	"HOME=/",
	"TERM=linux",
	"TERMINFO=/etc/terminfo",
	"LC_CTYPE=UTF-8",
	NULL
};


/* 
 * this needs to handle the following cases:
 *
 *	1) run from a CD root filesystem
 *	2) run from a read only nfs rooted filesystem
 *      3) run from a floppy
 *	4) run from a floppy that's been loaded into a ramdisk 
 *
 */

int testing = 0;
int klog_pid;


void fatal_error(char *msg)
{
	printf("FATAL ERROR IN INIT: %s\n\nI can't recover from this, please reboot manually and send bugreport.\n", msg);
        select(0, NULL, NULL, NULL, NULL);
}

void print_error(char *msg)
{
	printf("E: %s\n", msg);
}

void print_warning(char *msg)
{
	printf("W: %s\n", msg);
}

void print_int_init(int fd, int i)
{
	char buf[10];
	char * chptr = buf + 9;
	int j = 0;

	if (i < 0)
	{
		write(1, "-", 1);
		i = -1 * i;
	}

	while (i)
	{
		*chptr-- = '0' + (i % 10);
		j++;
		i = i / 10;
	}

	write(fd, chptr + 1, j);
}

void print_str_init(int fd, char * string)
{
	write(fd, string, strlen(string));
}

/* fork to:
 *   (1) watch /proc/kmsg and copy the stuff to /dev/tty4
 *   (2) listens to /dev/log and copy also this stuff (log from programs)
 */
void doklog()
{
	fd_set readset, unixs;
	int in, out, i;
	int log;
	socklen_t s;
	int sock = -1;
	struct sockaddr_un sockaddr;
	char buf[1024];
	int readfd;

	/* open kernel message logger */
	in = open("/proc/kmsg", O_RDONLY,0);
	if (in < 0) {
		print_error("could not open /proc/kmsg");
		return;
	}

	if ((log = open("/tmp/syslog", O_WRONLY | O_CREAT | O_APPEND, 0644)) < 0) {
		print_error("error opening /tmp/syslog");
		sleep(5);
		return;
	}

	if ((klog_pid = fork())) {
		close(in);
		close(log);
		return;
	} else {
		close(0); 
		close(1);
		close(2);
	}

	out = open("/dev/tty4", O_WRONLY, 0);
	if (out < 0) 
		print_warning("couldn't open tty for syslog -- still using /tmp/syslog\n");

	/* now open the syslog socket */
// ############# LINUX 2.4 /dev/log IS BUGGED! --> apparently the syslogs can't reach me, and it's full up after a while
//	  sockaddr.sun_family = AF_UNIX;
//	  strncpy(sockaddr.sun_path, "/dev/log", UNIX_PATH_MAX);
//	  sock = socket(AF_UNIX, SOCK_STREAM, 0);
//	  if (sock < 0) {
//		  printf("error creating socket: %d\n", errno);
//		  sleep(5);
//	  }
//
//	  print_str_init(log, "] got socket\n");
//	  if (bind(sock, (struct sockaddr *) &sockaddr, sizeof(sockaddr.sun_family) + strlen(sockaddr.sun_path)))	{
//		  print_str_init(log, "] bind error: ");
//		  print_int_init(log, errno);
//		  print_str_init(log, "\n");
//		  sleep(//	  }
//
//	  print_str_init(log, "] bound socket\n");
//	  chmod("/dev/log", 0666);
//	  if (listen(sock, 5)) {
//		  print_str_init(log, "] listen error: ");
//		  print_int_init(log, errno);
//		  print_str_init(log, "\n");
//		  sleep(5);
//	  }

	/* disable on-console syslog output */
	syslog(8, NULL, 1);

	print_str_init(log, "] kernel/system logger ok\n");
	FD_ZERO(&unixs);
	while (1) {
		memcpy(&readset, &unixs, sizeof(unixs));

		if (sock >= 0)
			FD_SET(sock, &readset);
		FD_SET(in, &readset);

		i = select(20, &readset, NULL, NULL, NULL);
		if (i <= 0)
			continue;

		/* has /proc/kmsg things to tell us? */
		if (FD_ISSET(in, &readset)) {
			i = read(in, buf, sizeof(buf));
			if (i > 0) {
				if (out >= 0)
					write(out, buf, i);
				write(log, buf, i);
			}
		} 

		/* the socket has moved, new stuff to do */
		if (sock >= 0 && FD_ISSET(sock, &readset)) {
			s = sizeof(sockaddr);
			readfd = accept(sock, (struct sockaddr *) &sockaddr, &s);
			if (readfd < 0) {
				char * msg_error = "] error in accept\n";
				if (out >= 0)
					write(out, msg_error, strlen(msg_error));
				write(log, msg_error, strlen(msg_error));
				close(sock);
				sock = -1;
			}
			else
				FD_SET(readfd, &unixs);
		}
	}
}


#define LOOP_CLR_FD	0x4C01

void del_loops(void) 
{
        char loopdev[] = "/dev/loop0";
        char chloopdev[] = "/dev/chloop0";
        int i;
        for (i=0; i<8; i++) {
                int fd;
                loopdev[9] = '0' + i;
                fd = open(loopdev, O_RDONLY, 0);
                if (fd > 0) {
                        if (!ioctl(fd, LOOP_CLR_FD, 0))
                                printf("\t%s\n", loopdev);
                        close(fd);
                }
                chloopdev[11] = '0' + i;
                fd = open(chloopdev, O_RDONLY, 0);
                if (fd > 0) {
                        if (!ioctl(fd, LOOP_CLR_FD, 0))
                                printf("\t%s\n", chloopdev);
                        close(fd);
                }
        }
}

struct filesystem
{
	char * dev;
	char * name;
	char * fs;
	int mounted;
};

char* strcat(register char* s,register const char* t)
{
  char *dest=s;
  s+=strlen(s);
  for (;;) {
    if (!(*s = *t))
	break;
    ++s; ++t;
  }
  return dest;
}

/* attempt to unmount all filesystems in /proc/mounts */
void unmount_filesystems(void)
{
	int fd, size;
	char buf[65535];			/* this should be big enough */
	char *p;
	struct filesystem fs[500];
	int numfs = 0;
	int i, nb;

	printf("unmounting filesystems...\n"); 

	fd = open("/proc/mounts", O_RDONLY, 0);
	if (fd < 1) {
		print_error("failed to open /proc/mounts");
		sleep(2);
		return;
	}

	size = read(fd, buf, sizeof(buf) - 1);
	buf[size] = '\0';

	close(fd);

	p = buf;
	while (*p) {
		fs[numfs].mounted = 1;
		fs[numfs].dev = p;
		while (*p != ' ') p++;
		*p++ = '\0';
		fs[numfs].name = p;
		while (*p != ' ') p++;
		*p++ = '\0';
		fs[numfs].fs = p;
		while (*p != ' ') p++;
		*p++ = '\0';
		while (*p != '\n') p++;
		p++;
		if (strcmp(fs[numfs].name, "/")
                    && !strstr(fs[numfs].dev, "ram")
                    && strcmp(fs[numfs].name, "/dev")
                    && strcmp(fs[numfs].name, "/sys")
                    && strncmp(fs[numfs].name, "/proc", 5))
                        numfs++;
	}

	/* Pixel's ultra-optimized sorting algorithm:
	   multiple passes trying to umount everything until nothing moves
	   anymore (a.k.a holy shotgun method) */
	do {
		nb = 0;
		for (i = 0; i < numfs; i++) {
			/*printf("trying with %s\n", fs[i].name);*/
                        del_loops();
			if (fs[i].mounted && umount(fs[i].name) == 0) { 
				printf("\t%s\n", fs[i].name);
				fs[i].mounted = 0;
				nb++;
			}
		}
	} while (nb);

	for (i = nb = 0; i < numfs; i++)
		if (fs[i].mounted) {
			printf("\tumount failed: %s\n", fs[i].name);
			if (strcmp(fs[i].fs, "ext3") == 0) nb++; /* don't count not-ext3 umount failed */
		}


	if (nb) {
		printf("failed to umount some filesystems\n");
                select(0, NULL, NULL, NULL, NULL);
	}
}

int in_reboot(void)
{
        int fd;
        if ((fd = open("/var/run/rebootctl", O_RDONLY, 0)) > 0) {
                char buf[100];
                int i = read(fd, buf, sizeof(buf));
                close(fd);
                if (strstr(buf, "halt"))
                        reboot_magic = LINUX_REBOOT_CMD_POWER_OFF;
                return i > 0;
        }
        return 0;
}

int recursive_remove(char *file);
int recursive_remove(char *file)
{
	struct stat sb;

	if (lstat(file, &sb) != 0) {
		printf("failed to stat %s: %d\n", file, errno);
		return -1;
	}

	/* only descend into subdirectories if device is same as dir */
	if (S_ISDIR(sb.st_mode)) {
		char * strBuf = alloca(strlen(file) + 1024);
		DIR * dir;
		struct dirent * d;

		if (!(dir = opendir(file))) {
			printf("error opening %s: %d\n", file, errno);
			return -1;
		}
		while ((d = readdir(dir))) {
			if (!strcmp(d->d_name, ".") || !strcmp(d->d_name, ".."))
				continue;

			strcpy(strBuf, file);
			strcat(strBuf, "/");
			strcat(strBuf, d->d_name);

			if (recursive_remove(strBuf) != 0) {
				closedir(dir);
				return -1;
			}
		}
		closedir(dir);

		if (rmdir(file)) {
			printf("failed to rmdir %s: %d\n", file, errno);
			return -1;
		}
	} else {
		if (unlink(file) != 0) {
			printf("failed to remove %s: %d\n", file, errno);
			return -1;
		}
	}
	return 0;
}


int create_initial_fs_symlinks(char* symlinks)
{
        FILE *f;
        char buf[5000];

        if (!(f = fopen(symlinks, "rb"))) {
                printf("Error opening symlink definitions file '%s'\n", symlinks);
                return -1;
        }
        while (fgets(buf, sizeof(buf), f)) {
                char oldpath[500], newpath[500];
                struct stat sb;

                buf[strlen(buf)-1] = '\0';  // trim \n
                if (sscanf(buf, "%s %s", oldpath, newpath) != 2) {
                        sprintf(oldpath, "%s%s", STAGE2_LOCATION, buf);
                        sprintf(newpath, "%s", buf);
                }
                if (lstat(newpath, &sb) == 0)
                        recursive_remove(newpath);
                printf("Creating symlink %s -> %s\n", oldpath, newpath);
                if (symlink(oldpath, newpath)) {
                        printf("Error creating symlink\n");
                        return -1;
                }
        }
        fclose(f);
        return 0;
}


int exit_value_restart = 0x35;

int main(int argc, char **argv)
{
	pid_t installpid, childpid;
	int wait_status;
	int fd;
	int abnormal_termination = 0;

        if (argc > 1 && argv[1][0] >= '0' && argv[1][0] <= '9') {
                printf("This is no normal init, sorry.\n"
                       "Call `reboot' or `halt' directly.\n");
                return 0;
        }

	if (!testing) {
		/* turn off screen blanking */
		printf("\033[9;0]");
		printf("\033[8]");
	}
	else
		printf("*** TESTING MODE *** (pid is %d)\n", getpid());


	// needed for ldetect:
	if (!testing)
		if (mount("none", "/sys/kernel/debug", "debugfs", MS_NOSUID, "mode=0755"))
			fatal_error("Unable to mount debugfs filesystem");


	/* ignore Control-C and keyboard stop signals */
	signal(SIGINT, SIG_IGN);
	signal(SIGTSTP, SIG_IGN);

	if (!testing) {
		fd = open("/dev/console", O_RDWR, 0);
		if (fd < 0)
			fatal_error("failed to open /dev/console");

		dup2(fd, 0);
		dup2(fd, 1);
		dup2(fd, 2);
		close(fd);
	}


	/* I set me up as session leader (probably not necessary?) */
	setsid();
//	if (ioctl(0, TIOCSCTTY, NULL))
//		print_error("could not set new controlling tty");

	if (!testing) {
		char my_hostname[] = "localhost";
		sethostname(my_hostname, sizeof(my_hostname));
		/* the default domainname (as of 2.0.35) is "(none)", which confuses 
		   glibc */
		setdomainname("", 0);
	}

	if (!testing) 
		doklog();

	if (create_initial_fs_symlinks(STAGE2_LOCATION "/usr/share/symlinks") != 0)
		fatal_error("Fatal error finishing initialization (could not create symlinks).");

	/* kernel modules and firmware is needed by stage2, so move them to the root */
	if (rename("/usr/lib/modules", "/modules"))
		fatal_error("Cannot rename modules folder");

	if (rename("/usr/lib/firmware", "/firmware"))
		fatal_error("Cannot rename firmware folder");

	/* Add some symlinks so stage1 is still valid on it's own - not strictly needed */
	if (symlink("/modules", "/usr/lib/modules"))
		fatal_error("Cannot symlink modules folder");

	if (symlink("/firmware", "/usr/lib/firmware"))
		fatal_error("Cannot symlink firmware folder");

	if (mount(STAGE2_LOCATION "/usr", "/usr", "none", MS_BIND|MS_RDONLY, NULL))
		fatal_error("Unable to bind mount /usr filesystem from rescue or installer stage2");


	if (access("/run/drakx/run-init", R_OK) == 0) {
		/* This is typically used in rescue mode */
		char * child_argv[2] = { "/sbin/init", NULL };

		kill(klog_pid, 9);
		printf("proceeding, please wait...\n");
		execve(child_argv[0], child_argv, env);
		fatal_error("failed to exec /sbin/init");
	}

	/* This is installer mode */
	do {
		printf("proceeding, please wait...\n");

		if (!(installpid = fork())) {
			/* child */
			char * child_argv[2] = { BINARY_STAGE2, NULL };
			execve(child_argv[0], child_argv, env);
			printf("error in exec of %s :-( [%d]\n", child_argv[0], errno);
			return 0;
		}

		do {
			childpid = wait4(-1, &wait_status, 0, NULL);
		} while (childpid != installpid);
	} while (WIFEXITED(wait_status) && WEXITSTATUS(wait_status) == exit_value_restart);

	/* allow Ctrl Alt Del to reboot */
	reboot(LINUX_REBOOT_CMD_CAD_ON);

	if (in_reboot()) {
		// any exitcode is valid if we're in_reboot
	} else if (!WIFEXITED(wait_status) || WEXITSTATUS(wait_status) != 0) {
		printf("exited abnormally :-( ");
		if (WIFSIGNALED(wait_status))
			printf("-- received signal %d", WTERMSIG(wait_status));
		printf("\n");
	  	abnormal_termination = 1;
	}

        if (!abnormal_termination) {
                int i;
                for (i=0; i<50; i++)
                        printf("\n");  /* cleanup startkde messages */
        }

	if (testing)
		return 0;

	sync(); sync();
	sleep(2);

	printf("sending termination signals...");
	kill(-1, 15);
	sleep(2);
	printf("done\n");

	printf("sending kill signals...");
	kill(-1, 9);
	sleep(2);
	printf("done\n");

	unmount_filesystems();

	sync(); sync();

	if (!abnormal_termination) {
                if (reboot_magic == LINUX_REBOOT_CMD_RESTART) {
#ifdef DEBUG
                        printf("automatic reboot in 10 seconds\n");
                        sleep(10);
#endif
                        reboot(reboot_magic);
                } else {
                        printf("you may safely poweroff your computer now\n");
                }
	} else {
		printf("you may safely reboot or halt your system\n");
	}

        select(0, NULL, NULL, NULL, NULL);
	return 0;
}
