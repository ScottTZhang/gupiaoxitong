#!/usr/bin/perl -w

use Getopt::Long;
use Time::ParseDate;
use Time::CTime;
use FileHandle;

use Date::Manip;

use Finance::QuoteHist::Yahoo;

$close=1;

$notime=0;
$open=0;
$high=0;
$low=0;
$close=0;
$vol=0;
$plot=0;
$from = "last year";
$to = "now";

&GetOptions( "notime"=>\$notime,
             "open" => \$open,
	     "high" => \$high,
	     "low" => \$low,
	     "close" => \$close,
	     "vol" => \$vol,
	     "from=s" => \$from,
	     "to=s" => \$to, "plot" => \$plot);


# convert date model to what QuoteHist wants
# while assuring we can use Time::ParseDate parsing
# for compatability with everything else
$from = parsedate($from);
$from = ParseDateString("epoch $from");
$to = parsedate($to);
$to = ParseDateString("epoch $to");


$usage = "usage: quotehist.pl [--open] [--high] [--low] [--close] [--vol] [--from=time] [--to=time] [--plot] SYMBOL\n";

$#ARGV == 0 or die $usage;

$symbol = shift;

%query = (
	  symbols    => [$symbol],
	  start_date => $from,
	  end_date   => $to,
	 );


$q = new Finance::QuoteHist::Yahoo(%query) or die "Cannot issue query\n";



if ($plot) { 
  open(DATA,">_plot.in") or die "Cannot open plot file\n";
  $output = DATA;
} else {
  $output = STDOUT;
}


foreach $row ($q->quotes()) {
  my @out;

  ($qsymbol, $qdate, $qopen, $qhigh, $qlow, $qclose, $qvolume) = @{$row};

  push @out, parsedate($qdate) if !$notime;
  push @out, $qopen if $open;
  push @out, $qhigh if $high;
  push @out, $qlow if $low;
  push @out, $qclose if $close;
  push @out, $qvolume if $vol;

  print $output join("\t",@out),"\n";
}

if ($plot) {
  close(DATA);
  open(GNUPLOT, "|gnuplot") or die "Cannot open gnuplot for plotting\n";
  GNUPLOT->autoflush(1);
  print GNUPLOT "set title '$symbol'\nset xlabel 'time'\nset ylabel 'data'\n";
  print GNUPLOT "plot '_plot.in' with linespoints;\n";
  STDIN->autoflush(1);
  <STDIN>;
}


