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
use POSIX 'strftime';
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
my $dbuser="qzw056";
my $dbpasswd="zM0rH5vkt";


my $cookiename="PORTFOLIOSession";

my $debug;
if (defined(param("debug"))) {
    $debug=param("debug");

} else {
    $debug=0;
}
my @sqlinput=();
my @sqloutput=();

#
# Get the session input and debug cookies, if any
#
my $inputcookiecontent = cookie($cookiename);


#
# Will be filled in as we process the cookies and paramters
#
my $outputcookiecontent = undef;
my $deletecookie=0;
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


if (defined(param("act"))) {
    $action=param("act");
    if (defined(param("run"))) {
        $run = param("run") == 1;
    } else {
        $run = 0;
    }
} else {
    $action="base";
    $run = 1;
}

my $dstr;


#
#
# Who is this?  Use the cookie or anonymous credentials
#
#
if (defined($inputcookiecontent)) {
    # Has cookie, let's decode it
    ($user,$password) = split(/\//,$inputcookiecontent);
    $outputcookiecontent = $inputcookiecontent;
} else {
    # No cookie, treat as anonymous user
    ($user,$password) = ("anon","anonanon");
}

#
# Is this a login request or attempt?
# Ignore cookies in this case.
#
if ($action eq "login") {
    if ($run) {
        # Login attempt
        # Ignore any input cookie.  Just validate user and
        # generate the right output cookie, if any.
        ($user,$password) = (param('user'),param('password'));
        if (ValidUser($user,$password)) {
            # if the user's info is OK, then give him a cookie
            # that contains his username and password
            # the cookie will expire in one hour, forcing him to log in again
            # after one hour of inactivity.
            # Also, land him in the base query screen
            $outputcookiecontent=join("/",$user,$password);
            $action = "base";
            $run = 1;
        } else {
            # uh oh.  Bogus login attempt.  Make him try again.
            # don't give him a cookie
            $logincomplain=1;
            $action="login";
            $run = 0;
        }
    } else {
        # Just a login screen request, but we should toss out any cookie
        # we were given
        undef $inputcookiecontent;
        ($user,$password)=("anon","anonanon");
    }
}


#
# If we are being asked to log out, then if
# we have a cookie, we should delete it.
#
if ($action eq "logout") {
    $deletecookie=1;
    $action = "base";
    $user = "anon";
    $password = "anonanon";
    $run = 1;
}


my @outputcookies;

#
# OK, so now we have user/password
# and we *may* have an output cookie.   If we have a cookie, we'll send it right
# back to the user.
#
# We force the expiration date on the generated page to be immediate so
# that the browsers won't cache it.
#
if (defined($outputcookiecontent)) {
    my $cookie=cookie(-name=>$cookiename,
        -value=>$outputcookiecontent,
        -expires=>($deletecookie ? '-1h' : '+1h'));
    push @outputcookies, $cookie;
}

#
# Headers and cookies sent back to client
#
# The page immediately expires so that it will be refetched if the
# client ever needs to update it
#

#
# Now we finally begin generating back HTML
#
#
if (!defined(param("distype")) or param("distype") ne 'Plot') {
    print header(-expires=>'now', -cookie=>\@outputcookies);
    print "<html style=\"height: 100\%\">";
    print "<head>";
    print "<title>Portfolio Management</title>";
    print "</head>";

    print "<body style=\"height:100\%;margin:0\">";

    #
# Force device width, for mobile phones, etc
    #
#print "<meta name=\"viewport\" content=\"width=device-width\" />\n";

# This tells the web browser to render the page in the style
# defined in the css file
    #
    print "<style type=\"text/css\">\n\@import \"portfolio.css\";\n</style>\n";
} else {
    print header(-type => 'image/png', -expires => 'now' , -cookie=>\@outputcookies);
}

#
# Generate debugging output if anything is enabled.
#
#
if ($debug) {
    print hr, p, hr,p, h2('Debugging Output');
    print h3('Parameters');
    print "<menu>";
    print map { "<li>$_ => ".escapeHTML(param($_)) } param();
    print "</menu>";
    print h3('Cookies');
    print "<menu>";
    print map { "<li>$_ => ".escapeHTML(cookie($_))} cookie();
    print "</menu>";
    my $max= $#sqlinput>$#sqloutput ? $#sqlinput : $#sqloutput;
    print h3('SQL');
    print "<menu>";
    for (my $i=0;$i<=$max;$i++) {
        print "<li><b>Input:</b> ".escapeHTML($sqlinput[$i]);
        print "<li><b>Output:</b> $sqloutput[$i]";
    }
    print "</menu>";
}

if($action eq "base"){
    print "<script src=\"http://ajax.googleapis.com/ajax/libs/jquery/1.4.2/jquery.min.js\" type=\"text/javascript\"></script>";
    if($user eq "anon"){
        print "<p>You are anonymous, but you can also <a href=\"portfolio.pl?act=login\">login</a></p>";
        print "<p>If you do not have an account,  you can also <a href=\"portfolio.pl?act=register\">register</a></p>";
    }
    else{
        print "<h1> Welcome to your portfolio management system, $user.</h1>";
        print "<p><a href=\"portfolio.pl?act=create-portfolio\">Create Portfolio</a></p>";
        print "<p><a href=\"portfolio.pl?act=manage-portfolio\">Manage Portfolio</a></p>";
        print "<p><a href=\"portfolio.pl?act=manage-cash\">Manage Cash</a></p>";
        print "<p><a href=\"portfolio.pl?act=logout\">Logout</a></p>";
    }
}

if($action eq "create-portfolio"){
    if(!$run){
        print start_form(-name=>'Account Creation'),
        h2('Create a portfolio'),
        "Portolio name:",textfield(-name=>'p_name'),p,
        hidden(-name=>'owner',default=>[$user]),
        "Initial cash:",textfield(-name=>'cash'),p,
        hidden(-name=>'run',default=>['1']),
        hidden(-name=>'act',-default=>['create-portfolio']),
        submit,
        end_form;
        hr;
    }
    else {

        print "welcome to the new page.\n";
        my $owner = param("owner");
        my $p_name = param("p_name");
        my $cash = param("cash");
        my $error;
        print $owner,$p_name,$cash;
        $error = PortfolioAdd($owner,$p_name,$cash);
        if ($error)
        {
            print h2("Cannot add user because: $error");
        }
        else
        {
            print "<h3>add portfolio $p_name success.</h3>";
            print "<p><a href=\"portfolio.pl?act=base&run=1\">Return</a></p>";
        }
    }
}

if($action eq "manage-portfolio"){
    if(!$run){
        print "Dear $user, you can view your portfolio from here";
        my (@str,$error) =  ShowPortfolio($user);
        #print $#str;
        if ($#str >= 0) {
            for(my $i=0; $i <= $#str; $i++){
                print "<p><a href=\"portfolio.pl?act=view&p_id=$str[$i][0]\">View Porfolio <b>$str[$i][2]</b></a></p>";
            }
        }
        print "<p><a href=\"portfolio.pl?act=base&run=1\">Return</a></p>";
    }
}

if($action eq "view"){
    if(!$run){
        my $p_id = param('p_id');
        my (@holdings,$error) =  ShowStockHoldings($p_id);

        print "<h3>Your cash account</h3>";
        my $balance = getBalance($p_id);
        print "<p>\$$balance</p>";

        my @holdInfo;
        my $total_value = 0;
        my $out = "<h3>Your holdings' daily information</h3>
        <table border=\"1\">
        <tr>
        <th>SYMBOL</th>
        <th>Date</th>
        <th>Time</th>
        <th>High</th>
        <th>low</th>
        <th>Close</th>
        <th>Open</th>
        <th>Volume</th>
        <th>Your Share</th>
        <th>Your Value</th>
        </tr>
        ";	
        if($#holdings >=0){
            for(my $i=0;$i<=$#holdings;$i++){
                #give a table to show the daily info 
                my $symbol = $holdings[$i][0];
                @holdInfo = getDailyInfo($symbol);
		### get xianzhi
                my $latest_price = $holdings[$i][1] * getLatestPrice($symbol);
                my $value = $latest_price;
                $total_value += $value;

                $out .= "<tr>
                <td><a href=\"portfolio.pl?act=viewstock&p_id=$p_id&symbol=$symbol\">$symbol</a></td>
                <td>$holdInfo[0]</td> 
                <td>$holdInfo[1]</td>
                <td>$holdInfo[2]</td>
                <td>$holdInfo[3]</td>
                <td>$holdInfo[4]</td>
                <td>$holdInfo[5]</td>
                <td>$holdInfo[6]</td>
                <td>$holdings[$i][1]</td> 
                <td>$value</td> 
                </tr>";
            }
        }
        $out .="</table>";
        print $out;
	my $trans_value = sellTotal($p_id) - buyTotal($p_id);
	my $net = $total_value + $trans_value;
        print "<p>  Total Current Value \$$total_value</p><p>+ Transaction Value \$$trans_value</p><p> = Net Income \$$net </p>";

        print "<h3>Actions</h3>";
        print "<p><a href=\"portfolio.pl?act=statistics&p_id=$p_id\">View Statistics</a></p>";
        print "<p><a href=\"portfolio.pl?act=history&p_id=$p_id\">View History</a></p>";
        print "<p><a href=\"portfolio.pl?act=buy_stock&p_id=$p_id\">Buy Stock</a></p>";
        print "<p><a href=\"portfolio.pl?act=sell_stock&p_id=$p_id\">Sell Stock</a></p>";
     	print "<p><a href=\"portfolio.pl?act=view_future&p_id=$p_id\">View Future</a></p>";
        print "<p><a href=\"portfolio.pl?act=manage-portfolio\">Return</a></p><br>";
    }
}

if($action eq "view_future"){
    if(!$run){
        if(url_param('p_id')){
            print "<h3>Let's see!</h3>";
	    my $p_id = url_param('p_id');
            my @stockHolds=();
            my (@holdings,$error) = ShowStockHoldings($p_id);
            for(my $j=0;$j < $#holdings;$j++){
                push(@stockHolds,$holdings[$j][0]);
            }
            print start_html(-title=>'FUTURE'),
	     start_form(-name=>'ViewFuture'),
            "Choose a holding: ",radio_group(-name=>'hold',
                -values=>\@stockHolds),p,
	    "Future Date (MM/DD/YY, Will override dropbox): ",textfield(-name=>'fudate',-id=>'fu'),p,
            #"SYMBOL",textfield(-name=>'symbol'),p,
	    "or choose one time Range:",popup_menu(
		-name   => 't',
		-values => [
			'',
			'Tomorrow',
			'One week from now',
			'One month from now',
			'One quarter to now',
			'One year from now'
		]
	  ),p,
            "Plot or Table:",radio_group(-name=>'distype',
                -values=>['Table','Plot']),p, 
            hidden( -name => 'pid', default => [$p_id] ),
            hidden( -name => 'act', default => 'view_future' ),
            hidden(-name=>'run',default=>['1']),
            submit(-name=>'future', -value => 'View Future'),p,
            end_form,
	end_html;
        }   
    	
    }
    else{
	my $hold = param('hold');
       	my $p_id = param('pid');
	my $t      = param("t");
	my $from   = time;
	my $to     = param('fudate');
	$to = parsedate($to);
	if ($t) {
		if ( $t eq "Tomorrow" ) {
			$to = $from + 86400;
		}
		elsif ( $t eq "One week from now" ) {
			$to = $from + 604800;
		}
		elsif ( $t eq "One month from now" ) {
			$to = $from + 2628000;
		}
		elsif ( $t eq "One quarter from now" ) {
			$to = $from + 7884000;
		}
		elsif ( $t eq "One year from now" ) {
			$to = $from + 31540000;
		}
	}
		if ( $from && $to ) {
		 	print "$from $to $t $hold";
			my $result = stockFutureValue( $hold, $from, $to );
			print $result;
		}

	print "<h3>See what?</h3>";
        print "<p><a href=\"portfolio.pl?act=view&p_id=$p_id\">Return Porfolio View</a></p>";
    }
    my $p_id= url_param('p_id');
    print "<p><a href=\"portfolio.pl?act=view&p_id=$p_id\">Return</a></p>";
}

if($action eq "viewstock"){
    if(!$run){
   	print "nothing here";
    }   
    else{
	print "hello";
    }
}

if($action eq "buy_stock"){
    my $p_id = param('p_id');

    if(!$run){
        print start_form(-name=>'Buy Stock'),
        h2('Buy Stock'),
        "Symbol:",textfield(-name=>'symbol'),
        p,
        "Share Amount:",textfield(-name=>'amount'),
        p,
        hidden(-name=>'p_id',default=>[$p_id]),
        hidden(-name=>'run',default=>['1']),
        hidden(-name=>'act',-default=>['buy-stock']),
        submit,
        end_form;
        hr;
    }
    else{
        my $p_id =  param('p_id');
        my $symbol = param('symbol');
        my $amount = param('amount');
        my $error;
        $error = BuyStock($p_id,$symbol,$amount, getLatestPrice($symbol));
        if($error){
            print "Cannot buy stock: $error";
        }
        else{
            print "You have bought $symbol for $amount shares.";
        }
    }
    print "<p><a href=\"portfolio.pl?act=view&p_id=$p_id\">Return Porfolio View</a></p>";
}

if($action eq "sell_stock"){
    my $p_id = param('p_id');

    if(!$run){
        my (@holdings,$error) =  ShowStockHoldings($p_id);
        my @stock_list = ();
        if ($#holdings >= 0) {
            for(my $i=0; $i <= $#holdings; $i++){
                push(@stock_list, $holdings[$i][0]);
            }
        }

        print start_form(-name=>'Sell Stock'),
        h2('Sell Stock'),
        "Symbol:",popup_menu(
            -name   => 'symbol',
            -values => \@stock_list
        ),
        p,
        "Share Amount:",textfield(-name=>'amount'),
        p,
        hidden(-name=>'p_id',default=>[$p_id]),
        hidden(-name=>'run',default=>['1']),
        hidden(-name=>'act',-default=>['sell-stock']),
        submit,
        end_form;
        hr;
    }
    else{
        my $p_id =  param('p_id');
        my $symbol = param('symbol');
        my $amount = param('amount');
        my $error;
        $error = SellStock($p_id,$symbol,$amount, getLatestPrice($symbol));
        if($error){
            print "Cannot sell stock: $error";
        }
        else{
            print "You have sold $symbol for $amount shares.";
        }
    }
    print "<p><a href=\"portfolio.pl?act=view&p_id=$p_id\">Return Porfolio View</a></p>";
}

if($action eq 'history'){
    if(!$run){	
        if(url_param('p_id')){
            my $p_id = url_param('p_id');
            my @stockHolds=();
            my (@holdings,$error) = ShowStockHoldings($p_id);
            for(my $j=0;$j < $#holdings;$j++){
                push(@stockHolds,$holdings[$j][0]);
            }

            print start_form(-name=>'ViewHistory'),
            "Choose a holding: ",radio_group(-name=>'hold',
                -values=>\@stockHolds),p,
            #"SYMBOL",textfield(-name=>'symbol'),p,
            "Choose options: ",checkbox_group(-name=>'options',
                ###?????get values from databases????### 
                -values=>['open','low','high','close','volume']),p, 
            "From", textfield( -name => 'from' ),
            "MM/DD/YEAR",p,
            "To", textfield( -name => 'to' ),
            "MM/DD/YEAR", p,
	    "Time Range:",popup_menu(
		-name   => 't',
		-values => [
			'',
			'Yesterday',
			'Last week to now',
			'Last month to now',
			'Last quarter to now',
			'Last year to now',
			'Last five years to now'
		]
	  ),p,
            "Plot or Table:",radio_group(-name=>'distype',
                -values=>['Table','Plot']),p, 
            hidden( -name => 'pid', default => [$p_id] ),
            hidden( -name => 'act', default => 'statistics' ),
            hidden(-name=>'run',default=>['1']),
            submit(-name=>'viewoption', -value => 'View Optional History'),p,
            end_form;
        }   
        my $p_id = url_param('p_id');
        print "<p><a href=\"portfolio.pl?act=view&p_id=$p_id\">Return</a></p>";
    }
    else {
        my $symbol = param('symbol');
        my $from=param('from');
        my $to = param('to');
	my $t = param('t');
        my $distype=param('distype');
        my $hold = param('hold');
        my $p_id = param('pid');
        my @options = param('options');
        my @oldhist;
        my @newhist;
        my $options = join(',',@options);

        if(param('viewoption')){
            if ($distype ne "Plot") {
            }
            getHist($symbol,$hold,$distype,$options,$from,$to,$t);
        }
    }
}

if($action eq "statistics"){
    if(!$run){
        if(url_param('p_id')){
            my $p_id = url_param('p_id');
            my @stockHolds=();
            my (@holdings,$error) = ShowStockHoldings($p_id);
            for(my $j=0;$j < $#holdings;$j++){
                push(@stockHolds,$holdings[$j][0]);
            }

            print start_form( -name => 'ViewMatrix' ),
            h2('View portfolio statistics'),
            "Holdings: ",checkbox_group(-name=>'holdings',
                -values=>\@stockHolds,
            ),p,
            "From", textfield( -name => 'from' ),
            "MM/DD/YEAR",p,
            "To", textfield( -name => 'to' ),
            "MM/DD/YEAR", p,
            "Volatility Type",radio_group(-name=>'type',
                -values=>['open','high','low','close','volume']),p,
            "Field1",radio_group(-name=>'field1',
                -values=>['open','high','low','close']),p,
            "Field2", radio_group(-name=>'field2',
                -values=>['open','high','low','close']),p,
            "Choose Correlation Coeffiicient or Covariance:<br>",radio_group(-name=>'cotype',
                -values=>['cor','cov']),p,
            hidden( -name => 'statisticsrun', default => ['1'] ),
            hidden( -name => 'pid', default => [$p_id] ),
            hidden( -name => 'act', default => 'statistics' ),
            hidden(-name=>'run',default=>['1']),
            submit(-name=>'vol', -value => 'View Volatility'),
            submit(-name=>'cov',-value=>'View Correlation'),
            submit(-name=>'beta',-value=>'View Beta'),
            p,
            end_form;
        } 
        my $p_id = url_param('p_id'); 
        print "<p><a href=\"portfolio.pl?act=view&p_id=$p_id\">return</a></p>"; 
    }
    else{
        my $field1=param('field1');
        my $field2=param('field2');
        my $type = param('type');
        my $cotype=param('cotype');
        my $from=param('from');
        my $to=param('to');
        my $p_id = param('pid');
        my @holdings = param('holdings');
        my $holdings =join(",",@holdings);
        if(param('vol')){
            print getVOL($field1,$field2,$type,$from,$to,$p_id,$holdings);
            print "<p><a href=\"portfolio.pl?act=statistics&p_id=$p_id\">return</p>";
        }
        if(param('cov')){
            if($#holdings<1){
                print "choose at least two stocks.<p><a href=\"portfolio.pl?act=statistics&p_id=$p_id\">return</p>";
            }
            else{    
                print getCOV($field1,$field2,$type,$cotype,$from,$to,$p_id,$holdings);
                print "choose at least two stocks.<p><a href=\"portfolio.pl?act=statistics&p_id=$p_id\">return</p>";
            }
        }
	if(param('beta')){
 	    
	    my $beta = getBeta($holdings,$from,$to);
	    print $beta;
            print "choose at least two stocks.<p><a href=\"portfolio.pl?act=statistics&p_id=$p_id\">return</p>";
	}
    }	
}


if($action eq "manage-cash"){
    if(!$run){
        print "Dear $user, you can view your portfolio from here<br>";
        my (@str,$error) =  ShowPortfolio($user);
        my ($bal,$err) = ShowBalance($user);
        print "<h3>balance</h3>$bal";
        my %hash = ();
        if ($#str >= 0) {
            for(my $i=0; $i <= $#str; $i++){
                $hash{$str[$i][0]} = $str[$i][2];
            }
        }
        print start_form(-name=>'por_radio'),
        radio_group(-name =>'p_id',
            -values=>[keys %hash],
            -labels=>\%hash,
            -linebreak=>'true'),
        p,
        'Action:',
        p,
        radio_group(-name=>'act_group',
            -values=>['deposit','withdraw'],
            -linebreak=>'true'),
        p,
        "Cash amount: ",textfield(-name=>'amount'),
        p,
        hidden(-name=>'run',-default=>['1']),
        hidden(-name=>'act',-default=>['manage-cash']),
        submit,
        end_form,
        hr;
        ;
    }
    else{
        my $p_id =  param('p_id');
        my $cash_act = param('act_group');
        my $amount = param('amount');
        my $error;
        $error = UpdateCash($user,$p_id,$cash_act,$amount);
        if($error){print "Cannot update cash:$error";}
        else{
            print "Update $p_id do $cash_act $amount.";
        }
    }
    print "<p><a href=\"portfolio.pl?act=base\">Return</a></p>";

}


if($action eq "update-daily-stocks"){

    my (@stocks,$error) =  ShowStocks();
    if ($#stocks >= 0) {
        for(my $i=0; $i <= $#stocks; $i++){
            DailyAdd($stocks[$i][0]);
        }
    }
    print "OK";
}

if($action eq "login"){
    if($logincomplain){
        print "login failed. try again.";
    }
    if($logincomplain or !$run){
        print start_form(-name=>'Login'),
        h2('Login to portfolio management:'),
        "Name:",textfield(-name=>'user'),p,
        "Password:",password_field(-name=>'password'),p,
        hidden(-name=>'act',default=>['login']),
        hidden(-name=>'run',default=>['1']),
        submit,
        end_form;
    }
}



if($action eq "register"){
    if(!$run)
    {
        print start_form(-name=>'Account Creation'),
        h2('Create an account for portfolio'),
        "Email:",textfield(-name=>'email'),p,
        "Name:",textfield(-name=>'user'),p,
        "Password:",password_field(-name=>'pwd'),p,
        hidden(-name=>'run',default=>['1']),
        hidden(-name=>'act',-default=>['register']),
        submit,
        end_form;
        hr;
    }
    else
    {
        print "welcome to the new page.\n";
        my $user = param("user");
        my $password = param("pwd");
        my $error;
        my $email = param("email");
        print $user,$password,$email;
        $error = UserAdd($user,$password,$email);
        if ($error)
        {
            print h2("Cannot add user because: $error");
        }
        else
        {
            print "<h3>add user $user success.</h3>";
            print "<p><a href=\"portfolio.pl?act=login&run=1\">Return to login</a></p>";
        }

    }
}

sub BuyStock{
    my ($p_id,$symbol,$amount,$price) = @_;

    if ($amount <= 0) {
        return "Invalid amount";
    }

    my $total = $amount * $price;

    my @query_list = (
        "insert into stock_transactions 
        (id,portfolio_id,symbol,share_amount,transaction_type,strike_price,transaction_time) 
        values(stock_transactions_id.nextval,$p_id,'$symbol',$amount,1,$price,current_timestamp)",

        "merge into stock_holdings using dual on (symbol='$symbol' and portfolio_id=$p_id)
        when matched then update set share_amount=share_amount+$amount
        when not matched then insert (portfolio_id,symbol,share_amount) 
        values ($p_id,'$symbol',$amount)",

        "update portfolio_accounts set cash=cash-$total where id=$p_id"
    );

    TransactionSQL($dbuser,$dbpasswd,@query_list);
    return $@;
}

sub SellStock{
    my ($p_id,$symbol,$amount,$price) = @_;

    if ($amount <= 0) {
        return "Invalid amount";
    }

    my $total = $amount * $price;

    my @query_list = (
        "insert into stock_transactions 
        (id,portfolio_id,symbol,share_amount,transaction_type,strike_price,transaction_time) 
        values(stock_transactions_id.nextval,$p_id,'$symbol',$amount,2,$price,current_timestamp)",

        "merge into stock_holdings using dual on (symbol='$symbol')
        when matched then update set share_amount=share_amount-$amount
        when not matched then insert (portfolio_id,symbol,share_amount) 
        values ($p_id,'$symbol',$amount)",

        "update portfolio_accounts set cash=cash+$total where id=$p_id"
    );

    TransactionSQL($dbuser,$dbpasswd,@query_list);
    return $@;
}

sub downloadIXIC{
    my ($nfrom,$nto) = @_;
   # my $nfrom='last year';
   # my $nto = 'now';
    if($nfrom eq ''){$nfrom='last year';}
    if($nto eq ''){$nto='now';}
    $nfrom = parsedate($nfrom);
    $nfrom = ParseDateString("epoch $nfrom");
    $nto = parsedate($nto);
    $nto = ParseDateString("epoch $nto");
    print "last year $nfrom now $nto";
    my %query=(symbols => ['^IXIC'],
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
        ####insert new data into stocks_daily##
        my $err=DailyAddnew(@line);
     	
    print @line,"<br>";
   }
}


######## using ^IXIC latest one year data to calculate #######
sub getBeta{
    my ($holdings,$from,$to) = @_;
    #downloadIXIC($from,$to);   
    my $out="<h3>Beta of $holdings</h3>";
    my @stockHolds=split(',',$holdings);
    my $s1;
    my $sql;
    my %covar;
    my %corrcoeff;
    my ($count,$mean_f1,$std_f1,$mean_f2, $std_f2)=@_;
    if (defined $from) { $from=parsedate($from);}
    if (defined $to) { $to=parsedate($to); }

    for (my $i=0;$i<=$#stockHolds;$i++) {
        $s1=$stockHolds[$i];

#first, get means and vars for the individual columns that match

            $sql = "select count(*),avg(l.close),stddev(l.close),avg(r.close),stddev(r.close) from Stocks_view1 l join Stocks_view1 r on l.timestamp= r.timestamp where l.symbol='$s1' and r.symbol='^IXIC'";
            $sql.= " and l.timestamp>=$from" if $from;
            $sql.= " and l.timestamp<=$to" if $to;

            ($count, $mean_f1,$std_f1, $mean_f2, $std_f2) = ExecStockSQL("ROW",$sql);

#skip this pair if there isn't enough data
            if ($count<30) { # not enough data
                $covar{$s1}='NODAT';
                $corrcoeff{$s1}='NODAT';
            } else {

                #otherwise get the covariance

                $sql = "select avg((l.close - $mean_f1)*(r.close - $mean_f2)) from Stocks_view1 l join Stocks_view1 r on  l.timestamp=r.timestamp where l.symbol='$s1' and r.symbol='^IXIC'";
                $sql.= " and l.timestamp>= $from" if $from;
                $sql.= " and l.timestamp<= $to" if $to;

                ($covar{$s1}) = ExecStockSQL("ROW",$sql);

#and the correlationcoeff

                $corrcoeff{$s1} = $covar{$s1}/($std_f2*$std_f2);

            }
         
    }

    $out .="<table border=\"1\">
    <tr><th>------</th>";
    foreach (@stockHolds){
        $out.="<th>$_</th>";
    }  
    $out.="</tr>";
    $out .="<tr><td>Beta</td>";

    for (my $i=0;$i<=$#stockHolds;$i++) {
        $s1=$stockHolds[$i];
            $corrcoeff{$s1} =  $corrcoeff{$s1} eq "NODAT" ? "NODAT" : sprintf('%.8f',$corrcoeff{$s1});
            $out .= "<td>$corrcoeff{$s1}</td>";
    }
    $out .= "</tr>";
    $out.="</tabel>";
    return $out;
}

#####newest function
sub sellTotal{
	my ($p_id)=@_;
    	my @rows;
    	eval {@rows =  ExecSQL($dbuser,$dbpasswd,
            "select sum(share_amount * strike_price ) from stock_transactions where portfolio_id = ? and transaction_type =2",undef,$p_id);};
    	return $rows[0][0];
}

#####newest function
sub buyTotal{
	my ($p_id)=@_;
    	my @rows;
    	eval {@rows =  ExecSQL($dbuser,$dbpasswd,
            "select sum(share_amount * strike_price ) from stock_transactions where portfolio_id = ? and transaction_type =1",undef,$p_id);};
    	return $rows[0][0];
}

######new function:predict #####
sub stockFutureValue{
	my ( $symbol, $from, $to ) = @_;
	my $days_ahead = int( ( $to - $from ) / 86400.0 );
	print "<p>Total days: ", $days_ahead;
	system
	  "~/www/portfolio/get_data.pl --close --from=$from --to=$to $symbol > _plot.in";
	system
	  "~/www/portfolio/time_series_project _plot.in $days_ahead AR 16 1>predictor.out";
	system "tail -n $days_ahead predictor.out > predictor.plot";

	my $num_years  = ( $to - $from ) / 31556926.0;
	my $num_months = ( $to - $from ) / 2629743.0;
	my $num_days   = ( $to - $from ) / 86400.0;

	my @xlabel;

	if ( $num_months > 24 ) {
		@xlabel = PlotwithYear( $from, $to );
	}
	elsif ( $num_days > 60 ) {
		@xlabel = PlotwithMonth( $from, $to );
	}
	else {
		@xlabel = PlotwithDay( $from, $to );
	}

	my $xtics = "(" . join( ", ", @xlabel ) . ")";
	$from = localtime($from);
	$to   = localtime($to);
	print "<p>From: $from\n";
	print "To: $to\n";
	my $outfile =
	  GnuPlotFuture( "$symbol", "predictor.plot", "image.png", "$from", "$to",
		"$xtics" );
	print "<img src=\"" . $outfile . "\">";    
}

##new func
sub GnuPlotFuture{
   my ($symbol, $datafile, $outputfile,$from,$to,$xtics)=@_;
   my $format = "%Y";		 
   open(GNUPLOT,"|gnuplot");
   print GNUPLOT "set terminal png\n";
   print GNUPLOT "set output \"$outputfile\"\n";
   print GNUPLOT "set xtics $xtics \n";
   print GNUPLOT "set size 2.0, 1.0\n";
   print GNUPLOT "set style fill empty\n";
   print GNUPLOT "set title '$symbol'\nset xlabel 'Time' 0.0,-1.0\nset ylabel 'Price'\n";
   print GNUPLOT "plot \"$datafile\" using 3 with linespoints\n";
   close(GNUPLOT);
   return $outputfile;
}

sub PlotwithYear {
    my ($from, $to) = @_;
    my @xlabel;
    my $fromyear = 1900 + (localtime($from))[5];
    my $toyear = 1900 + (localtime($to))[5];
	if ($from > timelocal(0,0,0,1,0,$fromyear)) {
		$fromyear+=1;
	}
    foreach ($fromyear..$toyear) {
        push @xlabel, "\"$_\" " . timelocal(0,0,0,1,0,$_);
    }
    return @xlabel;
}

sub PlotwithMonth {
    my ($from, $to) = @_;
    my @xlabel;
    my ($fromday, $frommonth, $fromyear) = (localtime($from))[3,4,5];
    $fromyear += 1900;
    if ($fromday > 1) {
        $frommonth = ($frommonth+1)%12;
        if ($frommonth == 0) {
            $fromyear += 1;
        }
    }
    my ($tomonth,$toyear) = (localtime($to))[4,5];
    $toyear += 1900;
    my $to_timestamp = timelocal(0,0,0,1,$tomonth,$toyear);
    my $from_timestamp = timelocal(0,0,0,1,$frommonth,$fromyear);
    my @mons = qw( Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec );
    do {
        my $xtic = "$mons[$frommonth]";
        $xtic .= "\\n$fromyear";
        push @xlabel, "\"$xtic\" " . $from_timestamp;
        $frommonth = ($frommonth+1)%12;
        if ($frommonth == 0) {
            $fromyear += 1;
        }
        $from_timestamp = timelocal(0,0,0,1,$frommonth,$fromyear);
    } while ($from_timestamp <= $to_timestamp);

    return @xlabel;
}

sub PlotwithDay {
    my ($from, $to) = @_;
    my @xlabel;
    
    my @mons = qw(NOF Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);
    my ($fromday, $frommonth, $fromyear) = (localtime($from))[3,4,5];
    $fromyear += 1900;
    my $from_timestamp = timelocal(0,0,0,$fromday,$frommonth,$fromyear);

    my ($today, $tomonth,$toyear) = (localtime($to))[3,4,5];
    $toyear += 1900;
    my $to_timestamp = timelocal(0,0,0,$today,$tomonth,$toyear);
    my ($previous_month, $previous_year) = (0,0);
    do {
        my ($day, $month,$year) = (localtime($from_timestamp))[3,4,5];
        $month += 1;
        $year += 1900;
        my $xtic = "$day";
        if ($month != $previous_month) {
            $xtic .= "\\n$mons[$month] $year";
        }
        push @xlabel, "\"$xtic\" " . $from_timestamp;
        ($previous_month, $previous_year) = ($month, $year);
        $from_timestamp += 86400;
    } while ($from_timestamp <= $to_timestamp);
    return @xlabel;
}

##new function :  maybe insert into stocks table##
sub getHist{	
    my ($symbol,$hold,$distype,$options,$from,$to,$t) = @_;
### download from Yahoo!###
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
        ####insert new data into stocks_daily##
        my $err =DailyAdd(@line);
    #print @line,"<br>";
   }
    my @data=();
    if($options eq ''){$options = 'close';}
    my $sql ="select * from (select timestamp,$options from cs339.stocksdaily where symbol='$hold'" ;
    if (defined $from) { $from=parsedate($from);}
    if (defined $to) { $to=parsedate($to); }
	if ($t) {
		$to = time;
		if ( $t eq "Yesterday" ) {
		   $from = $to - 86400;
		}
		elsif ( $t eq "Last week to now" ) {
			$from = $to - 604800;
		}
		elsif ( $t eq "Last month to now" ) {
			$from = $to - 2628000;
		}
		elsif ( $t eq "Last quarter to now" ) {
			$from = $to - 7884000;
		}
		elsif ( $t eq "Last year to now" ) {
			$from = $to - 31540000;
		}
		elsif ( $t eq "Last five years to now" ) {
			$from = $to - 157700000;
		}
	}
    $sql.= " and timestamp >= $from" if $from;
    $sql.= " and timestamp <= $to" if $to;
    $sql.=" union select timestamp,$options from stocks_daily where symbol = '$hold'";
    $sql.= " and timestamp >= $from" if $from;
    $sql.= " and timestamp <= $to" if $to;
    $sql.= ") order by timestamp";

    @data = ExecStockSQL("2D",$sql);
    ##### select data from stocks_daily##
    if($distype eq "Table"){
	$from = ParseDateString("epoch $from");
	$to = ParseDateString("epoch $to");
        print "<h2>History of $symbol from $from to $to dispaying in $distype</h2>";
        print "$#data new records<br>";
        foreach my $line(@data){print "@$line<br>";} 
    }
    if($distype eq "Plot"){
        my $sql ="select * from (select timestamp,close from cs339.stocksdaily where symbol='$symbol'" ;
        if (defined $from) { $from=parsedate($from);}
        if (defined $to) { $to=parsedate($to); }
        $sql.= " and timestamp >= $from" if $from;
        $sql.= " and timestamp <= $to" if $to;
        $sql.=" union select timestamp,close from stocks_daily where symbol = '$symbol'";
        $sql.= " and timestamp >= $from" if $from;
        $sql.= " and timestamp <= $to" if $to;
        $sql.= ") order by timestamp";

        my @rows = ExecStockSQL("2D",$sql);
        #foreach my $line(@rows)
        #   print "@$line<br>";

        open(GNUPLOT,"| gnuplot") or die "Cannot run gnuplot";

        print GNUPLOT "set term png\n";           # we want it to produce a PNG
        print GNUPLOT "set output\n";             # output the PNG to stdout
        print GNUPLOT "plot '-' using 1:2 with linespoints\n"; # feed it data to plot
        foreach my $r (@rows) {
            print GNUPLOT $r->[0], "\t", $r->[1], "\n";
        }
        print GNUPLOT "e\n"; # end of data
        #
        # Here gnuplot will print the image content
        #
        close(GNUPLOT);
    }    
}

