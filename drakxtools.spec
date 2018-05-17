%define perl_version %(perl -MConfig -e 'print $Config{version}')

Summary: The drakxtools (diskdrake, ...)
Name:    drakxtools
Version: 17.96
Release: 3%{?dist}
Url:     http://mageia.org/
# The source can be found at its git repository on:
# * http://gitweb.mageia.org/software/drakx/
# * git://git.mageia.org/software/drakx/
Source0: %name-%version.tar.xz
Source1: gqdnf.sh
#NO PATCH ALLOWED (testing exception)
Patch0: unity-test.patch 
License: GPLv2+
Group: System/Configuration
Requires: %{name}-curses = %version-%release, perl-Gtk3, perl-Glib >= 1.280.0-3, polkit, perl-Net-DBus, perl-Gtk3-WebKit2
Requires: polkit-agent
Requires: mageia-doc-common
# needed by drakfont (eg: type1inst):
Requires: font-tools
Requires: libxxf86misc
# needed by any::enable_x_screensaver()
Requires: xset
Requires: drakx-net
Requires: drakconf-icons
Conflicts: drakconf <= 13.1-1.mga6
# needed for installing packages through do_pkgs -> urpmi -> gmessage
#Requires: gurpmi >= 5.7
Requires: ldetect-lst >= 0.4.3
# needed by drakfont:
Requires: ttmkfdir
# needed by drakdoc:
Requires: perl-doc
# needed for SVG icons (e.g. in mgaonline and drakx-net)
Requires: %{_lib}rsvg2_2
BuildRequires: gettext
BuildRequires: ldetect-devel >= 0.9.0
BuildRequires: pkgconfig(ncurses)
BuildRequires: perl-devel >= 1:5.8.0-20
BuildRequires: perl_checker
BuildRequires: perl-Data-Dumper-Perltidy
BuildRequires: pkgconfig(libparted)
BuildRequires: drakx-installer-binaries
BuildRequires: emacs-common
BuildRequires: intltool
%global __requires_exclude perl\\((Net::FTP|Time::localtime|URPM|Xconfig.*|[a-z].*)\\)

%package curses
Summary: The drakxtools (diskdrake, ...)
Group: System/Configuration
#Requires: perl-base >= 2:5.8.6-1, urpmi >= 4.8.23, polkit
Requires: perl-base >= 2:5.8.6-1, polkit
Requires: polkit-agent
Requires: perl-Locale-gettext >= 1.05-4mdv2007
Requires: kmod
Requires: %{name}-backend = %version-%release
Requires: drakx-net-text
%global __requires_exclude perl\\((Gtk3::WebKit|Xconfig::various|[a-z].*)\\)

%package backend
Summary: Drakxtools libraries and background tools
Group: System/Configuration
Requires: dmidecode
Requires: perl-File-FnMatch
# for fileshareset and filesharelist (#17123)
#Requires: perl-suid
# for common::wrap_command_for_root()
Requires: perl-String-ShellQuote
# "post" here means %%triggerpostun:
Requires(post): perl-MDK-Common >= 1.2.13
# for lsnetdrake (mga#12579)
Requires: nmap
# require virtual samba(4)-client provide
Requires: smb-client
# Temp for gqdnf
Requires: zenity
Requires: wmctrl
Conflicts: drakxtools <= 16.27-1

%package http
Summary: The drakxtools via http
Group: System/Configuration
Requires: %{name}-curses = %version-%release, perl(Net::SSLeay) >= 1.22-1, perl-Authen-PAM >= 0.14-1, perl-CGI >= 2.91-1
Requires(pre): rpm-helper
Requires(post): rpm-helper

%package gtk2-compat
Summary: Gtk2 compatibility modules
Group: System/Configuration
Requires: %{name}
Conflicts: drakxtools <= 17.3-1.mga6

%package -n drakx-finish-install
Summary: First boot configuration
Group: System/Configuration
Requires: %{name} = %version-%release
Requires: drakx-installer-matchbox

%package -n harddrake
Summary: Main Hardware Configuration/Information Tool
Group: System/Configuration
Requires: %{name}-curses = %version-%release
Requires(pre): rpm-helper
Requires(post): rpm-helper
Requires: libdrakx-net >= 1.24 libdrakx-kbd-mouse-x11 >= 0.107 perl(Xconfig::glx)

Requires: meta-task

