use Test::More;

use File::Temp 0.22;
my $tmp = File::Temp->new(UNLINK => 1);
print $tmp qq|hello [% IF 0 %]true[% ELSE %]false[% END %]|;
close $tmp;

my $cond_while = qq|1 [% FOREACH account IN account_numbers %] [% IF loop.first %] WHERE [% ELSE %] OR [% END %] account_number LIKE '%[% account.remove('(\\W+)') %]%' [% END %]|;

# This is mostly testing Template Toolkit which probably isn't useful
my @templates = (
	[
		{file => $tmp->filename},
		qq|hello false|
	],
	[
		{sql => qq|hello [% IF 1 %]true[% END %]|},
		qq|hello true|
	],
	[
		{sql => qq|hello [% "there" %]|},
		qq|hello there|
	],
	[
		\qq|hello [% hello.there %]/[% hello.you %]|,
		 qq|hello silly/rabbit|
	],
	[
		{sql => $cond_while},
		qq|1   WHERE  account_number LIKE '%D001%'   OR  account_number LIKE '%D002%' |,
		{account_numbers => [' D001 ', 'D002']}
	],
	[
		{sql => $cond_while},
		qq|1   WHERE  account_number LIKE '%D002%' |,
		{account_numbers => ['D00 2']}
	],
	[
		{sql => $cond_while},
		qq|1 |,
		{account_numbers => []}
	]
);

plan tests => @templates + 1;

my $mod = 'DBIx::Enabler::Query';
require_ok($mod);

#my $config = test_config;
my $always = {hello => {there => 'silly', you => 'rabbit'}};

foreach my $template ( @templates ){
	my( $in, $out, $vars ) = @$template;
	my $q = $mod->new({%$in, variables => $always});
	is($q->sql($vars), $out, 'template');
}
