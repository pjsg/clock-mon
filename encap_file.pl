#!/usr/bin/perl
#
use strict;
use IO::Compress::Gzip qw(gzip);
use IO::File;

my %types = (
  html => 'text/html',
);

while (my $fn = shift @ARGV) {

  open(IN, "<$fn") || die "Cannot open $fn: $!";
  $fn =~ s/\./_/g;
  open(OUT, ">__$fn.lua") || die "Cannot open output __$fn.lua: $!";

  print OUT "local data = {\n";

  my $data;

  {
    local $/ = undef;
    $data = <IN>;
  }

  my $header = "HTTP/1.0 200 OK";

  if ($data =~ /(HTTP.*)/) {
    $header = $1;
    $data =~ s/(HTTP.*)\n+//;
  }

  my @out = ("$header\r\nConnection: close\r\nContent-type: ");

  my ($suffix) = $fn =~ /([a-z]+)$/;
  push @out, $types{$suffix};
  push @out, "\r\n";
  push @out, "Content-encoding: gzip\r\n";
  push @out, "\r\n";

  my $buffer;
  gzip \$data => \$buffer;
  push @out, $buffer;

  my $out = join('', @out);

  print OUT "-- Byte count is ", length($out), "\n";

  while (length($out)) {
    my $chunk = substr($out, 0, 1024);
    $out = substr($out, 1024);

    while (length($chunk)) {
      my $bit = substr($chunk, 0, 1024);
      $chunk = substr($chunk, 1024);

      $bit =~ s/([\x00-\x1f\\"\x7f-\xff])/sprintf("\\%03d", ord($1))/ge;
      print OUT '"', $bit, '"';

      if ($chunk) {
        print OUT " ..\n    ";
      }
    }

    if ($out) {
      print OUT ",\n";
    }
  }

  print OUT "}\n";

  print OUT <<EOF
return function() 
  local i = 0
  return function() 
    i = i + 1
    return data[i]
  end
end
EOF
}