sub DailyAdd{
    my ($symbol) = @_;
    my $con=Finance::Quote->new();

    my %quotes = $con->fetch("usa",$symbol);
    my $qdate = $quotes{$symbol,'date'};
    my $qopen = $quotes{$symbol,'open'};
    my $qhigh = $quotes{$symbol,'high'};
    my $qlow = $quotes{$symbol,'low'};
    my $qclose = $quotes{$symbol,'close'};
    my $qvolume = $quotes{$symbol,'volume'};
    my $timestamp = parsedate($qdate);

    eval { ExecSQL($dbuser,$dbpasswd,"insert into stocks_daily (symbol,timestamp,open,high,low,close,volume) VALUES (?,?,?,?,?,?,?)",undef,$symbol,$timestamp,$qopen,$qhigh,$qlow,$qclose,$qvolume);};
}

sub DailyAddnew{
        my @row;
	my ($qsymbol, $qdate, $qopen, $qhigh, $qlow, $qclose, $qvolume) = @_;
        eval {@row= ExecSQL($dbuser,$dbpasswd,"insert into stocks_daily (symbol,timestamp,open,high,low,close,volume) VALUES (?,?,?,?,?,?,?)",undef,$qsymbol,$qdate,$qopen,$qhigh,$qlow,$qclose,$qvolume);};
	return @row;
}

