create table portfolio_users (
    name  varchar(64) not null primary key,
    password VARCHAR(64) NOT NULL,
    constraints pwd_work CHECK (password LIKE '________%'),
    email  varchar(256) not null UNIQUE,
    constraint email_work CHECK (email LIKE '%@%')
);

create table portfolio_accounts (
    id number not null primary key,
    --user name
    owner varchar(64) not null references portfolio_users(name) on delete cascade,
    --portfolio name
    p_name varchar(64) not null,
    cash number not null, constraint cash_positive CHECK(cash >=0)
);

CREATE SEQUENCE portfolio_accounts_id
MINVALUE 1
START WITH 1
INCREMENT BY 1
CACHE 1024;

create table stocks (
    symbol  varchar(10) not null primary key
);

create table stocks_daily (
    symbol  varchar(64) not null,
    timestamp number not null,
    open number not null,
    high number not null,
    low number not null,
    close number not null,
    volume number not null,
    constraint sd_pk primary key(symbol,timestamp)
);

create table stock_holdings (
    portfolio_id number not null references portfolio_accounts(id) on delete cascade,
    symbol varchar(10) not null references stocks(symbol) on delete cascade,
    share_amount number not null,
    constraint amount_positive CHECK(share_amount >=0),
    constraint sh_pk primary key(portfolio_id, symbol)
);

create table stock_transactions (
    id number not null primary key,
    portfolio_id number not null references portfolio_accounts(id) on delete cascade,
    symbol varchar(10) not null references stocks(symbol) on delete cascade,
    share_amount number not null,
    transaction_type number not null,
    strike_price number not null,
    transaction_time timestamp not null
);
CREATE SEQUENCE stock_transactions_id
MINVALUE 1
START WITH 1
INCREMENT BY 1
CACHE 1024;

INSERT INTO stocks (symbol) select distinct symbol from cs339.stockssymbols;

INSERT INTO portfolio_users (name,password,email) VALUES ('root','rootroot','root@root.com');
INSERT INTO portfolio_users (name,password,email) VALUES ('anon','anonanon','anon@anon.com');

quit;
