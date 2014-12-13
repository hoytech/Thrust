use strict;

use ExtUtils::MakeMaker;

use LWP::Simple;
use Archive::Extract;
use File::ShareDir::Install;


my $thrust_version = '0.7.6';

my ($os, $arch);

if ($^O =~ /linux/i) {
  $os = 'linux';
  $arch = length(pack("P", 0)) == 8 ? 'x64' : 'ia32';
} elsif ($^O =~ /darwin/i) {
  $os = 'darwin';
  $arch = 'x64';
} elsif ($^O =~ /mswin/i) {
  $os = 'win32';
  $arch = 'ia32';
} else {
  die "Your platform is currently not supported by Thrust";
}

my $thrust_zipfile_url = "https://github.com/breach/thrust/releases/download/v$thrust_version/thrust-v$thrust_version-$os-$arch.zip";

if (!-e 'thrust.zip') {
  print "Downloading $thrust_zipfile_url (be patient)\n";
  unlink('thrust.zip.partial');
  getstore($thrust_zipfile_url, 'thrust.zip.partial');
  rename('thrust.zip.partial', 'thrust.zip');
}

if (!-d 'share') {
  print "Extracting into share/\n";
  mkdir('share');
  my $ae = Archive::Extract->new(archive => 'thrust.zip');
  $ae->extract(to => 'share/') || die "unable to extract archive: " . $ae->error;
}

install_share 'share';


my %args = (
  NAME => 'Thrust',
  VERSION_FROM => 'lib/Thrust.pm',
  LIBS => [''],
  INC => '-I lib/',
  PREREQ_PM => {
    'common::sense' => 0,
    'AnyEvent' => 0,
    'JSON::XS' => 0,
    'File::ShareDir' => 0,
    'Scalar::Util' => 0,
  },
  CONFIGURE_REQUIRES => {
    'LWP::Simple' => 0,
    'Archive::Extract' => 0,
    'File::ShareDir::Install' => 0,
  },
  LICENSE => 'perl',
  dist => {
    PREOP => 'pod2text $(VERSION_FROM) > $(DISTVNAME)/README',
  },
  META_MERGE => {
    resources => {
      repository => 'git://github.com/hoytech/Thrust.git',
      bugtracker => 'https://github.com/hoytech/Thrust/issues',
    },
  },
);

WriteMakefile(%args);

package MY;
use File::ShareDir::Install qw(postamble);