sub getDailyInfo{
    my ($stock) = @_;
    my @info = ( "date", "time", "high", "low", "close", "open", "volume" );
    my @data;
    my $con = Finance::Quote->new();
    $con->timeout(60);
    my %quotes = $con->fetch( "usa", $stock );

    if ( !defined( $quotes{ $stock, "success" } ) ) {
        print "<p>No Data</p>";
    }
    else {
        foreach my $key (@info){ 
            if (defined($quotes{$stock,$key})){
                push(@data,$quotes{$stock,$key});}
            else{
                push(@data,"----");}
        }
    }
    return @data;
}

sub getBalance{
    my ($p_id)=@_;
    my @rows;
    eval {@rows =  ExecSQL($dbuser,$dbpasswd,
            "select cash from portfolio_accounts where id=?",undef,$p_id);};
    return $rows[0][0];
}

sub getLatestPrice{
    my ($symbol)=@_;
    my $con=Finance::Quote->new();
    $con->timeout(60);
    my %quotes = $con->fetch("usa",$symbol);
    return $quotes{$symbol,'price'};
}


sub getCOV{
    my ($field1,$field2,$type,$cotype,$from,$to,$p_id,$holdings)=@_;
    my $out="";
    my @stockHolds=split(',',$holdings);
    my $s1;
    my $s2;
    my $sql;
    my %covar;
    my %corrcoeff;
    my ($count,$mean_f1,$std_f1,$mean_f2, $std_f2)=@_;
    if (defined $from) { $from=parsedate($from);}
    if (defined $to) { $to=parsedate($to); }

    print "$field1 $field2 $holdings";
    for (my $i=0;$i<=$#stockHolds;$i++) {
        $s1=$stockHolds[$i];
        for (my $j=$i; $j<=$#stockHolds; $j++) {
            $s2=$stockHolds[$j];

#first, get means and vars for the individual columns that match

            $sql = "select count(*),avg(l.$field1),stddev(l.$field1),avg(r.$field2),stddev(r.$field2) from CS339.StocksDaily l join CS339.StocksDaily r on l.timestamp= r.timestamp where l.symbol='$s1' and r.symbol='$s2'";
            $sql.= " and l.timestamp>=$from" if $from;
            $sql.= " and l.timestamp<=$to" if $to;

            ($count, $mean_f1,$std_f1, $mean_f2, $std_f2) = ExecStockSQL("ROW",$sql);

#skip this pair if there isn't enough data
            if ($count<30) { # not enough data
                $covar{$s1}{$s2}='NODAT';
                $corrcoeff{$s1}{$s2}='NODAT';
            } else {

                #otherwise get the covariance

                $sql = "select avg((l.$field1 - $mean_f1)*(r.$field2 - $mean_f2)) from ".GetStockPrefix()."StocksDaily l join ".GetStockPrefix()."StocksDaily r on  l.timestamp=r.timestamp where l.symbol='$s1' and r.symbol='$s2'";
                $sql.= " and l.timestamp>= $from" if $from;
                $sql.= " and l.timestamp<= $to" if $to;

                ($covar{$s1}{$s2}) = ExecStockSQL("ROW",$sql);

#and the correlationcoeff

                $corrcoeff{$s1}{$s2} = $covar{$s1}{$s2}/($std_f1*$std_f2);

            }
        } 
    }


    if($cotype eq 'cor') {
        $out .= "<h2>Correlation Coefficient Matrix</h2>";
    } else {
        $out .= "<h2>Covariance Matrix</h2>";
    }

    $out.= "Rows: $field1<br>Cols: $field2<br><br>";

    $out .="<table border=\"1\">
    <tr><th>------</th>";
    foreach (@stockHolds){
        $out.="<th>$_</th>";
    }  
    $out.="</tr>";

    for (my $i=0;$i<=$#stockHolds;$i++) {
        $s1=$stockHolds[$i];
        $out .="<tr><td>$s1</td>";
        for (my $j=0; $j<=$#stockHolds;$j++) {
            if ($i>$j) {
                $out .= "<td>null</td>";
            } else {
                $s2=$stockHolds[$j];
                if ($cotype eq 'cor') {
                    $corrcoeff{$s1}{$s2} =  $corrcoeff{$s1}{$s2} eq "NODAT" ? "NODAT" : sprintf('%3.2f',$corrcoeff{$s1}{$s2});
                    $out .= "<td>$corrcoeff{$s1}{$s2}</td>";
                } else {
                    $covar{$s1}{$s2} = $covar{$s1}{$s2} eq "NODAT" ? "NODAT" : sprintf('%3.2f',$covar{$s1}{$s2}); 
                    $out .= "<td>$covar{$s1}{$s2}</td>";
                }
            }
        }
        $out .= "</tr>";
    }
    $out.="</tabel>";
    return $out;
}

