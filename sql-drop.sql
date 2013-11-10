delete from portfolio_users;
delete from portfolio_accounts;
commit;

drop SEQUENCE portfolio_accounts_id;
drop table portfolio_accounts;
drop table portfolio_users;
quit;
