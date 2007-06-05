package Gentoo::Ebuild;

use strict;
use warnings;
use Gentoo::Util;
use IO::File;
use Cwd qw(getcwd abs_path cwd);
use File::Find ();

# for the convenience of &wanted calls, including -eval statements:
use vars qw/*name *dir *prune/;
*name  = *File::Find::name;
*dir   = *File::Find::dir;
*prune = *File::Find::prune;

#use Smart::Comments '###', '####';

my @store_found_dirs;
my @store_found_ebuilds;

require Exporter;
use base qw(Exporter);

our @EXPORT_OK = qw( check_ebuild read_ebuild scan_tree write_ebuild );
our %EXPORT_TAGS = (all => [qw(check_ebuild read_ebuild scan_tree write_ebuild)]);

our $VERSION = '0.01';

sub new
{
    my $proto = shift;
    my %args  = @_;
    my $class = ref($proto) || $proto;
    my $self  = {};
    foreach my $arg (keys %args)
    {
        $self->{$arg} = $args{$arg};
    }
    $self->{E} = undef;
    $self->{W} = undef;
    $self->{M} = undef;

    return bless $self, $class;
}

sub check_ebuild
{
    my $self        = shift;
    my $path_passed = shift;
    my @path_parts  = split "/", $path_passed;
    my $parts       = @path_parts;
    if ($parts < 3) { return $self->{E} = "$path_passed Too few arguments to check_ebuild" }
    if ( ! $self->{keyword} ) { return $self->{E} = "No keyword provided!" }
    my ($file, $package, $category, $portdir) = (pop @path_parts, pop @path_parts, pop @path_parts, join q{/}, @path_parts);
    #read_ebuild($self, $portdir, $category, $package, $file);
    read_ebuild($self, $path_passed);
    

    # Check everything has a value
    # Check that the deps exist...?

}

# @listOfEbuilds = getAvailableEbuilds($PORTDIR, category/packagename);
sub getAvailableEbuilds
{
    my $self       = shift;
    my $portdir    = shift;
    my $catPackage = shift;
    @{$self->{packagelist}} = ();
    if (-e $portdir . "/" . $catPackage)
    {

        # - get list of ebuilds >
        my $startdir = &cwd;
        chdir($portdir . "/" . $catPackage);
        @store_found_ebuilds = [];
        File::Find::find({wanted => \&wanted_ebuilds}, ".");
        chdir($startdir);
        foreach (@store_found_ebuilds)
        {
            $_ =~ s{^\./}{}xms;
            if ($_ =~ m/(.+)\.ebuild$/)
            {
                next if ($_ eq "skel.ebuild");
                push(@{$self->{packagelist}}, $_);
            }
            else
            {
                if (-d $portdir . "/" . $catPackage . "/" . $_)
                {
                    $_ =~ s{^\./}{}xms;
                    my $startdir = &cwd;
                    chdir($portdir . "/" . $catPackage . "/" . $_);
                    @store_found_ebuilds = [];
                    File::Find::find({wanted => \&wanted_ebuilds}, ".");
                    chdir($startdir);
                    foreach (@store_found_ebuilds)
                    {

                        if ($_ =~ m/(.+)\.ebuild$/)
                        {
                            next if ($_ eq "skel.ebuild");
                            push(@{$self->{packagelist}}, $_);
                        }
                    }
                }
            }
        }
    }
    else
    {
        if (-d $portdir)
        {
            if ($self->{debug})
            {
                warn("\n" . $portdir . "/" . $catPackage . " DOESN'T EXIST\n");
            }
        }
        else
        {
            die("\nPORTDIR hasn't been defined!\n\n");
        }
    }

}

sub getAvailableVersions
{
    my $self        = shift;
    my $portdir     = shift;
    my $find_ebuild = shift;
    return if ($find_ebuild =~ m{::});
    my %excludeDirs = (
        "."         => 1,
        ".."        => 1,
        "metadata"  => 1,
        "licenses"  => 1,
        "eclass"    => 1,
        "distfiles" => 1,
        "virtual"   => 1,
        "profiles"  => 1,
    );

    if ($find_ebuild)
    {
        return if (defined $self->{lc($find_ebuild)}{'found'});
    }
    while (<DATA>)
    {
        my ($cat, $eb, $cpan_file) = split /\s+|\t+/, $_;
        if ($cpan_file =~ m{^$find_ebuild$}i)
        {
            getBestVersion($self, $find_ebuild, $portdir, $cat, $eb);
            $self->{lc($find_ebuild)}{'found'}    = 1;
            $self->{lc($find_ebuild)}{'category'} = $cat;
            $self->{lc($find_ebuild)}{'name'}     = $eb;
            return;
        }
    }

    unless (defined $self->{lc($find_ebuild)}{'name'})
    {

        ### Expects $self->{portage_categories} to be an array of acceptable categories to check
        foreach my $tc (@{$self->{portage_categories}})
        {
            ### getAvailableVersions portdir: $portdir
            ### getAvailableVersions find_ebuild: $find_ebuild
            ### getAvailableVersions tc: $tc
            next if (!-d "$portdir/$tc");
            @store_found_dirs = [];

            # Where we started
            my $startdir = &cwd;

            # chdir to our target dir
            chdir($portdir . "/" . $tc);

            # Traverse desired filesystems
            File::Find::find({wanted => \&wanted_dirs}, ".");

            # Return to where we started
            chdir($startdir);
            foreach my $tp (sort @store_found_dirs)
            {
                $tp =~ s{^\./}{}xms;

                # - not excluded and $_ is a dir?
                if (!$excludeDirs{$tp} && -d $portdir . "/" . $tc . "/" . $tp)
                {    #STARTS HERE
                    if ($find_ebuild)
                    {
                        next
                            unless (lc($find_ebuild) eq lc($tp));
                    }
                    getBestVersion($self, $find_ebuild, $portdir, $tc, $tp);
                }    #Ends here
            }
        }
    }
    if ($find_ebuild)
    {
        if (defined $self->{lc($find_ebuild)}{'name'})
        {
            $self->{lc($find_ebuild)}{'found'} = 1;
            return;
        }
    }
    return ($self);
}

sub getBestVersion
{
    my $self = shift;
    my ($find_ebuild, $portdir, $tc, $tp) = @_;
    getAvailableEbuilds($self, $portdir, $tc . "/" . $tp);

    $self->{lc($tp)}{path} = "$portdir/$tc/$tp";
    foreach (@{$self->{packagelist}})
    {
        my @tmp_availableVersions = ();
        push(@tmp_availableVersions, getEbuildVersionSpecial($_));

        # - get highest version >
        if ($#tmp_availableVersions > -1)
        {
            $self->{lc($tp)}{$_}{'version'} = (sort(@tmp_availableVersions))[$#tmp_availableVersions];

            read_ebuild($self, [$portdir, $tc, $tp, $_]);

            # - get rid of -rX >
            $self->{lc($tp)}{$_}{'version'} =~ s{
    			([a-zA-Z0-9\-_\/]+) #Save of the name
        			(
        				(
        					(_alpha|_beta) #remove any alpha/beta names
        					\d+			#and their numbers
        				)
        				(
        					(-r|-rc|_p|_pre) #remove any of the ebuild specifics
        					\d+ #and their numbers
        				)
        			)+?
        		}{$1}gxmio;
            $self->{lc($tp)}{$_}{'version'} =~ s/[a-zA-Z]+$//;

            if ($tc eq "perl-core"
                and (@{$self->{'portage_bases'}}))
            {

                # We have a perl-core module - can we satisfy it with a virtual/perl-?
                foreach my $portage_root (@{$self->{'portage_bases'}})
                {
                    if (-d $portage_root)
                    {
                        if (-d "$portage_root/virtual/perl-$tp")
                        {
                            $self->{lc($find_ebuild)}{$_}{'name'}     = "perl-$tp";
                            $self->{lc($find_ebuild)}{$_}{'category'} = "virtual";
                            last;
                        }
                    }
                }

            }
            else
            {
                $self->{lc($find_ebuild)}{$_}{'name'}     = $tp;
                $self->{lc($find_ebuild)}{$_}{'category'} = $tc;
            }

        }
    }
}

# Description:
# Returns version of an ebuild. (Without -rX string etc.)
# $version = getEbuildVersionSpecial("foo-1.23-r1.ebuild");
sub getEbuildVersionSpecial
{
    my $ebuildVersion = shift;
    $ebuildVersion = substr($ebuildVersion, 0, length($ebuildVersion) - 7);
    $ebuildVersion =~ s/^([a-zA-Z0-9\-_\/\+]*)-([0-9\.]+[a-zA-Z]?)([\-r|\-rc|_alpha|_beta|_pre|_p]?)/$2$3/;

    return $ebuildVersion;
}

sub has_keyword
{
    my $self = shift;
    my $keyword = shift;
    my ($module, $ebuild) = @_;
    my @keyw = split " ", $self->{$module}{$ebuild}{KEYWORDS};
    my %ebuild_keywords = map { $_ => 1 } @keyw;
    if ($ebuild_keywords{$keyword}) { return }
    else { return $self->{E} = "$keyword not found!" }
}

# Given an ebuild, find the best possible keyword we can use
sub best_keyword
{
    my $self = shift;
    my $keyword = $self->{keyword};
    unless ($keyword) { $keyword = shift }
    my ($module, $ebuild) = @_;
    my @keyw = split " ", $self->{$module}{$ebuild}{KEYWORDS};
    my %ebuild_keywords;
    foreach my $key (@keyw)
    {
        if ($key =~ m{^~} ) { $ebuild_keywords{$key} = 1 }
        else { %ebuild_keywords = {$key => 1, "~$key" => 1 } }
    }
    if ($ebuild_keywords{$keyword}) { return $keyword }
    elsif ($keyword !~ m{^~} && $ebuild_keywords{"~$keyword"})
    { return "~$keyword" }
    else { $self->{E} = "$keyword not found!"; return 0 }
}

sub read_ebuild
{
    use Shell::EnvImporter;
    my $self = shift;
    my $components = shift;

    my ($portdir, $tc, $tp, $file);
    if ( ref($components) eq "ARRAY" || ref($components) eq "LIST" )
    {
        my $part_count = @{$components};
        if ($part_count != 4 )
        {
            return $self->{E} = "Insuffucient path elements sent!"
        } else {
            ($file, $tp, $tc, $portdir) = (pop @{$components}, pop @{$components}, pop @{$components}, join q{/}, @{$components});
        }
    } elsif ( !ref($components) && grep ("/", $components ))
    {
        my @path_parts  = split "/", $components;
        ###$components
        ($file, $tp, $tc, $portdir) = (pop @path_parts, pop @path_parts, pop @path_parts, join q{/}, @path_parts);
    } else {
        return $self->{E} = "Failed to pass an ARRAY, LIST, or SCALAR for a path"
    }

    my $util = Gentoo::Util->new();
    my $e_file = "$portdir/$tc/$tp/$file";
    $util->check_access($self, [$portdir, $tc, $tp]);
    if ($self->{E})
    {
        return ($self);
    }
    elsif ( -f $e_file )
    {


        # Save original ENV for restoration
        my %O_ENV = %ENV;

        # Set some of the common ebuild specific vars
        $ENV{PN} = $tp;
        ($ENV{PF}  = $file)     =~ s/\.ebuild//gxm;
        ($ENV{PVR} = $ENV{PF})  =~ s/$ENV{PN}\-//gxm;
        ($ENV{PV}  = $ENV{PVR}) =~ s/\-r\d*//gxm;
        ($ENV{PR}  = $ENV{PVR}) =~ s/$ENV{PV}\-//gxm;
        ($ENV{P}   = $ENV{PF})  =~ s/\-$ENV{PR}//gxm;


        # Grab some info for display
        my $e_import = Shell::EnvImporter->new(
            file            => $e_file,
            shell           => 'bash',
            auto_run        => 1,
            auto_import     => 0,
            import_modified => 1,
            import_added    => 1,
            import_removed  => 1,
        );
        $e_import->shellobj->envcmd('set');
        $e_import->run();
        $e_import->env_import();
        $self->{lc($tp)}{$file}{'DESCRIPTION'} = Gentoo::Util->strip_env($ENV{DESCRIPTION});
        $self->{lc($tp)}{$file}{'HOMEPAGE'}    = Gentoo::Util->strip_env($ENV{HOMEPAGE});
        $self->{lc($tp)}{$file}{'KEYWORDS'}    = Gentoo::Util->strip_env($ENV{KEYWORDS});
        if (exists $ENV{'DEPEND'})  { $self->{lc($tp)}{$file}{'DEPEND'}  = Gentoo::Util->strip_env($ENV{DEPEND}) }
        if (exists $ENV{'RDEPEND'}) { $self->{lc($tp)}{$file}{'RDEPEND'} = Gentoo::Util->strip_env($ENV{RDEPEND}) }
        if (exists $ENV{'PDEPEND'}) { $self->{lc($tp)}{$file}{'PDEPEND'} = Gentoo::Util->strip_env($ENV{PDEPEND}) }
        $e_import->restore_env;
        %ENV = %O_ENV;
        return ($self);
    }
    return;

}