sub getVOL{
    my ($field1,$field2,$type,$from,$to,$p_id,$holdings)=@_;
    my $out="<h3>volatility</h3><table border=\"1\">
    <tr>
    <th>Symbol</th>
    <th>amount</th>
    <th>avg($type)</th>
    <th>stddev($type)</th>
    </tr>";
    my @stockHolds=split(',',$holdings);
#foreach (@stockHolds){print $_;} 
    if ( defined $from ) { $from = parsedate($from); }
    if ( defined $to ) { $to = parsedate($to); }
    my $hold;
    print "$type $from $to<br>";
    foreach $hold(@stockHolds){
        my @row;
        my $sql="select count(*),avg($type),stddev($type) from (select timestamp,$type from CS339.StocksDaily where symbol ='$hold'";
        $sql.=" and timestamp >=$from" if $from;	
        $sql.=" and timestamp <=$to" if $to;
	$sql .= " union select timestamp,$type from stocks_daily where symbol='$hold'";
        $sql.=" and timestamp >=$from" if $from;	
        $sql.=" and timestamp <=$to" if $to;
	$sql .= ")";
        eval{@row=ExecSQL($dbuser,$dbpasswd,$sql,"ROW");};
        my ($cnt,$avg,$steddev) = @row;
        $out.= "<tr><td>$hold</td><td>$cnt</td><td>$avg</td><td>$steddev</td><tr>"; 
    }	

    $out.="</table><br>";
    return $out;
}


