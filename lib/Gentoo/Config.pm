package Gentoo::Config;

use 5.008007;
use strict;
use warnings;

require Exporter;

our @ISA = qw(Exporter);
our @EXPORT = qw(getParamFromFile getFileContents getValue );


our $VERSION = '0.01';

sub new {
     my $self  = shift;
     my $class = ref($self) || $self;
     return bless {}, $class;
}

# Description:
# Returns the value of $param. Expects filecontents in $file.
# $valueOfKey = getParamFromFile($filecontents,$key);
# e.g.
# $valueOfKey = getParamFromFile(getFileContents("/path/to.ebuild","IUSE","firstseen");
sub getParamFromFile {
    my $file  = shift;
    my $param = shift;
    my $mode  = shift;   # ("firstseen","lastseen") - default is "lastseen"
    my $c     = 0;
    my $d     = 0;
    my @lines = ();
    my @aTmp  = ();      # temp (a)rray
    my $sTmp  = "";      # temp (s)calar
    my $text  = "";      # complete text/file after being cleaned up and striped
    my $value = "";      # value of $param
    my $this  = "";

    # - 1. split file in lines >
    @lines = split( /\n/, $file );

    # - 2 & 3 >
    for ( $c = 0 ; $c <= $#lines ; $c++ ) {

       # - 2. remove leading and trailing whitespaces and tabs from every line >
        $lines[$c] =~ s/^[ |\t]+//;    # leading whitespaces and tabs
        $lines[$c] =~ s/[ |\t]+$//;    # trailing whitespaces and tabs

        # - 3. remove comments >
        $lines[$c] =~ s/#(.*)//g;

        if ( $lines[$c] =~ /^$param="(.*)"/ ) {

            # single-line with quotationmarks >
            $value = $1;

            if ( $mode eq "firstseen" ) {

                # - 6. clean up value >
                $value =~ s/^[ |\t]+//;   # remove leading whitespaces and tabs
                $value =~ s/[ |\t]+$//;   # remove trailing whitespaces and tabs
                $value =~ s/\t/ /g;       # replace tabs with whitespaces
                $value =~
                  s/ {2,}/ /g;    # replace 1+ whitespaces with 1 whitespace
                return $value;
            }
        }
        elsif ( $lines[$c] =~ /^$param="(.*)/ ) {

            # multi-line with quotationmarks >
            $value = $1 . " ";
            for ( $d = $c + 1 ; $d <= $#lines ; $d++ ) {

                # - look for quotationmark >
                if ( $lines[$d] =~ /(.*)"/ ) {

                    # - found quotationmark; append contents and leave loop >
                    $value .= $1;
                    last;
                }
                else {

                    # - no quotationmark found; append line contents to $value >
                    $value .= $lines[$d] . " ";
                }
            }

            if ( $mode eq "firstseen" ) {

                # - 6. clean up value >
                $value =~ s/^[ |\t]+//;   # remove leading whitespaces and tabs
                $value =~ s/[ |\t]+$//;   # remove trailing whitespaces and tabs
                $value =~ s/\t/ /g;       # replace tabs with whitespaces
                $value =~
                  s/ {2,}/ /g;    # replace 1+ whitespaces with 1 whitespace
                return $value;
            }
        }
        elsif ( $lines[$c] =~ /^$param=(.*)/ ) {

            # - single-line without quotationmarks >
            $value = $1;

            if ( $mode eq "firstseen" ) {

                # - 6. clean up value >
                $value =~ s/^[ |\t]+//;   # remove leading whitespaces and tabs
                $value =~ s/[ |\t]+$//;   # remove trailing whitespaces and tabs
                $value =~ s/\t/ /g;       # replace tabs with whitespaces
                $value =~
                  s/ {2,}/ /g;    # replace 1+ whitespaces with 1 whitespace
                return $value;
            }
        }
    }

    # - 6. clean up value >
    $value =~ s/^[ |\t]+//;       # remove leading whitespaces and tabs
    $value =~ s/[ |\t]+$//;       # remove trailing whitespaces and tabs
    $value =~ s/\t/ /g;           # replace tabs with whitespaces
    $value =~ s/ {2,}/ /g;        # replace 1+ whitespaces with 1 whitespace

    return $value;
}

# Description:
# Returnvalue is the content of the given file.
# $filecontent = getFileContents($file);
sub getFileContents {
    my $content = "";

    open( FH, "<" . $_[0] ) || die( "Cannot open file " . $_[0] );
    while (<FH>) { $content .= $_; }
    close(FH);
    return $content;
}

sub getValue {
	my $self = shift;
	my $confVal = shift;
	my $makeconf = getParamFromFile( getFileContents("/etc/make.conf"), "$confVal","lastseen" );
	if (! $makeconf ) 
	{
		$makeconf = getParamFromFile( getFileContents("/etc/make.globals"), "$confVal", "lastseen" );
	}
	
	if ( ! $makeconf )
	{
		return undef
	}
	$self->{lc($confVal)} = $makeconf;
}
sub DESTROY
{
	my ($self) = @_;
	return if $self->{DESTROY}{__PACKAGE__}++;
}

1;