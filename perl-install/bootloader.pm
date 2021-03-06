package bootloader;

use diagnostics;
use strict;

#-######################################################################################
#- misc imports
#-######################################################################################
use common;
use fs::type;
use fs::get;
use fs::loopback;
use fs::proc_partitions;
use log;
use any;
use devices;
use detect_devices;
use partition_table::raw;
use run_program;
use modules;

=head1 SYNOPSYS

B<bootloader> enables to configure various boot loaders (LILO, GRUB Legacy, GRUB2, ...)

Example of usage:

    $all_hds = fsedit::get_hds();
    fs::get_raw_hds('', $all_hds);
    fs::get_info_from_fstab($all_hds);
    $fstab = [ fs::get::fstab($all_hds) ];
    $bootloader = bootloader::read($all_hds);
    (...)
    bootloader::action($bootloader, 'write', $all_hds);

=head1 Functions

=over

=cut

my $vmlinuz_regexp = 'vmlinu[xz]|win4lin|uImage';
my $decompose_vmlinuz_name = qr/((?:$vmlinuz_regexp).*?)-(\d+\.\d+.*)/;

sub expand_vmlinuz_symlink {
    my ($vmlinuz) = @_;
    my $f = $::prefix . ($vmlinuz =~ m!^/! ? $vmlinuz : "/boot/$vmlinuz");
    -l $f ? readlink($f) : $vmlinuz;
}

sub installed_vmlinuz_raw() { grep { /^($vmlinuz_regexp)/ } all("$::prefix/boot") }
sub installed_vmlinuz() { grep { ! -l "$::prefix/boot/$_" } installed_vmlinuz_raw() }
sub vmlinuz2version {
    my ($vmlinuz) = @_;
    expand_vmlinuz_symlink($vmlinuz) =~ /$decompose_vmlinuz_name/ && $2;
}
sub vmlinuz2kernel_str {
    my ($vmlinuz) = @_;
    my ($basename, $version) = expand_vmlinuz_symlink($vmlinuz) =~ /$decompose_vmlinuz_name/ or return;
    { 
	basename => $basename,
	version => $version, 
	$version =~ /([\d.]*)-(\D.*)-((\d+|0\.rc\d+.*)\.mga.*)$/ ? #- eg: 3.0.0-1.mga2
	  (ext => $2, version_no_ext => "$1-$3") :
	$version =~ /(.*mga)-?(.*)/ ? #- (old) eg: 2.6.17-13mdventerprise
	  (ext => $2, version_no_ext => $1) : (version_no_ext => $version),
    };
}

sub kernel_str2short_name {
    my ($kernel) = @_;
    $kernel->{basename};
}

sub basename2initrd_basename {
    my ($basename) = @_;
    $basename =~ s!(vmlinu[zx]|uImage)-?!!; #- here we do not use $vmlinuz_regexp since we explicitly want to keep all that is not "vmlinuz"
    'initrd' . ($basename ? "-$basename" : '');    
}
sub kernel_str2vmlinuz_long {
    my ($kernel) = @_;
    $kernel->{basename} . '-' . $kernel->{version};
}
sub kernel_str2initrd_long {
    my ($kernel) = @_;
    basename2initrd_basename(kernel_str2short_name($kernel)) . '-' . $kernel->{version} . '.img';
}
sub kernel_str2vmlinuz_short {
    my ($kernel) = @_;
    if ($kernel->{use_long_name}) {
	kernel_str2vmlinuz_long($kernel);
    } else {
	kernel_str2short_name($kernel);
    }
}
sub kernel_str2initrd_short {
    my ($kernel) = @_;
    if ($kernel->{use_long_name}) {
	kernel_str2initrd_long($kernel);
    } else {
	basename2initrd_basename(kernel_str2short_name($kernel)) . '.img';
    }
}

sub kernel_str2label {
    my ($kernel, $o_use_long_name) = @_;
    if ($o_use_long_name || $kernel->{use_long_name}) {
	_sanitize_ver($kernel);
    } else {
	my $short_name = kernel_str2short_name($kernel);
	$kernel->{ext} =~ /^xen/ ? 'xen' : ($short_name eq 'vmlinuz' ? 'linux' : $short_name);
    }
}

sub get {
    my ($vmlinuz, $bootloader) = @_;
    $_->{kernel_or_dev} && $_->{kernel_or_dev} eq $vmlinuz and return $_ foreach @{$bootloader->{entries}};
    undef;
}
sub get_label {
    my ($label, $bootloader) = @_;
    $_->{label} && lc(make_label_lilo_compatible($_->{label})) eq lc(make_label_lilo_compatible($label)) and return $_ foreach @{$bootloader->{entries}};
    undef;
}

=item mkinitrd($kernel_version, $bootloader, $entry, $initrd)

Regenerates kernel's initrd.

=cut

sub mkinitrd {
    my ($kernel_version, $bootloader, $entry, $initrd) = @_;

    my $dir = dirname($initrd);
    if ($::testing) {
      log::l("Skipping initrd generation: testing mode");
      return $initrd;
    } elsif (-e "$::prefix/$initrd") {
      log::l("Skipping initrd generation: already exists");
      return $initrd;
    } elsif ($initrd =~ /\(hd/) {
      log::l("Skipping initrd generation: unrecognized partition");
      return $initrd;
    } elsif (!-d "$::prefix/$dir") {
      log::l("Skipping initrd generation: dir doesn't exist (probably !mounted foreign part)");
      return $initrd;
    }

    # for /boot on dos partitions when installing on loopback file on dos partition
    my $loop_boot = fs::loopback::prepare_boot();

    modules::load('loop');
    my @options = (
		   if_($::isInstall, "-v"), "-f", $initrd, $kernel_version, 
		   if_($entry->{initrd_options}, split(' ', $entry->{initrd_options})),
		  );

    my $err;
    if (!run_program::rooted($::prefix, 'mkinitrd', '2>', \$err, @options)) {
	unlink("$::prefix/$initrd");
	log::explanations("mkinitrd failed:\n(mkinitrd @options)\nError: <$err>");
	die "mkinitrd failed:\n(mkinitrd @options)\nError: $err";
    }
    add_boot_splash($initrd, $entry->{vga} || $bootloader->{vga});

    fs::loopback::save_boot($loop_boot);

    -e "$::prefix/$initrd" && $initrd;
}

=item rebuild_initrd($kernel_version, $bootloader, $entry, $initrd)

Saves the old initrd then regenerate it.
If it fails, restore the old initrd.

=cut

sub rebuild_initrd {
    my ($kernel_version, $bootloader, $entry, $initrd) = @_;

    my $old = $::prefix . $entry->{initrd} . '.old';
    unlink $old;
    rename "$::prefix$initrd", $old;
    if (!mkinitrd($kernel_version, $bootloader, $entry, $initrd)) {
	log::l("rebuilding initrd failed, putting back the old one");
	rename $old, "$::prefix$initrd";
    }
}

sub remove_boot_splash {
    my ($initrd) = @_;
    run_program::rooted($::prefix, '/usr/share/bootsplash/scripts/remove-boot-splash', $initrd);
}
sub add_boot_splash {
    my ($initrd, $vga) = @_;

    $vga or return;

    eval { require Xconfig::resolution_and_depth } or return;
    if (my $res = Xconfig::resolution_and_depth::from_bios($vga)) {
	run_program::rooted($::prefix, '/usr/share/bootsplash/scripts/make-boot-splash', $initrd, $res->{X});
    } else {
	log::l("unknown vga bios mode $vga");
    }
}
sub update_splash {
    my ($bootloader) = @_;

    my %real_initrd_entries;
    foreach (@{$bootloader->{entries}}) {
	if ($_->{initrd} && $_->{vga}) {
	    my $initrd = expand_symlinks($_->{initrd});
	    $real_initrd_entries{$initrd} = $_;
	}
    }
    foreach (values %real_initrd_entries) {
        log::l("add boot splash to $_->{initrd}\n");
	add_boot_splash($_->{initrd}, $_->{vga} || $bootloader->{vga});
    }
}

=item read($all_hds)

Reads bootloader config by calling the proper read_XYZ function.

=cut

sub read {
    my ($all_hds) = @_;
    my $fstab = [ fs::get::fstab($all_hds) ];
    foreach my $main_method (main_method_choices()) {
	my $f = $bootloader::{"read_$main_method"} or die "unknown bootloader method $main_method (read)";
	my $bootloader = $f->($fstab);

	cleanup_entries($bootloader);

	# handle raid-extra-boot (lilo)
	my @devs = $bootloader->{boot};
	if ($bootloader->{'raid-extra-boot'} =~ /mbr/ && 
	    (my $md = fs::get::device2part($bootloader->{boot}, $all_hds->{raids}))) {
	    @devs = map { $_->{rootDevice} } @{$md->{disks}};
	} elsif ($bootloader->{'raid-extra-boot'} =~ m!/dev/!) {
	    @devs = split(',', $bootloader->{'raid-extra-boot'});
	}

	my ($type) = map {
	    if (m!/fd\d+$!) {
		warn "not checking the method on floppy, assuming $main_method is right\n";
		$main_method;
	    } elsif (member($main_method, qw(cromwell uboot))) {
		#- not checking, there's only one bootloader anyway :)
		$main_method;
	    } elsif (my $type = partition_table::raw::typeOfMBR($_)) {
		warn "typeOfMBR $type on $_ for method $main_method\n" if $ENV{DEBUG};
		$type;
	    } else { () }
	} @devs;

	if ($type eq $main_method) {
	    return $bootloader if read_($bootloader);
	}
    }
    # still no boot loader found? let's check for ESP if using UEFI: 
    if (is_uefi()) {
	if (-f "/boot/EFI/EFI/mageia/grubx64.efi" || -f "/boot/EFI/EFI/mageia/grubia32.efi") {
	    my $bootloader = bootloader::read_grub2();
	    return $bootloader if read_($bootloader);
	}
    }
}

sub read_ {
    my ($bootloader) = @_;
	    my @prefered_entries = map { get_label($_, $bootloader) } $bootloader->{default}, 'linux';

	    if (my $default = find { $_ && $_->{type} eq 'image' } (@prefered_entries, @{$bootloader->{entries}})) {
		$bootloader->{default_options} = $default;
		$bootloader->{perImageAppend} ||= $default->{append};
		log::l("perImageAppend is now $bootloader->{perImageAppend}");
		$bootloader->{default_vga} ||= $default->{vga};
		log::l("default_vga is now $bootloader->{default_vga}");
	    } else {
		$bootloader->{default_options} = {};
	    }
	    return $bootloader;
}


=item is_grub2_already_crypted($password)

Returns whether grub2 password is already encrypted or not

=cut

sub is_grub2_already_crypted {
    my ($password) = @_;
    $password =~ /grub.pbkdf2.sha512/;
}

=item read_grub2 ($o_fstab)

Read back GRUB2 config

=cut

sub read_grub2() {
    my %bootloader = read_grub2_install_sh();
    return if is_empty_hash_ref(\%bootloader) & !-s "$::prefix/boot/grub2/grub.cfg";
    my %h = getVarsFromSh("$::prefix/etc/default/grub");
    $bootloader{timeout} = $h{GRUB_TIMEOUT};
    # keep suggested perImageAppend and default_vga on first run (during installer) or when migrating from grub-legacy or lilo:
    my ($vga, $other) = partition { /^vga=/ } split(' ', $h{GRUB_CMDLINE_LINUX_DEFAULT});
    $bootloader{perImageAppend} ||= join(' ', @$other) if @$other;
    $bootloader{default_vga} ||= $vga->[0] =~ /vga=(.*)/ && $1 if @$vga;
    $bootloader{entries} = [];
    my $entry;
    my $f = "$::prefix/boot/grub2/grub.cfg";
    my @menus;
    foreach (cat_utf8($f)) {
	next if /^#/;
	if (/menuentry\s+['"]([^']+)["']/) {
	    $entry = { label => $1, real_label => join('>', @menus, $1) };
	} elsif (/linux(?:16)?\s+([^-]\S+)\s+(.*)?/ || /module\s+(\S+vmlinu\S+)\s+(.*)?/) {
	    $entry->{type} = 'image';
	    @$entry{qw(kernel_or_dev append)} = ($1, $2);
	    my ($vga, $other) = partition { /^vga=/ } split(' ', $entry->{append});
	    if (@$vga) {
	        $entry->{vga} = $vga->[0] =~ /vga=(.*)/ && $1;
	        $entry->{append} = join(' ', @$other);
	    }
	} elsif (/initrd(?:16)?\s+(\S+)/ || /module\s+(\S+initrd\S+)\s+(.*)?/) {
	    $entry->{initrd} = $1;
	} elsif (/submenu\s+['"]([^']+)["']/) {
	    push @menus, $1;
	} elsif (/^\s+}/) {
	    if ($entry) {
		push @{$bootloader{entries}}, $entry;
		undef $entry;
	    } else {
		pop @menus;
	    }
	}
    }

    # get default entry:
    foreach (run_program::rooted_get_stdout($::prefix, qw(grub2-editenv list))) {
	$bootloader{default} = $1 if /saved_entry=(.*)/;
	$bootloader{default} =~ s/.*>//; # strip full menu entry path
    }

    # Get password prior to run update-grub2:
    $bootloader{password} = { getVarsFromSh(get_grub2_users()) }->{GRUB2_PASSWORD};

    $bootloader{method} = cat_($f) =~ /set theme=.*maggy/ ? 'grub2-graphic' : 'grub2';
    \%bootloader;
}

