package Pandoc::Release;
use strict;
use warnings;
use 5.010;

# core modules since 5.014
use HTTP::Tiny;
use JSON::PP;

use Pandoc;
use Pandoc::Version;
use Cwd;
use File::Path qw(make_path remove_tree);
use File::Copy 'move';

=head1 NAME

Pandoc::Release - get pandoc releases from GitHub

=cut

our $VERSION = '0.7.0';

sub list {
    my ($class, %opts) = @_;

    my $range = $opts{range};
    my $since = Pandoc::Version->new($opts{since} // 0);
	my $client = HTTP::Tiny->new();
    my $url = "https://api.github.com/repos/jgm/pandoc/releases";
    my @releases;

    LOOP: while ($url) {
        say $url if $opts{verbose};
        my $res = $client->get($url);
        $res->{success} or die "failed to fetch $url";
        foreach (@{ JSON::PP::decode_json($res->{content}) }) {
            my $version = Pandoc::Version->new($_->{tag_name});
            last LOOP unless $since < $version; # abort if possible
            if (!$range || $version->fulfills($range)) {
                push @releases, bless $_, $class;
                last LOOP if $range and $range =~ /^==v?(\d+(\.\d)*)$/;
            }
        }

        my $link = $res->{headers}{link} // '';
        $link =~ /<([^>]+)>; rel="next"/ or last;
        $url = $1;
    }

    @releases;
}

sub download {
    my ($self, %opts) = @_;

	my $dir = $opts{dir} // die 'directory not specified';
	my $arch = $opts{arch} // die 'architecture not specified';
    my $bin = $opts{bin};
	my $client = HTTP::Tiny->new;

    make_path($dir);
	-d $dir or die "missing directory $dir";
    if ($bin) {
        make_path($bin);
		-d $bin or die "missing directory $bin";
    }

    my ($asset) = grep { $_->{name} =~ /-$arch\.deb$/ } @{$self->{assets}};
    return if !$asset or $asset->{name} =~ /^pandoc-1\.17-/; # version had a bug

    my $url = $asset->{browser_download_url} or return;
    my $version = Pandoc::Version->new($self->{tag_name});
    my $deb = "$dir/".$asset->{name};
    say $deb if $client->mirror($url, $deb)->{success} and $opts{verbose};

    if ($bin) {
        my $cmd = "dpkg --fsys-tarfile '$deb'"
                . "| tar -x ./usr/bin/pandoc -O > '$bin/$version'"
                . "&& chmod +x '$bin/$version'";
        system($cmd) and die "failed to extract pandoc from $deb:\n $cmd";
        say "$bin/$version" if $opts{verbose};
	}

    return $version;
}

1;

__END__

=head1 SYNOPSIS

  use Pandoc::Release;

  my @releases = Pandoc::Release->list(since => '2.0', verbose => 1);
  foreach my $release (@releases) {

      # print version number
  	  say $release->{tag_name};

      # download Debian package and executable
      $release->download(arch => 'amd64', dir => './deb', bin => './bin');
  }

=head1 DESCRIPTION

This utility module fetches information about pandoc releases via GitHub API.
It requires at least Perl 5.14 or L<HTTP::Tiny> and L<JSON::PP> installed.

=head1 METHODS

=head2 list( [ since => $version ] [ range => $range ] [, verbose => 0|1 ] )

Get a list of all pandoc releases at GitHub, optionally since some version and
within a version range such as C<!=1.16, <=1.17> or C<==2.1.2>. See
L<CPAN::Meta::Spec/Version Ranges> for possible values. Option C<verbose> will
print URLs before each request.

=head2 download( arch => $arch, dir => $dir [, bin => $bin] [, verbose => 0|1] )

Download the Debian release file for some architecture (e.g. C<amd64>) to
directory C<dir>, unless already there. Optionally extract pandoc executables
to directory C<bin>, each named by pandoc version number (e.g. C<2.1.2>).
These executables can be used with constructor of L<Pandoc> and with
L<App::Prove::Plugin::andoc>:

  my $pandoc = Pandoc->new("$bin/$version");

=head1 SEE ALSO

L<https://developer.github.com/v3/repos/releases/>

=cut
