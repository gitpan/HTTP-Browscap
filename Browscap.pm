package HTTP::Browscap;

use 5.00405;
use strict;

use IO::File;
use DB_File;
use Storable;
use Carp;
use MLDBM qw(DB_File Storable);
use vars qw($VERSION $BROWSCAP_INI $FALLBACK @EXPORT @ISA);
use Scalar::Util qw( looks_like_number );

require Exporter;

@ISA = qw( Exporter );
@EXPORT = qw(browscap);

$VERSION = '0.06';
$BROWSCAP_INI = qq();
$FALLBACK = 1;

##########################################################
sub browscap
{
    my( $ua ) = @_;

    unless( $BROWSCAP_INI ) {
        die __PACKAGE__, " wasn't installed properly.  BROWSCAP_INI isn't set.";
    }

    my $bc = __PACKAGE__->new( $BROWSCAP_INI, $FALLBACK );
    return $bc->match( $ua );

}


##########################################################
sub new
{
    my( $package, $file, $fallback ) = @_;
    $fallback = 1 unless defined $fallback;
    my $self = bless { fallback=>$fallback }, $package;
    if( $file ) {
        $self->__set_file( $file );
    }
    return $self;
}

##########################################################
sub __guess_ua
{
    my( $self ) = @_;

    my $ua = $ENV{HTTP_USER_AGENT};

    if( not $ua and $ENV{MOD_PERL} ) {
        my $r;
        if( $ENV{MOD_PERL} =~ m(mod_perl/1)) {
            $r = Apache->request;
        }
        elsif( $ENV{MOD_PERL} =~ m(mod_perl/2)) {
            $r = Apache2::RequestUtil->request;
        }
        $ua = $r->headers_in->{'User-Agent'} if $r;
    }
    unless( $ua ) {
        $ua = '';
    }
    return $ua;    
}


##########################################################
sub __set_file
{
    my( $self, $file ) = @_;
    $self->{file} = $file;
    $self->{cache} = "$file.cache";
    delete $self->{data};
}

##########################################################
# Load and parse a browscap.ini file
# This trades space for speed :
#   - all inheritance is done here
#   - wildcard matches are converted to regexes
#   - we keep a list of all these regexes
sub __parse
{
    my( $self ) = @_;

    local $.;
    my $fh = IO::File->new;
    $fh->open( $self->{file} ) or die "Unable to open $self->{file}: $!";
    
    my($def, $ua);
    while( <$fh> ) {
        chomp;
        tr/\cM//d;
        if( /^\[(.+)\]$/ ) {            # UA definition
            $ua = $1;
            $self->__latest_keep( $def ) if $def;

            $def = { UA => $ua, 
                     LINE=>$. 
                   };

            $self->__parse_add( $ua, $def );
            next;
        }

        next unless $def;

        s/^\s+//;   # ltrim
        s/\s+$//;   # rtrim
        if( /^(.+?)\s*=\s*(.+)$/ ) {          # key=value
            $self->__parse_kv( $def, $1, $2 );
        }
    }    
    $fh->close;

    $self->__fix_defs;
    $self->__latest_wild();
    $self->__parse_parents;
    return keys %{ $self->{data} };
}

##########################################################
sub __parse_add
{
    my( $self, $ua, $def ) = @_;
    confess "Why nothing to add" unless $ua;
    $self->{data}{ $ua } = $def;
                                        # Does UA have wildcards in it?
    my($wild, $w_details)  = $self->__parse_wild( $ua );
    if( $wild ) {               # yes, then save those
        # Keep this for iterative matching later
        push @{ $self->{data}{ALL_WILD} }, $wild;
        $self->{data}{$wild} = $w_details;
    }
}

##########################################################
# Gary is perpetually changing his schema.
#  Css => CssVersion
#  SupportCss disapeared
#  Aol => AolVersion
sub __fix_defs
{
    my( $self ) = @_;
    while( my( $ua, $def ) = each %{ $self->{data} } ) {
        next unless 'HASH' eq ref $def;         # aka ALL_WILD
        $self->__fix_def( $def );
    }
}

sub __fix_def
{
    my( $self, $def ) = @_;
    $def->{css} = $def->{cssversion} if exists $def->{cssversion} and not defined $def->{css};
    $def->{supportcss} = 0!=$def->{cssversion} 
                    if exists $def->{cssversion} and not defined $def->{supportcss};
    $def->{aol} = 0!=$def->{aolversion} 
                    if exists $def->{aolversion} and not defined $def->{aol};
    return $def;
}