sub read_grub2_install_sh() {
    my $s = cat_(get_grub2_install_sh());
    my %h;
    if ($s =~ m!(/dev/\S+)!m) {
	$h{boot} = $1;
    }
    $h{no_esp_or_mbr} = $s =~ m!--grub-setup=/bin/true!;
    %h;
}

=item read_grub($fstab)

Reads back Grub Legacy config.

=cut

sub read_grub {
    my ($fstab) = @_;

    my $grub2dev = read_grub_device_map();
    my $boot_root = read_grub_install_sh();
    _may_fix_grub2dev($fstab, $grub2dev, $boot_root->{boot_part});

    my $bootloader = read_grub_menu_lst($fstab, $grub2dev) or return;

    if ($boot_root->{boot}) {
	$bootloader->{boot} = grub2dev($boot_root->{boot}, $grub2dev);
    }

    $bootloader;
}


=item _may_fix_grub2dev($fstab, $grub2dev, $boot_part)

Adapts device.map (aka $grub2dev) when for example hda is now sda.
nb:

=over 4

=item * $boot_part comes from C</boot/grub/install.sh> C<root (hd...)> line

=item * $grub2dev is C</boot/grub/device.map>

=back

=cut

sub _may_fix_grub2dev {
    my ($fstab, $grub2dev, $boot_part) = @_;

    $boot_part or log::l("install.sh does not contain 'root (hd...)' line, no way to magically adapt device.map"), return;

    my $real_boot_part = fs::get::root_($fstab, 'boot') or
      log::l("argh... the fstab given is useless, it doesn't contain '/'"), return;
    
    my $real_boot_dev = $real_boot_part->{rootDevice} or return; # if /boot is on Linux RAID 1, hope things are all right...

    if (my $prev_boot_part = fs::get::device2part(grub2dev($boot_part, $grub2dev), $fstab)) { # the boot_device as far as grub config files say
	$real_boot_part == $prev_boot_part and return;
    }

    log::l("WARNING: we have detected that device.map is inconsistent with the system");

    my ($hd_grub, undef, undef) = parse_grub_file($boot_part); # extract hdX 
    if (my $prev_hd_grub = find { $grub2dev->{$_} eq $real_boot_dev } keys %$grub2dev) {
	$grub2dev->{$prev_hd_grub} = $grub2dev->{$hd_grub};
	log::l("swapping result: $hd_grub/$real_boot_dev and $prev_hd_grub/$grub2dev->{$hd_grub}");
    } else {
	log::l("argh... can't swap, setting $hd_grub to $real_boot_dev anyway");
    }
    $grub2dev->{$hd_grub} = $real_boot_dev;
}

