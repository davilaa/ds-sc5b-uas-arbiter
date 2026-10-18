#!/usr/bin/perl
# BUS=012 perr.pl DEVNUM... : USB 3 hub GetPortErrorCount (bmRequestType 0xA3, bRequest 0x0D) for ports 1-4
# of each hub (/dev/bus/usb/BUS/DEV). Link errors stay 0 on the DS-SC5B even during resets.
use strict; use Fcntl;
for my $d (@ARGV) { sysopen(my $fh,"/dev/bus/usb/$ENV{BUS}/$d",O_RDWR) or die; my @o;
  for my $p (1..4) { my $b="\0\0"; my $s=pack("CCSSSLx4p",0xA3,0x0D,0,$p,2,1000,$b);
    push @o, defined ioctl($fh,0xC0185500,$s) ? "p$p=".unpack("v",$b) : "p$p=ERR($!)"; }
  print "hub $d: @o\n"; }