##########################################################
sub __parse_kv
{
    my( $self, $def, $key, $value ) = @_;
    $key = lc $key;
    $key =~ s/^\s+//;
    $key =~ s/\s+$//;

    $value = $1 if /^".+"$/;   # the special PHP version has quoted values
    $value =~ s/^\s+//;
    $value =~ s/\s+$//;
    $def->{$key} = $value;
    if( $value eq 'False' ) {   # make true/false more perl-like
        $def->{$key} = '';
    }
    elsif( $value eq 'True' ) {
        $def->{$key} = 1;
    }
}

##########################################################
# Go through all the possibilities, adding info that is defined by 
# the parent;
sub __parse_parents
{
    my( $self ) = @_;
    while( my( $ua, $def ) = each %{ $self->{data} } ) {
        next unless 'HASH' eq ref $def;         # aka ALL_WILD
        next unless $def->{parent};

        $self->__parse_parent( $def );
    }
}

##########################################################
sub __parse_parent
{
    my( $self, $def ) = @_;

    my $parent = $self->{data}{ $def->{parent} };
    unless( $parent and ref $parent ) {
        warn "Can't find '$def->{parent}' of parent of '$def->{UA}' at line $def->{LINE} of $self->{file}\n";
        return;
    }
    # Make sure all grand-parent keys get into parent first
    $self->__parse_parent( $parent ) if $parent->{parent};


    while( my($key, $value) = each %$parent ) {
        next if exists $def->{$key};
        $def->{$key} = $value;
    }
}

##########################################################
sub __parse_wild
{
    my( $self, $ua ) = @_;

    my $wild = quotemeta $ua;
    my $uses = ( $wild =~ s/(\\\*)+/.*?/g );
    $uses += ( $wild =~ s/\\\?/./g );

    return unless $uses;

    return $wild, {
        # Too look up the definition
        UA => $ua,
        # to calc the size of the UA string matched by this RE, we need to 
        # know the number of chars in $ua that aren't a wildcard
        size => length( $ua ) - $uses
    };
}

##########################################################
# Save the parent definition of all the latest browsers
# This way, any future versions can fall back to these versions
sub __latest_keep
{
    my( $self, $def ) = @_;
    return unless $def->{parent};
    return unless $self->{fallback};

    if( $def->{parent} eq 'DefaultProperties' ) {
        $self->{latest}{ $def->{UA} }{UA} = $def->{UA};
        $self->{latest}{ $def->{UA} }{children} ||= [];
    }
    else {
        push @{ $self->{latest}{ $def->{parent} }{children} }, $def->{UA};
    }
}

##########################################################
# Create wildcards UA strings that will catch future version
sub __latest_wild
{
    my( $self ) = @_;
    foreach my $M ( values %{ $self->{latest} } ) {
        next unless $M->{UA};
        foreach my $parent ( sort @{ $M->{children} } ) {
            next unless $parent;
            my @other = ( $self->__latest_browser( $M, $parent ), 
                          $self->__latest_OS( $M, $parent )
                        );
            push @other, $self->__latest_OS( $M, $other[0]{ua}, 1 ) if $other[0];
            foreach my $O ( @other ) {
                next unless $O;
                next if $O->{ua} eq $parent;
                $self->__parse_add( $O->{ua}, 
                                       { UA=>$O->{ua}, 
                                         parent=>$parent,
                                         LINE=>-1,
                                         FALLBACK=>$O->{why}
                                       } );
            }
        }
    }
    delete $self->{latest};
}