=item read_grub_install_sh() {

Reads "config" from /boot/grub/install.sh (mainly used partitions)

=cut

sub read_grub_install_sh() {
    my $s = cat_("$::prefix/boot/grub/install.sh");
    my %h;

    #- matches either:
    #-   setup (hd0)
    #-   install (hd0,0)/boot/grub/stage1 d (hd0) (hd0,0)/boot/grub/stage2 p (hd0,0)/boot/grub/menu.lst
    if ($s =~ /^(?:setup.*|install\s.*\sd)\s+(\(.*?\))/m) {
	$h{boot} = $1;
    }    
    if ($s =~ /^root\s+(\(.*?\))/m) {
	$h{boot_part} = $1;
    }
    \%h;
}

sub _parse_grub_menu_lst() {
    my $global = 1;
    my ($e, %b);

    my $menu_lst_file = "$::prefix/boot/grub/menu.lst";
    -e $menu_lst_file or return;

    foreach (MDK::Common::File::cat_utf8($menu_lst_file)) {
	my $verbatim = $_;
        chomp;
	s/^\s*//; s/\s*$//;
        next if /^#/ || /^$/;
	my ($keyword, $v) = split('[ \t=]+', $_, 2) or
	  warn qq(unknown line in /boot/grub/menu.lst: "$_"\n), next;

	if ($keyword eq 'root') {
	    #- rename to avoid name conflict
	    $keyword = 'grub_root';
	}

        if ($keyword eq 'title') {
            push @{$b{entries}}, $e = { label => $v };
            $global = 0;
        } elsif ($global) {
            $b{$keyword} = $v;
        } else {
            if ($keyword eq 'kernel') {
                $e->{type} = 'image';
		$e->{kernel} = $v;
            } elsif ($keyword eq 'chainloader') {
                $e->{type} = 'other';
                $e->{append} = "";
            } elsif ($keyword eq 'configfile') {
                $e->{type} = 'grub_configfile';
                $e->{configfile} = $v;
            } elsif ($keyword eq 'map') {
		$e->{mapdrive}{$2} = $1 if $v =~ m/\((.*)\) \((.*)\)/;
            } elsif ($keyword eq 'module') {
		push @{$e->{modules}}, $v;
	    } else {
		$e->{$keyword} = $v eq '' ? 1 : $v;
	    }
        }
	$e and $e->{verbatim} .= $verbatim;
    }

    %b;
}


=item is_already_crypted($password)

Returns whether grub password is already encrypted or not

=cut

sub is_already_crypted {
    my ($password) = @_;
    $password =~ /^--md5 (.*)/;
}

=item read_grub_menu_lst($fstab, $grub2dev)

Read config from /boot/grub/menu.lst

=cut

sub read_grub_menu_lst {
    my ($fstab, $grub2dev) = @_;

    my %b = _parse_grub_menu_lst();

    foreach my $keyword (grep { $_ ne 'entries' } keys %b) {
	$b{$keyword} = $b{$keyword} eq '' ? 1 : grub2file($b{$keyword}, $grub2dev, $fstab, \%b);
    }

    #- sanitize
    foreach my $e (@{$b{entries}}) {
	if (member($e->{type}, 'other', 'grub_configfile')) {
	    eval { $e->{kernel_or_dev} = grub2dev($e->{rootnoverify} || $e->{grub_root}, $grub2dev) };
	    $e->{keep_verbatim} = 1 unless $e->{kernel_or_dev}; 
	} elsif ($e->{initrd}) {
 	    my $initrd;
 	    eval { $initrd = grub2file($e->{initrd}, $grub2dev, $fstab, $e) };
 	    if ($initrd) {
 		$e->{initrd} = $initrd;
 	    } else {
 		$e->{keep_verbatim} = 1;
 	    }
	}

	if ($e->{kernel} =~ /xen/ && @{$e->{modules} || []} == 2 && $e->{modules}[1] =~ /initrd/) {
	    (my $xen, $e->{xen_append}) = split(' ', $e->{kernel}, 2);
	    ($e->{kernel}, my $initrd) = @{delete $e->{modules}};
	    $e->{xen} = grub2file($xen, $grub2dev, $fstab, $e);
	    $e->{initrd} = grub2file($initrd, $grub2dev, $fstab, $e);
	}
	if (my $v = delete $e->{kernel}) {
	    (my $kernel, $e->{append}) = split(' ', $v, 2);
	    $e->{append} = join(' ', grep { !/^BOOT_IMAGE=/ } split(' ', $e->{append}));
	    $e->{root} = $1 if $e->{append} =~ s/root=(\S*)\s*//;
	    eval { $e->{kernel_or_dev} = grub2file($kernel, $grub2dev, $fstab, $e) };
	    $e->{keep_verbatim} = 1 if !$e->{kernel_or_dev} || dirname($e->{kernel_or_dev}) ne '/boot';
	}
	my ($vga, $other) = partition { /^vga=/ } split(' ', $e->{append});
	if (@$vga) {
	    $e->{vga} = $vga->[0] =~ /vga=(.*)/ && $1;
	    $e->{append} = join(' ', @$other);
	}
    }

    $b{nowarn} = 1;
    # handle broken installkernel -r:
    if (@{$b{entries}}) {
	$b{default} = min($b{default}, scalar(@{$b{entries}}) - 1);
	$b{default} = $b{entries}[$b{default}]{label};
    }
    $b{method} = $b{gfxmenu} ? 'grub-graphic' :  'grub-menu';

    \%b;
}

# FIXME: actually read back previous conf
sub read_uboot() {
    +{ method => 'uboot' };
}
sub read_cromwell() {
    +{ method => 'cromwell' };
}


sub read_lilo() {
    my $bootloader = read_lilo_like("/etc/lilo.conf", sub { $_[0] });

    delete $bootloader->{timeout} unless $bootloader->{prompt};
    $bootloader->{timeout} = $bootloader->{timeout} / 10 if $bootloader->{timeout};

    my $submethod = member($bootloader->{install}, 'text', 'menu') ? $bootloader->{install} : 'menu';
    $bootloader->{method} = "lilo-$submethod";
    
    $bootloader;
}
sub read_lilo_like {
    my ($file, $filter_file) = @_;

    my $global = 1;
    my ($e);
    my %b;
    -e "$::prefix$file" or return;
    foreach my $line (cat_("$::prefix$file")) {
	next if $line =~ /^\s*#/ || $line =~ /^\s*$/;
	my ($cmd, $v) = $line =~ /^\s*([^=\s]+)\s*(?:=\s*(.*?))?\s*$/ or log::l("unknown line in $file: $line"), next;

	if ($cmd =~ /^(?:image|other|macos|macosx|bsd|darwin)$/) {
	    $v = $filter_file->($v);
	    push @{$b{entries}}, $e = { type => $cmd, kernel_or_dev => $v };
	    $global = 0;
	} elsif ($global) {
	    if ($cmd eq 'disk' && $v =~ /(\S+)\s+bios\s*=\s*(\S+)/) {
		$b{bios}{$1} = $2;
	    } elsif ($cmd eq 'bios') {
		$b{bios}{$b{disk}} = $v;
	    } elsif ($cmd eq 'init-message') {
		$v =~ s/\\n//g; 
		$v =~ s/"//g;
		$b{'init-message'} = $v;
	    } else {
		$b{$cmd} = $v eq '' ? 1 : $v;
	    }
	} else {
	    if (($cmd eq 'map-drive' .. $cmd eq 'to') && $cmd eq 'to') {
		$e->{mapdrive}{$e->{'map-drive'}} = $v;
	    } else {
		if ($cmd eq 'initrd') {
		    $v = $filter_file->($v);
		}
		$e->{$cmd} = $v || 1;
	    }
	}
    }

    sub remove_quotes_and_spaces {
	local ($_) = @_;
	s/^\s*//; s/\s*$//;
	s/^"(.*?)"$/$1/;
	s/\\"/"/g;
	s/^\s*//; s/\s*$//; #- do it again for append=" foo"
	$_;
    }

    foreach ('append', 'root', 'default', 'raid-extra-boot') {
	$b{$_} = remove_quotes_and_spaces($b{$_}) if $b{$_};
    }
    foreach my $entry (@{$b{entries}}) {
	foreach ('append', 'root', 'label') {
	    $entry->{$_} = remove_quotes_and_spaces($entry->{$_}) if $entry->{$_};
	}
	if ($entry->{kernel_or_dev} =~ /\bmbootpack\b/) {
	    $entry->{initrd} = $entry->{kernel_or_dev};
	    $entry->{initrd} =~ s/\bmbootpack/initrd/;
	    $entry->{kernel_or_dev} =~ s/\bmbootpack/vmlinuz/;
	    $entry->{kernel_or_dev} =~ s/.img$//;
	    #- assume only xen is configured with mbootpack
	    $entry->{xen} = '/boot/xen.gz';
	    $entry->{root} = $1 if $entry->{append} =~ s/root=(\S*)\s*//;
	    ($entry->{xen_append}, $entry->{append}) = split '\s*--\s*', $entry->{append}, 2;
	}
    }

    # cleanup duplicate labels (in case file is corrupted)
    @{$b{entries}} = uniq_ { $_->{label} } @{$b{entries}};

    \%b;
}

sub cleanup_entries {
    my ($bootloader) = @_;

    #- cleanup bad entries (in case file is corrupted)
    @{$bootloader->{entries}} = 
	grep { 
	    my $pb = $_->{type} eq 'image' && !$_->{keep_verbatim} && ! -e "$::prefix$_->{kernel_or_dev}";
	    log::l("dropping bootloader entry $_->{label} since $_->{kernel_or_dev} doesn't exist") if $pb;
	    !$pb;
	} @{$bootloader->{entries}};
}

sub suggest_onmbr {
    my ($hd) = @_;
    
    my ($onmbr, $unsafe) = (1, 1);

    if (my $type = partition_table::raw::typeOfMBR($hd->{device})) {
	if (member($type, qw(dos dummy empty))) {
	    $unsafe = 0;
	} elsif (!member($type, qw(lilo grub grub2))) {
	    $onmbr = 0;
	}
	log::l("bootloader::suggest_onmbr: type $type, onmbr $onmbr, unsafe $unsafe");
    }
    ($onmbr, $unsafe);
}


=item allowed_boot_parts($bootloader, $all_hds)

Returns list of places where we can install the bootloader when not in UEFI mode
(in UEFI mode, grub2 automatically look for the ESP).

=cut

sub allowed_boot_parts {
    my ($bootloader, $all_hds) = @_;
    (
     ( # GPT disks w/o a BIOS boot partition do not have free space for grub2 to embed:
      grep { c::get_disk_type($_->{file}) ne 'gpt' ||
		 any { isBIOS_GRUB($_) } map { partition_table::get_normal_parts($_) } $_;
      } @{$all_hds->{hds}}), # MBR

     if_($bootloader->{method} =~ /lilo/,
	 grep { $_->{level} eq '1' } @{$all_hds->{raids}}
	),
     (if_(main_method($bootloader->{method}) ne 'grub2',
	  grep { !isFat_or_NTFS($_) } fs::get::fstab($all_hds)), # filesystems except those who do not leave space for our bootloaders
     ),
     detect_devices::floppies(),
    );
}

sub same_entries {
    my ($a, $b) = @_;

    foreach (uniq(keys %$a, keys %$b)) {
	if (member($_, 'label', 'append', 'mapdrive', 'readonly', 'makeactive', 'verbatim')) {
	    next;
	} elsif ($_ eq 'grub_root' && (!$a->{$_} || !$b->{$_})) {
	    #- grub_root is mostly internal stuff. if it misses, it's ok
	    next;
	} else {
	    next if $a->{$_} eq $b->{$_};

	    my ($inode_a, $inode_b) = map { (stat "$::prefix$_")[1] } ($a->{$_}, $b->{$_});
	    next if $inode_a && $inode_b && $inode_a == $inode_b;
	}

	log::l("entries $a->{label} do not have same $_: $a->{$_} ne $b->{$_}");
	return;
    }
    1;
}

sub add_entry {
    my ($bootloader, $v) = @_;

    my $to_add = $v;
    my $label = $v->{label};
    for (my $i = 0; $i < 100;) {
	my $conflicting = get_label($label, $bootloader);

	$to_add->{label} = $label;

	if ($conflicting) {
	    #- replacing $conflicting with $to_add
	    @{$bootloader->{entries}} = map { $_ == $conflicting ? $to_add : $_ } @{$bootloader->{entries}};

	    #- we will keep $conflicting, but not with same symlinks if used by the entry to add
	    expand_entry_symlinks($bootloader, $conflicting);
	} else {
	    #- we have found an unused label
	    push @{$bootloader->{entries}}, $to_add;
	}

	if (!$conflicting || same_entries($conflicting, $to_add)) {
	    log::l("current labels: " . join(" ", map { $_->{label} } @{$bootloader->{entries}}));
	    return $v;
	}
	$to_add = $conflicting;

	if ($to_add->{label} eq 'linux') {
	    $label = kernel_str2label(vmlinuz2kernel_str($to_add->{kernel_or_dev}), 'use_long_name');
	} else {
	    $label =~ s/^alt\d*_//;
	    $label = 'alt' . ($i++ ? $i : '') . "_$label";
	}
    }
    die 'add_entry';
}

sub expand_entry_symlinks {
    my ($bootloader, $entry) = @_;

    foreach my $kind ('kernel_or_dev', 'initrd') {
	my $old_long_name = $bootloader->{old_long_names} && $bootloader->{old_long_names}{$entry->{$kind}} or next;

	#- replace all the {$kind} using this symlink to the real file
	log::l("replacing $entry->{$kind} with $old_long_name for bootloader label $entry->{label}");
	$entry->{$kind} = $old_long_name;
    }
}

sub _do_the_symlink {
    my ($bootloader, $link, $long_name) = @_;

    my $existing_link = readlink("$::prefix$link");
    if ($existing_link && $existing_link eq $long_name) {
	#- nothing to do :)
	return;
    }

    if ($existing_link) {
	#- the symlink is going to change! 
	#- replace all the {$kind} using this symlink to the real file
	my $old_long_name = $existing_link =~ m!^/! ? $existing_link : "/boot/$existing_link";
	if (-e "$::prefix$old_long_name") {
	    $bootloader->{old_long_names}{$link} = $old_long_name;
	} else {
	    log::l("ERROR: $link points to $old_long_name which does not exist");
	}
    } elsif (-e "$::prefix$link") {
	log::l("ERROR: $link is not a symbolic link");
    }

    #- changing the symlink
    symlinkf($long_name, "$::prefix$link")
      or cp_af("$::prefix/boot/$long_name", "$::prefix$link");
}

# for lilo & xen
sub get_mbootpack_filename {
    my ($entry) = @_;
    my $mbootpack_file = $entry->{initrd};
    $mbootpack_file =~ s/\binitrd/mbootpack/;
    $entry->{xen} && $mbootpack_file;
}

# for lilo & xen
sub build_mbootpack {
    my ($entry) = @_;

    my $mbootpack = '/usr/bin/mbootpack';
    -f $::prefix . $entry->{kernel_or_dev} && -f $::prefix . $entry->{initrd} or return;

    my $mbootpack_file = get_mbootpack_filename($entry);
    -f ($::prefix . $mbootpack_file) and return 1;

    my $error;
    my $xen_kernel = '/tmp/xen_kernel';
    my $xen_vmlinux = '/tmp/xen_vmlinux';
    my $_b = before_leaving { unlink $::prefix . $_ foreach $xen_kernel, $xen_vmlinux };
    run_program::rooted($::prefix, '/bin/gzip', '>', $xen_kernel, '2>', \$error, '-dc', $entry->{xen})
      or die "unable to uncompress xen kernel";
    run_program::rooted($::prefix, '/bin/gzip', '>', $xen_vmlinux, '2>', \$error, '-dc', $entry->{kernel_or_dev})
      or die "unable to uncompress xen vmlinuz";

    run_program::rooted($::prefix, $mbootpack,
                        "2>", \$error,
                        '-o', $mbootpack_file,
                        '-m', $xen_vmlinux,
                        '-m', $entry->{initrd},
                        $xen_kernel)
      or die "mbootpack failed: $error";

    1;
}

sub add_kernel {
    my ($bootloader, $kernel_str, $v, $b_nolink, $b_no_initrd) = @_;

    #- eg: for /boot/vmlinuz-2.6.17-13mdvxen0 (pkg kernel-xen0-xxx) 
    #-      or /boot/vmlinuz-2.6.18-xen (pkg kernel-xen-uptodate)
    if ($kernel_str->{version} =~ /xen/ && -f '/boot/xen.gz') {
	$v->{xen} = '/boot/xen.gz';
    }

    add2hash($v,
	     {
	      type => 'image',
	      label => kernel_str2label($kernel_str),
	     });

    #- normalize append and handle special options
    {
	my ($simple, $dict) = unpack_append("$bootloader->{perImageAppend} $v->{append}");
	if ($v->{label} eq 'failsafe') {
	    #- perImageAppend contains resume=/dev/xxx which we don't want
	    @$dict = grep { $_->[0] ne 'resume' } @$dict;
	}
	$v->{append} = pack_append($simple, $dict);
    }

    $b_no_initrd //= arch() =~ /arm/;

    $b_nolink ||= $kernel_str->{use_long_name};

    #- do not link /boot/vmlinuz to xen
    $b_nolink ||= $v->{xen};

    my $vmlinuz_long = kernel_str2vmlinuz_long($kernel_str);
    my $initrd_long = kernel_str2initrd_long($kernel_str);
    $v->{kernel_or_dev} = "/boot/$vmlinuz_long";
    -e "$::prefix$v->{kernel_or_dev}" or log::l("unable to find kernel image $::prefix$v->{kernel_or_dev}"), return;
    log::l("adding $v->{kernel_or_dev}");

    if (!$b_no_initrd) {
	$v->{initrd} = mkinitrd($kernel_str->{version}, $bootloader, $v, "/boot/$initrd_long");
    }

    if (!$b_nolink) {
	$v->{kernel_or_dev} = '/boot/' . kernel_str2vmlinuz_short($kernel_str);
	    _do_the_symlink($bootloader, $v->{kernel_or_dev}, $vmlinuz_long);

	if ($v->{initrd}) {
	    $v->{initrd} = '/boot/' . kernel_str2initrd_short($kernel_str);
		_do_the_symlink($bootloader, $v->{initrd}, $initrd_long);
	}
    }

    add_entry($bootloader, $v);
}

=item rebuild_initrds($bootloader)

Rebuilds all initrds

=cut

sub rebuild_initrds {
    my ($bootloader) = @_;

    my %done;
    foreach my $v (grep { $_->{initrd} } @{$bootloader->{entries}}) {
	my $kernel_str = vmlinuz2kernel_str($v->{kernel_or_dev}) or next;
	my $initrd_long = '/boot/' . kernel_str2initrd_long($kernel_str);
	next if $done{$initrd_long}++;

	rebuild_initrd($kernel_str->{version}, $bootloader, $v, $initrd_long);
    }
}

# unused (?)
sub duplicate_kernel_entry {
    my ($bootloader, $new_label) = @_;

    get_label($new_label, $bootloader) and return;

    my $entry = { %{ get_label('linux', $bootloader) }, label => $new_label };
    add_entry($bootloader, $entry);
}

my $uniq_dict_appends = join('|', qw(acpi pci resume PROFILE XFree));

sub unpack_append {
    my ($s) = @_;
    my @l = "$s " =~ /((?:[^"\s]+|".*?")*)\s+/g;
    [ grep { !/=/ } @l ], [ map { if_(/(.*?)=(.*)/, [$1, $2]) } @l ];
}
sub pack_append {
    my ($simple, $dict) = @_;

    #- normalize
    $simple = [ reverse(uniq(reverse @$simple)) ];
    $dict = [ reverse(uniq_ { 
	my ($k, $v) = @$_; 
	$k =~ /^($uniq_dict_appends)$/ ? $k : "$k=$v";
    } reverse @$dict) ];

    join(' ', @$simple, map { "$_->[0]=$_->[1]" } @$dict);
}

sub modify_append {
    my ($b, $f) = @_;

    my @l = grep { $_->{type} eq 'image' && !$_->{keep_verbatim} && !($::isStandalone && $_->{label} eq 'failsafe') } @{$b->{entries}};

    foreach (\$b->{perImageAppend}, map { \$_->{append} } @l) {
	my ($simple, $dict) = unpack_append($$_);
	$f->($simple, $dict);
	$$_ = pack_append($simple, $dict);
	log::l("modify_append: $$_");
    }
}

sub get_append_simple {
    my ($b, $key) = @_;
    my ($simple, $_dict) = unpack_append($b->{perImageAppend});
    member($key, @$simple);
}
sub get_append_with_key {
    my ($b, $key) = @_;
    my ($_simple, $dict) = unpack_append($b->{perImageAppend});
    my @l = map { $_->[1] } grep { $_->[0] eq $key } @$dict;

    log::l("more than one $key in $b->{perImageAppend}") if @l > 1;
    $l[0];
}
sub remove_append_simple {
    my ($b, $key) = @_;
    modify_append($b, sub {
	my ($simple, $_dict) = @_;
	@$simple = grep { $_ ne $key } @$simple;
    });
}
sub set_append_with_key {
    my ($b, $key, $val) = @_;

    modify_append($b, sub {
	my ($_simple, $dict) = @_;

	if ($val eq '') {
	    @$dict = grep { $_->[0] ne $key } @$dict;
	} else {
	    push @$dict, [ $key, $val ];
	}
    });
}
sub set_append_simple {
    my ($b, $key) = @_;

    modify_append($b, sub {
	my ($simple, $_dict) = @_;
	@$simple = uniq(@$simple, $key);
    });
}
sub may_append_with_key {
    my ($b, $key, $val) = @_;
    set_append_with_key($b, $key, $val) if !get_append_with_key($b, $key);
}

sub get_append_netprofile {
    my ($e) = @_;
    my ($simple, $dict) = unpack_append($e->{append});
    my ($p, $dict_) = partition { $_->[0] eq 'PROFILE' } @$dict;
    pack_append($simple, $dict_), $p->[0][1];
}
sub set_append_netprofile {
    my ($e, $append, $profile) = @_;
    my ($simple, $dict) = unpack_append($append);
    push @$dict, [ 'PROFILE', $profile ] if $profile;
    $e->{append} = pack_append($simple, $dict);
}

=item configure_entry($bootloader, $entry)

Used when a bootloader $entry has been modified (eg: $entry->{vga})

=cut

sub configure_entry {
    my ($bootloader, $entry) = @_;
    $entry->{type} eq 'image' or return;

    if (my $kernel_str = vmlinuz2kernel_str($entry->{kernel_or_dev})) {
	$entry->{initrd} = 
	  mkinitrd($kernel_str->{version}, $bootloader, $entry,
		   $entry->{initrd} || '/boot/' . kernel_str2initrd_short($kernel_str));
    }
}

sub get_kernels_and_labels_before_kernel_remove {
    my ($to_remove_kernel) = @_;
    my @kernels = grep { $_ ne $to_remove_kernel } installed_vmlinuz();
    map { kernel_str2label($_) => $_ } get_kernel_labels(\@kernels);
}

sub get_kernels_and_labels() {
    get_kernel_labels([ installed_vmlinuz() ]);
}

sub get_kernel_labels {
    my ($kernels) = @_;
    
    my @kernels_str = 
      sort { common::cmp_kernel_versions($b->{version_no_ext}, $a->{version_no_ext}) } 
      grep { -d "$::prefix/lib/modules/$_->{version}" }
      map { vmlinuz2kernel_str($_) } @$kernels;

    my %labels;
    foreach (@kernels_str) {
	if ($labels{$_->{ext}}) {
	    $_->{use_long_name} = 1;
	} else {
	    $labels{$_->{ext}} = 1;
	}
    }

    $kernels_str[0]{ext} = '';

    @kernels_str;
}

sub short_ext {
    my ($kernel_str) = @_;

    my $short_ext = {
	'xen0' => 'xen',
    }->{$kernel_str->{ext}};

    $short_ext || $kernel_str->{ext};
}

sub _sanitize_ver {
    my ($kernel_str) = @_;

    my $name = $kernel_str->{basename};
    $name = '' if $name eq 'vmlinuz';

    my $v = $kernel_str->{version_no_ext};

    $v =~ s!(md[kv]|mnb)$!!;
    $v =~ s!-0\.(pre|rc)(\d+)\.!$1$2-!;

    my $return = join(' ', grep { $_ } $name, short_ext($kernel_str), $v);

    $return;
}

=item suggest_message_text($bootloader)

Provides a description text for Lilo

=cut

sub suggest_message_text {
    my ($bootloader) = @_;

    if (!$bootloader->{message} && !$bootloader->{message_text}) {
	my $msg_en =
#-PO: these messages will be displayed at boot time in the BIOS, use only ASCII (7bit)
N_("Welcome to the operating system chooser!

Choose an operating system from the list above or
wait for default boot.

");
	my $msg = translate($msg_en);
	#- use the English version if more than 40% of 8bits chars
	#- else, use the translation but force a conversion to ascii
	#- to be sure there won't be undisplayable characters
	if (int(grep { $_ & 0x80 } unpack "c*", $msg) / length($msg) > 0.4) {
	    $msg = $msg_en;
	} else {
	    $msg = Locale::gettext::iconv($msg, "utf-8", "ascii//TRANSLIT");
	}
	$bootloader->{message_text} = $msg;
    }
}

sub suggest {
    my ($bootloader, $all_hds, %options) = @_;
    my $fstab = [ fs::get::fstab($all_hds) ];
    my $root_part = fs::get::root($fstab);
    my $root = isLoopback($root_part) ? '/dev/loop7' : fs::wild_device::from_part('', $root_part);
    my $boot = fs::get::root($fstab, 'boot')->{device};
    my $mbr;
    
    # If installing onto an USB drive, put the MBR there, else on the first non removable drive
    if ($root_part->{is_removable}) {
        $mbr = fs::get::part2hd($root_part, $all_hds);
    } else {
        $mbr = find { !$_->{is_removable} } @{$all_hds->{hds}};
    }

    my ($onmbr, $unsafe) = $bootloader->{crushMbr} ? (1, 0) : suggest_onmbr($mbr);
    add2hash_($bootloader,
	{
	 bootUnsafe => $unsafe,
	 entries => [],
	 timeout => $onmbr && 10,
	 nowarn => 1,
	 boot => "/dev/" . ($onmbr ? $mbr->{device} : $boot),
	 map => "/boot/map",
	 compact => 1,
    	 'large-memory' => 1,
	 color => 'black/cyan yellow/cyan',
	 'menu-scheme' => 'wb:bw:wb:bw'
	});

    suggest_message_text($bootloader);

    add2hash_($bootloader, { memsize => $1 }) if cat_("/proc/cmdline") =~ /\bmem=(\d+[KkMm]?)(?:\s.*)?$/;
    if (my ($s, $port, $speed) = cat_("/proc/cmdline") =~ /console=(ttyS(\d),(\d+)\S*)/) {
	log::l("serial console $s $port $speed");
	set_append_with_key($bootloader, console => $s);
	any::set_login_serial_console($port, $speed);
    }

    my @kernels = get_kernels_and_labels() or die "no kernel installed";
    log::l("found kernels: ", join(', ', map { $_->{version} } @kernels));

    my %old_kernels = map { vmlinuz2version($_->{kernel_or_dev}) => 1 } @{$bootloader->{entries}};
    @kernels = grep { !$old_kernels{$_->{version}} } @kernels;

    #- remove existing failsafe and linux-nonfb, do not care if the previous one was modified by the user?
    @{$bootloader->{entries}} = grep { !member($_->{label}, qw(failsafe linux-nonfb)) } @{$bootloader->{entries}};

    foreach my $kernel (@kernels) {
	my $e = add_kernel($bootloader, $kernel,
	       {
		root => $root,
		if_($options{vga_fb}, vga => $options{vga_fb}), #- using framebuffer
		if_($options{vga_fb} && $options{splash}, append => "splash noiswmd audit=0"),
		if_($options{quiet}, append => "splash quiet noiswmd audit=0"),
	       });

	if ($options{vga_fb} && $e->{label} eq 'linux') {
	    add_kernel($bootloader, $kernel, { root => $root, label => 'linux-nonfb' });
	}
    }

    add_kernel($bootloader, $kernels[0],
	       { root => $root, label => 'failsafe', append => 'failsafe noiswmd audit=0' })
      if @kernels;

	#- search for dos (or windows) boot partition. Do not look in extended partitions!
	my @windows_boot_parts =
	  grep { $_->{active}
		 && isFat_or_NTFS($_) && member(fs::type::fs_type_from_magic($_), qw(vfat ntfs ntfs-3g))
		 && !$_->{is_removable}
		 && !isRecovery($_);
	     }
	    map { @{$_->{primary}{normal}} } @{$all_hds->{hds}};
	each_index {
	    add_entry($bootloader,
		      {
		       type => 'other',
		       kernel_or_dev => "/dev/$_->{device}",
		       label => 'windows' . ($::i || ''),
		       table => "/dev/$_->{rootDevice}",
		       makeactive => 1,
		      });
	} @windows_boot_parts;

    my @preferred = map { "linux-$_" } 'server';
    if (my $preferred = find { get_label($_, $bootloader) } @preferred) {
	$bootloader->{default} ||= $preferred;
    }
    $bootloader->{default} ||= "linux";
    $bootloader->{method} ||= first(method_choices($all_hds, 1), # best installed
				    method_choices($all_hds, 0)); # or best if no valid one is installed

    $bootloader->{perImageAppend} = $bootloader->{entries}[0]{append};
    $bootloader->{default_vga} = $options{vga_fb};

    if (main_method($bootloader->{method}) eq 'grub') {
	my %processed_entries = {};
	foreach my $c (find_other_distros_grub_conf($fstab)) {	    
	    my %h = (
		     type => 'grub_configfile',
		     label => $c->{name},
		     kernel_or_dev => "/dev/$c->{bootpart}{device}",
		     configfile => $c->{grub_conf},
		    );
	    if ($c->{root}) {
		my $key = "$c->{name} - $c->{linux} - $c->{initrd}";
		next if $processed_entries{$key};
		$processed_entries{$key} = 1;
		add_entry($bootloader, {
		    %h,
		    linux => $c->{linux},
		    initrd => $c->{initrd},
		    root => $c->{root},
		});
	    } else {
		add_entry($bootloader, \%h);
	    }
	}
    }
}

sub detect_main_method {
    my ($all_hds) = @_;
    my $bootloader = &read($all_hds);
    $bootloader && main_method($bootloader->{method});
}

sub main_method {
    my ($method) = @_;
    $method =~ /(\w+)/ && $1;
}

sub config_files() {
    my %files = (
	lilo => '/etc/lilo.conf',
	grub => '/boot/grub/menu.lst',
	grub_install => '/boot/grub/install.sh',
    );
    
    map_each { 
	my $content = cat_("$::prefix/$::b");
	{ main_method => main_method($::a), name => $::a, file => $::b, content => $content };
    } %files;
}

sub method2text {
    my ($method) = @_;
    +{
	'lilo-menu'    => N("LILO with text menu"),
	'grub2-graphic' => N("GRUB2 with graphical menu"),
	'grub2'        => N("GRUB2 with text menu"),
	'grub-graphic' => N("GRUB with graphical menu"),
	'grub-menu'    => N("GRUB with text menu"),
    }->{$method};
}


=item method_choices_raw($b_prefix_mounted)

Returns list of bootloaders.

method_choices_raw(1) will return the list of installed boot loaders.

method_choices_raw(0) will return the list of all boot loaders supported by drakboot.

Returns: ("grub2", "grub2-graphic")

=cut

sub method_choices_raw {
    my ($b_prefix_mounted) = @_;
    detect_devices::is_xbox() ? 'cromwell' :
    arch() =~ /arm/ ? 'uboot' :
       if_(!$b_prefix_mounted || whereis_binary('grub2-reboot', $::prefix), 
	   'grub2-graphic', 'grub2'),
      # only grub2 works on UEFI:
      # lilo & grub-legacy do not suppport new ext4/xfs format and are unmainted so only allow them on upgrade:
      if_(!is_uefi() && !($::isInstall && !$::o->{isUpgrade} || $::isLiveInstall), (
       if_(!$b_prefix_mounted || whereis_binary('grub', $::prefix) && -f "$::prefix/boot/grub/install.sh", 
	   'grub-graphic', 'grub-menu'),
       if_(!$b_prefix_mounted || whereis_binary('lilo', $::prefix) && -f "$::prefix/etc/lilo.conf", 
	   'lilo-menu'),
      ));
}

=item method_choices($all_hds, $b_prefix_mounted)

Returns list of supported bootloaders according to what is detected.

Like method_choices_raw(), the $b_prefix_mounted parameter enables to return the list of either installed supported methods or the list of all supported boot loaders.

=cut

sub method_choices {
    my ($all_hds, $b_prefix_mounted) = @_;
    my $fstab = [ fs::get::fstab($all_hds) ];
    my $root_part = fs::get::root($fstab);
    my $boot_part = fs::get::root($fstab, 'boot');
    my $have_dmraid = find { fs::type::is_dmraid($_) } @{$all_hds->{hds}};

    grep {
	!(/lilo/ && (isLoopback($root_part) || $have_dmraid))			# LILO doesn't work fake raid
	  && (/grub2/ || $boot_part->{fs_type} ne 'btrfs')			# Only grub2 works on btrfs
	  && !(/grub2?-graphic/ && cat_("/proc/cmdline") =~ /console=ttyS/);	# No Gfx mode on console
    } method_choices_raw($b_prefix_mounted);
}

=item main_method_choices($b_prefix_mounted)

Returns list of supported bootloaders, not distinging text/gfx mode.

Like method_choices_raw(), the $b_prefix_mounted parameter enables to return the list of either installed supported methods or the list of all supported boot loaders.

=cut

sub main_method_choices {
    my ($b_prefix_mounted) = @_;
    uniq(map { main_method($_) } method_choices_raw($b_prefix_mounted));
}
sub configured_main_methods() {
    my @bad_main_methods = map { if_(!$_->{content}, $_->{main_method}) } config_files();
    difference2([ main_method_choices(1) ], \@bad_main_methods);
}

# for lilo
sub keytable {
    my ($f) = @_;
    $f or return;

    if ($f !~ /\.klt$/) {
	my $file = "/boot/$f.klt";
	run_program::rooted($::prefix, "keytab-lilo.pl", ">", $file, $f) or return;
	$f = $file;
    }
    -r "$::prefix/$f" && $f;
}

sub check_enough_space() {
    my $e = "$::prefix/boot/.enough_space";
    output $e, 1; -s $e or die N("not enough room in /boot");
    unlink $e;
}

sub install_uboot { 
    my ($_bootloader, $_all_hds) = @_;
    log::l("uboot - nothing to install...");
}
sub write_uboot { 
    my ($_bootloader, $_all_hds) = @_;
    log::l("uboot - nothing to write...");
}
sub when_config_changed_uboot {
    my ($_bootloader) = @_;
    #- do not do anything
}

sub install_cromwell { 
    my ($_bootloader, $_all_hds) = @_;
    log::l("XBox/Cromwell - nothing to install...");
}
sub write_cromwell { 
    my ($_bootloader, $_all_hds) = @_;
    log::l("XBox/Cromwell - nothing to write...");
}
sub when_config_changed_cromwell {
    my ($_bootloader) = @_;
    #- do not do anything
}

sub simplify_label {
    my ($label) = @_;

    length($label) < 31 or $label =~ s/\.//g;

    $label = substr($label, 0, 31); #- lilo does not handle more than 31 char long labels
    $label =~ s/ /_/g; #- lilo does not support blank character in image names, labels or aliases
    $label;
}

sub make_label_lilo_compatible {
    my ($label) = @_;
    '"' . simplify_label($label) . '"';
}

sub write_lilo {
    my ($bootloader, $all_hds, $o_backup_extension) = @_;
    $bootloader->{prompt} ||= $bootloader->{timeout};

    my $file2fullname = sub {
	my ($file) = @_;
	if (arch() =~ /ia64/) {
	    my $fstab = [ fs::get::fstab($all_hds) ];
	    (my $part, $file) = fs::get::file2part($fstab, $file);
	    my %hds = map_index { $_ => "hd$::i" } map { $_->{device} } 
	      sort { 
		  my ($a_is_fat, $b_is_fat) = ($a->{fs_type} eq 'vfat', $b->{fs_type} eq 'vfat');
		  $a_is_fat <=> $b_is_fat || $a->{device} cmp $b->{device};
	      } @$fstab;
	    $hds{$part->{device}} . ":" . $file;
	} else {
	    $file;
	}
    };

    my $quotes = sub {
	my ($s) = @_;
	$s =~ s/"/\\"/g;
	qq("$s");
    };

    my $quotes_if_needed = sub {
	my ($s) = @_;
	$s =~ /["=\s]/ ? $quotes->($s) : $s;
    };
    

    my @sorted_hds = sort_hds_according_to_bios($bootloader, $all_hds);

    if (is_empty_hash_ref($bootloader->{bios} ||= {}) && $all_hds->{hds}[0] != $sorted_hds[0]) {
	log::l("Since we're booting on $sorted_hds[0]{device}, make it bios=0x80");
	$bootloader->{bios} = { "/dev/$sorted_hds[0]{device}" => '0x80' };
    }

    my @conf;

    #- normalize: RESTRICTED and MANDATORY are only valid if PASSWORD is set
    if ($bootloader->{password}) {
	# lilo defaults to mandatory, use restricted by default to have 
	# the same behaviour as with grub
	$bootloader->{restricted} = 1;
    } else {
        delete $bootloader->{mandatory} if !$bootloader->{password};
        delete $bootloader->{restricted} if !$bootloader->{password};
    }
    foreach my $entry (@{$bootloader->{entries}}) {
	delete $entry->{mandatory} if !$entry->{password} && !$bootloader->{password};
	delete $entry->{restricted} if !$entry->{password} && !$bootloader->{password};
    }
    if (get_append_with_key($bootloader, 'console') =~ /ttyS(.*)/) {
	$bootloader->{serial} ||= $1;
    }

    if (!get_label($bootloader->{default}, $bootloader)) {
	log::l("default bootloader entry $bootloader->{default} is invalid, choosing another one");
	$bootloader->{default} = $bootloader->{entries}[0]{label};
    }
    push @conf, "# File generated by DrakX/drakboot";
    push @conf, "# WARNING: do not forget to run lilo after modifying this file\n";
    push @conf, "default=" . make_label_lilo_compatible($bootloader->{default}) if $bootloader->{default};
    push @conf, map { $_ . '=' . $quotes_if_needed->($bootloader->{$_}) } grep { $bootloader->{$_} } qw(boot root map install serial vga keytable raid-extra-boot menu-scheme vmdefault);
    push @conf, grep { $bootloader->{$_} } qw(linear geometric compact prompt mandatory nowarn restricted static-bios-codes large-memory);
    push @conf, "append=" . $quotes->($bootloader->{append}) if $bootloader->{append};
    push @conf, "password=" . $bootloader->{password} if $bootloader->{password}; #- also done by msec
    push @conf, "timeout=" . round(10 * $bootloader->{timeout}) if $bootloader->{timeout};
    
    push @conf, "message=$bootloader->{message}" if $bootloader->{message};

    push @conf, "ignore-table" if any { $_->{unsafe} && $_->{table} } @{$bootloader->{entries}};

    push @conf, map_each { "disk=$::a bios=$::b" } %{$bootloader->{bios}};

    foreach my $entry (@{$bootloader->{entries}}) {
	my $mbootpack_file = get_mbootpack_filename($entry);
        if ($mbootpack_file && !build_mbootpack($entry)) {
	    warn "mbootpack is required for xen but unavailable, skipping\n";
	    next;
	}
	if ($entry->{type} eq 'grub_configfile') {
	    next;
	}

	push @conf, "$entry->{type}=" . $file2fullname->($mbootpack_file || $entry->{kernel_or_dev});
	my @entry_conf;
	push @entry_conf, "label=" . make_label_lilo_compatible($entry->{label}) if $entry->{label};

	if ($entry->{type} eq "image") {		
	    push @entry_conf, 'root=' . $quotes_if_needed->($entry->{root}) if $entry->{root} && !$entry->{xen};
	    push @entry_conf, "initrd=" . $file2fullname->($entry->{initrd}) if $entry->{initrd} && !$mbootpack_file;
	    my $append = join(' ', if_($entry->{xen_append}, $entry->{xen_append}),
	                           if_($entry->{xen}, '--', 'root=' . $entry->{root}),
	                           if_($entry->{append}, $entry->{append}));
	    push @entry_conf, "append=" . $quotes->($append) if $append;
	    push @entry_conf, "vga=$entry->{vga}" if $entry->{vga};
	    push @entry_conf, grep { $entry->{$_} } qw(read-write read-only optional);
	    push @entry_conf, "mandatory" if $entry->{lock};
	} else {
	    delete $entry->{unsafe} if $entry->{table}; #- we can't have both
	    push @entry_conf, map { "$_=$entry->{$_}" } grep { $entry->{$_} } qw(table boot-as);
	    push @entry_conf, grep { $entry->{$_} } qw(unsafe master-boot);
		
	    if ($entry->{table}) {
		#- hum, things like table=c: are needed for some os2 cases,
		#- in that case $hd below is undef
		my $hd = fs::get::device2part($entry->{table}, $all_hds->{hds});
		if ($hd && $hd != $sorted_hds[0]) {		       
		    #- boot off the nth drive, so reverse the BIOS maps
		    my $nb = sprintf("0x%x", 0x80 + (find_index { $hd == $_ } @sorted_hds));
		    $entry->{mapdrive} ||= { '0x80' => $nb, $nb => '0x80' }; 
		}
	    }
	    if ($entry->{mapdrive}) {
		push @entry_conf, map_each { "map-drive=$::a", "   to=$::b" } %{$entry->{mapdrive}};
	    }
	}
	push @entry_conf, "password=$entry->{password}" if $entry->{password};
	push @entry_conf, grep { $entry->{$_} } qw(mandatory vmwarn vmdisable);

	push @conf, map { "\t$_" } @entry_conf;
    }
    my $f = arch() =~ /ia64/ ? "$::prefix/boot/efi/elilo.conf" : "$::prefix/etc/lilo.conf";

    log::l("writing lilo config to $f");
    renamef($f, $f . ($o_backup_extension || '.old'));
    output_with_perm($f, $bootloader->{password} ? 0600 : 0644, map { "$_\n" } @conf);
}

sub install_lilo {
    my ($bootloader, $all_hds) = @_;

    if (my ($install) = $bootloader->{method} =~ /lilo-(text|menu)/) {
	$bootloader->{install} = $install;
    } else {
	delete $bootloader->{install};
    }
    if ($bootloader->{message_text}) {
	output("$::prefix/boot/message-text", $bootloader->{message_text});
    }
    my $message = "message-text";
    if (-r "$::prefix/boot/$message") {
	symlinkf $message, "$::prefix/boot/message";
	$bootloader->{message} = '/boot/message';
    }

    #- ensure message does not contain the old graphic format
    if ($bootloader->{message} && -s "$::prefix$bootloader->{message}" > 65_000) {
	output("$::prefix$bootloader->{message}", '');
    }

    write_lilo($bootloader, $all_hds);

    when_config_changed_lilo($bootloader);

    configure_kdm_BootManager('Lilo');
}

sub install_raw_lilo {
    my ($o_force_answer) = @_;

    my $error;
    my $answer = $o_force_answer || '';
    run_program::rooted($::prefix, "echo $answer | lilo", '2>', \$error) or die "lilo failed: $error";
}

sub when_config_changed_lilo {
    my ($bootloader) = @_;
    if (!$::testing && $bootloader->{method} =~ /lilo/) {
	log::l("Installing boot loader on $bootloader->{boot}...");
	install_raw_lilo($bootloader->{force_lilo_answer});
    }
}

#- NB: ide is lower than scsi, this is important for sort_hds_according_to_bios()
sub hd2bios_kind {
    my ($hd) = @_;
    lc(join('_', $hd->{bus}, $hd->{host}));
}

sub ensafe_first_bios_drive {
    my ($hds) = @_;
    mixed_kind_of_disks($hds) || @$hds > 1 && _not_first_bios_drive($hds->[0]);
}
sub mixed_kind_of_disks {
    my ($hds) = @_;
    (uniq_ { hd2bios_kind($_) } @$hds) > 1;
}
sub _not_first_bios_drive {
    my ($hd) = @_;
    my $bios = $hd && $hd->{bios_from_edd};
    $bios && $bios ne '80';
}

sub sort_hds_according_to_bios {
    my ($bootloader, $all_hds) = @_;
    my $boot_hd = fs::get::device2part($bootloader->{first_hd_device} || $bootloader->{boot}, $all_hds->{hds}); #- $boot_hd is undefined when installing on floppy
    my $boot_kind = $boot_hd && hd2bios_kind($boot_hd);

    my $translate = sub {
	my ($hd) = @_;
	my $kind = hd2bios_kind($hd);
	$boot_hd ? ($hd == $boot_hd ? 0 : $kind eq $boot_kind ? 1 : 2) . "_$kind" : $kind;
    };
    sort { $translate->($a) cmp $translate->($b) } @{$all_hds->{hds}};
}

sub device_string2grub {
    my ($dev, $legacy_floppies, $sorted_hds) = @_;
    if (my $device = fs::get::device2part($dev, [ @$sorted_hds, fs::get::hds_fstab(@$sorted_hds) ])) {
	device2grub($device, $sorted_hds);
    } elsif (my $floppy = fs::get::device2part($dev, $legacy_floppies)) {
	my $bios = find_index { $floppy eq $_ } @$legacy_floppies;
	"(fd$bios)";
    } else {
	internal_error("unknown device $dev");
    }
}
sub device2grub {
    my ($device, $sorted_hds) = @_;

    if (isRAID($device) && $device->{level} == 1) {
	#- we can take any disk
	$device = $device->{disks}[0];
    }
    my ($hd, $part_nb) = 
      $device->{rootDevice} ?
	(fs::get::device2part($device->{rootDevice}, $sorted_hds), $device->{device} =~ /(\d+)$/) :
	$device;
    my $bios = eval { find_index { $hd eq $_ } @$sorted_hds };
    if (defined $bios) {
	my $part_string = defined $part_nb ? ',' . ($part_nb - 1) : '';    
	"(hd$bios$part_string)";
    } else {
	undef;
    }
}

sub read_grub_device_map() {
    my %grub2dev = map { m!\((.*)\)\s+/dev/(.*)$! } cat_("$::prefix/boot/grub/device.map");
    \%grub2dev;
}
sub write_grub_device_map {
    my ($legacy_floppies, $sorted_hds) = @_;
    my $f = "$::prefix/boot/grub/device.map";
    renamef($f, "$f.old");
    output($f,
	   (map_index { "(fd$::i) /dev/$_->{device}\n" } @$legacy_floppies),
	   (map_index { "(hd$::i) /dev/$_->{device}\n" } @$sorted_hds));
}

=item parse_grub_file($grub_file)

Parses things like C<(hd0,4)/boot/vmlinuz>

Returns: ("hd0", 4, "boot/vmlinuz")

=cut

sub parse_grub_file {
    my ($grub_file) = @_;
    my ($grub_dev, $rel_file) = $grub_file =~ m!\((.*?)\)/?(.*)! or return;
    my ($hd, $part) = split(',', $grub_dev);
    ($hd, $part, $rel_file);
}

=item grub2dev_and_file($grub_file, $grub2dev, $o_block_device)

Takes things like C<(hd0,4)/boot/vmlinuz>

Returns: ("/dev/sda5", "boot/vmlinuz")

=cut

sub grub2dev_and_file {
    my ($grub_file, $grub2dev, $o_block_device) = @_;
    my ($hd, $part, $rel_file) = parse_grub_file($grub_file) or return;
    $grub2dev->{$hd} or internal_error("$hd has no mapping in device.map (when translating $grub_file)");
    $part = $o_block_device ? '' : defined $part && $part + 1; #- grub wants "(hdX,Y)" where lilo just want "hdY+1"
    my $device = '/dev/' . ($part eq '' ? $grub2dev->{$hd} : devices::prefix_for_dev($grub2dev->{$hd}) . $part);
    $device, $rel_file;
}

=item grub2devd($grub_file, $grub2dev, $o_block_device)

Takes things like C<(hd0,4)/boot/vmlinuz>

Returns: "/dev/sda5"

=cut

sub grub2dev {
    my ($grub_file, $grub2dev, $o_block_device) = @_;
    first(grub2dev_and_file($grub_file, $grub2dev, $o_block_device));
}

=item grub2file($grub_file, $grub2dev, $fstab, $o_entry)

Replaces

=over 4

=item * C</vmlinuz> with C</boot/vmlinuz> when "root" or "rootnoverify" is set for the entry

=item * C<(hdX,Y)> in C<(hdX,Y)/boot/vmlinuz...> by appropriate path if possible/needed

=back

=cut

sub grub2file {
    my ($grub_file, $grub2dev, $fstab, $o_entry) = @_;

    if ($grub_file =~ m!^/!) {
	my $root = $o_entry && ($o_entry->{rootnoverify} || $o_entry->{grub_root});
	$root and $grub_file = "$root$grub_file";
    }

    if (my ($device, $rel_file) = grub2dev_and_file($grub_file, $grub2dev)) {	
	my $part = fs::get::device2part($device, $fstab);
	if (my $mntpoint = $part && $part->{mntpoint})  {
	    ($mntpoint eq '/' ? '' : $mntpoint) . '/' . $rel_file;
	} else {
	    log::l("ERROR: unknown device $device (computed from $grub_file)");
	    $grub_file;
	}
    } else {
	$grub_file;
    }
}

sub boot_copies_dir() { '/boot/copied' }
sub create_copy_in_boot {
    my ($file) = @_;

    my $s = $file;
    $s =~ s!/!_!g;
    my $file2 = boot_copies_dir() . "/$s";

    log::l("$file is not available at boot time, creating a copy ($file2)");
    mkdir_p(boot_copies_dir());
    output("$file2.link", $file . "\n");
    update_copy_in_boot("$file2.link");

    $file2;
}
sub update_copy_in_boot {
    my ($link) = @_;
    my $orig = chomp_(cat_("$::prefix$link"));
    (my $dest = $link) =~ s/\.link$// or internal_error("update_copy_in_boot: $link");
    if (-e "$::prefix$orig") {
	log::l("updating $dest from $orig");
	cp_af("$::prefix$orig", "$::prefix$dest");
    } else {
	log::l("removing $dest since $orig does not exist anymore");
	unlink "$::prefix$link", "$::prefix$orig";
    }
}

sub crypt_grub_password {
    my ($password) = @_;
    require IPC::Open2;
    local $ENV{LC_ALL} = 'C';
    my ($his_out, $his_in);
    my $cmd = ($::prefix ? "chroot $::prefix " : "") . "/sbin/grub-md5-crypt";

    my $pid = IPC::Open2::open2($his_out, $his_in, $cmd);

    my ($line, $res);
    while (sysread($his_out, $line, 100)) {
        if ($line =~ /Password/i) {
            syswrite($his_in, "$password\n");
        } else {
            $res = $line;
        }
    }
    waitpid($pid, 0);
    my $status = $? >> 8;           
    die "failed to encrypt password (status=$status)" if $status != 0;
    chomp_($res);
}

sub get_grub2_first_entry {
    my ($bootloader) = @_;
    # set default parameters:
    my ($entry) = grep { $_->{kernel_or_dev} =~ /vmlin/ } @{$bootloader->{entries}};
    $entry;
}

sub get_grub2_append {
    my ($bootloader) = @_;
    # get default parameters from first entry:
    my ($entry) = get_grub2_first_entry($bootloader);
    my $append = $entry->{append};
    if (my $vga = $entry->{vga} || $bootloader->{vga}) {
	$append .= " vga=$vga";
    }
    $append =~ s/root=\S+//g;
    $append =~ s/\bro\b//g;
    $append =~ s/\s+/ /g;
    $append;
}

sub crypt_grub2_password {
    my ($password) = @_;
    require IPC::Open2;
    local $ENV{LC_ALL} = 'C';
    my ($his_out, $his_in);
    my $pid = IPC::Open2::open2($his_out, $his_in, "$::prefix/bin/grub2-mkpasswd-pbkdf2");

    my ($line, $res);
    while (sysread($his_out, $line, 100)) {
        if ($line =~ /enter.*password:/i) {
            syswrite($his_in, "$password\n");
        } else {
            chomp($line);
            $res .= $line if $line;
        }
    }
    $res =~ s/^PBKDF2 hash of your password is //;
    waitpid($pid, 0);
    my $status = $? >> 8;
    die "failed to encrypt password (status=$status)" if $status != 0;
    chomp_($res);
}

sub write_grub2_sysconfig {
    my ($bootloader, $_all_hds, $o_backup_extension) = @_;

    # Set password prior to run update-grub2:
    my $pw_f = get_grub2_users();
    if ($bootloader->{password}) {
	if (!is_grub2_already_crypted($bootloader->{password})) {
	    $bootloader->{password} = crypt_grub2_password($bootloader->{password});
        }
	output_with_perm($pw_f, 0600, "GRUB2_PASSWORD=$bootloader->{password}");
    } else {
	unlink($pw_f);
    }

    my $f = "$::prefix/etc/default/grub";
    my %conf = getVarsFromSh($f);

    my $append = $bootloader->{perImageAppend} || get_grub2_append($bootloader);
    my $vga = $bootloader->{default_vga};
    $append .= " vga=$vga" if $append !~ /vga=/ && $vga && $vga ne "normal";

    $conf{GRUB_CMDLINE_LINUX_DEFAULT} = $append;
    $conf{GRUB_GFXPAYLOAD_LINUX} = 'auto' if is_uefi();
    $conf{GRUB_DISABLE_RECOVERY} = 'false'; # for 'failsafe' entry
    $conf{GRUB_DEFAULT} //= 'saved'; # for default entry but do not overwrite user choice
    $conf{GRUB_SAVEDEFAULT} //= 'true'; # for default entry but do not overwrite user choice
    $conf{GRUB_TIMEOUT} = $bootloader->{timeout};
    renamef($f, $f . ($o_backup_extension || '.old'));
    setVarsInSh($f, \%conf);
}

sub write_grub2_default_entry {
    my ($bootloader, $_all_hds, $o_backup_extension) = @_;

    my $default = $bootloader->{default};
    # menu entry must be identified by its full path. eg: "submenu1>submenu2>title":
    if (my $def = find { $_->{label} eq $bootloader->{default} } @{$bootloader->{entries}}) {
	$default = $def->{real_label} if $def->{real_label};
    }

    # set default entry:
    eval {
	my $f2 = "$::prefix/boot/grub2/grubenv";
	cp_af($f2, $f2 . ($o_backup_extension || '.old'));
	my $error;
	run_program::rooted($::prefix, 'grub2-set-default', '2>', \$error, $default) or die "grub2-set-default failed: $error";
    };
    if (my $err = $@) {
	log::l("error while running grub2-set-default: $err");
    }
}

sub write_grub2 {
    my ($bootloader, $o_all_hds, $o_backup_extension) = @_;
    my $error;

    write_grub2_sysconfig($bootloader, $o_all_hds, $o_backup_extension);

    my $f1 = "$::prefix/boot/grub2/grub.cfg";
    renamef($f1, $f1 . '.old');
    run_program::rooted($::prefix, 'update-grub2', '2>', \$error) or die "update-grub2 failed: $error";
    log::l("update-grub2 logs: $error");

    write_grub2_default_entry($bootloader, $o_all_hds, $o_backup_extension);
    check_enough_space();
}

sub get_grub2_users() {
    "$::prefix/boot/grub2/user.cfg";
}

sub get_grub2_install_sh() {
    "$::prefix/boot/grub2/install.sh";
}

sub write_grub2_install_sh    {
    my ($bootloader, $o_backup_extension) = @_;
    my $f = get_grub2_install_sh();
    my $boot = $bootloader->{boot};
    my @options;
    if (is_uefi()) {
	push @options, qw(--bootloader-id=tmp --no-nvram) if $bootloader->{no_esp_or_mbr};
    } else {
	@options = $bootloader->{no_esp_or_mbr} ? ('--grub-setup=/bin/true', $boot) : $boot;
    }
    renamef($f, $f . ($o_backup_extension || '.old'));
    output_with_perm($f, 0755, join(' ', 'grub2-install', @options));
}

sub write_grub {
    my ($bootloader, $all_hds, $o_backup_extension) = @_;

    my $fstab = [ fs::get::fstab($all_hds) ]; 
    my @legacy_floppies = detect_devices::floppies();
    my @sorted_hds = sort_hds_according_to_bios($bootloader, $all_hds);
    write_grub_device_map(\@legacy_floppies, \@sorted_hds);

    my $file2grub; $file2grub = sub {
	my ($file) = @_;
	if ($file =~ m!^\(.*\)/!) {
	    $file; #- it's already in grub format
	} else {
	    my ($part, $rel_file) = fs::get::file2part($fstab, $file, 'keep_simple_symlinks');
	    if (my $grub = device2grub($part, \@sorted_hds)) {
		$grub . $rel_file;
	    } elsif (!begins_with($file, '/boot/')) {
		log::l("$file is on device $part->{device} which is not available at boot time. Copying it");
		$file2grub->(create_copy_in_boot($file));
	    } else {
		log::l("ERROR: $file is on device $part->{device} which is not available at boot time. Defaulting to a dumb value");
		"(hd0,0)$file";
	    }
	}
    };

    if (get_append_with_key($bootloader, 'console') =~ /ttyS(\d),(\d+)/) {
	$bootloader->{serial} ||= "--unit=$1 --speed=$2";
	$bootloader->{terminal} ||= "--timeout=" . ($bootloader->{timeout} || 0) . " console serial";
    } elsif ($bootloader->{method} eq 'grub-graphic') {
	my $bin = '/usr/sbin/grub-gfxmenu';
	if ($bootloader->{gfxmenu} eq '' && -x "$::prefix$bin") {
	    my $locale = $::o->{locale} || do { require lang; lang::read() };
	    run_program::rooted($::prefix, $bin, '--lang', $locale->{lang}, '--update-gfxmenu');
	    $bootloader->{gfxmenu} ||= '/boot/gfxmenu';
	}
	#- not handled anymore
	delete $bootloader->{$_} foreach qw(splashimage viewport shade);
    } else {
	delete $bootloader->{gfxmenu};
    }

    my $format = sub { map { "$_ $bootloader->{$_}" } @_ };

    {
	my @conf;

        if ($bootloader->{password}) {
	    if (!is_already_crypted($bootloader->{password})) {
		my $encrypted = crypt_grub_password($bootloader->{password});
		$bootloader->{password} = "--md5 $encrypted";
	    }
        }

	push @conf, $format->(grep { defined $bootloader->{$_} } qw(timeout));
	push @conf, $format->(grep { $bootloader->{$_} } qw(color password serial shade terminal viewport background foreground));

	push @conf, map { $_ . ' ' . $file2grub->($bootloader->{$_}) } grep { $bootloader->{$_} } qw(gfxmenu);

	eval {
	    push @conf, "default " . (find_index { $_->{label} eq $bootloader->{default} } @{$bootloader->{entries}});
	};

	foreach my $entry (@{$bootloader->{entries}}) {
	    my $title = "\ntitle $entry->{label}";

	    if ($entry->{keep_verbatim}) {
		push @conf, '', $entry->{verbatim};
	    } elsif ($entry->{type} eq "image") {
		push @conf, $title;
		push @conf, grep { $entry->{$_} } 'lock';
		push @conf, join(' ', 'kernel', $file2grub->($entry->{xen}), $entry->{xen_append}) if $entry->{xen};

		my $vga = $entry->{vga} || $bootloader->{vga};
		push @conf, join(' ', $entry->{xen} ? 'module' : 'kernel', 
		       $file2grub->($entry->{kernel_or_dev}),
		       $entry->{xen} ? () : 'BOOT_IMAGE=' . simplify_label($entry->{label}),
		       if_($entry->{root}, $entry->{root} =~ /loop7/ ? "root=707" : "root=$entry->{root}"), #- special to workaround bug in kernel (see #ifdef CONFIG_BLK_DEV_LOOP)
		       $entry->{append},
		       if_($entry->{'read-write'}, 'rw'),
		       if_($vga && $vga ne "normal", "vga=$vga"));
		push @conf, "module " . $_ foreach @{$entry->{modules} || []};
		if ($entry->{initrd}) {
		    # split partition from initrd path and place
		    # it to a separate 'root' entry.
		    # Grub2's mkconfig takes initrd entry 'as is',
		    # but grub2 fails to load smth like '(hd0,1)/boot/initrd' taken from grub-legacy
		    my $initrd_path = $file2grub->($entry->{initrd});
		    if ($initrd_path =~ /^(\([^\)]+\))/) {
			push @conf, "root $1";
			$initrd_path =~ s/^(\([^\)]+\))//;
		    }
		    push @conf, join(' ', $entry->{xen} ? 'module' : 'initrd', $initrd_path);
		}
	    } else {
		my $dev = eval { device_string2grub($entry->{kernel_or_dev}, \@legacy_floppies, \@sorted_hds) };
		if (!$dev) {
		    log::l("dropping bad entry $entry->{label} for unknown device $entry->{kernel_or_dev}");
		    next;
		}
		push @conf, $title;
		push @conf, grep { $entry->{$_} } 'lock';
		if ($entry->{type} ne 'grub_configfile' || $entry->{configfile} !~ /grub\.cfg/ || !$entry->{root}) {
		    push @conf, join(' ', $entry->{rootnoverify} ? 'rootnoverify' : 'root', $dev);
		}

		if ($entry->{table}) {
		    if (my $hd = fs::get::device2part($entry->{table}, \@sorted_hds)) {
			if (my $bios = find_index { $hd eq $_ } @sorted_hds) {
			    #- boot off the nth drive, so reverse the BIOS maps
			    my $nb = sprintf("0x%x", 0x80 + $bios);
			    $entry->{mapdrive} ||= { '0x80' => $nb, $nb => '0x80' }; 
			}
		    }
		}
		if ($entry->{mapdrive}) {
		    push @conf, map_each { "map ($::b) ($::a)" } %{$entry->{mapdrive}};
		}
		push @conf, "makeactive" if $entry->{makeactive};
		# grub.cfg is grub2 config, can't use it as configfile for grub-legacy
		if ($entry->{type} eq 'grub_configfile' && $entry->{configfile} !~ /grub\.cfg/) {
		    push @conf, "configfile $entry->{configfile}";
		} elsif ($entry->{linux}) {
		    push @conf, "root $entry->{root}", "kernel $entry->{linux}";
		    push @conf, "initrd $entry->{initrd}" if $entry->{initrd};
		} else {
		    push @conf, "chainloader +1";
		}
	    }
	}
	my $f = "$::prefix/boot/grub/menu.lst";
	log::l("writing grub config to $f");
	renamef($f, $f . ($o_backup_extension || '.old'));
	output_with_perm($f, 0600, map { "$_\n" } @conf);
    }
    {
	my $f = "$::prefix/boot/grub/install.sh";
	my $boot_dev = device_string2grub($bootloader->{boot}, \@legacy_floppies, \@sorted_hds);
	my $files_dev = device2grub(fs::get::root_($fstab, 'boot'), \@sorted_hds);
	renamef($f, $f . ($o_backup_extension || '.old'));
	output_with_perm($f, 0755,
"grub --device-map=/boot/grub/device.map --batch <<EOF
root $files_dev
setup --stage2=/boot/grub/stage2 $boot_dev
quit
EOF
");
    }

    check_enough_space();
}

sub configure_kdm_BootManager {
    my ($name) = @_;
    eval { common::update_gnomekderc_no_create("$::prefix/etc/kde/kdm/kdmrc", 'Shutdown' => (
	BootManager => $name
    )) };
}

sub sync_partition_data_to_disk {
    my ($part) = @_;

    common::sync();

    if ($part->{fs_type} eq 'xfs') {
	run_program::rooted($::prefix, 'xfs_freeze', '-f', $part->{mntpoint});
	run_program::rooted($::prefix, 'xfs_freeze', '-u', $part->{mntpoint});
    }
}

sub _dev_to_MBR_backup {
    my ($dev) = @_;
    $dev =~ s!/dev/!!;
    $dev =~ s!/!_!g;
    "$::prefix/boot/boot.backup.$dev";
}

sub save_previous_MBR_bootloader {
    my ($dev) = @_;
    my $t;
    open(my $F, $dev);
    CORE::read($F, $t, 0x1b8); #- up to disk magic
    output(_dev_to_MBR_backup($dev), $t);
}

sub restore_previous_MBR_bootloader {
    my ($dev) = @_;
    log::l("restoring previous bootloader on $dev");
    output($dev, scalar cat_(_dev_to_MBR_backup($dev)));
}

sub install_grub2 {
    my ($bootloader, $all_hds) = @_;
    write_grub2($bootloader, $all_hds);
    write_grub2_install_sh($bootloader, '.old');
    install_raw_grub2();
}

sub install_raw_grub2() {
    my $error;
    my $f = '/boot/grub2/install.sh';
    if (!run_program::rooted($::prefix, "sh", "2>", \$error, $f)) {
	log::explanations("grub2-install failed:\n(" . cat_($f) . ")\nError: <$error>");
	die "grub2-install failed: $error";
    }
}

sub install_grub {
    my ($bootloader, $all_hds) = @_;

    write_grub($bootloader, $all_hds);

    if (!$::testing) {
	if ($bootloader->{previous_boot} && $bootloader->{previous_boot} eq $bootloader->{boot}) {
	    # nothing to do (already installed in {boot})
	} else {
	    if ($bootloader->{previous_boot}) {
		restore_previous_MBR_bootloader(delete $bootloader->{previous_boot});
	    }
	    if (fs::get::device2part($bootloader->{boot}, [ fs::get::hds($all_hds) ])) {
		save_previous_MBR_bootloader($bootloader->{boot});
		$bootloader->{previous_boot} = $bootloader->{boot};
	    }
	}

	my @files = grep { /(stage1|stage2|_stage1_5)$/ } glob("$::prefix/lib/grub/*/*");
	cp_af(@files, "$::prefix/boot/grub");
	sync_partition_data_to_disk(fs::get::root([ fs::get::fstab($all_hds) ], 'boot'));
	install_raw_grub(); 
    }

    configure_kdm_BootManager('Grub');
}
sub install_raw_grub() {
    log::l("Installing boot loader...");
    my $error;
    run_program::rooted($::prefix, "sh", "2>", \$error, '/boot/grub/install.sh') or die "grub failed: $error";
}

sub when_config_changed_grub2 {
    my ($_bootloader) = @_;
    #- do not do anything
}

sub when_config_changed_grub {
    my ($_bootloader) = @_;
    #- do not do anything

    update_copy_in_boot($_) foreach glob($::prefix . boot_copies_dir() . '/*.link');
}

=item action($bootloader, $action, @para)

Calls the C<$action> function with @para parameters:

   $actions->($bootloader, @para)

If needed, the function name will be resolved to call a boot loader specific function (eg: for LILO/GRUB/...)

=cut

sub action {
    my ($bootloader, $action, @para) = @_;

    my $main_method = main_method($bootloader->{method});
    my $f = $bootloader::{$action . '_' . $main_method} or die "unknown bootloader method $bootloader->{method} ($action)";
    $f->($bootloader, @para);
}

=item install($bootloader, $all_hds)

Writes back the boot loader config. Calls the proper write_XYZ() function.

=cut

sub install {
    my ($bootloader, $all_hds) = @_;

    $bootloader->{keytable} = keytable($bootloader->{keytable}) if $bootloader->{method} eq 'lilo';
    action($bootloader, 'install', $all_hds);
}

sub ensure_pkg_is_installed {
    my ($do_pkgs, $bootloader) = @_;

    my %suppl = (
	# method => [ 'pkg_name', 'file_to_test' ],
	'grub-graphic' => [ qw(mageia-gfxboot-theme /usr/share/gfxboot/themes/Mageia/boot/message) ],
	'grub2-graphic' => [ qw(grub2-mageia-theme /boot/grub2/themes/maggy/theme.txt) ],
    );
    my $main_method = main_method($bootloader->{method});
    if ($main_method eq 'grub2') {
	my $pkg = is_uefi() ? 'grub2-efi' : 'grub2';
	my $prefix = is_uefi() ? (arch() eq 'x86_64' ? 'x86_64-efi' : 'i386-efi') : 'i386-pc';
	$do_pkgs->ensure_is_installed($pkg, "/usr/lib/grub/$prefix/ext2.mod", 1) or return 0;
    } elsif (member($main_method, qw(grub grub2 lilo))) {
	$do_pkgs->ensure_binary_is_installed($main_method, $main_method, 1) or return 0;
    }
    # Install gfx theme if needed:
    if (my $pkg = $suppl{$bootloader->{method}}) {
	$do_pkgs->ensure_is_installed(@$pkg, 1) or return 0;
    }
    1;
}

sub parse_grub2_config {
    my ($l, $grubcfg, $part) = @_;

    my ($linux, $menuentry, $root, $root_dev, $initrd);

    foreach (cat_($grubcfg)) {
	chomp;
	if (/^menuentry\s+['"]([^']+)["']/) {
	    if ($menuentry && $root) {
		my $parttype = partition_table::raw::typeOfMBR($root_dev);
		if ((!$parttype || $parttype eq "empty") && $linux) {
	    	    push @$l, { menuentry => $menuentry, bootpart => $part, root => $root, linux => $linux, initrd => $initrd, grub_conf => $grubcfg };
		}
	    }
	    $menuentry = $1;
	    $root = $linux = undef;
	} elsif (/set root='(\([^\)]+\))'/) {
	    $root = $1;

	    if ($root =~ /\(([^,]+),msdos(\d+)\)/) {
		my $dev_title = "/" . $1;
		my $part_num = $2;
		my $dec_part_num = $part_num-1;
		$dev_title =~ s!hd!dev/sd!;
		$dev_title =~ tr/0123456789/abcdefghi/;

	        $root_dev = $part_num ? $dev_title . $part_num : $dev_title;
               $root =~ s/msdos$part_num/$dec_part_num/;
	    }
	} elsif (/^\s+linux\s+(.+)/) {
	    $linux = $1;
	} elsif (/^\s+initrd\s+(.+)/) {
	    $initrd = $1;
	}
    }
}

=item find_other_distros_grub_conf($fstab)

Returns a list of other distros' grub.conf

=cut

sub find_other_distros_grub_conf {
    my ($fstab) = @_;

    my @unknown_true_fs = 
      grep { isTrueLocalFS($_) && 
	     (!$_->{mntpoint} || !member($_->{mntpoint}, '/home', fs::type::directories_needed_to_boot()));
	 } @$fstab;

    log::l("looking for configured grub on partitions " . join(' ', map { $_->{device} } @unknown_true_fs));

    my @l;
    foreach my $part (@unknown_true_fs) {
	my $handle = any::inspect($part, $::prefix) or next;

	foreach my $bootdir ('', '/boot') {
	    my $f = find { -e "$handle->{dir}$bootdir/$_" } 'grub.conf', 'grub/menu.lst' or next;
	    push @l, { bootpart => $part, bootdir => $bootdir, grub_conf => "$bootdir/$f" };
	}
	foreach my $bootdir ('', '/boot', '/boot/grub', '/boot/grub2') {
	    my $f = find { -e "$handle->{dir}$bootdir/$_" } 'grub.cfg' or next;
	    my $parttype = partition_table::raw::typeOfMBR($part->{device});
	    if (!$parttype || $parttype eq "empty") {
		parse_grub2_config(\@l, "$handle->{dir}/$bootdir/$f", $part);
	    } else {
	        push @l, { bootpart => $part, bootdir => $bootdir, grub_conf => "$bootdir/$f" };
	    }
	}
	if (my $f = common::release_file($handle->{dir})) {
	    my $h = common::parse_release_file($handle->{dir}, $f, $part);
	    $h->{name} = $h->{release};
	    push @l, $h;
	} elsif ($handle && -e "$handle->{dir}/etc/issue") {
	    my ($s, $dropped) = cat_("$handle->{dir}/etc/issue") =~ /^([^\\\n]*)(.*)/;
	    log::l("found /etc/issue: $s (removed: $dropped)");
	    push @l, { name => $s, part => $part };
	}
    }
    my $root;
    my $set_root = sub {
	my ($v) = @_;
	$root and log::l("don't know what to do with $root->{name} ($root->{part}{device})");
	$root = $v;
    };
    my @found;
    while (my $e = shift @l) {
	if ($e->{name}) {
	    $set_root->($e);
	} else {
	    if (@l && $l[0]{name}) {
		$set_root->(shift @l);
	    }

	    my $ok;
	    if ($root && $root->{part} == $e->{bootpart} && $e->{bootdir}) {
		# easy case: /boot is not a separate partition
		$ok = 1;
	    } elsif ($root && $root->{part} != $e->{bootpart} && !$e->{bootdir}) {
		log::l("associating '/' $root->{part}{device} with '/boot' $e->{bootpart}{device}");
		$ok = 1;
	    }
	    if ($ok) {
		add2hash($e, $root);
		undef $root;
	    } elsif ($root) {
		log::l("weird case for grub conf in $e->{bootpart}{device}, keeping '/' from $root->{part}{device}");
	    } else {
		log::l("could not recognise the distribution for $e->{grub_conf} in $e->{bootpart}{device}");
	    }
	    $e->{name} ||= "Linux $e->{bootpart}{device}";
	    push @found, $e;
	}
    }
    $set_root->(undef);

    @found;
}

sub update_for_renumbered_partitions {
    my ($in, $renumbering, $all_hds) = @_;

    my @configs = grep { $_->{content} } config_files();
    $_->{new} = $_->{orig} = $_->{content} foreach @configs;

    my @sorted_hds; {
 	my $grub2dev = read_grub_device_map();
	map_each {
	    $sorted_hds[$1] = fs::get::device2part($::b, $all_hds->{hds}) if $::a =~ /hd(\d+)/;
	} %$grub2dev;
    }

    #- NB: we make the changes with an added string inside so that hda5 is only renamed once to hda6

    foreach (@$renumbering) {
	my ($old, $new) = @$_;
	log::l("renaming $old -> $new");
	(my $lnew = $new) =~ s/(\d+)$/__DRAKX_DONE__$1/;
	$_->{new} =~ s/\b$old/$lnew/g foreach @configs;

	any { $_->{name} eq 'grub' } @configs or next;

	my ($old_grub, $new_grub) = map { device_string2grub($_, [], \@sorted_hds) } $old, $new;
	log::l("renaming $old_grub -> $new_grub");
	(my $lnew_grub = $new_grub) =~ s/\)$/__DRAKX_DONE__)/;
	$_->{new} =~ s/\Q$old_grub/$lnew_grub/g foreach @configs;
    }

    $_->{new} =~ s/__DRAKX_DONE__//g foreach @configs;

    my @changed_configs = grep { $_->{orig} ne $_->{new} } @configs or return 1; # no need to update

    $in->ask_okcancel('', N("Your bootloader configuration must be updated because partition has been renumbered")) or return;

    foreach (@changed_configs) {
	renamef("$::prefix/$_->{file}", "$::prefix/$_->{file}.old");
	output("$::prefix/$_->{file}", $_->{new});
    }

    my $main_method = detect_main_method($all_hds);
    my @needed = map { 
	$_ eq 'grub' ? 'grub_install' : $_;
    } $main_method ? $main_method : ('lilo', 'grub');

    if (intersection(\@needed, [ map { $_->{name} } @changed_configs ])) {
	$in->ask_warn('', N("The bootloader cannot be installed correctly. You have to boot rescue and choose \"%s\"", 
			    N("Re-install Boot Loader")));
    }
    1;
}

=back

=cut

1;
