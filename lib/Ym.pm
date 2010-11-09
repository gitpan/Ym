#!/usr/bin/perl

package Ym;

BEGIN {
  use Cwd;
  use FindBin;

  chroot('/');

  $ENV{'YM_BIN'}  = "$FindBin::RealBin";
  $ENV{'YM_LIB'}  = Cwd::abs_path("$ENV{'YM_BIN'}/../lib");
  $ENV{'YM_ETC'}  = Cwd::abs_path("$ENV{'YM_BIN'}/../etc");
}

use 5.008008;
use warnings;
use strict;

require Exporter;

our @ISA = qw(Exporter);

our %EXPORT_TAGS = ( 'all' => [ qw() ] );
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );
our @EXPORT = qw();

our $VERSION = '0.01';

my $ymcfg = "$ENV{'YM_ETC'}/ymconfig.pl";

if (-s $ymcfg) {
  do $ymcfg;
}
else {
  die "No config file [$ymcfg].\n";
}

use Data::Dumper;
use File::Copy;
use Storable qw/dclone store retrieve/;

require "$ENV{'YM_LIB'}/ymcmd.pl";
require "$ENV{'YM_LIB'}/ymcommon.pl";
require "$ENV{'YM_LIB'}/ymgen.pl";
require "$ENV{'YM_LIB'}/ymparse.pl";
require "$ENV{'YM_LIB'}/ymstat.pl";

eval {
  require "$ENV{'YM_LIB'}/ymspecific.pl";
  YmSpecific->import();
};

1;

__END__

=head1 NAME

Ym - a command line tool for manipulating Nagios configuration.

=head1 SYNOPSIS

  Type ym --help and see all available commands.

=head1 AUTHOR

Andrey Grunau, E<lt>andrey-grunau@yandex.ruE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2010 by Andrey Grunau

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.

=cut
