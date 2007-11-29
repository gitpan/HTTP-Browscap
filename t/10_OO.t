#!/usr/bin/perl -w

#########################
use strict;
# use Data::Denter;

use Test::More tests => 15;
BEGIN { use_ok('HTTP::Browscap') or die "ARG!" };

#########################
my $BC = HTTP::Browscap->new;
ok( $BC, "Created HTTP::Browscap object");

$BC->__set_file( 't/browscap.ini' );
ok( ($BC->{file} and $BC->{cache}), 
        "Set file and cache file members");

my $ok = $BC->__parse;
ok( ($ok and $BC->{data} and $BC->{data}{ALL_WILD}), 
        "File loaded and parsed");

$ok = $BC->__save_cache;
ok( ($ok and -f $BC->{cache}), "Created cache file") 
            or die "Why no $BC->{cache}?";

my $CACHE_AGE = -M _;

$ok = $BC->__open_cache;
ok( ($ok and $BC->{data} and $BC->{data}{ALL_WILD}),  "Cache file opened") 
            or die keys %{ $BC->{data} };


#########################
$BC = HTTP::Browscap->new( 't/browscap.ini' );
ok( ($BC and $BC->{file} and $BC->{cache}), 
        "Created HTTP::Browscap object with file");


$ok = $BC->open;
ok( ($ok and $BC->{data} and $BC->{data}{ALL_WILD}), 
        "File loaded and parsed");


ok( ($CACHE_AGE == -M $BC->{cache}), "Cache file wasn't changed")
        or die "Why did $BC->{cache} change";


#########################
# Straight match
my $def = $BC->match( "Alta Vista" );
ok( ($def and $def->{browser} eq 'Alta Vista' and $def->{frames}
          and not $def->{vbscript} and not $def->{win16}),
            "Found Alta Vista");

# Straight match, one parent
$def = $BC->match( "Googlebot-Image/1.0" );
ok( ($def and $def->{browser} eq 'Googlebot-Image' and $def->{frames}
            and not $def->{javascript} and not $def->{aol}),
                "Found Googlebot-Image/1.0" );

# Wild match, one parent
$def = $BC->match( "Scooter/*" );
ok( ($def and $def->{browser} eq 'AltaVista' and $def->{frames}
          and not $def->{vbscript} and not $def->{win16}),
            "Found Scooter");

# Complex match, one parent
$def = $BC->match( "Mozilla/4.0 (compatible; MSIE; sureseeker.com; win32)" );
ok( ($def and $def->{browser} eq 'Excite' and $def->{tables}
          and not $def->{stripper} and not $def->{wap}),
            "Found Excite (sureseeker.com)");

# Complex match, one parent
$def = $BC->match( "Mozilla/5.0 (X11; U; Linux i686; en-US; rv:1.7.8) Gecko/20050511 Firefox/1.0.4" );
ok( ($def and $def->{browser} eq 'Firefox' and $def->{cookies}
        and $def->{css}==2 and $def->{javascript} and 
                $def->{version} eq '1.0'), "Found Firefox 1.0.4");

unlink $BC->{cache};

#########################
# Make sure grand-parent fits
$def = $BC->match( 'Accoona-AI-Agent/1.1.1 (crawler at accoona dot com)' );
ok( ($def and $def->{browser} eq 'Accoona' and $def->{tables} and
        $def->{frames} and $def->{crawler}), "Found Accouna crawler");
