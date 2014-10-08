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

use stock_data_access;

use Data::Dumper;
use Finance::Quote;
use FileHandle;
use Time::CTime;
use Date::Manip;
use Finance::QuoteHist::Yahoo;
use Time::Local;
#use POSIX 'strftime';
use Getopt::Long;

# The session cookie will contain the user's name and password so that
# he doesn't have to type it again and again.
#
# "PortfolioSession"=>"user/password"
#
# BOTH ARE UNENCRYPTED AND THE SCRIPT IS ALLOWED TO BE RUN OVER HTTP
# THIS IS FOR ILLUSTRATION PURPOSES.  IN REALITY YOU WOULD ENCRYPT THE COOKIE
# AND CONSIDER SUPPORTING ONLY HTTPS
#
# You need to override these for access to your database
#
my $debug = 0;
my $dbuser="qzw056";
my $dbpasswd="zM0rH5vkt";


my @sqlinput=();
my @sqloutput=();

my $user = undef;
my $password = undef;
my $logincomplain=0;
my $validatecomplain=0;
#
# Get the user action and whether he just wants the form or wants us to
# run the form
#
my $action;
my $run;

my $dstr;

print header(-expires=>'now');
print "<html style=\"height: 100\%\">";
print "<head>";
print "<title>Portfolio Management</title>";
print "</head>";

print "<body style=\"height:100\%;margin:0\">";

print "<style type=\"text/css\">\n\@import \"portfolio.css\";\n</style>\n";


my (@stocks,$error) = ShowStocks();
if ($#stocks >= 0) {
    for(my $i=1900; $i <= $#stocks; $i++){
        DownHist($stocks[$i][0]);
        print "now at $i: $stocks[$i][0] </br> \n";
    }
}
print "OK";


sub DownHist{
    my ($hold) = @_;
    $hold = uc($hold);
    my $nfrom='last year';
    my $nto = 'now';
    $nfrom = parsedate($nfrom);
    $nfrom = ParseDateString("epoch $nfrom");
    $nto = parsedate($nto);
    $nto = ParseDateString("epoch $nto");
    my %query=(symbols => [$hold],
        start_date => $nfrom,
        end_date => $nto,
    );
    my $q = new Finance::QuoteHist::Yahoo(%query);
    foreach my $row ($q->quotes()) {
        my ($qsymbol, $qdate, $qopen, $qhigh, $qlow, $qclose, $qvolume) = @$row;
        my @line;
        my $newd = parsedate($qdate);
        push(@line,$qsymbol);
        push(@line,$newd);
        push(@line,$qopen);
        push(@line,$qhigh);
        push(@line,$qlow);
        push(@line,$qclose);
        push(@line,$qvolume);
        my $err = DailyAdd(@line);
   }
}

sub DailyAdd{
    my ($qsymbol, $qdate, $qopen, $qhigh, $qlow, $qclose, $qvolume) = @_;
    TransactionSQL($dbuser,$dbpasswd,
        "insert into stocks_daily
        (symbol,timestamp,open,high,low,close,volume) VALUES
        ('$qsymbol',$qdate,$qopen,$qhigh,$qlow,$qclose,$qvolume)");
}

sub TransactionSQL {

    my ($user, $passwd, @query_list) = @_;
    my $dbh = DBI->connect("DBI:Oracle:",$user,$passwd,{
            AutoCommit => 0,
            RaiseError => 1,
        });
    if (not $dbh) {
        die "Can't connect to database because of ".$DBI::errstr;
    }

    eval {
        foreach my $index (0..$#query_list) {
            my $querystring = $query_list[$index];

            my $sth = $dbh->prepare($querystring);
            if (not $sth) {
                my $errstr="Can't prepare $querystring because of ".$DBI::errstr;
                $dbh->disconnect();
                die $errstr;
            }

            if (not $sth->execute()) {
                my $errstr="Can't execute $querystring because of ".$DBI::errstr;
                $dbh->disconnect();
                die $errstr;
            }
        }
        $dbh->commit();
    };

    if ($@) {
        $dbh->rollback();
    }

    $dbh->disconnect();
}

sub ShowStocks{
    my @rows;
    eval {@rows =  ExecSQL($dbuser,$dbpasswd,
            "select * from stocks",undef,@_);};
    return @rows;
}

sub ExecSQL {
    my ($user, $passwd, $querystring, $type, @fill) =@_;
    if ($debug) {
        # if we are recording inputs, just push the query string and fill list onto the
        # global sqlinput list
        push @sqlinput, "$querystring (".join(",",map {"'$_'"} @fill).")";
    }
    my $dbh = DBI->connect("DBI:Oracle:",$user,$passwd);
    if (not $dbh) {
        # if the connect failed, record the reason to the sqloutput list (if set)
        # and then die.
        if ($debug) {
            push @sqloutput, "<b>ERROR: Can't connect to the database because of ".$DBI::errstr."</b>";
        }
        die "Can't connect to database because of ".$DBI::errstr;
    }
    my $sth = $dbh->prepare($querystring);
    if (not $sth) {
        #
        # If prepare failed, then record reason to sqloutput and then die
        #
        if ($debug) {
            push @sqloutput, "<b>ERROR: Can't prepare '$querystring' because of ".$DBI::errstr."</b>";
        }
        my $errstr="Can't prepare $querystring because of ".$DBI::errstr;
        $dbh->disconnect();
        die $errstr;
    }
    if (not $sth->execute(@fill)) {
        #
        # if exec failed, record to sqlout and die.
        if ($debug) {
            push @sqloutput, "<b>ERROR: Can't execute '$querystring' with fill (".join(",",map {"'$_'"} @fill).") because of ".$DBI::errstr."</b>";
        }
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
        if ($debug) {push @sqloutput, MakeTable("debug_sqloutput","ROW",undef,@data);}
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
        if ($debug) {push @sqloutput, MakeTable("debug_sqloutput","COL",undef,@data);}
        $dbh->disconnect();
        return @data;
    }
    $sth->finish();
    if ($debug) {push @sqloutput, MakeTable("debug_sql_output","2D",undef,@ret);}
    $dbh->disconnect();
    return @ret;
}
