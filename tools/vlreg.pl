#!/usr/bin/perl
# vlreg.pl DEV r ADDR [COUNT] | DEV w ADDR VAL  -- VIA VL82x hub XDATA register access via usbfs
use strict; use Fcntl;
my ($dev,$op,$addr,$x)=@ARGV; $addr=hex($addr);
sysopen(my $fh,$dev,O_RDWR) or die "open $dev: $!";
my $IOC=0xC0185500;
sub ctrl { my ($rt,$rq,$val,$idx,$len)=@_; my $buf="\0" x ($len||1);
  my $s=pack("CCSSSLx4p",$rt,$rq,$val,$idx,$len,1000,$buf);
  my $r=ioctl($fh,$IOC,$s); defined $r or return undef; return $len? ord(substr($buf,0,1)) : 0; }
if ($op eq 'r') { my $n=defined $x? hex($x):1; my $line="";
  for my $i (0..$n-1) { my $a=$addr+$i; my $v=ctrl(0xC0,$a>>8,$a&0xff,0,1);
    $line.= (($i%16)==0? sprintf("\n%04x:",$a):"") . (defined $v? sprintf(" %02x",$v):" --"); }
  print "$line\n"; }
elsif ($op eq 'w') { my $v=hex($x); my $r=ctrl(0x40,$addr>>8,$addr&0xff,$v,0);
  printf "w %04x=%02x %s\n",$addr,$v,(defined $r?"ok":"FAIL $!"); }