sub scan_tree
{
    my $self   = shift;
    my $module = shift;
    $module or return;
    my $root_checks = 0;

    if ($module =~ /pathtools/gimx) { $module = "File-Spec" }
    #### Expect to receive $self->{portage_bases} as a hash of available portage directories
    foreach my $portage_root (@{$self->{portage_bases}})
    {
        if (-d $portage_root)
        {
            $root_checks++;
            ### Roots checked: $root_checks
            ### Looking for module: $module
            ### in: $portage_root
            #$self->getAvailableVersions($self, $portage_root, $module);
            getAvailableVersions($self, $portage_root, $module);

        }

        # Pop out of the loop if we've found the module
        defined $self->{lc($module)}{found} and last;
    }
    if ($root_checks == 0) { return $self->{E} = qq{NO EBUILD DIRECTORIES FOUND!!}; }
    if   ($self->{lc($module)}{'found'}) { return $self }
    else                                 { return $self->{E} = "Module not found!" }
    return;
}

sub wanted_ebuilds
{
    /\.ebuild\z/s
        && push @store_found_ebuilds, $name;
}

sub wanted_dirs
{
    my ($dev, $ino, $mode, $nlink, $uid, $gid);
    (($dev, $ino, $mode, $nlink, $uid, $gid) = lstat($_))
        && -d _
        && ($name !~ m|/files|)
        && ($name !~ m|/CVS|)
        && push @store_found_dirs, $name;
}