sub ShowStocks{
    my @rows;
    eval {@rows =  ExecSQL($dbuser,$dbpasswd,
            "select * from stocks",undef,@_);};
    return @rows;
}

sub ShowStockHoldings{
    my @rows;
    eval {@rows =  ExecSQL($dbuser,$dbpasswd,
            "select symbol,share_amount from stock_holdings where portfolio_id=? and share_amount > 0",undef,@_);};
    return @rows;
}

sub UpdateCash{
    my ($user,$p_id,$cash_act,$amount)=@_;
    my $newamount;
    if($cash_act eq "withdraw"){$newamount=0-$amount;}
    else{$newamount=$amount;}
    eval {ExecSQL($dbuser,$dbpasswd,"update portfolio_accounts set cash = cash +? where owner=? and id=?",undef,$newamount,$user,$p_id);};
    return $@;
}

sub ShowPortfolio{
    my ($user)=@_;
    my @rows;
    eval {@rows =  ExecSQL($dbuser,$dbpasswd,
            "select * from portfolio_accounts where owner=?",undef,$user);};
    return @rows;
}

sub ShowBalance{
    my ($user)=@_;
    my @rows;
    eval {@rows =  ExecSQL($dbuser,$dbpasswd,
            "select p_name,cash from portfolio_accounts where owner=?",undef,$user);};
    if($@){return (undef,$@);}
    else{
        return (MakeTable("show balance","2D",["portfolio name","cash"],@rows),$@);
    }
}

