#!/usr/bin/perl -w

use strict;
use CGI qw(:standard);
use DBI;
use Time::ParseDate;
BEGIN {
    $ENV{PORTF_DBMS}="oracle";
    $ENV{PORTF_DB}="cs339";
    $ENV{PORTF_DBUSER}="qzw056";
    $ENV{PORTF_DBPASS}="zM0rH5vkt";

    unless ($ENV{BEGIN_BLOCK}) {
        use Cwd;
        $ENV{ORACLE_BASE}="/raid/oracle11g/app/oracle/product/11.2.0.1.0";
        $ENV{ORACLE_HOME}=$ENV{ORACLE_BASE}."/db_1";
        $ENV{ORACLE_SID}="CS339";
        $ENV{LD_LIBRARY_PATH}=$ENV{ORACLE_HOME}."/lib";
        $ENV{BEGIN_BLOCK} = 1;
        exec 'env',cwd().'/'.$0,@ARGV;
    }
};

use Data::Dumper;
use Finance::Quote;
use FileHandle;
use Time::CTime;
use Date::Manip;
use Finance::QuoteHist::Yahoo;
use Time::Local;
use Getopt::Long;

my $dbuser="qzw056";
my $dbpasswd="zM0rH5vkt";


my @sqlinput=();
my @sqloutput=();

my $user = undef;
my $password = undef;
my $logincomplain=0;
my $validatecomplain=0;


my (@stocks,$error) = ShowStocks();
if ($#stocks >= 0) {
    for(my $i=0; $i <= $#stocks; $i++){
        DailyAdd($stocks[$i][0]);
        print "now at $i: $stocks[$i][0] \n";
    }
}
print "OK";


sub DailyAdd {
    my ($symbol) = @_;
    my $con=Finance::Quote->new();
    my %quotes = $con->fetch("usa",$symbol);
    my $qdate = $quotes{$symbol,'date'};
    my $qopen = $quotes{$symbol,'open'};
    my $qhigh = $quotes{$symbol,'high'};
    my $qlow = $quotes{$symbol,'low'};
    my $qclose = $quotes{$symbol,'close'};
    my $qvolume = $quotes{$symbol,'volume'};
    if ($qdate and $qopen and $qhigh and $qlow and $qclose and $qvolume) {
        my $timestamp = parsedate($qdate);
        print $qvolume;

        eval { ExecSQL($dbuser,$dbpasswd,"insert into stocks_daily (symbol,timestamp,open,high,low,close,volume) VALUES (?,?,?,?,?,?,?)",undef,$symbol,$timestamp,$qopen,$qhigh,$qlow,$qclose,$qvolume);};
    }
}

sub ShowStocks{
    my @rows;
    eval {@rows =  ExecSQL($dbuser,$dbpasswd,
            "select * from stocks",undef,@_);};
    return @rows;
}

sub ExecSQL {
    my ($user, $passwd, $querystring, $type, @fill) =@_;
    my $dbh = DBI->connect("DBI:Oracle:",$user,$passwd);
    if (not $dbh) {
        # if the connect failed, record the reason to the sqloutput list (if set)
        # and then die.
        die "Can't connect to database because of ".$DBI::errstr;
    }
    my $sth = $dbh->prepare($querystring);
    if (not $sth) {
        #
        # If prepare failed, then record reason to sqloutput and then die
        #
        my $errstr="Can't prepare $querystring because of ".$DBI::errstr;
        $dbh->disconnect();
        die $errstr;
    }
    if (not $sth->execute(@fill)) {
        #
        # if exec failed, record to sqlout and die.
        my $errstr="Can't execute $querystring with fill (".join(",",map {"'$_'"} @fill).") because of ".$DBI::errstr;
        $dbh->disconnect();
        die $errstr;
    }
    #
    # The rest assumes that the data will be forthcoming.
    #
    my @data;
    if (defined $type and $type eq "ROW") {
        @data=$sth->fetchrow_array();
        $sth->finish();
        $dbh->disconnect();
        return @data;
    }
    my @ret;
    while (@data=$sth->fetchrow_array()) {
        push @ret, [@data];
    }
    if (defined $type and $type eq "COL") {
        @data = map {$_->[0]} @ret;
        $sth->finish();
        $dbh->disconnect();
        return @data;
    }
    $sth->finish();
    $dbh->disconnect();
    return @ret;
}