sub write_ebuild
{
    my $self = shift;
    Gentoo::Util->make_path($self->{path});
    if (defined $self->{E}) { return $self->{E} }
    if (-f "$self->{path}/$self->{ebuild}") { return $self->{W} = "Ebuild already exists!" }
    my $EBUILD = IO::File->new($self->{path} . "/" . $self->{ebuild}, '>') or return ($self->{E} = "Unable to open $self->{ebuild} for writing: $!");
    print {$EBUILD} <<"HERE";
# Copyright 1999-2007 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2
# This ebuild generated by $self->{prog} $self->{VERSION}

inherit perl-module

S=\${WORKDIR}/$self->{'portage_sdir'}

DESCRIPTION="$self->{'description'}"
HOMEPAGE="http://search.cpan.org/search?query=$self->{cpan_name}\&mode=dist"
SRC_URI="mirror://cpan/authors/id/$self->{'src_uri'}"


IUSE=""

SLOT="0"
LICENSE="|| ( Artistic GPL-2 )"
KEYWORDS="$self->{keywords}"

HERE
    print {$EBUILD} "DEPEND=\"dev-lang/perl";

#### Expect $self->{depends} to be an array containing the defined module paths now

    if (defined $self->{depends})
    {
        foreach (@{$self->{depends}}) { print {$EBUILD} "\n\t$_" }
    }

    print {$EBUILD} q(");
### Add flag for buildpkg and buildpkgonly
    if (defined $self->{buildpkg} or defined $self->{buildpkgonly})
    {
        print {$EBUILD} qq{\npkg_postinst() \{\n};
        print {$EBUILD} qq{elog "If you redistribute this package, please remember to"\n};
        print {$EBUILD} qq{elog "update /etc/portage/categories with an entry for perl-gpcan"\n};
        print {$EBUILD} qq{\}\n};
    }

    undef $EBUILD;
    autoflush STDOUT 1;
}

1;

=pod



=head1 NAME

Gentoo::Ebuild - ebuild specific functions

=head1 DESCRIPTION

The C<Gentoo::Ebuild> class provides basic ebuild functionality for reading,
writing and testing ebuilds.



=over 2

=item $obj->read_ebuild($portage_dir, $category, $module, $ebuild_file);

Providing the 



=item *



=back



=cut

__DATA__
dev-perl    XML-Sablot		XML-Sablotron
dev-perl    CPAN-Mini-Phalanx	CPAN-Mini-Phalanx100
perl-core   PodParser		Pod-Parser
dev-perl    Boulder			Stone
dev-perl    crypt-des-ede3		Crypt-DES_EDE3
dev-perl    DateManip		Date-Manip
dev-perl    DelimMatch		Text-DelimMatch
perl-core   File-Spec		PathTools
dev-perl    gimp-perl		Gimp
dev-perl    glib-perl		Glib
dev-perl    gnome2-perl		Gnome2
dev-perl    gnome2-vfs-perl		Gnome2-VFS
dev-perl    gtk2-perl		Gtk2
dev-perl    ImageInfo		Image-Info
dev-perl    ImageSize		Image-Size
dev-perl    Locale-gettext		gettext
dev-perl    Net-SSLeay		Net_SSLeay
dev-perl    OLE-StorageLite		OLE-Storage_Lite
dev-perl    PDF-Create      perl-pdf
dev-perl    perl-tk			Tk
dev-perl    perltidy		Perl-Tidy
dev-perl    RPM			Perl-RPM
dev-perl    sdl-perl		SDL_perl
dev-perl    SGMLSpm			SGMLSpmii
dev-perl    Term-ANSIColor		ANSIColor
perl-core   CGI			CGI.pm
dev-perl    Net-SSLeay		Net_SSLeay.pm
perl-core   digest-base		Digest
dev-perl    gtk2-fu			Gtk2Fu
dev-perl    Test-Builder-Tester	Test-Simple
dev-perl    wxperl			Wx
media-gfx   imagemagick        PerlMagick
