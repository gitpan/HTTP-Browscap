#!/usr/bin/perl -w 

use strict;

use Test::More tests => 14;

use HTTP::Browscap;
pass( 'Module loaded' );

$HTTP::Browscap::BROWSCAP_INI = "t/browscap.ini";
unlink "$HTTP::Browscap::BROWSCAP_INI.cache";

my $def = browscap( "Googlebot-Image/1.0" );
ok( ($def and $def->{browser} eq 'Googlebot-Image' and $def->{frames}
            and not $def->{javascript} and not $def->{aol}),
                "Found with explicit name" );

$ENV{HTTP_USER_AGENT} = "Googlebot-Image/1.0";
$def = browscap( );
ok( ($def and $def->{browser} eq 'Googlebot-Image' and $def->{frames}
            and not $def->{javascript} and not $def->{aol}),
                "Found via CGI ENV" );


delete $ENV{HTTP_USER_AGENT};

$ENV{MOD_PERL} = "mod_perl/1.1";
$def = browscap( );
ok( ($def and $def->{browser} eq 'Firefox' and $def->{cookies}
        and $def->{css}==2 and $def->{javascript} and 
                $def->{version} eq '1.0'), "Found with mod_perl/1 interface");


$ENV{MOD_PERL} = "mod_perl/2.3";
$def = browscap( );
ok( ($def and $def->{browser} eq 'Firefox' and $def->{cookies}
        and $def->{css}==2 and $def->{javascript} and 
                $def->{version} eq '1.0'), "Found with mod_perl/2 interface");

delete $ENV{MOD_PERL};

$def = browscap();

ok( ($def and $def->{browser} eq 'Default Browser' and not $def->{css}
        and not $def->{javascript} and $def->{tables}), "Found default browser");


##############################
$ENV{HTTP_USER_AGENT}='Mozilla/5.0 (compatible; MSIE 9.0; Windows NT 6.1; Trident/5.0)';
$def = browscap( );
ok( ($def and $def->{browser} eq 'IE'), "MSIE 9.0 found" );

$ENV{HTTP_USER_AGENT}='Mozilla/5.0 (compatible; MSIE 9.0; Windows NT 6.1; WOW64; Trident/5.0)';
$def = browscap( );
ok( ($def and $def->{browser} eq 'IE'), "MSIE 9.0 found" );
# use Data::Dumper;
# warn Dumper $def;


$ENV{HTTP_USER_AGENT}='Mozilla/5.0 (Windows NT 6.1; rv:5.0) Gecko/20100101 Firefox/5.0';
$def = browscap( );
ok( ($def and $def->{browser} eq 'Firefox'), "Firefox 5 found" );

$ENV{HTTP_USER_AGENT}='Mozilla/5.0 (Windows NT 6.1; rv:7.0.1) Gecko/20100101 Firefox/7.0.1';
$def = browscap( );
is( $def->{browser}, 'Firefox', "Firefox 7 fallback to 5" );
is( $def->{FALLBACK}, 'browser' );

$ENV{HTTP_USER_AGENT}='Mozilla/5.0 (Windows NT 16.1; rv:7.0.1) Gecko/20100101 Firefox/5.0.1';
$def = browscap( );
is( $def->{platform}, 'Win7', "Windows 16(!) fallback to Win7" );
is( $def->{FALLBACK}, 'OS' );

$ENV{HTTP_USER_AGENT}='Mozilla/5.0 (Windows NT 16.1; rv:7.0.1) Gecko/20100101 Firefox/7.0.1';
$def = browscap( );
is( $def->{FALLBACK}, 'browser+OS', "Firefox 7 on Win 16 fallback to 5 on Win7" );


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