%package -n harddrake-ui
Summary: Main Hardware Configuration/Information Tool
Group: System/Configuration
Requires: %name = %version-%release
Requires: sane-backends
Requires: libdrakx-net libdrakx-kbd-mouse-x11 >= 0.107 perl(Xconfig::glx)

%description
Contains many Mageia Linux applications simplifying users and
administrators life on a Mageia Linux machine. Nearly all of
them work both under X.Org (graphical environment) and in console
(text environment), allowing easy distant work.

- drakbug: interactive bug report tool
- drakbug_report: help find bugs in DrakX
- drakclock: date & time configurator
- drakfloppy: boot disk creator
- drakfont: import fonts in the system
- draklog: show extracted information from the system logs
- drakperm: msec GUI (permissions configurator)
- draksec: security options managment / msec frontend

%description backend
See package %name

%description curses
Contains many Mageia Linux applications simplifying users and
administrators life on a Mageia Linux machine. Nearly all of
them work both under X.Org (graphical environment) and in console
(text environment), allowing easy distant work.

- adduserdrake: help you adding a user
- diskdrake: DiskDrake makes hard disk partitioning easier. It is
  graphical, simple and powerful. Different skill levels are available
  (newbie, advanced user, expert). It's written entirely in Perl and
  Perl/Gtk. It uses resize_fat which is a perl rewrite of the work of
  Andrew Clausen (libresize).
- drakauth: configure authentification (LDAP/NIS/...)
- drakautoinst: help you configure an automatic installation replay
- drakboot: configures your boot configuration (Lilo/GRUB,
  Bootsplash, X, autologin)
- drakkeyboard: configure your keyboard (both console and X)
- draklocale: language configurator, available both for root
  (system wide) and users (user only)
- drakmouse: autodetect and configure your mouse
- drakscanner: scanner configurator
- draksound: sound card configuration
- drakx11: menu-driven program which walks you through setting up
  your X server; it autodetects both monitor and video card if
  possible
- drakxservices: SysV services and daemons configurator
- drakxtv: auto configure tv card for xawtv grabber
- lsnetdrake: display available nfs and smb shares
- lspcidrake: display your pci information, *and* the corresponding
  kernel module

%description http
This package lets you configure your computer through your Web browser:
it provides an HTTP interface to the Mageia tools found in the drakxtools
package.

%description gtk2-compat
This package provides Gtk2 compatibility modules for legacy tools.

%description -n drakx-finish-install
For OEM-like duplications, it allows at first boot:
- network configuration
- creating users
- setting root password
- choosing authentication


%description -n harddrake
The harddrake service is a hardware probing tool run at system boot
time to determine what hardware has been added or removed from the
system.
It then offer to run needed config tool to update the OS
configuration.


%description -n harddrake-ui
This is the main configuration tool for hardware that calls all the
other configuration tools.
It offers a nice GUI that show the hardware configuration splitted by
hardware classes.


%prep
%autosetup -p1

%build
#Don't use strict for now
find perl-install -type f -exec sed -i -e 's!use strict;!!g' {} \;
%make_build -C perl-install -f Makefile.drakxtools CFLAGS="$RPM_OPT_FLAGS"

%install
%make_build -C perl-install -f Makefile.drakxtools PREFIX=$RPM_BUILD_ROOT install
mkdir -p $RPM_BUILD_ROOT%_sysconfdir/{X11/xinit.d,X11/wmsession.d,sysconfig/harddrake2}
touch $RPM_BUILD_ROOT/etc/sysconfig/harddrake2/previous_hw

dirs1="usr/lib/libDrakX usr/share/libDrakX"
(cd $RPM_BUILD_ROOT ; find $dirs1 usr/bin usr/sbin usr/libexec usr/share/polkit-1 ! -type d -printf "/%%p\n")|grep -E -v 'bin/.*harddrake' > %{name}.list
(cd $RPM_BUILD_ROOT ; find $dirs1 -type d -printf "%%%%dir /%%p\n") >> %{name}.list

perl -ni -e '/Xdrakres|clock|display_help|display_release_notes.pl|drak(bug$|clock|dvb|floppy|font|hosts|log|perm|sec|splash)|gtk|icons|logdrake|pixmaps|\.png$/ ? print STDERR $_ : print' %{name}.list 2> %{name}-gtk.list
# exclude gtk2 stuff:
fgrep gtk2 %{name}-gtk.list >%{name}-gtk2.list
perl -pi -e 'undef $_ if /gtk2/' %{name}-gtk.list
perl -ni -e '/http/ ? print STDERR $_ : print' %{name}.list 2> %{name}-http.list
perl -ni -e 'm!lib/libDrakX|bootloader-config|fileshare|lsnetdrake|drakupdate_fstab|rpcinfo|serial_probe! && !/curses/i ? print STDERR $_ : print' %{name}.list 2> %{name}-backend.list
perl -ni -e '/finish-install/ ? print STDERR $_ : print' %{name}.list 2> finish-install.list