sub PortfolioAdd{
    eval { ExecSQL($dbuser,$dbpasswd,
            "insert into portfolio_accounts (id,owner,p_name,cash) values (portfolio_accounts_id.nextval,?,?,?)",undef,@_);};
    return $@;

}

sub UserAdd{
    eval { ExecSQL($dbuser,$dbpasswd,
            "insert into portfolio_users (name,password,email) values (?,?,?)",undef,@_);};
    return $@;
}


sub ValidUser {
    my ($user,$password)=@_;
    my @col;
    eval {@col=ExecSQL($dbuser,$dbpasswd, "select count(*) from portfolio_users where name=? and password=?","COL",$user,$password);};
    if ($@) {
        return 0;
    } else {
        return $col[0]>0;
    }
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

sub MakeTable {
    my ($id,$type,$headerlistref,@list)=@_;
    my $out;
    #
    # Check to see if there is anything to output
    #
    if ((defined $headerlistref) || ($#list>=0)) {
        # if there is, begin a table
        #
        $out="<table id=\"$id\" border>";
        #
        # if there is a header list, then output it in bold
        #
        if (defined $headerlistref) {
            $out.="<tr>".join("",(map {"<td><b>$_</b></td>"} @{$headerlistref}))."</tr>";
        }
        #
        # If it's a single row, just output it in an obvious way
        #
        if ($type eq "ROW") {
            #
            # map {code} @list means "apply this code to every member of the list
            # and return the modified list.  $_ is the current list member
            #
            $out.="<tr>".(map {defined($_) ? "<td>$_</td>" : "<td>(null)</td>" } @list)."</tr>";
        } elsif ($type eq "COL") {
            #
            # ditto for a single column
            #
            $out.=join("",map {defined($_) ? "<tr><td>$_</td></tr>" : "<tr><td>(null)</td></tr>"} @list);
        } else {
            #
            # For a 2D table, it's a bit more complicated...
            #
            $out.= join("",map {"<tr>$_</tr>"} (map {join("",map {defined($_) ? "<td>$_</td>" : "<td>(null)</td>"} @{$_})} @list));
        }
        $out.="</table>";
    } else {
        # if no header row or list, then just say none.
        $out.="(none)";
    }
    return $out;
}