sub __latest_browser
{
    my( $self, $M, $ua ) = @_;
    # Here we convert the most recent version's string into something
    # That will cover future versions as well.  
    # Note that because we match longer strings (less wildcard matching) 
    # before shorter (see match()) we can get away with it
    if( $M->{UA} =~ /Firefox/ ) {
        $ua =~ s((Firefox/)[\d.]+\*)($1*);
        $ua =~ s((rv/)[\d.]+\*)($1*);
    }
    elsif( $M->{UA} =~ /IE/ ) {
        $ua =~ s((MSIE )[\d.]+)($1*);
        $ua =~ s((Trident/)[\d.]+\*)($1*);
    }
    elsif( $M->{UA} =~ /Opera/ ) {
        $ua =~ s((Opera/)[\d.]+\*)($1*);
    }
    elsif( $M->{UA} =~ /Safari Generic/ ) {
        $ua =~ s((Safari/)[\d.]+\*)($1*);
    }
    # Far to many variants on Chrome for me to be bothered
    else {
        return;
    }
    $ua =~ s/\*\*/*/g;
    return {ua=>$ua, why=>'browser'};
}

sub __latest_OS
{
    my( $self, $M, $ua, $both ) = @_;
    if( $ua =~ /Windows NT/ ) { 
        $ua =~ s((Windows NT )[.\d]+)($1*);
    }
    else {
        return;
    }
    $ua =~ s/\*\*/*/g;
    return { ua=>$ua, why=>($both ? 'browser+OS' : 'OS') };
}


##########################################################
sub __save_cache
{
    my( $self ) = @_;

    return unless $self->{data};

    if( -f $self->{cache} ) {
        unlink $self->{cache};
    }

    my %data;
    tie %data, 'MLDBM', $self->{cache}, (O_RDWR|O_CREAT), 0666;
    unless( tied %data ) {
        warn "Cannot write to $self->{cache}: $!\n";
        return;
    }

    while( my($k, $v) = each %{ $self->{data} } ) {
        $data{$k} = $v;
    }

    delete $self->{data};
    return 1;
}

##########################################################
sub __open_cache
{
    my( $self ) = @_;

    delete $self->{data};

    my %data;
    tie %data, 'MLDBM', $self->{cache}, (O_RDONLY), 0666
        or die "Cannot read from $self->{cache}: $!\n";

    $self->{data}=\%data;
    return 1;
}

##########################################################
sub open
{
    my( $self, $file ) = @_;
    
    $self->__set_file( $file ) if $file;

    $self->__set_file( $BROWSCAP_INI ) if $BROWSCAP_INI and not $self->{file};

    return 1 if $self->{data};

    # cache not file present or is older than browscap.ini
    unless( -f $self->{cache} and (-M _) < (-M $self->{file}) ) {
        # build a new cache file
        $self->__parse;
        return unless $self->{data};        # parse failed?
        unless( $self->__save_cache ) {     # no, but could we create cache?
            return 1;                       # no, {data} will have to do
        }
    }
    return $self->__open_cache;
}


##########################################################
sub match
{
    my( $self, $ua ) = @_;

    $ua ||= $self->__guess_ua;

    $self->open;            # make sure {data} is set

    my $m = $self->{data}{$ua};     # straight match;
    return $m if $m;

    ## We are looking for the most relevant of the wildcard matches
    ## That is, the match that needs the least chars matched by a wild card
    ## So, give a) Foo*honk and b) Fo*honk and looking for 'FoooHonk', a
    ## has a relevance of 1 ('o') and b of 2 ('oo').   a) wins.


    my $possible;
    my $UAs = $self->{data}{ALL_WILD};
    foreach my $re ( @{ $UAs } ) {
        next unless $ua =~ /^($re)$/;           # is this a match?

        my $match = $1;
        my $m_details = $self->{data}{$re};     # yes, get some details
        my $rel = length( $match) - $m_details->{size}; # relevance of match

        next if $possible and $rel > $possible->{rel};  # More relevant?
        $possible = $m_details;                 # Yes!  save this one
        $possible->{rel} = $rel;
    }

    return $self->{data}{ $possible->{UA} } if $possible;
    return $self->{data}{ '*' };    # Default browser
}

1;
__END__

=head1 NAME

HTTP::Browscap - Parse and search browscap.ini files

=head1 SYNOPSIS

    use HTTP::Browscap;

    my $capable = browscap();

    if( $capable->{wap} ) {
        output_WAP();
    }

    if( $capable->{css} > 1 ) {
        # Browser can handle CSS2
    }

    # OO interface
    my $BC = HTTP::Browscap->new( 'browscap.ini' );

    $capable = $BC->match( $ENV{HTTP_USER_AGENT} );



=head1 ABSTRACT

Browscap.ini is a file, introduced with Microsoft's IIS, that lists the
User-Agent strings that different browsers send, and various capabilities
of those browsers.  This module parses browscap.ini and allows you to find
the capability definitions for a given browser.

=head1 DESCRIPTION