cat > $RPM_BUILD_ROOT%_sysconfdir/X11/xinit.d/harddrake2 <<EOF
#!/bin/sh
exec /usr/share/harddrake/service_harddrake X11
EOF

cat > $RPM_BUILD_ROOT%_sysconfdir/sysconfig/harddrake2/kernel <<EOF
KERNEL=2.6
EOF

mv $RPM_BUILD_ROOT%_sbindir/service_harddrake_confirm $RPM_BUILD_ROOT%_datadir/harddrake/confirm

chmod +x $RPM_BUILD_ROOT{%_datadir/harddrake/{conf*,service_harddrake},%_sysconfdir/X11/xinit.d/harddrake2}
# temporary fix until we reenable this feature
rm -f $RPM_BUILD_ROOT%_sysconfdir/X11/xinit.d/harddrake2

perl -I perl-install -mharddrake::data -e 'print "DETECT_$_->{class}=yes\n" foreach @harddrake::data::tree' |sort > $RPM_BUILD_ROOT%_sysconfdir/sysconfig/harddrake2/service.conf
echo -e "AUTORECONFIGURE_RIGHT_XORG_DRIVER=yes\n" >> $RPM_BUILD_ROOT%_sysconfdir/sysconfig/harddrake2/service.conf

install -m 555 %{SOURCE1} $RPM_BUILD_ROOT%_bindir/gqdnf

%find_lang libDrakX
%find_lang libDrakX-standalone
cat libDrakX.lang libDrakX-standalone.lang >> %name.list

%check
%make_build -C perl-install -f Makefile.drakxtools check

%post
%make_session
rm -f %_sbindir/kbdconfig %_sbindir/mouseconfig
:

%postun
%make_session
:

%post http
%_post_service drakxtools_http

%preun http
%_preun_service drakxtools_http

%postun -n harddrake
file /etc/sysconfig/harddrake2/previous_hw | grep -F -q perl && %_datadir/harddrake/convert || :

%files backend -f %{name}-backend.list
%_bindir/gqdnf
%config(noreplace) /etc/security/fileshare.conf
%attr(4755,root,root) %_sbindir/fileshareset

%files curses -f %name.list
%{_datadir}/applications/localedrake*.desktop
#%%doc perl-install/diskdrake/diskdrake.html
%_iconsdir/localedrake.png
%_iconsdir/large/localedrake.png
%_iconsdir/mini/localedrake.png

%files -f %{name}-gtk.list

%files gtk2-compat -f %{name}-gtk2.list

%files -n harddrake
%dir /etc/sysconfig/harddrake2/
%config(noreplace) /etc/sysconfig/harddrake2/previous_hw
%config(noreplace) /etc/sysconfig/harddrake2/service.conf
%config(noreplace) %_sysconfdir/sysconfig/harddrake2/kernel
%dir %_datadir/harddrake/
%_datadir/harddrake/*
%_sysconfdir/X11/xsetup.d/??notify-x11-free-driver-switch.xsetup
#%%_sysconfdir/X11/xinit.d/harddrake2

%files -n harddrake-ui
%dir /etc/sysconfig/harddrake2/
%_sbindir/harddrake2
%_datadir/pixmaps/harddrake2
%{_datadir}/applications/harddrake.desktop
%_iconsdir/large/harddrake.png
%_iconsdir/mini/harddrake.png
%_iconsdir/harddrake.png

%files -n drakx-finish-install
%config(noreplace) %_sysconfdir/sysconfig/finish-install
%_sysconfdir/X11/xsetup.d/??finish-install.xsetup
%_sbindir/finish-install

%files http -f %{name}-http.list
%dir %_sysconfdir/drakxtools_http
%config(noreplace) %_sysconfdir/pam.d/miniserv
%_sysconfdir/init.d/drakxtools_http
%config(noreplace) %_sysconfdir/drakxtools_http/conf
%config(noreplace) %_sysconfdir/drakxtools_http/authorised_progs
%config(noreplace) %_sysconfdir/logrotate.d/drakxtools-http
