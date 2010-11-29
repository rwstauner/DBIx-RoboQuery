use strict;
use warnings;
use Test::More;
use Template;
use DBIx::Enabler::Query;

my $pod_example =
[
	q|color == 'red'|,
	q|color == 'green'|,
	q|smell == 'good'|
];
my $place = 
[
	q|place == 'here'|,
	q|place == 'there' OR place == 'over there' OR place == 'back here'|
];
my $fruit = [
	q|name == 'orange'|,
	q|color == 'green'|,
	q|stem|
];
my @tests = (
	# [ winning record (starting from 1), ["rule", "rule"], {r => 1}, {r => 2} ]
	[
		2, $pod_example,
		{color => 'blue',  smell => 'good'},
		{color => 'green', smell => 'bad'}
	],
	[
		2, $pod_example,
		{color => 'blue',   smell => 'ok'},
		{color => 'orange', smell => 'good'},
		{color => 'yellow', smell => 'bad'}
	],
	[
		3, $pod_example,
		{color => 'blue',  smell => 'ok'},
		{color => 'green', smell => 'bad'},
		{color => 'red',   smell => 'ok'}
	],
	[
		2, $place,
		{place => 'nowhere', name => 'Gourd'},
		{place => 'here', name => 'Jimmy'},
		{place => 'over there', name => 'Jerry'}
	],
	[
		1, $place,
		{place => 'here', name => 'Jimmy'},
		{place => 'over there', name => 'Jerry'},
		{place => 'nowhere', name => 'Gourd'}
	],
	[
		3, $place,
		{place => 'nowhere', name => 'Gourd'},
		{place => 'over there', name => 'Jerry'},
		{place => 'here', name => 'Jimmy'}
	],
	[
		2, $place,
		{place => 'there', name => 'Eric'},
		{place => 'over there', name => 'Bob'},
		{place => 'nowhere', name => 'Goober'}
	],
	[
		3, $place,
		{place => 'nowhere', name => 'Goober'},
		{place => 'nowhere', name => 'Eric'},
		{place => 'nowhere', name => 'Bob'}
	],
	[
		2, $fruit,
		{name => 'grape',  color => 'red',    stem => 0},
		{name => 'apple',  color => 'red',    stem => 1},
		{name => 'banana', color => 'yellow', stem => 0}
	],
	[
		2, $fruit,
		{name => 'grape',  color => 'red',    stem => 0},
		{name => 'orange', color => 'orange', stem => 0},
		{name => 'banana', color => 'green',  stem => 0}
	],
	[
		3, $fruit,
		{name => 'grape',  color => 'red',    stem => 0},
		{name => 'pear',   color => 'yellow', stem => 0},
		{name => 'banana', color => 'yellow', stem => 0}
	]
);

plan tests => scalar @tests;

my $r = DBIx::Enabler::Query->new(sql => '')->resultset;
foreach my $test ( @tests ){
	my $p = shift @$test;
	$r->{preferences} = shift @$test;
	is_deeply($r->preference(@$test), $$test[$p-1], "expected record $p");
}

# TODO: test $query->prefer()