Starting with Microsoft's IIS, a browscap.ini file was used to list the
capabilities of various browsers.  Using the User-Agent header sent by a
browser during each HTTP request, the capabilities of a browser are
retrieved.  If an exact match of the User-Agent string isn't found,
wild-card expantion is done.  If all fails, a default browser definition is
used.

The information in Browscap allows you to adapt your response to the
browser's capabalities.  There are however limits it's usefulness.  It only
detects if a browser has a certain capability, but not if this capability
has been deactivated nor if it's badly implemented.  In particular, most CSS
and JavaScript implementations will make you scream.  You might want to use
L<HTTP::BrowserDetect> or L<HTTP::BrowserSupport> to detect a specific
feature or bug.


=head2 Capabilities

The browser capability definition returned by L</browscap> or L</match> is
a hash reference.  The keys are defined below.  Boolean capabilites can have
values '' (false) or 1 (true).

Microsoft defines the following capabilities :

=over 8

=item activexcontrols

Browser supports ActiveX controls?  Boolean.

=item backgroundsounds

Browser supports background sounds?  Boolean.

=item beta

Is this a beta version of the browser?  Boolean.

=item browser

String containing a useful name for the browser.

=item cdf

Does the browser support Channel Definition Format for Webcasting?  Boolean.

=item cookies

Does the browser support cookies?  Note that this does not mean that the
browser has cookie support currently turned on.  Boolean.

=item frames

Does the browser support HTML <FRAMESET> and <FRAME> tags?  Boolean.

=item javaapplets

Does the browser support Java applets?  Note that even if this is true, 
the user could have Java turned off.  Boolean.

=item javascript

Does the browser support javascript?  Note that even if this is true, 
the user could have javascript turned off.  Boolean.

=item platform

Which platform (ie, OS) is the browser running on.  Example : WinNT, WinXP,
Win2003, Palm, Linux, Debian.

If you want a list of all possible values, run the following on your
browscap.ini file :

    grep platform= browscap.ini | sort | uniq

=item tables

Does the browser support HTML <TABLE> tags?  Boolean.

=item vbscript

Does the browser support VBscript?  Note that even if this is true, 
the user should have VBscript turned off.  Boolean.

=item version

Full version number of the browser.  Example: 1.10

=back



Gary Keith adds the following:

=over 8

=item alpha

Browser is an alpha version and still under development?  Boolean.

=item aol

Is this an AOL-branded browser?  Boolean.

=item aolversion

A number indicating what version, if any, of the America Online browser is being used.

=item crawler

Is this browser in fact a web-crawler or spider, often sent by a search
engine?  Boolean.

=item cssversion

CSS version supported by this browser.  Possible values : 0 (no CSS
support), 1 or 2.

=item cssversion

Same as above.

=item supportcss

Does this user-agent support CSS?  Boolean.

=item iframes

Does the browser support MS's <IFRAME> tags?  Boolean.

=item isbanned

Is the user-agent string banned by Gary Keith?  Boolean.

=item ismobiledevice

Is this a browser on a mobile device (iPhone, Blackberry, etc)?  Boolean.

=item issyndicationreader

Is this user-agent an RSS or ATOM reader?  Boolean.

=item netclr

Is this a .NET CLR user-agent?  Boolean.  (Seems to longer exist.)

=item majorver

Major version number.  Example: given a version of 1.10, majorver is 1.

=item minorver

Minor version number.  Example: given a version of 1.10, minorver is 10.

=item stripper

Identifies the browser as a crawler that does not obey robots.txt. This
includes e-mail harvesters, download managers and so on.  Boolean.

=item tables

Does the browser support HTML <TABLE> tags?  Boolean.

=item wap

Is browser a WAP-enabled mobile phone?  Boolean.

=item win16

Is this the 16-bit windows version of the browser?  Detecting this might be
useful if you want the user to save a file with 8.3 length.  Boolean.

=item win32

Is this the 32-bit windows version of the browser?  
Boolean.

=item win64

Is this the 32-bit windows version of the browser?  
Boolean.

=back

C<HTTP::Browscap> adds the following:

=over 8

=item UA

Full text of the User-Agent string used to match this definition.

=item LINE

Line in browscap.ini where the browser's capabilites are defined.  Useful
for debuging.

=item FALLBACK

If fallback was needed to match a UA string, this contains what was modified
to make the match. Can be one of C<browser>, C<OS> or C<browser+OS>.

