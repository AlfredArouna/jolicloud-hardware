#!/usr/bin/perl

use Data::Dumper;

my $aliases = {};
my $pciList = [];
my $usbList = [];

# snarf jockey's modaliases
my @modaliasPaths = ( "/usr/share/jockey/modaliases" );

foreach $path ( @modaliasPaths ) {
    next unless ( -d $path );
    foreach my $file ( <$path/*> ) {
        open( FILE, $file );
        while( <FILE> ) {
            next unless /^alias/;
            my ( $c, $a, $m, $p ) = split( " " );
            if ( $a =~ /^pci:v([0-F]*|\*)d([0-F]*|\*)sv([0-F]*|\*)sd([0-F]*|\*)bc([0-F]*|\*)sc([0-F]*|\*)i([0-F]*|\*)$/ ) {
                my ( $v, $d, $sv, $sd, $bc, $sc, $i ) = 
                        ( $1, $2, $3, $4, $5, $6, $7 );
                # Convert hex to dec to make them easier to parse
                $v = hex( $v ) unless ( $v eq '*' );
                $d = hex( $d ) unless ( $d eq '*' );
                $sv = hex( $sv ) unless ( $sv eq '*' );
                $sd = hex( $sd ) unless ( $sd eq '*' );
                push ( @{ $aliases->{ 'pci' } }, { alias => $a,
                        vendor => $v, device => $d,
                        subvendor => $sv, subdevice => $sd,
                        baseclass => $bc, subclass => $sc, interface => $i,
                        module => $m, package => $p,
                } );
            }
            elsif ( $a =~ /^usb:v([0-F]*|\*)p([0-F]*|\*)d([0-F]*|\*)dc([0-F]*|\*)dsc([0-F]*|\*)dp([0-F]*|\*)ic([0-F]*|\*)isc([0-F]*|\*)ip([0-F]*|\*)$/ ) {
                my ( $v, $p, $d, $dc, $dsc, $dp, $ic, $isc, $ip ) = 
                        ( $1, $2, $3, $4, $5, $6, $7, $8, $9 );
                # Convert hex to dec to make them easier to parse
                $v = hex( $v ) unless ( $v eq '*' );
                $p = hex( $p ) unless ( $p eq '*' );
                push ( @{ $aliases->{ 'usb' } }, { alias => $a,
                        vendor => $v, product => $p,
                        device => $d, deviceClass => $dc,
                        deviceSubClass => $dsc, deviceProtocol => $dp,
                        interfaceClass => $ic, interfaceSubClass => $isc,
                        interfaceProtocol => $ip,
                        module => $m, package => $p,
                } );
            }
        }
        close( FILE );
    }
}


# Go through the systems' hardware and try to find matches

my $lspci = `lspci -m -n`;
foreach ( split( "\n", $lspci ) ) {
    my @fields = split( " " );
    foreach ( reverse 0..$#fields ) {
        splice( @fields, $_, 1 ) if ( $fields[ $_ ] =~ /^\-/ );
        $fields[ $_ ] =~ s/"//g;
    }
    my ( $s, $c, $v, $d, $sv, $sd ) = @fields;
    $v = hex( $v );
    $d = hex( $d );
    $sv = hex( $sv );
    $sd = hex( $sd );
    push( @{ $pciList }, { slot => $s, class => $c,
        vendor => $v, device => $d,
        subvendor => $sv, subdevice => $sd,
    } );
}


# Match em up!

my $matched = {};
my $install = [];

foreach my $pci ( @{ $pciList } ) {
    foreach my $alias ( @{ $aliases->{ 'pci' } } ) {
        next unless ( $pci->{ 'vendor' } eq $alias->{ 'vendor' } ||
                      $alias->{ 'vendor' } eq '*' );
        next unless ( $pci->{ 'device' } eq $alias->{ 'device' } ||
                      $alias->{ 'device' } eq '*' );
        next unless ( $pci->{ 'subVendor' } eq $alias->{ 'subVendor' } ||
                      $alias->{ 'subVendor' } eq '*' );
        next unless ( $pci->{ 'subDevice' } eq $alias->{ 'subDevice' } ||
                      $alias->{ 'subDevice' } eq '*' );
        # WARNING: No comparision yet on baseClass, subClass, or the
        # interface fields in the modaliases data. Modules aren't usually
        # identified using these fields, anyway.

        push( @{ $matched->{ $alias->{ 'module' } } }, $alias );
    }
}

# Some jockey modaliases will match multiple packages for one piece of
# hardware. This is its way of saying that there are different releases of
# the respective driver available. This code picks the "highest-naming"
# package and selects it to be installed. If only one match is found, its
# selected anyway.
while ( my ( $module, $matches ) = each %{ $matched } ) {
    my @sorted = sort { $a->{ 'package' } cmp $b->{ 'package' } } @{ $matches };
    push( @{ $install }, pop( @sorted ) );
}

my $err = 0;

foreach ( @{ $install } ) {
    my $handler = "/usr/lib/jolicloud-hardware/handler/$_->{ 'module' }";

    print "Identified package '$_->{ 'package' }' provides module '$_->{ 'module' }'\n";
    if ( -x $handler ) {
        print "Running handler $handler $_->{ 'module' } $_->{ 'package' }\n";
        system( $handler, $_->{ 'module' }, $_->{ 'package' } );
        $err = $? >> 8;
	warn "$handler returned errorcode $err";
    }
}


# We're all done running, so there should be no reason to continue to keep
# jolicloud-hardware or jolicloud-hardware-repo on this machine, that is
# unless we're booting in LiveUSB mode. Remove it, but only if we're in an
# installed state.

# Except if a system call to a handler failed, that is.
exit $err if $err;

open ( FD, '/proc/cmdline' );
my $cmdline = <FD>;
close( FD );
if ( $cmdline !~ / boot=casper / ) {
    system( "/usr/bin/apt-mark", "markauto", "jolicloud-hardware" );
    system( "/usr/bin/apt-mark", "markauto", "jolicloud-hardware-repo" );
}

exit 0
