use 5.00405;
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    'NAME'		=> 'HTTP::Browscap',
    'VERSION_FROM'	=> 'Browscap.pm', # finds $VERSION
    'LICENSE'       => 'perl',
    
    'PREREQ_PM'		=> {
        'Test::More'  =>  0,
        Storable      =>  0,
        DB_File       =>  0,
        MLDBM         =>  2
    }, 
    dist=>{COMPRESS=>'gzip -9f', EXT=>'gz'},
    EXE_FILES => [ qw( browscap-update ) ],

    ($] >= 5.005 ?    ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM => 'Browscap.pm', # retrieve abstract from module
       AUTHOR     => 'Philip Gwyn <fil@localdomain>') : ()),
);


package MY;
sub install
{
    my $self = shift;
    my $ret = $self->SUPER::install(@_);

    $ret =~ s((\npure_(site|perl|vendor)_install.+?)\n\n)
              ($1\n\t\@echo -e "\\n----------------------------------------------------\\nPlease read README for instructions on downloading a full browscap.ini.\\n----------------------------------------------------\\n"\n\n)sg;
    return $ret;
}

# You will need to run \$(INSTALLSCRIPT)/browscap-update browscap.ini once you fetch it.\\n