=back

The browscap.ini I<standard> also defines C<parent>, which is a link to
another capability list that complements the current definition. 
C<HTTP::Browscap> handles these internaly, so that you only have to do one
lookup.

Note that, contrary to other implementations, all capability names are in
lower case, except for C<UA> and C<LINE>.  This means you should look for
C<'win16'> instead of C<'Win16'>.

=head2 Cached data

Because parsing browscap.ini is slow, a cached version of the parsed data is
automatically created and used where possible.  Normaly this cached version
is created when you ran C<browscap-update> during installation.

The cache file is a MLDBM file created with L<DB_File> and L<Storable>.  You
may change this by overloading L</__save_cache> and L</__open_cache>.



=head1 UPDATING browscap.ini

You will want to periodically fetch a new browscap.ini.  This can be done
with the following :

    wget -O browscap.ini \
        "http://browsers.garykeith.com/stream.asp?BrowsCapINI"
    browscap-update browscap.ini
    rm browscap.ini

However, you must read L<http://browsers.garykeith.com/terms.asp> before
automating this.



=head1 FUNCTIONS

=head2 browscap

    $def = browscap();
    $def = browscap( $ua );

Find the capabilities of a browser identified by a given User-Agent string.
If the string is missing, C<browscap> will attempt to find one.  See
C<__guess_ua> below.

Returns a hashref.  See L</Capabilities> above.

=head1 METHODS

There is also an object oriented interface to this module.

=head2 new

    my $BC = HTTP::Browscap->new;
    my $BC = HTTP::Browscap->new( $ini_file, $fallback );

Creates a new browscap object.  If you do not specify C<$ini_file>, the
system's browscap.ini will be used.

If C<$fallback> is true, an attempt is made to make unknown versions of
Windows, Firefox, IE and Opera match the most recent known versions. 
That is C<IE 24.8> (if/when it is released) should match C<IE 9.0> (currenty
most recent as of this writing).

Default is true.

=head2 match

    $def = $BC->match;
    $def = $BC->match( $ua );

Find the capabilities of a browser identified by the User-Agent string given
in C<$ua>. If the string is missing, C<match> will attempt to find one. 
See L</__guess_ua> below.

Returns a hashref.  See L</Capabilities> above.

=head2 open

    $BC->open

Parse and load the browscap.ini file.  If there is a cache-file present and
it is more recent then browscap.ini, the cache-file is used instead. 
Creates the cache file if possible

This method is called automatically when needed.  You should only call this
yourself when you want to create a cache file but not bother with matching.

=head1 OVERLOADING METHODS

The following methods are documented in case you wish to create a sub-class.

=head2 __guess_ua

    $BC->__guess_ua;

Used to guess at a User-Agent string.  First L</__guess_ua> looks in
C<$ENV{HTTP_USER_AGENT}> (CGI environement variable).  If this fails and
C<$ENV{MOD_PERL}> is set, C<__guess_ua> will use the mod_perl's 
L<Apache/headers_in()>
to find it.  If both these fails, the default User-Agent is returned, which
is probably not what you want.

Returns the User-Agent string.

=head2 __set_file

    $BC->__set_file( $file );

Called to set a new browscap.ini file.  This method set's data members,
generates the new cache-file name based on C<$file> and clears any parsed
data from memory.

=head2 __save_cache

Saves the parsed browscap.ini file (which is in C<{data}>) to the cache file
named C<{cache}>.

Returns true on success.  

Returns false on failure, with C<$!> set accordingly.

=head2 __open_cache

Called to open the cache C<{cache}> and tie it to C<{data}>.

Returns true on success.  Dies on failure.

=head2 __parse

Load and parse the browscap.ini file.   You will have to read the source
code if you want to modify it.

=head2 __parse_wild

Converts a UA string from browscap.ini to a Perl patern.  The UA strings
in browscap.ini may contain C<*> or C<.>, which act like file-globs.


=head1 SEE ALSO

L<http://browsers.garykeith.com/>,
L<http://www.microsoft.com/windows2000/en/server/iis/default.asp?url=/windows2000/en/server/iis/htm/asp/comp1g11.htm>
L<HTTP::BrowserDetect>.

=head1 AUTHOR

Philip Gwyn, E<lt>gwyn-AT-cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2005-2011 by Philip Gwyn

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself. 

=cut
