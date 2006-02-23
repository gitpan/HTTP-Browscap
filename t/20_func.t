#!/usr/bin/perl -w 

use strict;

use Test::More tests => 6;
use Data::Denter;

use HTTP::Browscap;
pass( 'Module loaded' );

$HTTP::Browscap::BROWSCAP_INI = "t/browscap.ini";

my $def = browscap( "Googlebot-Image/1.0" );
ok( ($def and $def->{browser} eq 'Googlebot-Image' and $def->{frames}
            and not $def->{javascript} and not $def->{aol}),
                "Found with explicit name" ) or warn "Why not? ", Denter $def;

$ENV{HTTP_USER_AGENT} = "Googlebot-Image/1.0";
$def = browscap( );
ok( ($def and $def->{browser} eq 'Googlebot-Image' and $def->{frames}
            and not $def->{javascript} and not $def->{aol}),
                "Found via CGI ENV" ) or warn "Why not? ", Denter $def;


delete $ENV{HTTP_USER_AGENT};

$ENV{MOD_PERL} = "mod_perl/1.1";
$def = browscap( );
ok( ($def and $def->{browser} eq 'Firefox' and $def->{cookies}
        and $def->{css}==2 and $def->{javascript} and 
                $def->{version} eq '1.0'), "Found with mod_perl/1 interface")
            or warn "Why not? ", Denter $def;


$ENV{MOD_PERL} = "mod_perl/2.3";
$def = browscap( );
ok( ($def and $def->{browser} eq 'Firefox' and $def->{cookies}
        and $def->{css}==2 and $def->{javascript} and 
                $def->{version} eq '1.0'), "Found with mod_perl/2 interface")
            or warn "Why not? ", Denter $def;

delete $ENV{MOD_PERL};

$def = browscap();

ok( ($def and $def->{browser} eq 'Default Browser' and not $def->{css}
        and not $def->{javascript} and $def->{tables}), "Found default browser")
            or warn "Why not? ", Denter $def;


unlink "browscap.ini.cache";

##############################
package Apache;

use strict;

sub request
{
    return bless {}, __PACKAGE__;
}

sub headers_in
{
    my( $self )=@_;
    
    return { 'User-Agent' => 
             "Mozilla/5.0 (X11; U; Linux i686; en-US; rv:1.7.8) Gecko/20050511 Firefox/1.0.4" };
}


package Apache2::RequestUtil;
use strict;
use vars qw( @ISA );
BEGIN {
    @ISA = qw( Apache );
}
