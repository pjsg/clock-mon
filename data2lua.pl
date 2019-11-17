#!/usr/bin/perl
#
use strict;

while (my $fn = shift @ARGV) {
  open(IN, "<$fn.data");
  open(OUT, ">$fn.lua");

  print OUT "return function() return \"";

  while (<IN>) {
    my @hexes = /0x([a-f0-9A-F][a-f0-9A-F])/g;

    foreach my $hex (@hexes) {
      printf OUT "\\%03d", hex($hex);
    }
  }

  print OUT "\"\nend\n";
}
